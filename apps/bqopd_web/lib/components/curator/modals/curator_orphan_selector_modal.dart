import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../../utils/web_firebase_interop.dart';

/// Selection drawer for orphan library assets inside Curator scopes.
/// Decoupled from Editor selection states.
class CuratorOrphanSelectorModal extends StatefulComponent {
  final String fanzineId;
  final String userId;
  final VoidCallback onCancel;
  final Function(List<Map<String, dynamic>>) onAddSelected;

  const CuratorOrphanSelectorModal({
    required this.fanzineId,
    required this.userId,
    required this.onCancel,
    required this.onAddSelected,
    super.key,
  });

  @override
  State<CuratorOrphanSelectorModal> createState() => _CuratorOrphanSelectorModalState();
}

class _CuratorOrphanSelectorModalState extends State<CuratorOrphanSelectorModal> {
  bool _loading = true;
  List<Map<String, dynamic>> _orphanImages = [];
  final Set<String> _selectedImageIds = {};
  dynamic _imagesUnsub;

  @override
  void initState() {
    super.initState();
    _listenToOrphans();
  }

  @override
  void dispose() {
    _imagesUnsub?.callAsFunction(); // FIXED: Changed _imagesSub to _imagesUnsub and cancel() to callAsFunction()
    super.dispose();
  }

  void _listenToOrphans() {
    _imagesUnsub?.callAsFunction(); // FIXED: Changed cancel() to callAsFunction()
    _imagesUnsub = null;

    // Listen in real-time to images uploaded by this user
    _imagesUnsub = fsListenQuery('images', 'uploaderId', '==', jsonEncode(component.userId), '', false, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr) as List;
        final images = decoded.map((d) {
          final data = d['data'] as Map<String, dynamic>;
          data['id'] = d['id'];
          return data;
        }).toList();

        // Filter out images that are already attached to this fanzine
        final orphans = images.where((img) {
          final List usedIn = img['usedInFanzines'] ?? [];
          final String? contextId = img['folioContext'];
          return contextId != component.fanzineId && !usedIn.contains(component.fanzineId);
        }).toList();

        if (mounted) {
          setState(() {
            _orphanImages = orphans;
            _loading = false;
          });
        }
      } catch (e) {
        print("Error listening to orphan library assets: $e");
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedImageIds.contains(id)) {
        _selectedImageIds.remove(id);
      } else {
        _selectedImageIds.add(id);
      }
    });
  }

  void _confirmSelection() {
    final selectedMetadata = _orphanImages
        .where((img) => _selectedImageIds.contains(img['id']))
        .toList();
    component.onAddSelected(selectedMetadata);
  }

  @override
  Component build(BuildContext context) {
    return div(
      classes: 'global-modal-overlay',
      attributes: const {
        'style': 'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.65); z-index: 20000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(6px);'
      },
      [
        div(
          attributes: const {
            'style': 'background-color: white; border-radius: 12px; width: 100%; max-width: 600px; max-height: 80vh; display: flex; flex-direction: column; overflow: hidden; box-shadow: 0 10px 25px rgba(0,0,0,0.2); text-align: left; margin: 16px; box-sizing: border-box;'
          },
          [
            // Modal Header
            div(
              attributes: const {
                'style': 'padding: 16px 20px; border-bottom: 1px solid #e5e7eb; display: flex; align-items: center; justify-content: space-between;'
              },
              [
                h2(
                  [text("Select Orphan Images to Add (${_selectedImageIds.length})")],
                  attributes: const {
                    'style': 'font-size: 16px; font-weight: bold; margin: 0; color: #1a1a1a;'
                  },
                ),
                div(
                  attributes: const {'style': 'display: flex; gap: 8px; align-items: center;'},
                  [
                    if (_selectedImageIds.isNotEmpty)
                      button(
                        [text("add selected")],
                        attributes: const {
                          'style': 'background-color: #6750A4; color: white; border: none; border-radius: 20px; padding: 6px 14px; font-size: 11px; font-weight: bold; cursor: pointer; transition: background 0.15s;'
                        },
                        events: {
                          'click': (e) => _confirmSelection(),
                        },
                      ),
                    button(
                      [text("×")],
                      attributes: const {
                        'style': 'border: none; background: #f3f4f6; border-radius: 50%; width: 28px; height: 28px; display: flex; align-items: center; justify-content: center; cursor: pointer; font-size: 14px; font-weight: bold; transition: background 0.15s;'
                      },
                      events: {
                        'click': (e) => component.onCancel(),
                      },
                    )
                  ],
                )
              ],
            ),

            // Modal Body Grid
            div(
              attributes: const {
                'style': 'padding: 20px; overflow-y: auto; flex: 1; box-sizing: border-box; min-height: 180px;'
              },
              [
                if (_loading)
                  div(
                    [text("Loading gallery...")],
                    attributes: const {
                      'style': 'text-align: center; padding: 40px 0; color: #888; font-style: italic; font-size: 13px;'
                    },
                  )
                else if (_orphanImages.isEmpty)
                  div(
                    [
                      span([text('image_not_supported')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 48px; color: #ccc;'}),
                      p([text("No orphan images available in your library.")], attributes: const {'style': 'font-size: 13px; font-style: italic; margin-top: 8px; margin-bottom: 0;'})
                    ],
                    attributes: const {
                      'style': 'display: flex; flex-direction: column; align-items: center; justify-content: center; text-align: center; padding: 40px 0; color: #888;'
                    },
                  )
                else
                  div(
                    attributes: const {
                      'style': 'display: grid; grid-template-columns: repeat(auto-fill, minmax(110px, 1fr)); gap: 12px; width: 100%; box-sizing: border-box;'
                    },
                    [
                      for (var imgData in _orphanImages)
                        _buildOrphanGridItem(imgData)
                    ],
                  )
              ],
            )
          ],
        )
      ],
    );
  }

  Component _buildOrphanGridItem(Map<String, dynamic> imgData) {
    final String imageId = imgData['id'] ?? '';
    final bool isSelected = _selectedImageIds.contains(imageId);
    final String? thumbUrl = imgData['gridUrl'] ?? imgData['fileUrl'];

    return div(
      attributes: {
        'style': 'aspect-ratio: 5/8; background-color: #f3f4f6; border-radius: 6px; overflow: hidden; border: 2.5px solid ${isSelected ? '#6750A4' : 'transparent'}; position: relative; cursor: pointer; box-shadow: 0 1px 3px rgba(0,0,0,0.1); transition: border-color 0.15s;'
      },
      events: {
        'click': (e) => _toggleSelection(imageId),
      },
      [
        if (thumbUrl != null && thumbUrl.isNotEmpty)
          img(
              src: thumbUrl,
              attributes: const {
                'style': 'width: 100%; height: 100%; object-fit: cover; display: block; -webkit-user-select: none; user-select: none;'
              }
          )
        else
          div(
              [text("no preview")],
              attributes: const {
                'style': 'display: flex; align-items: center; justify-content: center; height: 100%; color: #aaa; font-size: 11px;'
              }
          ),

        // Selected Status Icon Badge
        if (isSelected)
          div(
            [
              span(
                [text('check')],
                classes: 'material-symbols-outlined',
                attributes: const {
                  'style': 'font-size: 12px; color: white; font-weight: bold;'
                },
              )
            ],
            attributes: const {
              'style': 'position: absolute; top: 6px; right: 6px; background-color: #6750A4; border-radius: 50%; width: 20px; height: 20px; display: flex; align-items: center; justify-content: center; box-shadow: 0 1px 3px rgba(0,0,0,0.2);'
            },
          )
      ],
    );
  }
}