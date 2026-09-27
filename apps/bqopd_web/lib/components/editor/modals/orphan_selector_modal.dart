import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../../../utils/web_utils.dart';
import '../../fanzine_thumbnail_card.dart';

/// Modal dialog allowing users to pick orphan images or library assets
/// and attach them directly to the active fanzine sequence.
/// Renders library candidates in a 3-column grid of FanzineThumbnailCards,
/// sorted with the newest uploads at the top and oldest at the bottom.
class OrphanSelectorModal extends StatefulComponent {
  final String fanzineId;
  final String userId;
  final VoidCallback onCancel;
  final void Function(List<Map<String, dynamic>> selected) onAddSelected;

  const OrphanSelectorModal({
    required this.fanzineId,
    required this.userId,
    required this.onCancel,
    required this.onAddSelected,
    super.key,
  });

  @override
  State<OrphanSelectorModal> createState() => _OrphanSelectorModalState();
}

class _OrphanSelectorModalState extends State<OrphanSelectorModal> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _orphanImages = [];
  final Set<String> _selectedImageIds = {};

  @override
  void initState() {
    super.initState();
    _loadOrphanImages();
  }

  int _compareTimestamps(Map<String, dynamic> a, Map<String, dynamic> b) {
    int extractMillis(dynamic val) {
      if (val == null) return 0;
      if (val is int) return val;
      if (val is num) return val.toInt();
      if (val is DateTime) return val.millisecondsSinceEpoch;
      if (val is Map) {
        if (val['iso'] != null) {
          final dt = DateTime.tryParse(val['iso'].toString());
          if (dt != null) return dt.millisecondsSinceEpoch;
        }
        if (val['seconds'] != null) {
          return ((val['seconds'] as num) * 1000).toInt();
        }
      }
      if (val is String) {
        final dt = DateTime.tryParse(val);
        if (dt != null) return dt.millisecondsSinceEpoch;
        final asInt = int.tryParse(val);
        if (asInt != null) return asInt;
      }
      return 0;
    }

    final aTime = extractMillis(a['timestamp'] ?? a['createdAt']);
    final bTime = extractMillis(b['timestamp'] ?? b['createdAt']);
    // Descending order: newest at top, oldest at bottom
    if (aTime != bTime) {
      return bTime.compareTo(aTime);
    }
    return (b['id'] ?? '').toString().compareTo((a['id'] ?? '').toString());
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

      // Sort newest at the top, oldest at the bottom
      candidates.sort((a, b) => _compareTimestamps(a, b));

      if (mounted) {
        setState(() {
          _orphanImages = candidates;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error loading orphan images in modal: $e");
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
        .where((imageDoc) => _selectedImageIds.contains(imageDoc['id']))
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
          attributes: const {
            'style':
            'width: 90%; max-width: 720px; max-height: 85vh; background: white; border-radius: 12px; padding: 24px; box-sizing: border-box; display: flex; flex-direction: column; gap: 16px; align-items: stretch; position: relative; box-shadow: 0 10px 25px rgba(0,0,0,0.2);'
          },
          [
            // Header Bar
            div(
              attributes: const {
                'style':
                'display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #eee; padding-bottom: 12px; width: 100%;'
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
                  attributes: const {'style': 'font-size: 12px; color: #888; font-weight: 500;'},
                ),
              ],
            ),
            if (_isLoading)
              div(
                [
                  span(
                    [Component.text('progress_activity')],
                    classes: 'material-symbols-outlined',
                    attributes: const {
                      'style':
                      'font-size: 32px; color: #6750A4; animation: spin 1s linear infinite; margin-bottom: 8px;'
                    },
                  ),
                  p(
                    [Component.text('Loading library images...')],
                    attributes: const {
                      'style':
                      'margin: 0; color: #888; font-size: 13px; font-style: italic;'
                    },
                  )
                ],
                attributes: const {
                  'style':
                  'padding: 60px 16px; display: flex; flex-direction: column; align-items: center; justify-content: center; width: 100%; box-sizing: border-box;'
                },
              )
            else if (_orphanImages.isEmpty)
              div(
                attributes: const {
                  'style':
                  'padding: 60px 16px; text-align: center; color: #888; font-size: 13px; font-style: italic; display: flex; flex-direction: column; align-items: center; justify-content: center; width: 100%; box-sizing: border-box;'
                },
                [
                  span(
                    [Component.text('photo_library')],
                    classes: 'material-symbols-outlined',
                    attributes: const {'style': 'font-size: 40px; color: #ccc; margin-bottom: 8px; display: block;'},
                  ),
                  Component.text('No available orphan images found in your master library.'),
                ],
              )
            else
              div(
                attributes: const {
                  'style':
                  'display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 14px; overflow-y: auto; max-height: 60vh; width: 100%; box-sizing: border-box; padding: 4px;'
                },
                [
                  for (var imageDoc in _orphanImages)
                    _buildCardItem(imageDoc),
                ],
              ),
            div(
              attributes: const {
                'style':
                'display: flex; justify-content: flex-end; gap: 10px; border-top: 1px solid #eee; padding-top: 14px; margin-top: auto; width: 100%;'
              },
              [
                button(
                  [Component.text('cancel')],
                  classes: 'profile-btn',
                  attributes: const {
                    'type': 'button',
                    'style':
                    'padding: 8px 18px; font-size: 11px; font-weight: bold; border: 1px solid #ccc; background: white; color: #444; border-radius: 6px; cursor: pointer;'
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
                    'padding: 8px 20px; font-size: 11px; font-weight: bold; border: none; border-radius: 6px; cursor: ${selectedCount > 0 ? "pointer" : "default"}; color: white; background-color: ${selectedCount > 0 ? "#6750A4" : "#ccc"}; transition: background-color 0.2s;',
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

  Component _buildCardItem(Map<String, dynamic> imageDoc) {
    final String id = imageDoc['id'] ?? '';
    final String? optimalUrl =
        imageDoc['gridUrl'] ?? imageDoc['fileUrl'] ?? imageDoc['imageUrl'];
    final String rawTitle =
        imageDoc['title'] ?? imageDoc['fileName'] ?? 'untitled';
    final bool isSelected = _selectedImageIds.contains(id);

    final cardData = Map<String, dynamic>.from(imageDoc);
    cardData['title'] = rawTitle;

    return div(
      classes: 'transition-all',
      attributes: {
        'style':
        'position: relative; cursor: pointer; box-sizing: border-box; '
            'outline: ${isSelected ? "3px solid #6750A4" : "none"}; '
            'outline-offset: 2px; '
            'background-color: ${isSelected ? "rgba(103, 80, 164, 0.04)" : "transparent"};',
      },
      events: {
        'click': (dynamic e) {
          _toggleSelection(id);
        },
      },
      [
        FanzineThumbnailCard(
          fanzineData: cardData,
          customCoverUrl: optimalUrl,
          cardType: 'image',
          key: ValueKey('orphan_card_$id'),
          onCardTap: () => _toggleSelection(id),
          onMenuTap: () => _toggleSelection(id),
        ),
        if (isSelected)
          div(
            [
              span(
                [Component.text('check_circle')],
                classes: 'material-symbols-outlined',
                attributes: const {
                  'style':
                  'font-size: 26px; color: #6750A4; background: white; border-radius: 50%; display: block;'
                },
              ),
            ],
            attributes: const {
              'style':
              'position: absolute; top: 6px; right: 6px; z-index: 10; pointer-events: none; filter: drop-shadow(0 1px 2px rgba(0,0,0,0.3));'
            },
          ),
      ],
    );
  }
}