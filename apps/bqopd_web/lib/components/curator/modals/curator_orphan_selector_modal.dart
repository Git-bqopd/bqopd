import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../../../utils/web_utils.dart';

/// Modal dialog allowing curators to pick orphan images or library assets
/// and attach them directly to the active fanzine sequence.
class CuratorOrphanSelectorModal extends StatefulComponent {
  final String fanzineId;
  final String userId;
  final VoidCallback onCancel;
  final void Function(List<Map<String, dynamic>> selected) onAddSelected;

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
  bool _isLoading = true;
  List<Map<String, dynamic>> _orphanImages = [];
  final Set<String> _selectedImageIds = {};

  @override
  void initState() {
    super.initState();
    _loadOrphanImages();
  }

  Future<void> _loadOrphanImages() async {
    setState(() => _isLoading = true);
    try {
      final jsonStr = await fsQuery(
        'images',
        'uploaderId',
        '==',
        jsonEncode(component.userId),
        '',
      );
      final List decoded = jsonDecode(jsonStr);
      final List<Map<String, dynamic>> candidates = [];

      for (var item in decoded) {
        final data = item['data'] as Map<String, dynamic>;
        data['id'] = item['id'];
        final List usedIn = data['usedInFanzines'] ?? [];
        final String? contextId = data['folioContext'];

        // Consider as candidate if not currently used in this fanzine
        final bool isAlreadyInFolio = contextId == component.fanzineId || usedIn.contains(component.fanzineId);
        if (!isAlreadyInFolio) {
          candidates.add(data);
        }
      }

      candidates.sort((a, b) {
        final aT = a['timestamp'] ?? a['createdAt'] ?? '';
        final bT = b['timestamp'] ?? b['createdAt'] ?? '';
        return bT.toString().compareTo(aT.toString());
      });

      if (mounted) {
        setState(() {
          _orphanImages = candidates;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error loading orphan images in curator modal: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
    final selectedDocs = _orphanImages
        .where((img) => _selectedImageIds.contains(img['id']))
        .toList();
    component.onAddSelected(selectedDocs);
  }

  @override
  Component build(BuildContext context) {
    final selectedCount = _selectedImageIds.length;

    return div(
      classes: 'global-modal-overlay',
      attributes: const {
        'style':
        'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0, 0, 0, 0.65); z-index: 10000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(4px);'
      },
      [
        div(
          classes: 'white-sticker shadow-lg',
          attributes: const {
            'style':
            'width: 90%; max-width: 640px; max-height: 80vh; background: white; border-radius: 12px; padding: 24px; box-sizing: border-box; display: flex; flex-direction: column; gap: 16px;'
          },
          [
            // Header Bar
            div(
              attributes: const {
                'style':
                'display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #eee; padding-bottom: 12px;'
              },
              [
                h3(
                  [Component.text('Select Images from Library')],
                  attributes: const {
                    'style':
                    'margin: 0; font-size: 16px; font-weight: bold; color: #111;'
                  },
                ),
                span(
                  [Component.text('${_orphanImages.length} available')],
                  attributes: const {'style': 'font-size: 12px; color: #888;'},
                ),
              ],
            ),

            // Content Area
            if (_isLoading)
              div(
                [Component.text('Loading candidate images...')],
                attributes: const {
                  'style':
                  'padding: 40px; text-align: center; color: #888; font-size: 13px; font-style: italic;'
                },
              )
            else if (_orphanImages.isEmpty)
              div(
                attributes: const {
                  'style':
                  'padding: 40px; text-align: center; color: #888; font-size: 13px; font-style: italic;'
                },
                [
                  span(
                    [Component.text('photo_library')],
                    classes: 'material-symbols-outlined',
                    attributes: const {'style': 'font-size: 36px; color: #ccc; margin-bottom: 8px; display: block;'},
                  ),
                  Component.text('No available orphan images found in your master library.'),
                ],
              )
            else
              div(
                attributes: const {
                  'style':
                  'display: grid; grid-template-columns: repeat(auto-fill, minmax(110px, 1fr)); gap: 10px; overflow-y: auto; max-height: 50vh; padding: 4px;'
                },
                [
                  for (var img in _orphanImages)
                    _buildImageTile(img),
                ],
              ),

            // Footer Action Bar
            div(
              attributes: const {
                'style':
                'display: flex; justify-content: flex-end; gap: 10px; border-top: 1px solid #eee; padding-top: 12px; margin-top: auto;'
              },
              [
                button(
                  [Component.text('cancel')],
                  classes: 'profile-btn',
                  attributes: const {
                    'type': 'button',
                    'style':
                    'padding: 8px 16px; font-size: 11px; font-weight: bold; border: 1px solid #ccc; background: white; color: #444; border-radius: 6px; cursor: pointer;'
                  },
                  events: {
                    'click': (e) => component.onCancel(),
                  },
                ),
                button(
                  [Component.text(selectedCount > 0 ? 'add selected ($selectedCount)' : 'add selected')],
                  attributes: {
                    'type': 'button',
                    'style':
                    'padding: 8px 18px; font-size: 11px; font-weight: bold; border: none; border-radius: 6px; cursor: ${selectedCount > 0 ? "pointer" : "default"}; color: white; background-color: ${selectedCount > 0 ? "#6750A4" : "#ccc"};',
                    if (selectedCount == 0) 'disabled': 'true',
                  },
                  events: {
                    'click': (e) {
                      if (selectedCount > 0) {
                        _confirmSelection();
                      }
                    },
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Component _buildImageTile(Map<String, dynamic> imageDoc) {
    final String id = imageDoc['id'] ?? '';
    final String? optimalUrl = imageDoc['gridUrl'] ?? imageDoc['fileUrl'];
    final String title = imageDoc['title'] ?? imageDoc['fileName'] ?? 'untitled';
    final int width = imageDoc['width'] ?? 0;
    final int height = imageDoc['height'] ?? 0;
    final bool isSelected = _selectedImageIds.contains(id);

    return div(
      attributes: {
        'style':
        'aspect-ratio: 5 / 8; background-color: #f5f5f5; border: 2px solid ${isSelected ? "#6750A4" : "rgba(0,0,0,0.1)"}; border-radius: 6px; position: relative; overflow: hidden; cursor: pointer; box-shadow: 0 1px 3px rgba(0,0,0,0.05);'
      },
      events: {
        'click': (e) => _toggleSelection(id),
      },
      [
        if (optimalUrl != null && optimalUrl.isNotEmpty)
          img(
            src: optimalUrl,
            attributes: const {'style': 'width: 100%; height: 100%; object-fit: cover; display: block;'},
          )
        else
          div(
            [Component.text('no preview')],
            attributes: const {
              'style':
              'display: flex; align-items: center; justify-content: center; height: 100%; color: #aaa; font-size: 10px;'
            },
          ),
        // Selection Checkmark Badge
        if (isSelected)
          div(
            [
              span(
                [Component.text('check_circle')],
                classes: 'material-symbols-outlined',
                attributes: const {'style': 'font-size: 20px; color: #6750A4; background: white; border-radius: 50%;'},
              )
            ],
            attributes: const {
              'style': 'position: absolute; top: 4px; right: 4px;'
            },
          ),
        // Dimension badge
        div(
          [Component.text('${width}x$height')],
          attributes: const {
            'style':
            'position: absolute; top: 4px; left: 4px; background: rgba(0,0,0,0.65); color: white; font-size: 8px; font-weight: bold; border-radius: 3px; padding: 2px 4px;'
          },
        ),
        // Bottom Title Label
        div(
          [
            span(
              [Component.text(title.toLowerCase())],
              attributes: const {
                'style':
                'font-size: 8px; color: white; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; display: block; text-align: center;'
              },
            )
          ],
          attributes: const {
            'style':
            'position: absolute; bottom: 0; left: 0; right: 0; background-color: rgba(0,0,0,0.65); padding: 4px 6px; text-align: center;'
          },
        ),
      ],
    );
  }
}