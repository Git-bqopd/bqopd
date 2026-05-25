import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import '../utils/web_utils.dart';
import '../utils/web_shortcode_service.dart';
import '../components/fanzine_header.dart';

/// Refined workspace editor experience for the Jaspr web application.
/// Form-fitting, height-adaptive panel supporting dynamic folio adjustments.
class FanzineEditor extends StatefulComponent {
  final String fanzineId;
  final String? shortCode;
  final Map<String, dynamic>? fanzineData;
  final Map<String, Map<String, dynamic>> creatorProfiles;
  final Map<String, Map<String, dynamic>> imageStats;
  final List<Map<String, dynamic>> pageStructure;
  final AuthState? authState;
  final AuthBloc? authBloc;

  const FanzineEditor({
    required this.fanzineId,
    this.shortCode,
    this.fanzineData,
    this.creatorProfiles = const {},
    this.imageStats = const {},
    this.pageStructure = const [],
    this.authState,
    this.authBloc,
    super.key,
  });

  @override
  State<FanzineEditor> createState() => _FanzineEditorState();
}

class _FanzineEditorState extends State<FanzineEditor> {
  int _activeTab = 0; // 0: settings, 1: order, 2: upload

  // State Management Fields
  String _title = '';
  String _volume = '';
  String _issue = '';
  String _wholeNumber = '';
  bool _twoPage = true;
  bool _hasCover = true;
  bool _isSavingSettings = false;

  // Single Page Upload Settings
  String _uploadTitle = '';
  String _uploadDescription = '';
  String _uploadIndicia = '';
  String? _uploadImageBase64;
  String? _uploadImageName;
  String? _uploadPreviewUrl;
  List<Map<String, dynamic>> _uploadCreators = [];
  String _newCreatorHandle = '';
  String _newCreatorRole = '';
  bool _isUploadingImage = false;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    _syncMetadata();
  }

  @override
  void didUpdateComponent(FanzineEditor oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.fanzineData != component.fanzineData) {
      _syncMetadata();
    }
  }

  void _syncMetadata() {
    final fd = component.fanzineData;
    if (fd != null) {
      _title = fd['title'] ?? '';
      _volume = fd['volume'] ?? '';
      _issue = fd['issue'] ?? '';
      _wholeNumber = fd['wholeNumber'] ?? '';
      _twoPage = fd['twoPage'] ?? true;
      _hasCover = fd['hasCover'] ?? true;
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSavingSettings = true);
    try {
      final config = {
        'title': _title.trim(),
        'volume': _volume.trim(),
        'issue': _issue.trim(),
        'wholeNumber': _wholeNumber.trim(),
        'twoPage': _twoPage,
        'hasCover': _hasCover,
      };
      await fsUpdateDoc('fanzines/${component.fanzineId}', jsonEncode(config));
    } catch (e) {
      print("Error saving fanzine settings: $e");
    } finally {
      setState(() => _isSavingSettings = false);
    }
  }

  Future<void> _deletePage(String pageId) async {
    try {
      await fsDeleteDoc('fanzines/${component.fanzineId}/pages/$pageId');
    } catch (e) {
      print("Error removing page: $e");
    }
  }

  Future<void> _reorderPage(Map<String, dynamic> page, int delta) async {
    final String pageId = page['__id'] ?? '';
    final int currentNum = page['pageNumber'] ?? 0;
    if (pageId.isEmpty) return;

    try {
      await fsUpdateDoc(
        'fanzines/${component.fanzineId}/pages/$pageId',
        jsonEncode({'pageNumber': currentNum + delta}),
      );
    } catch (e) {
      print("Error reordering: $e");
    }
  }

  Future<void> _updatePageLayout(Map<String, dynamic> page, String? spreadPosition, String sidePreference) async {
    final String pageId = page['__id'] ?? '';
    if (pageId.isEmpty) return;

    try {
      await fsUpdateDoc(
        'fanzines/${component.fanzineId}/pages/$pageId',
        jsonEncode({
          'spreadPosition': spreadPosition,
          'sidePreference': sidePreference,
        }),
      );
    } catch (e) {
      print("Error updating page layout: $e");
    }
  }

  void _pickAndPreviewImage() {
    triggerFilePicker('folio-editor-upload-picker', (base64, fileName, objectUrl) {
      setState(() {
        _uploadImageBase64 = base64;
        _uploadImageName = fileName;
        _uploadPreviewUrl = objectUrl;
        _uploadError = null;
      });
    });
  }

  void _onFileInputChanged() {
    readSelectedFile('folio-editor-upload-picker', (base64, fileName, objectUrl) {
      setState(() {
        _uploadImageBase64 = base64;
        _uploadImageName = fileName;
        _uploadPreviewUrl = objectUrl;
        _uploadError = null;
      });
    });
  }

  Future<void> _addCreator() async {
    final handle = _newCreatorHandle.trim();
    final role = _newCreatorRole.trim();
    if (handle.isEmpty) return;

    final cleanHandle = handle.toLowerCase().replaceAll('@', '');
    String resolvedName = handle;
    String? resolvedUid;

    try {
      final resStr = await fsQuery('profiles', 'username', '==', jsonEncode(cleanHandle), '');
      final List docs = jsonDecode(resStr);
      if (docs.isNotEmpty) {
        final doc = docs.first;
        final data = doc['data'];
        resolvedName = data['displayName'] ?? data['username'] ?? handle;
        resolvedUid = doc['id'];
      }
    } catch (_) {}

    setState(() {
      _uploadCreators.add({
        'uid': resolvedUid,
        'name': resolvedName,
        'role': role.isNotEmpty ? role : 'Contributor',
      });
      _newCreatorHandle = '';
      _newCreatorRole = '';
    });
  }

  Future<void> _submitSingleImage() async {
    if (_uploadTitle.trim().isEmpty) {
      setState(() => _uploadError = "Title is required.");
      return;
    }
    if (_uploadImageBase64 == null) {
      setState(() => _uploadError = "Please select an image first.");
      return;
    }

    setState(() {
      _isUploadingImage = true;
      _uploadError = null;
    });

    final String? uid = getCurrentUserId();
    if (uid == null) {
      setState(() {
        _uploadError = "Unauthenticated user.";
        _isUploadingImage = false;
      });
      return;
    }

    try {
      final Uint8List bytes = base64Decode(_uploadImageBase64!);
      final String path = 'uploads/$uid/folio_assets/${component.fanzineId}/img_${DateTime.now().millisecondsSinceEpoch}_$_uploadImageName';

      // Perform secure upload to Firebase Storage
      final String downloadUrl = await stUpload(path, bytes, 'image/jpeg');

      final imageId = 'img_${DateTime.now().millisecondsSinceEpoch}';

      // Strict inlined owner check for vanity eligibility to prevent other users from obtaining vanity URLs
      final String? email = component.authState?.user?.email;
      final bool useVanity = email != null && email.trim().toLowerCase() == 'kevin@712liberty.com';

      // Generate and register shortcode for image using shared logic!
      final shortCode = await WebShortcodeService.assignShortcode(
        contentType: 'image',
        contentId: imageId,
        isVanity: useVanity,
      ) ?? imageId.substring(imageId.length - 7).toUpperCase();

      final imgData = {
        'uid': uid,
        'uploaderId': uid,
        'fileUrl': downloadUrl,
        'fileName': _uploadImageName,
        'title': _uploadTitle.trim(),
        'description': _uploadDescription.trim(),
        'status': 'approved',
        'tags': {},
        'indicia': _uploadIndicia.trim(),
        'creators': _uploadCreators,
        'timestamp': WebFieldValue.serverTimestamp(),
        'shortCode': shortCode,
        'storagePath': path,
        'folioContext': component.fanzineId,
        'usedInFanzines': [component.fanzineId],
      };

      await fsSetDoc('images/$imageId', jsonEncode(imgData), true);

      // Add to fanzine pages
      final int nextNum = component.pageStructure.length + 1;
      final pageId = 'page_${DateTime.now().millisecondsSinceEpoch}';
      await fsSetDoc('fanzines/${component.fanzineId}/pages/$pageId', jsonEncode({
        'imageId': imageId,
        'imageUrl': downloadUrl,
        'pageNumber': nextNum,
        'status': 'ready',
        'createdAt': WebFieldValue.serverTimestamp(),
      }), true);

      setState(() {
        _activeTab = 1; // Swap to the order tab to see the fresh flatplan sequence
        _uploadTitle = '';
        _uploadDescription = '';
        _uploadIndicia = '';
        _uploadImageBase64 = null;
        _uploadImageName = null;
        _uploadPreviewUrl = null;
        _uploadCreators = [];
      });
    } catch (e) {
      setState(() => _uploadError = e.toString());
    } finally {
      setState(() => _isUploadingImage = false);
    }
  }

  @override
  Component build(BuildContext context) {
    return div(classes: 'white-sticker-flexible w-full mt-2', [
      // 1. Core Tab Row
      div(classes: 'flex-row justify-center items-center py-2 bg-gray-100', [
        _buildTabButton('settings', 0),
        span(classes: 'px-4 text-gray text-xs', [text('|')]),
        _buildTabButton('order', 1),
        span(classes: 'px-4 text-gray text-xs', [text('|')]),
        _buildTabButton('upload', 2),
      ]),

      // 2. Active Tab Sheet - Height Auto adaptive
      div(classes: 'flex-col p-4', [
        if (_activeTab == 0) _buildSettingsTab(),
        if (_activeTab == 1) _buildOrderTab(),
        if (_activeTab == 2) _buildUploadTab(),
      ]),
    ]);
  }

  Component _buildTabButton(String label, int index) {
    final isActive = _activeTab == index;
    return span(
      classes: 'text-xs cursor-pointer ${isActive ? 'font-bold' : 'text-gray'}',
      events: {'click': (e) => setState(() => _activeTab = index)},
      [text(label)],
    );
  }

  Component _buildSettingsTab() {
    final String currentShortcode = component.shortCode?.toLowerCase() ?? 'pending...';

    return div(classes: 'flex-col text-left p-2', attributes: {'style': 'gap: 16px; display: flex;'}, [
      div(classes: 'flex-col mb-3', [
        span(classes: 'text-xs font-bold text-gray mb-1', [text('fanzine name')]),
        input(
          attributes: {'type': 'text', 'placeholder': 'Title', 'value': _title},
          events: {'input': (e) => _title = (e.target as dynamic).value},
        )
      ]),

      div(classes: 'flex-row gap-2 mb-3', attributes: {'style': 'display: flex; gap: 8px;'}, [
        div(classes: 'flex-1 flex-col', [
          span(classes: 'text-xs font-bold text-gray mb-1', [text('Volume')]),
          input(
            attributes: {'type': 'text', 'placeholder': 'Vol.', 'value': _volume},
            events: {'input': (e) => _volume = (e.target as dynamic).value},
          )
        ]),
        div(classes: 'flex-1 flex-col', [
          span(classes: 'text-xs font-bold text-gray mb-1', [text('Issue')]),
          input(
            attributes: {'type': 'text', 'placeholder': 'No.', 'value': _issue},
            events: {'input': (e) => _issue = (e.target as dynamic).value},
          )
        ]),
        div(classes: 'flex-1 flex-col', [
          span(classes: 'text-xs font-bold text-gray mb-1', [text('Whole Number')]),
          input(
            attributes: {'type': 'text', 'placeholder': 'Whole No.', 'value': _wholeNumber},
            events: {'input': (e) => _wholeNumber = (e.target as dynamic).value},
          )
        ]),
      ]),

      // Shortcode rendered cleanly inline with metadata
      div(
          classes: 'text-xs text-gray-500 font-semibold mb-3 text-left',
          [text('shortcode: $currentShortcode')]
      ),

      // Custom M3 Switch for two page layout
      div(
          classes: 'flex-row items-center justify-between cursor-pointer',
          attributes: {
            'style': 'padding: 12px; background-color: #f9f9f9; border: 1px solid #eee; border-radius: 8px; margin-bottom: 16px; display: flex; align-items: center; justify-content: space-between;'
          },
          events: {
            'click': (e) => setState(() => _twoPage = !_twoPage)
          },
          [
            span(classes: 'text-xs font-medium', attributes: {'style': 'color: #4a4a4a;'}, [text('Enable two page spread view')]),
            _buildCustomToggleSwitch(_twoPage)
          ]
      ),

      button(
          classes: 'btn-primary w-full',
          attributes: _isSavingSettings ? {'disabled': 'true'} : {},
          events: {'click': (e) => _saveSettings()},
          [text(_isSavingSettings ? 'Saving Configuration...' : 'Save Configuration')]
      )
    ]);
  }

  Component _buildCustomToggleSwitch(bool val) {
    return div(
        attributes: {
          'style': 'width: 44px; height: 24px; border-radius: 12px; background-color: ${val ? '#6750A4' : '#ccc'}; position: relative; transition: background-color 0.2s; cursor: pointer; display: inline-block;'
        },
        [
          div(
              attributes: {
                'style': 'width: 16px; height: 16px; border-radius: 50%; background-color: white; position: absolute; top: 4px; left: ${val ? '24px' : '4px'}; transition: left 0.2s;'
              },
              []
          )
        ]
    );
  }

  Component _buildOrderTab() {
    if (component.pageStructure.isEmpty) {
      return div(classes: 'p-16 text-center text-gray italic', [
        span(classes: 'material-symbols-outlined text-gray-300', attributes: {'style': 'font-size: 48px;'}, [text('format_list_numbered')]),
        p([text('No pages added to zine flatplan yet.')])
      ]);
    }

    return div(classes: 'flex-col gap-3 text-left p-2', [
      h2(
          classes: 'text-sm font-bold text-gray uppercase tracking-wider mb-3',
          [text('Folio Flatplan Sequence')]
      ),

      for (int i = 0; i < component.pageStructure.length; i++)
        _buildOrderPageRow(component.pageStructure[i], i)
    ]);
  }

  Component _buildOrderPageRow(Map<String, dynamic> page, int idx) {
    final pageNum = page['pageNumber'] ?? (idx + 1);
    final String? optimalUrl = page['gridUrl'] ?? page['listUrl'] ?? page['imageUrl'];
    final bool isPending = optimalUrl == null || optimalUrl.isEmpty;

    final String selectedSpreadPos = page['spreadPosition'] ?? '';
    final String selectedSidePref = page['sidePreference'] ?? 'either';

    return div(
        classes: 'flex-col bg-gray-50 border border-gray-150 p-3 rounded-lg mb-2',
        attributes: {'style': 'gap: 8px;'},
        [
          // Top row: Page number, Image thumbnail, delete button
          div(classes: 'flex-row items-center justify-between', [
            div(classes: 'flex-row items-center gap-3', [
              span(
                  classes: 'font-black text-xs text-gray-400',
                  attributes: {'style': 'width: 20px; text-align: right;'},
                  [text('$pageNum.')]
              ),
              div(
                  classes: 'rounded border border-gray-200 overflow-hidden bg-white',
                  attributes: {'style': 'width: 36px; height: 50px; position: relative;'},
                  [
                    if (!isPending)
                      img(
                          src: optimalUrl!,
                          attributes: {'style': 'width: 100%; height: 100%; object-fit: cover;'}
                      )
                    else
                      div(
                          classes: 'shimmer-bg w-full h-full flex items-center justify-center',
                          [
                            span(
                                classes: 'material-symbols-outlined text-gray-300',
                                attributes: {'style': 'font-size: 16px;'},
                                [text('progress_activity')]
                            )
                          ]
                      )
                  ]
              ),
              span(
                  classes: 'text-xs font-bold text-gray-700',
                  [text(isPending ? 'Processing web asset...' : 'Archival Page')]
              )
            ]),

            // Action Arrow reordering
            div(classes: 'flex-row items-center gap-1', [
              button(
                  classes: 'p-1 hover:bg-gray-100 rounded border-none bg-transparent cursor-pointer',
                  attributes: pageNum <= 1 ? {'disabled': 'true'} : {},
                  events: {'click': (e) => _reorderPage(page, -1)},
                  [span(classes: 'material-symbols-outlined text-sm', [text('arrow_upward')])]
              ),
              button(
                  classes: 'p-1 hover:bg-gray-100 rounded border-none bg-transparent cursor-pointer',
                  attributes: pageNum >= component.pageStructure.length ? {'disabled': 'true'} : {},
                  events: {'click': (e) => _reorderPage(page, 1)},
                  [span(classes: 'material-symbols-outlined text-sm', [text('arrow_downward')])]
              ),
              span(classes: 'px-1 text-gray-300', [text('|')]),
              button(
                  classes: 'p-1 hover:bg-red-50 rounded border-none bg-transparent cursor-pointer',
                  events: {'click': (e) => _deletePage(page['__id'] ?? '')},
                  [span(classes: 'material-symbols-outlined text-sm text-red-500', [text('close')])]
              ),
            ])
          ]),

          // Bottom Row: Spread Position and Side Preference configuration (Only if not Page 1 cover)
          if (pageNum > 1 || !_hasCover)
            div(
                classes: 'flex-row flex-wrap gap-2 pt-2 border-t border-gray-200 mt-1 justify-between items-center',
                [
                  // Spread Position Segmented Button
                  div(classes: 'flex-row gap-1', [
                    _buildSegmentButton(
                      'start',
                      selectedSpreadPos == 'start',
                          () => _updatePageLayout(page, 'start', selectedSidePref),
                    ),
                    _buildSegmentButton(
                      'end',
                      selectedSpreadPos == 'end',
                          () => _updatePageLayout(page, 'end', selectedSidePref),
                    ),
                    _buildSegmentButton(
                      'none',
                      selectedSpreadPos.isEmpty,
                          () => _updatePageLayout(page, null, selectedSidePref),
                    ),
                  ]),

                  // Side Preference Segmented Button
                  div(classes: 'flex-row gap-1', [
                    _buildSegmentButton(
                      'left',
                      selectedSidePref == 'left',
                          () => _updatePageLayout(page, selectedSpreadPos, 'left'),
                    ),
                    _buildSegmentButton(
                      'either',
                      selectedSidePref == 'either',
                          () => _updatePageLayout(page, selectedSpreadPos, 'either'),
                    ),
                    _buildSegmentButton(
                      'right',
                      selectedSidePref == 'right',
                          () => _updatePageLayout(page, selectedSpreadPos, 'right'),
                    ),
                  ]),
                ]
            )
        ]
    );
  }

  Component _buildSegmentButton(String label, bool isSelected, void Function() onTap) {
    return button(
        classes: 'm3-chip ${isSelected ? 'active' : ''}',
        attributes: {
          'style': 'height: 24px; font-size: 10px; padding: 0 8px; border-radius: 4px; border: 1px solid #ddd; margin: 0; outline: none;'
        },
        events: {'click': (e) => onTap()},
        [text(label)]
    );
  }

  Component _buildUploadTab() {
    return div(classes: 'flex-col gap-3 text-left p-2', [
      h2(
          classes: 'text-sm font-bold text-gray uppercase tracking-wider mb-2',
          [text('Upload Image into Folio')]
      ),

      // 1. The 5:8 Drag & Select Sheet (Matches profile_page)
      div(
          classes: 'aspect-5-8 bg-gray-100 flex-col items-center justify-center relative rounded-lg border-2 border-dashed border-gray-300 cursor-pointer overflow-hidden mb-3',
          attributes: {'style': 'width: 100%; aspect-ratio: 5 / 8;'},
          events: {'click': (e) => _pickAndPreviewImage()},
          [
            if (_uploadPreviewUrl != null)
              img(
                  src: _uploadPreviewUrl!,
                  attributes: {'style': 'width: 100%; height: 100%; object-fit: contain; position: absolute; top: 0; left: 0;'}
              )
            else
              div(classes: 'flex flex-col items-center justify-center p-4 text-center', [
                span(classes: 'material-symbols-outlined text-gray-400 mb-2', attributes: {'style': 'font-size: 48px;'}, [text('add_photo_alternate')]),
                span(classes: 'text-xs font-bold text-gray-500', [text('Click or Tap to select image')]),
                span(classes: 'text-xs text-gray-400 mt-1', [text('Image will automatically resize to optimal page metrics')])
              ]),

            input(
                id: 'folio-editor-upload-picker',
                attributes: {
                  'type': 'file',
                  'accept': 'image/*',
                  'style': 'position: absolute; top: 0; left: 0; width: 100%; height: 100%; opacity: 0; cursor: pointer; z-index: 10;'
                },
                events: {
                  'change': (e) => _onFileInputChanged(),
                  'click': (e) => (e as dynamic).stopPropagation()
                }
            )
          ]
      ),

      // Metadata inputs
      div(classes: 'flex-col mb-3', [
        input(
          attributes: {'type': 'text', 'placeholder': 'Title (Required)', 'value': _uploadTitle},
          events: {'input': (e) => _uploadTitle = (e.target as dynamic).value},
        ),
        input(
          attributes: {'type': 'text', 'placeholder': 'Caption / Description (Optional)', 'value': _uploadDescription},
          events: {'input': (e) => _uploadDescription = (e.target as dynamic).value},
        ),
        input(
          attributes: {'type': 'text', 'placeholder': 'Indicia / Copyright (Optional)', 'value': _uploadIndicia},
          events: {'input': (e) => _uploadIndicia = (e.target as dynamic).value},
        ),
      ]),

      // Creators listing
      div(classes: 'flex-col mb-3 p-3 bg-gray-50 border border-gray-150 p-2 rounded-lg', [
        span(classes: 'text-xs font-bold text-gray-700 mb-2 block', [text('Credited Creators')]),

        if (_uploadCreators.isNotEmpty)
          div(classes: 'flex-col gap-1 mb-2', [
            for (int i = 0; i < _uploadCreators.length; i++)
              div(classes: 'flex-row items-center justify-between bg-white border border-gray-150 p-2 rounded mb-1 text-xs font-medium', [
                span([text('${_uploadCreators[i]['name']} (${_uploadCreators[i]['role']})')]),
                span(
                    classes: 'material-symbols-outlined text-red-500 cursor-pointer',
                    attributes: {'style': 'font-size: 16px;'},
                    events: {
                      'click': (e) => setState(() => _uploadCreators.removeAt(i))
                    },
                    [text('remove_circle')]
                )
              ])
          ]),

        div(classes: 'flex-row gap-2 items-center', [
          div(classes: 'flex-1', [
            input(
                attributes: {'type': 'text', 'placeholder': '@handle', 'value': _newCreator_Handle ?? _newCreatorHandle, 'style': 'margin-bottom: 0; padding: 6px 12px; font-size: 12px;'}
            )
          ]),
          div(classes: 'flex-1', [
            input(
                attributes: {'type': 'text', 'placeholder': 'Role', 'value': _newCreator_Role ?? _newCreatorRole, 'style': 'margin-bottom: 0; padding: 6px 12px; font-size: 12px;'}
            )
          ]),
          span(
              classes: 'material-symbols-outlined text-green-600 cursor-pointer',
              attributes: {'style': 'font-size: 22px; padding: 2px;'},
              events: {'click': (e) => _addCreator()},
              [text('add_circle')]
          )
        ])
      ]),

      if (_uploadError != null)
        p(classes: 'error-msg mb-3', [text(_uploadError!)]),

      button(
          classes: 'btn-primary w-full',
          attributes: (_isUploadingImage || _uploadImageBase64 == null) ? {'disabled': 'true'} : {},
          events: {'click': (e) => _submitSingleImage()},
          [text(_isUploadingImage ? 'Publishing page to Folio...' : 'Publish to Folio')]
      )
    ]);
  }

  // Fallbacks to handle legacy compilation properties safely
  String? get _newCreator_Handle => null;
  String? get _newCreator_Role => null;
}