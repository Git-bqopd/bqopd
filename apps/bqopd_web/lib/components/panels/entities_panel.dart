import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';
import '../../repositories/repositories.dart';

/// The 'entities' social panel displaying Cards for any [[wiki-linked]] text.
/// Aligns with Clean Architecture by utilizing abstract Repository interfaces.
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

  final IUserRepository _userRepo = createUserRepository();
  final IUploadRepository _uploadRepo = createUploadRepository();

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
              _userRepo.watchUser(uid).first.then((profile) {
                if (profile != null) {
                  tempProfiles[uid] = profile.toMap();
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
      // Find matching profile username cleanly via abstract repository
      final result = await _uploadRepo.lookupUserByHandle(cleanHandle);

      if (result == null) {
        setState(() {
          _modalError = 'Profile @$cleanHandle not found in database.';
          _modalSaving = false;
        });
        return;
      }

      final targetUid = result['uid'];

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
      return div(
        [
          div([], classes: 'skeleton-line shimmer-bg', attributes: const {'style': 'height: 12px; border-radius: 4px; width: 100%;'}),
          div([], classes: 'skeleton-line medium shimmer-bg', attributes: const {'style': 'height: 12px; border-radius: 4px; width: 85%;'}),
          div([], classes: 'skeleton-line shimmer-bg', attributes: const {'style': 'height: 12px; border-radius: 4px; width: 100%;'}),
          div([], classes: 'skeleton-line short shimmer-bg', attributes: const {'style': 'height: 12px; border-radius: 4px; width: 60%;'}),
        ],
        classes: 'flex-col gap-2 py-4',
        attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px; width: 100%;'},
      );
    }

    if (_entities.isEmpty) {
      return div(
        [text('No entity links found in page text.')],
        classes: 'p-6 text-center text-gray italic text-xs',
      );
    }

    return div(
      [
        for (var entity in _entities)
          _buildEntityCard(entity),

        if (_editingEntity != null)
          _buildEditModal()
      ],
      classes: 'flex-col gap-3',
      attributes: const {'style': 'display: flex; flex-direction: column; gap: 12px; width: 100%;'},
    );
  }

  Component _buildEntityCard(EntityLink entity) {
    final String? uid = entity.ref != null && entity.ref!.startsWith('user:') ? entity.ref!.substring(5) : null;
    final Map<String, dynamic>? profile = uid != null ? _loadedProfiles[uid] : null;

    final bool isLinked = profile != null;
    final String labelText = isLinked ? (profile['displayName'] ?? entity.label) : entity.label;
    final String? username = isLinked ? profile['username'] : null;
    final String? photoUrl = isLinked ? profile['photoUrl'] : null;

    return div(
      [
        div(
          [
            div(
              [
                if (photoUrl != null && photoUrl.isNotEmpty)
                  img(
                      src: photoUrl,
                      attributes: const {'style': 'width: 100%; height: 100%; object-fit: cover; display: block;'}
                  )
                else
                  div(
                    [text(labelText.isNotEmpty ? labelText[0].toUpperCase() : '?')],
                    classes: 'user-avatar-placeholder',
                    attributes: const {'style': 'font-size: 14px; font-weight: bold; color: #9ca3af;'},
                  )
              ],
              classes: 'user-avatar-container',
              attributes: const {'style': 'width: 32px; height: 32px; border-radius: 50%; overflow: hidden; background-color: #f1f1f1; flex-shrink: 0; display: flex; align-items: center; justify-content: center; border: 1px solid rgba(0,0,0,0.05);'},
            ),

            div(
              [
                div([text(labelText)], classes: 'user-display-name', attributes: const {'style': 'font-size: 13px; font-weight: bold; color: black; line-height: 1.2;'}),
                if (username != null)
                  div([text('@$username')], classes: 'text-xs text-gray', attributes: const {'style': 'color: #555555; font-size: 11px; font-weight: 500; margin-top: 2px;'})
              ],
              classes: 'user-info',
              attributes: const {'style': 'display: flex; flex-direction: column; justify-content: center;'},
            )
          ],
          classes: 'user-tile',
          attributes: const {'style': 'display: flex; flex-direction: row; align-items: center; gap: 12px;'},
        ),

        if (component.isEditingMode)
          span(classes: 'material-symbols-outlined text-gray', attributes: const {'style': 'font-size: 18px; color: #79747E;'}, [
            text(isLinked ? 'edit_note' : 'link_off')
          ])
        else if (isLinked)
          span(classes: 'material-symbols-outlined text-indigo-600', attributes: const {'style': 'font-size: 18px; color: #6750A4;'}, [
            text('arrow_forward_ios')
          ])
      ],
      classes: 'hover:shadow-md transition-all',
      attributes: const {
        'style': 'display: flex; flex-direction: row; align-items: center; justify-content: space-between; padding: 16px; margin-bottom: 12px; cursor: pointer; background-color: #ffffff; border: 1px solid #e2e8f0; border-radius: 12px; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.04); width: 100%; box-sizing: border-box;'
      },
    );
  }

  Component _buildEditModal() {
    return div(
      [
        div(
          [
            div(
              [
                div(
                  [
                    div(
                      [
                        h2([text('Link Entity')], attributes: const {'style': 'font-size: 16px; font-weight: bold; margin-bottom: 4px; margin-top: 0;'}),
                        p(
                            [
                              text('Set the target profile username to link with "'),
                              span([text(_editingEntity!.label)], attributes: const {'style': 'font-weight: bold; color: #6750A4;'}),
                              text('".')
                            ],
                            attributes: const {'style': 'font-size: 12px; color: #555; line-height: 1.4; margin: 0;'}
                        ),

                        div(
                          [
                            input(
                                attributes: {
                                  'type': 'text',
                                  'placeholder': '@username / handle',
                                  'value': _handleInput,
                                  'style': 'width: 100%; padding: 10px; border: 1px solid #ccc; border-radius: 8px; box-sizing: border-box; outline: none; background: white;'
                                },
                                events: {
                                  'input': (e) => _handleInput = getInputValue(e)
                                }
                            ),
                            if (_modalError != null)
                              p([text(_modalError!)], classes: 'error-msg mt-2', attributes: const {'style': 'font-size: 11px; margin-top: 4px; color: #ef4444;'})
                          ],
                          classes: 'flex-col w-full mt-4',
                          attributes: const {'style': 'display: flex; flex-direction: column; width: 100%; margin-top: 16px;'},
                        )
                      ],
                      classes: 'flex-col w-full text-left',
                      attributes: const {'style': 'display: flex; flex-direction: column; width: 100%; text-align: left;'},
                    ),

                    div(
                      [
                        if (_editingEntity!.ref != null)
                          button(
                            [text('Unlink')],
                            classes: 'profile-btn text-red-500',
                            attributes: const {'style': 'padding: 8px 16px; font-size: 12px; cursor: pointer; margin-right: auto; border: 1px solid #ff5252; color: #ff5252; border-radius: 4px; background: white;'},
                            events: {
                              'click': (e) => _unlinkEntity()
                            },
                          ),
                        button(
                          [text('Cancel')],
                          classes: 'profile-btn',
                          attributes: const {'style': 'padding: 8px 16px; font-size: 12px; cursor: pointer; border: 1px solid #ccc; border-radius: 4px; background: white; color: #374151;'},
                          events: {
                            'click': (e) {
                              setState(() {
                                _editingEntity = null;
                                _modalError = null;
                                _handleInput = '';
                              });
                            }
                          },
                        ),
                        button(
                          [text(_modalSaving ? 'Saving...' : 'Save Link')],
                          classes: 'btn-primary nav-pill mb-0',
                          attributes: {
                            'style': 'padding: 8px 16px; font-size: 12px; height: 32px; display: inline-flex; align-items: center; width: auto; background-color: #6750A4; border: none; border-radius: 50px; color: white; cursor: pointer;',
                            if (_modalSaving) 'disabled': 'true'
                          },
                          events: {
                            'click': (e) => _saveEntityLink()
                          },
                        )
                      ],
                      classes: 'flex-row gap-2 mt-4 justify-end w-full',
                      attributes: const {'style': 'display: flex; flex-direction: row; gap: 8px; width: 100%; align-items: center; justify-content: flex-end; margin-top: 16px;'},
                    )
                  ],
                  classes: 'white-sticker p-6 w-full h-full flex flex-col justify-between items-center',
                  attributes: const {'style': 'display: flex; flex-direction: column; justify-content: space-between; align-items: center; width: 100%; height: 100%; box-sizing: border-box;'},
                )
              ],
              classes: 'manila-envelope',
              attributes: const {
                'style': 'max-width: 400px; max-height: 480px; border-radius: 12px; overflow: hidden; position: relative; width: 100%;'
              },
            )
          ],
          classes: 'global-modal-overlay',
          attributes: const {
            'style': 'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.6); z-index: 10000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(4px);'
          },
        )
      ],
    );
  }
}