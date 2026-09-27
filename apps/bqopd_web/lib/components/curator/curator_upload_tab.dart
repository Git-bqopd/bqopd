import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_utils.dart';
import '../../utils/web_shortcode_service.dart';
import '../../repositories/repositories.dart';
import '../fanzine_thumbnail_card.dart';
import './modals/curator_orphan_selector_modal.dart';
import './modals/curator_confirm_modal.dart';

/// Curator-only isolated Upload tab for adding new assets, selecting from the master library,
/// and compiling template pages directly into the active folio sequence.
/// Renders library assets using the reusable squared FanzineThumbnailCard component without drop shadows.
class CuratorUploadTab extends StatefulComponent {
  final Fanzine fanzine;
  final List<FanzinePage> pages;
  final FanzineEditorBloc bloc;
  final bool isUploading;

  const CuratorUploadTab({
    required this.fanzine,
    required this.pages,
    required this.bloc,
    required this.isUploading,
    super.key,
  });

  @override
  State<CuratorUploadTab> createState() => _CuratorUploadTabState();
}

class _CuratorUploadTabState extends State<CuratorUploadTab> {
  dynamic _imagesSub;
  List<Map<String, dynamic>> _userImages = [];
  bool _showOrphanModal = false;
  bool _isGcsUploading = false;

  // Custom warning dialog states
  String? _pendingDeleteId;
  bool _isPendingDeleteDirect = false;

  @override
  void initState() {
    super.initState();
    _listenToUserImages();
  }

  @override
  void dispose() {
    _imagesSub?.cancel();
    super.dispose();
  }

  bool get _isUploading => _isGcsUploading || component.isUploading;

  void _listenToUserImages() {
    _imagesSub?.cancel();
    final uid = getCurrentUserId();
    if (uid == null) {
      setState(() {
        _userImages = [];
      });
      return;
    }
    _imagesSub = fsListenQuery('images', 'uploaderId', '==', jsonEncode(uid), '', false, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr) as List;
        final images = decoded.map((d) {
          final data = d['data'] as Map<String, dynamic>;
          data['id'] = d['id'];
          return data;
        }).toList();

        if (mounted) {
          setState(() {
            _userImages = images;
          });
        }
      } catch (e) {
        print("Error streaming user gallery in CuratorUploadTab: $e");
      }
    });
  }

  bool _isImage5x8(Map<String, dynamic> img) {
    if (img['is5x8'] == false) return false;
    if (img['is5x8'] == true || img['type'] == 'template') return true;
    final w = img['width'] as num?;
    final h = img['height'] as num?;
    if (w == null || h == null || w == 0 || h == 0) return true;
    final ratio = w / h;
    return ratio >= 0.58 && ratio <= 0.67;
  }

  void _triggerUpload() {
    triggerFilePicker('curator-folio-uploader-native-picker', (base64, fileName, objectUrl) async {
      setState(() {
        _isGcsUploading = true;
      });
      try {
        final dims = await getImageDimensions(objectUrl);
        final width = dims['width'] ?? 0;
        final height = dims['height'] ?? 0;
        final double ratio = (width > 0 && height > 0) ? width / height : 0.625;
        final bool is5x8 = (ratio >= 0.58 && ratio <= 0.67);
        final uid = getCurrentUserId();
        if (uid == null) throw Exception("Session authentication required.");

        final String path = 'uploads/$uid/folio_assets/${component.fanzine.id}/${DateTime.now().millisecondsSinceEpoch}_$fileName';
        final bytes = base64Decode(base64);
        final downloadUrl = await stUpload(path, bytes, 'image/jpeg');
        final imageId = 'img_${DateTime.now().millisecondsSinceEpoch}';

        final String? email = createAuthRepository().currentUser?.email;
        final bool useVanity = email != null && email.trim().toLowerCase() == 'kevin@712liberty.com';
        final shortCode = await WebShortcodeService.assignShortcode(
          contentType: 'image',
          contentId: imageId,
          isVanity: useVanity,
        ) ?? imageId.substring(imageId.length - 7).toUpperCase();

        final imgData = {
          'uid': uid,
          'uploaderId': uid,
          'fileUrl': downloadUrl,
          'fileName': fileName,
          'title': fileName,
          'status': 'approved',
          'tags': {},
          'indicia': '',
          'creators': [],
          'timestamp': WebFieldValue.serverTimestamp(),
          'shortCode': shortCode,
          'storagePath': path,
          'folioContext': component.fanzine.id,
          'usedInFanzines': [component.fanzine.id],
          'width': width,
          'height': height,
          'aspectRatio': ratio,
          'is5x8': is5x8,
        };

        await fsSetDoc('images/$imageId', jsonEncode(imgData), true);

        if (is5x8) {
          component.bloc.add(AddExistingImageRequested(imageId, downloadUrl, width: width, height: height));
        } else {
          await fsUpdateDoc('images/$imageId', jsonEncode({
            'usedInFanzines': WebFieldValue.arrayUnion([component.fanzine.id])
          }));
          component.bloc.add(LoadFanzineRequested(component.fanzine.id));
        }
      } catch (e) {
        print("Failed direct folio asset upload: $e");
        component.bloc.add(LoadFanzineRequested(component.fanzine.id));
      } finally {
        if (mounted) {
          setState(() {
            _isGcsUploading = false;
          });
        }
      }
    });
  }

  Future<void> _addSelectedOrphans(List<Map<String, dynamic>> selected) async {
    setState(() => _showOrphanModal = false);
    try {
      for (final img in selected) {
        final String imageId = img['id'] ?? '';
        final String? url = img['fileUrl'] ?? img['gridUrl'];
        final int width = img['width'] ?? 0;
        final int height = img['height'] ?? 0;

        if (imageId.isNotEmpty && url != null) {
          if (_isImage5x8(img)) {
            component.bloc.add(AddExistingImageRequested(imageId, url, width: width, height: height));
          } else {
            await fsUpdateDoc('images/$imageId', jsonEncode({
              'usedInFanzines': WebFieldValue.arrayUnion([component.fanzine.id])
            }));
          }
        }
      }
      component.bloc.add(LoadFanzineRequested(component.fanzine.id));
    } catch (e) {
      print("Error adding selected orphans in CuratorUploadTab: $e");
      component.bloc.add(LoadFanzineRequested(component.fanzine.id));
    }
  }

  void _triggerNewTextPage() {
    component.bloc.add(AddPageRequested('generating_template...'));
    final IFanzineRepository repo = createFanzineRepository();
    final int afterPageNum = component.pages.isNotEmpty ? component.pages.length : 0;
    final initialText = """
# THE PUBLISHER
## New Custom Page Created
Start typing directly inside the text editor panel below to generate columns of printable markdown text.

{{IMAGE}}

* Enter bullet lists with an asterisk
* Customize headers with # or ##
""";
    repo.insertPublisherPage(component.fanzine.id, afterPageNum, initialText, component.pages).then((_) {
      component.bloc.add(LoadFanzineRequested(component.fanzine.id));
    }).catchError((e) {
      print("Error creating text page in CuratorUploadTab: $e");
      component.bloc.add(LoadFanzineRequested(component.fanzine.id));
    });
  }

  void _triggerNewCalendarPage() {
    component.bloc.add(AddPageRequested('generating_calendar...'));
    final int nextNum = component.pages.length + 1;
    final String pageId = 'page_${DateTime.now().millisecondsSinceEpoch}';

    fsSetDoc('fanzines/${component.fanzine.id}/pages/$pageId', jsonEncode({
      'pageNumber': nextNum,
      'status': 'ready',
      'templateId': 'calendar_left',
      'createdAt': WebFieldValue.serverTimestamp(),
    }), true).then((_) {
      component.bloc.add(LoadFanzineRequested(component.fanzine.id));
    }).catchError((e) {
      print("Error creating calendar page in CuratorUploadTab: $e");
      component.bloc.add(LoadFanzineRequested(component.fanzine.id));
    });
  }

  Future<void> _toggleFullPage(Map<String, dynamic> doc, bool isFullPage) async {
    final String imageId = doc['id'] ?? '';
    if (imageId.isEmpty) return;
    final String? optimalUrl = doc['gridUrl'] ?? doc['fileUrl'] ?? doc['imageUrl'];
    final int width = doc['width'] ?? 0;
    final int height = doc['height'] ?? 0;

    // 1. Update local document state for instant UI responsiveness
    setState(() {
      doc['is5x8'] = isFullPage;
    });

    try {
      if (kIsWeb) {
        await fsUpdateDoc('images/$imageId', jsonEncode({'is5x8': isFullPage}));
      }

      if (isFullPage) {
        // Add as a page in this folio sequence if not already present
        final bool alreadyPage = component.pages.any((p) => p.imageId == imageId);
        if (!alreadyPage && optimalUrl != null && optimalUrl.isNotEmpty) {
          component.bloc.add(AddExistingImageRequested(
            imageId,
            optimalUrl,
            width: width,
            height: height,
          ));
        } else if (alreadyPage) {
          // If already in pages but was unordered (pageNumber == 0), restore to ordered sequence
          final p = component.pages.firstWhere((p) => p.imageId == imageId);
          if (p.pageNumber == 0) {
            component.bloc.add(TogglePageOrderingRequested(p, true));
          }
        }
      } else {
        // Remove from folio pages sequence if present
        FanzinePage? pageToRemove;
        for (final p in component.pages) {
          if (p.imageId == imageId) {
            pageToRemove = p;
            break;
          }
        }
        if (pageToRemove != null) {
          component.bloc.add(RemovePageRequested(pageToRemove, component.pages));
        }
      }
    } catch (e) {
      print("Error setting image full page in CuratorUploadTab: $e");
    }
  }

  @override
  Component build(BuildContext context) {
    final folioImages = _userImages.where((img) {
      final List usedIn = img['usedInFanzines'] ?? [];
      final String? contextId = img['folioContext'];
      return contextId == component.fanzine.id || usedIn.contains(component.fanzine.id);
    }).toList();

    folioImages.sort((a, b) {
      final aT = a['timestamp'] ?? a['createdAt'] ?? '';
      final bT = b['timestamp'] ?? b['createdAt'] ?? '';
      return aT.toString().compareTo(bT.toString());
    });

    final Map<String, String> imageShortNames = {};
    for (int i = 0; i < folioImages.length; i++) {
      final String id = folioImages[i]['id'] ?? '';
      if (id.isNotEmpty) {
        imageShortNames[id] = "img${(i + 1).toString().padLeft(2, '0')}";
      }
    }

    final fiveByEightDocs = folioImages.where((img) => _isImage5x8(img)).toList();
    final otherDocs = folioImages.where((img) => !_isImage5x8(img)).toList();

    return div(
      classes: 'flex-col gap-3 text-left p-2',
      [
        div(
            attributes: const {
              'style':
              'display: flex; gap: 12px; justify-content: center; width: 100%; margin-top: 8px; margin-bottom: 12px; flex-wrap: wrap;'
            },
            [
              button(
                  [
                    if (_isUploading)
                      span(
                        [Component.text('progress_activity')],
                        classes: 'material-symbols-outlined',
                        attributes: const {
                          'style':
                          'font-size: 18px; margin-right: 6px; animation: spin 1s linear infinite;'
                        },
                      )
                    else
                      span(
                        [Component.text('upload')],
                        classes: 'material-symbols-outlined',
                        attributes: const {
                          'style': 'font-size: 18px; margin-right: 6px;'
                        },
                      ),
                    Component.text(_isUploading ? "uploading..." : "upload new image")
                  ],
                  attributes: {
                    'style':
                    'background-color: #9e9e9e; color: white; border-radius: 20px; border: none; padding: 10px 18px; font-size: 11px; font-weight: bold; cursor: pointer; display: flex; align-items: center; justify-content: center;',
                    if (_isUploading) 'disabled': 'true'
                  },
                  events: {
                    'click': (e) => _triggerUpload(),
                  }
              ),
              button(
                  [
                    span(
                      [Component.text('photo_library')],
                      classes: 'material-symbols-outlined',
                      attributes: const {
                        'style': 'font-size: 18px; margin-right: 6px;'
                      },
                    ),
                    Component.text("select orphan image")
                  ],
                  attributes: {
                    'style':
                    'background-color: #9e9e9e; color: white; border-radius: 20px; border: none; padding: 10px 18px; font-size: 11px; font-weight: bold; cursor: pointer; display: flex; align-items: center; justify-content: center;',
                    if (_isUploading) 'disabled': 'true'
                  },
                  events: {
                    'click': (e) => setState(() => _showOrphanModal = true),
                  }
              ),
            ]
        ),
        div(
            attributes: const {
              'style':
              'display: flex; gap: 12px; justify-content: center; width: 100%; margin-bottom: 20px; flex-wrap: wrap;'
            },
            [
              button(
                  [
                    span(
                      [Component.text('note_add')],
                      classes: 'material-symbols-outlined',
                      attributes: const {
                        'style': 'font-size: 18px; margin-right: 6px;'
                      },
                    ),
                    Component.text("new text page")
                  ],
                  attributes: {
                    'style':
                    'background-color: #7e57c2; color: white; border-radius: 20px; border: none; padding: 10px 18px; font-size: 11px; font-weight: bold; cursor: pointer; display: inline-flex; align-items: center; justify-content: center;',
                    if (_isUploading) 'disabled': 'true'
                  },
                  events: {
                    'click': (e) => _triggerNewTextPage(),
                  }
              ),
              button(
                  [
                    span(
                      [Component.text('calendar_today')],
                      classes: 'material-symbols-outlined',
                      attributes: const {
                        'style': 'font-size: 18px; margin-right: 6px;'
                      },
                    ),
                    Component.text("new calendar page")
                  ],
                  attributes: {
                    'style':
                    'background-color: #7e57c2; color: white; border-radius: 20px; border: none; padding: 10px 18px; font-size: 11px; font-weight: bold; cursor: pointer; display: inline-flex; align-items: center; justify-content: center;',
                    if (_isUploading) 'disabled': 'true'
                  },
                  events: {
                    'click': (e) => _triggerNewCalendarPage(),
                  }
              ),
            ]
        ),
        if (_isUploading)
          div(
              [
                div([], attributes: const {
                  'style':
                  'height: 3px; background-color: #6750A4; width: 60%; border-radius: 2px; animation: shimmerKeyframe 1.5s infinite linear;'
                })
              ],
              attributes: const {
                'style':
                'width: 100%; height: 3px; background-color: #eee; border-radius: 2px; overflow: hidden; margin-top: -12px; margin-bottom: 16px;'
              }
          ),
        if (folioImages.isEmpty && !_isUploading)
          div(
            [Component.text("no images in this folio yet.")],
            attributes: const {
              'style':
              'text-align: center; padding: 40px 16px; color: #888; font-size: 13px; font-style: italic; width: 100%; border-top: 1px solid #f0f0f0;'
            },
          )
        else ...[
          if (fiveByEightDocs.isNotEmpty || (_isUploading && fiveByEightDocs.isEmpty && otherDocs.isEmpty)) ...[
            div([
              span(
                [Component.text("full pages (5x8)")],
                attributes: const {
                  'style':
                  'font-size: 11px; font-weight: bold; color: #666; text-transform: uppercase; letter-spacing: 0.5px;'
                },
              )
            ], attributes: const {'style': 'margin-top: 12px; margin-bottom: 8px;'}),
            _buildUploadedImagesGrid(
              fiveByEightDocs,
              imageShortNames,
              showUploadPlaceholder: _isUploading,
              isInlineAsset: false,
            ),
            div([], attributes: const {'style': 'height: 16px;'})
          ],
          if (otherDocs.isNotEmpty && !(_isUploading && fiveByEightDocs.isEmpty && otherDocs.isEmpty)) ...[
            div([
              span(
                [Component.text("inline assets")],
                attributes: const {
                  'style':
                  'font-size: 11px; font-weight: bold; color: #666; text-transform: uppercase; letter-spacing: 0.5px;'
                },
              )
            ], attributes: const {'style': 'margin-top: 12px; margin-bottom: 8px;'}),
            _buildUploadedImagesGrid(
              otherDocs,
              imageShortNames,
              isInlineAsset: true,
            ),
            div([], attributes: const {'style': 'height: 16px;'})
          ]
        ],
        if (_showOrphanModal)
          CuratorOrphanSelectorModal(
            fanzineId: component.fanzine.id,
            userId: getCurrentUserId() ?? '',
            onCancel: () => setState(() => _showOrphanModal = false),
            onAddSelected: _addSelectedOrphans,
          ),
        if (_pendingDeleteId != null)
          CuratorConfirmModal(
            title: _isPendingDeleteDirect
                ? "Delete Image Completely?"
                : "Remove from Folio?",
            message: _isPendingDeleteDirect
                ? "This is a direct upload or publisher template page. Deleting it will remove it from ALL issues and your library forever."
                : "This image is from your library. Removing it will only take it out of this specific folio.",
            confirmLabel: _isPendingDeleteDirect ? "DELETE FOREVER" : "REMOVE",
            isDestructive: _isPendingDeleteDirect,
            onCancel: () => setState(() => _pendingDeleteId = null),
            onConfirm: () {
              final id = _pendingDeleteId!;
              setState(() => _pendingDeleteId = null);
              component.bloc.add(DeleteAssetRequested(id, _isPendingDeleteDirect));
            },
          ),
      ],
    );
  }

  Component _buildUploadedImagesGrid(
      List<Map<String, dynamic>> docs,
      Map<String, String> imageShortNames, {
        bool showUploadPlaceholder = false,
        bool isInlineAsset = false,
      }) {
    return div(
      [
        if (showUploadPlaceholder)
          _buildShimmerPlaceholderCard(),
        for (var doc in docs) ...[
          _buildCardItem(doc, imageShortNames, isInlineAsset: isInlineAsset),
        ]
      ],
      attributes: const {
        'style':
        'display: grid; grid-template-columns: repeat(auto-fill, minmax(130px, 1fr)); gap: 14px; width: 100%; margin-top: 8px; box-sizing: border-box;'
      },
    );
  }

  Component _buildCardItem(
      Map<String, dynamic> doc,
      Map<String, String> imageShortNames, {
        required bool isInlineAsset,
      }) {
    final String imageId = doc['id'] ?? '';
    final String? optimalUrl = doc['gridUrl'] ?? doc['fileUrl'] ?? doc['imageUrl'];
    final bool isDirect = doc['folioContext'] == component.fanzine.id;
    final bool isTemplate = doc['isGenerated'] == true || doc['type'] == 'template';
    final String shortName = imageShortNames[imageId] ?? '';

    final cardData = Map<String, dynamic>.from(doc);
    final String rawTitle = doc['title'] ?? doc['fileName'] ?? 'untitled';
    cardData['title'] = shortName.isNotEmpty ? '$shortName: $rawTitle' : rawTitle;

    return FanzineThumbnailCard(
      fanzineData: cardData,
      customCoverUrl: optimalUrl,
      cardType: 'image',
      key: ValueKey('curator_asset_${doc['id']}'),
      isFullPage: !isInlineAsset,
      onToggleFullPage: (val) => _toggleFullPage(doc, val),
      onDelete: (id, title) {
        setState(() {
          _pendingDeleteId = imageId;
          _isPendingDeleteDirect = isDirect || isTemplate;
        });
      },
    );
  }

  Component _buildShimmerPlaceholderCard() {
    return div(
        [
          div(
              [
                span(
                  [Component.text('progress_activity')],
                  classes: 'material-symbols-outlined',
                  attributes: const {
                    'style':
                    'font-size: 24px; color: #6750A4; animation: spin 1s linear infinite;'
                  },
                ),
                span(
                  [Component.text("processing...")],
                  attributes: const {
                    'style':
                    'font-size: 9px; color: #6750A4; font-weight: bold; margin-top: 8px;'
                  },
                )
              ],
              attributes: const {
                'style':
                'display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%;'
              }
          )
        ],
        classes: 'shimmer-bg',
        attributes: const {
          'style':
          'aspect-ratio: 5 / 8; background-color: #f5f5f5; border: 1px solid rgba(103, 80, 164, 0.3); border-radius: 0px; position: relative; overflow: hidden; box-shadow: none;'
        }
    );
  }
}

typedef EditorCuratorUploadTab = CuratorUploadTab;