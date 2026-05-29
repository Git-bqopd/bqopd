import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';

/// The 'entities' social panel displaying Cards for any [[wiki-linked]] text.
/// Allows curators to link/unlink handles to profiles, and readers to tap and navigate.
class EntitiesPanel extends StatefulComponent {
  final String imageId;
  final String? fanzineId;
  final bool isEditingMode;

  const EntitiesPanel({
    required this.imageId,
    this.fanzineId,
    required this.isEditingMode,
    super.key,
  });

  @override
  State<EntitiesPanel> createState() => _EntitiesPanelState();
}

class EntityLink {
  final String label;
  final String? ref; // user:uid
  final String rawMatch;
  EntityLink({required this.label, this.ref, required this.rawMatch});
}

class _ListEntry {
  final String uid;
  final String displayName;
  final String username;
  _ListEntry({required this.uid, required this.displayName, required this.username});
}

class _EntitiesPanelState extends State<EntitiesPanel> {
  List<EntityLink> _entities = [];
  Map<String, Map<String, dynamic>> _loadedProfiles = {};
  String _rawFullText = '';
  bool _loading = true;

  // Modal Editing State
  EntityLink? _editingEntity;
  String _handleInput = '';
  bool _modalSaving = false;
  String? _modalError;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loadTextData();
    }
  }

  @override
  void didUpdateComponent(EntitiesPanel oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.imageId != component.imageId && kIsWeb) {
      _loadTextData();
    }
  }

  Future<void> _loadTextData() async {
    if (component.imageId.isEmpty) {
      setState(() {
        _entities = [];
        _loading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final res = await fsGetDoc('images/${component.imageId}');
      final doc = jsonDecode(res);
      if (doc['exists'] && mounted) {
        final data = doc['data'] as Map<String, dynamic>;

        final textLinked = data['text_linked'] ?? '';
        final textCorrected = data['text_corrected'] ?? data['text'] ?? '';
        final textRaw = data['text_raw'] ?? '';

        _rawFullText = textLinked.isNotEmpty ? textLinked : (textCorrected.isNotEmpty ? textCorrected : textRaw);

        // Parse wiki links [[Label]] or [[Label|user:uid]]
        final regex = RegExp(r'\[\[(.*?)(?:\|(.*?))?\]\]');
        final matches = regex.allMatches(_rawFullText);
        final List<EntityLink> parsed = [];

        for (final m in matches) {
          final label = m.group(1)?.trim() ?? '';
          final ref = m.group(2)?.trim();
          final raw = m.group(0) ?? '';
          if (label.isNotEmpty) {
            parsed.add(EntityLink(label: label, ref: ref, rawMatch: raw));
          }
        }

        setState(() {
          _entities = parsed;
          _loading = false;
        });

        // Load profiles for linked entities in parallel
        _loadEntityProfiles(parsed);
      } else {
        setState(() {
          _entities = [];
          _loading = false;
        });
      }
    } catch (e) {
      print('[ENTITIES PANEL ERROR] Failed loading: $e');
      setState(() {
        _entities = [];
        _loading = false;
      });
    }
  }

  Future<void> _loadEntityProfiles(List<EntityLink> links) async {
    final Map<String, Map<String, dynamic>> tempProfiles = {};
    final List<Future<void>> fetches = [];

    for (var link in links) {
      if (link.ref != null && link.ref!.startsWith('user:')) {
        final uid = link.ref!.substring(5);
        if (!tempProfiles.containsKey(uid)) {
          fetches.add(
              fsGetDoc('profiles/$uid').then((res) {
                final doc = jsonDecode(res);
                if (doc['exists'] == true) {
                  tempProfiles[uid] = doc['data'] as Map<String, dynamic>;
                }
              }).catchError((e) {
                print('Error loading profile $uid: $e');
              })
          );
        }
      }
    }

    if (fetches.isNotEmpty) {
      await Future.wait(fetches);
      if (mounted) {
        setState(() {
          _loadedProfiles = tempProfiles;
        });
      }
    }
  }

  void _onEntityTap(EntityLink entity) {
    if (component.isEditingMode) {
      // Open link configuration dialog
      String initialHandle = '';
      if (entity.ref != null && entity.ref!.startsWith('user:')) {
        final uid = entity.ref!.substring(5);
        initialHandle = _loadedProfiles[uid]?['username'] ?? '';
      }

      setState(() {
        _editingEntity = entity;
        _handleInput = initialHandle;
        _modalError = null;
        _modalSaving = false;
      });
    } else {
      // In Reader Mode: Tap to Navigate if linked
      if (entity.ref != null && entity.ref!.startsWith('user:')) {
        final uid = entity.ref!.substring(5);
        final String? username = _loadedProfiles[uid]?['username'];
        if (username != null && username.isNotEmpty) {
          Router.of(context).push('/$username');
        }
      }
    }
  }

  Future<void> _saveEntityLink() async {
    final entity = _editingEntity;
    if (entity == null || _modalSaving) return;

    final cleanHandle = _handleInput.trim().toLowerCase().replaceAll('@', '');
    if (cleanHandle.isEmpty) {
      setState(() => _modalError = 'Please enter a valid username.');
      return;
    }

    setState(() {
      _modalSaving = true;
      _modalError = null;
    });

    try {
      // Find matching profile username
      final resStr = await fsQuery('profiles', 'username', '==', jsonEncode(cleanHandle), '');
      final List docs = jsonDecode(resStr);

      if (docs.isEmpty) {
        setState(() {
          _modalError = 'Profile @$cleanHandle not found in database.';
          _modalSaving = false;
        });
        return;
      }

      final targetDoc = docs.first;
      final targetUid = targetDoc['id'];

      // Update string text replacement
      final String replacement = "[[${entity.label}|user:$targetUid]]";
      final String updatedText = _rawFullText.replaceAll(entity.rawMatch, replacement);

      await fsUpdateDoc('images/${component.imageId}', jsonEncode({
        'text_linked': updatedText,
        'needs_linking': false,
      }));

      // Bubble up manual entities list to parent fanzine
      if (component.fanzineId != null) {
        await fsUpdateDoc('fanzines/${component.fanzineId}', jsonEncode({
          'draftEntities': WebFieldValue.arrayUnion([entity.label])
        }));
      }

      setState(() {
        _editingEntity = null;
        _handleInput = '';
        _modalSaving = false;
        _modalError = null;
      });

      // Reload text content locally
      _loadTextData();
    } catch (e) {
      setState(() {
        _modalError = 'Save failed: $e';
        _modalSaving = false;
      });
    }
  }

  Future<void> _unlinkEntity() async {
    final entity = _editingEntity;
    if (entity == null || _modalSaving) return;

    setState(() {
      _modalSaving = true;
      _modalError = null;
    });

    try {
      final String replacement = "[[${entity.label}]]";
      final String updatedText = _rawFullText.replaceAll(entity.rawMatch, replacement);

      await fsUpdateDoc('images/${component.imageId}', jsonEncode({
        'text_linked': updatedText,
      }));

      setState(() {
        _editingEntity = null;
        _handleInput = '';
        _modalSaving = false;
        _modalError = null;
      });

      _loadTextData();
    } catch (e) {
      setState(() {
        _modalError = 'Unlink failed: $e';
        _modalSaving = false;
      });
    }
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(classes: 'flex-col gap-2 py-4', [
        div(classes: 'skeleton-line shimmer-bg', []),
        div(classes: 'skeleton-line medium shimmer-bg', []),
        div(classes: 'skeleton-line shimmer-bg', []),
        div(classes: 'skeleton-line short shimmer-bg', []),
      ]);
    }

    if (_entities.isEmpty) {
      return div(classes: 'p-6 text-center text-gray italic text-xs', [
        text('No entity links found in page text.')
      ]);
    }

    return div(classes: 'flex-col gap-3', [
      for (var entity in _entities)
        _buildEntityCard(entity),

      if (_editingEntity != null)
        _buildEditModal()
    ]);
  }

  Component _buildEntityCard(EntityLink entity) {
    final String? uid = entity.ref != null && entity.ref!.startsWith('user:') ? entity.ref!.substring(5) : null;
    final Map<String, dynamic>? profile = uid != null ? _loadedProfiles[uid] : null;

    final bool isLinked = profile != null;
    final String labelText = isLinked ? (profile['displayName'] ?? entity.label) : entity.label;
    final String? username = isLinked ? profile['username'] : null;
    final String? photoUrl = isLinked ? profile['photoUrl'] : null;

    return div(
        classes: 'hover:shadow-md transition-all',
        attributes: {
          'style': 'display: flex; flex-direction: row; align-items: center; justify-content: space-between; '
              'padding: 16px; margin-bottom: 12px; cursor: pointer; '
              'background-color: #ffffff; border: 1px solid #e2e8f0; border-radius: 12px; '
              'box-shadow: 0 2px 4px rgba(0, 0, 0, 0.04);'
        },
        events: {
          'click': (e) => _onEntityTap(entity)
        },
        [
          div(classes: 'user-tile', [
            // Left Card Leading: Image or Letter avatar
            div(classes: 'user-avatar-container', [
              if (photoUrl != null && photoUrl.isNotEmpty)
                img(classes: 'user-avatar', src: photoUrl, attributes: const {'style': 'width: 100%; height: 100%; object-fit: cover;'})
              else
                div(classes: 'user-avatar-placeholder', [
                  text(labelText.isNotEmpty ? labelText[0].toUpperCase() : '?')
                ])
            ]),

            // Center Card Info: Label Text / Supporting Text
            div(classes: 'user-info', [
              div(classes: 'user-display-name', [text(labelText)]),
              if (username != null)
                div(classes: 'text-xs text-gray', attributes: const {'style': 'color: #555; font-size: 11px; font-weight: 500;'}, [text('@$username')])
            ])
          ]),

          // Card action indicator
          if (component.isEditingMode)
            span(classes: 'material-symbols-outlined text-gray', attributes: const {'style': 'font-size: 18px; color: #79747E;'}, [
              text(isLinked ? 'edit_note' : 'link_off')
            ])
          else if (isLinked)
            span(classes: 'material-symbols-outlined text-indigo-600', attributes: const {'style': 'font-size: 18px;'}, [
              text('arrow_forward_ios')
            ])
        ]
    );
  }

  Component _buildEditModal() {
    return div(classes: 'global-modal-overlay', attributes: const {
      'style': 'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.6); z-index: 10000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(4px);'
    }, [
      div(classes: 'manila-envelope', attributes: const {
        'style': 'max-width: 400px; max-height: 480px; border-radius: 12px; overflow: hidden; position: relative;'
      }, [
        div(classes: 'white-sticker p-6 w-full h-full flex flex-col justify-between items-center', [
          div(classes: 'flex-col w-full text-left', [
            h2([text('Link Entity')], attributes: const {'style': 'font-size: 16px; font-weight: bold; margin-bottom: 4px;'}),
            p([
              text('Set the target profile username to link with "'),
              span([text(_editingEntity!.label)], attributes: const {'style': 'font-weight: bold; color: #6750A4;'}),
              text('".')
            ], attributes: const {'style': 'font-size: 12px; color: #555; line-height: 1.4;'}),

            div(classes: 'flex-col w-full mt-4', [
              input(
                  attributes: {
                    'type': 'text',
                    'placeholder': '@username / handle',
                    'value': _handleInput,
                    'style': 'width: 100%; padding: 10px; border: 1px solid #ccc; border-radius: 8px; box-sizing: border-box; outline: none;'
                  },
                  events: {
                    'input': (e) => _handleInput = getInputValue(e)
                  }
              ),
              if (_modalError != null)
                p([text(_modalError!)], classes: 'error-msg mt-2', attributes: const {'style': 'font-size: 11px; margin-top: 4px;'})
            ])
          ]),

          div(classes: 'flex-row gap-2 mt-4 justify-end w-full', attributes: const {'style': 'display: flex; gap: 8px; width: 100%;'}, [
            if (_editingEntity!.ref != null)
              button(
                  classes: 'profile-btn text-red-500',
                  attributes: const {'style': 'padding: 8px 16px; font-size: 12px; cursor: pointer; margin-right: auto; border: 1px solid #ff5252; color: #ff5252;'},
                  events: {
                    'click': (e) => _unlinkEntity()
                  },
                  [text('Unlink')]
              ),
            button(
                classes: 'profile-btn',
                attributes: const {'style': 'padding: 8px 16px; font-size: 12px; cursor: pointer;'},
                events: {
                  'click': (e) {
                    setState(() {
                      _editingEntity = null;
                      _modalError = null;
                      _handleInput = '';
                    });
                  }
                },
                [text('Cancel')]
            ),
            button(
                classes: 'btn-primary nav-pill mb-0',
                attributes: {
                  'style': 'padding: 8px 16px; font-size: 12px; height: 32px; display: inline-flex; align-items: center; width: auto; background-color: #6750A4; color: white;',
                  if (_modalSaving) 'disabled': 'true'
                },
                events: {
                  'click': (e) => _saveEntityLink()
                },
                [text(_modalSaving ? 'Saving...' : 'Save Link')]
            )
          ])
        ])
      ])
    ]);
  }
}