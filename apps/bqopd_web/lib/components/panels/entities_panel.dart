import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart' hide initAddressAutocomplete;
import '../../utils/web_utils.dart';
import '../../repositories/repositories.dart';

/// The 'entities' social panel displaying Cards for any [[wiki-linked]] text.
/// Supports both Person (user:uid) and Place (address:normalized_address) types.
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
  final String label; // The Canonical Name/Display Address
  final String? ref; // user:uid or address:normalized_address
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
  String _entityType = 'person'; // 'person' or 'place'
  String _handleInput = '';      // For Person type
  String _addressInput = '';     // For Place type
  bool _modalSaving = false;
  String? _modalError;
  String? _suggestedHandle;

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

  String _normalize(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
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

        // Parse wiki links [[Label]] with support for multi-part layout structures
        final regex = RegExp(r'\[\[(.*?)\]\]');
        final matches = regex.allMatches(_rawFullText);
        final Map<String, EntityLink> uniqueEntities = {};

        for (final m in matches) {
          final content = m.group(1) ?? '';
          final parts = content.split('|');
          final raw = m.group(0) ?? '';
          if (parts.isNotEmpty && parts[0].trim().isNotEmpty) {
            final canonical = parts[0].trim();
            String? ref;

            if (parts.length == 2 && parts[1].contains(':')) {
              ref = parts[1].trim();
            } else if (parts.length >= 3) {
              ref = parts[2].trim();
            }

            final key = canonical.toLowerCase();
            // If the entity doesn't exist yet OR has a more complete reference, insert/upgrade it
            if (!uniqueEntities.containsKey(key) || (ref != null && uniqueEntities[key]!.ref == null)) {
              uniqueEntities[key] = EntityLink(label: canonical, ref: ref, rawMatch: raw);
            }
          }
        }

        setState(() {
          _entities = uniqueEntities.values.toList();
          _loading = false;
        });

        // Load profiles for linked user entities in parallel
        _loadEntityProfiles(_entities);
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

  Future<void> _findSuggestedHandle(EntityLink entity) async {
    if (!mounted) return;
    setState(() {
      _suggestedHandle = null;
    });

    final String label = entity.label;
    final String handle = _normalize(label);

    try {
      final String userRes = await fsGetDoc('usernames/$handle');
      final Map<String, dynamic> doc = jsonDecode(userRes);
      if (doc['exists'] == true) {
        final Map<String, dynamic> data = doc['data'] as Map<String, dynamic>? ?? {};
        String targetHandle = handle;
        if (data['isAlias'] == true && data['redirect'] != null) {
          targetHandle = data['redirect'];
        }
        if (mounted) {
          setState(() {
            _suggestedHandle = targetHandle;
          });
          return;
        }
      }
    } catch (e) {
      print('[EntitiesPanel _findSuggestedHandle] Error checking usernames: $e');
    }

    if (component.fanzineId != null && component.fanzineId!.isNotEmpty) {
      try {
        final imagesRes = await fsQuery('images', 'usedInFanzines', 'array-contains', jsonEncode(component.fanzineId), '');
        final List decodedImages = jsonDecode(imagesRes);

        for (var imgDoc in decodedImages) {
          final Map<String, dynamic> imgData = imgDoc['data'] as Map<String, dynamic>? ?? {};
          final String textLinked = imgData['text_linked'] ?? '';
          if (textLinked.isNotEmpty) {
            final regex = RegExp(r'\[\[(' + RegExp.escape(label) + r')\|user:(.*?)\]\]', caseSensitive: false);
            final match = regex.firstMatch(textLinked);
            if (match != null) {
              final String targetUid = match.group(2)?.trim() ?? '';
              if (targetUid.isNotEmpty) {
                final profileRes = await fsGetDoc('profiles/$targetUid');
                final Map<String, dynamic> pDoc = jsonDecode(profileRes);
                if (pDoc['exists'] == true) {
                  final Map<String, dynamic> pData = pDoc['data'] as Map<String, dynamic>? ?? {};
                  final String? username = pData['username'];
                  if (username != null && username.isNotEmpty && mounted) {
                    setState(() {
                      _suggestedHandle = username;
                    });
                    return;
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        print('[EntitiesPanel _findSuggestedHandle] Error checking fanzine pages: $e');
      }
    }
  }

  void _onEntityTap(EntityLink entity) {
    if (component.isEditingMode) {
      String initialHandle = '';
      String initialAddress = '';
      String resolvedType = 'person';

      if (entity.ref != null) {
        if (entity.ref!.startsWith('user:')) {
          final uid = entity.ref!.substring(5);
          initialHandle = _loadedProfiles[uid]?['username'] ?? '';
          resolvedType = 'person';
        } else if (entity.ref!.startsWith('address:')) {
          initialAddress = entity.ref!.substring(8);
          resolvedType = 'place';
        }
      }

      setState(() {
        _editingEntity = entity;
        _entityType = resolvedType;
        _handleInput = initialHandle;
        _addressInput = initialAddress;
        _modalError = null;
        _modalSaving = false;
        _suggestedHandle = null;
      });

      if (resolvedType == 'person') {
        _findSuggestedHandle(entity);
      } else {
        // Auto-initialize Google places on modal element display
        Timer(const Duration(milliseconds: 120), () {
          initAddressAutocomplete('modal-address-input', (String address) {
            setState(() {
              _addressInput = address;
            });
          });
        });
      }
    } else {
      if (entity.ref != null) {
        if (entity.ref!.startsWith('user:')) {
          final uid = entity.ref!.substring(5);
          final String? username = _loadedProfiles[uid]?['username'];
          if (username != null && username.isNotEmpty) {
            Router.of(context).push('/@$username');
          }
        } else if (entity.ref!.startsWith('address:')) {
          final addressVal = entity.ref!.substring(8);
          final encoded = Uri.encodeComponent(addressVal);
          openMapLauncher(encoded);
        }
      }
    }
  }

  void openMapLauncher(String encodedAddress) {
    openWindow('https://www.google.com/maps/search/?api=1&query=$encodedAddress', '_blank');
  }

  Future<void> _saveEntityLink() async {
    final entity = _editingEntity;
    if (entity == null || _modalSaving) return;

    setState(() {
      _modalSaving = true;
      _modalError = null;
    });

    try {
      String replacement = '';
      if (_entityType == 'place') {
        final cleanAddress = _addressInput.trim();
        if (cleanAddress.isEmpty) {
          setState(() {
            _modalError = 'Please enter or select a valid address.';
            _modalSaving = false;
          });
          return;
        }
        final content = entity.rawMatch.substring(2, entity.rawMatch.length - 2);
        final parts = content.split('|');

        if (parts.length >= 2 && !parts[1].startsWith('address:') && !parts[1].startsWith('user:')) {
          replacement = "[[${parts[0].trim()}|${parts[1].trim()}|address:$cleanAddress]]";
        } else {
          replacement = "[[${entity.label}|address:$cleanAddress]]";
        }
      } else {
        // Person linking flow
        final cleanHandle = _handleInput.trim().toLowerCase().replaceAll('@', '');
        if (cleanHandle.isEmpty) {
          setState(() {
            _modalError = 'Please enter a valid username.';
            _modalSaving = false;
          });
          return;
        }

        final result = await _uploadRepo.lookupUserByHandle(cleanHandle);
        if (result == null) {
          setState(() {
            _modalError = 'Profile @$cleanHandle not found in database.';
            _modalSaving = false;
          });
          return;
        }

        final targetUid = result['uid'];
        final content = entity.rawMatch.substring(2, entity.rawMatch.length - 2);
        final parts = content.split('|');

        if (parts.length == 3) {
          replacement = "[[${parts[0].trim()}|${parts[1].trim()}|user:$targetUid]]";
        } else if (parts.length == 2 && !parts[1].contains(':')) {
          replacement = "[[${parts[0].trim()}|${parts[1].trim()}|user:$targetUid]]";
        } else {
          replacement = "[[${entity.label}|user:$targetUid]]";
        }

        if (component.fanzineId != null) {
          await fsUpdateDoc('fanzines/${component.fanzineId}', jsonEncode({
            'draftEntities': WebFieldValue.arrayUnion([entity.label])
          }));
        }
      }

      final String updatedText = _rawFullText.replaceAll(entity.rawMatch, replacement);
      await fsUpdateDoc('images/${component.imageId}', jsonEncode({
        'text_linked': updatedText,
        'needs_linking': false,
      }));

      setState(() {
        _editingEntity = null;
        _handleInput = '';
        _addressInput = '';
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
      final content = entity.rawMatch.substring(2, entity.rawMatch.length - 2);
      final parts = content.split('|');
      String replacement;

      if (parts.length >= 2 && !parts[1].contains(':')) {
        replacement = "[[${parts[0].trim()}|${parts[1].trim()}]]";
      } else {
        replacement = "[[${entity.label}]]";
      }

      final String updatedText = _rawFullText.replaceAll(entity.rawMatch, replacement);
      await fsUpdateDoc('images/${component.imageId}', jsonEncode({
        'text_linked': updatedText,
      }));

      setState(() {
        _editingEntity = null;
        _handleInput = '';
        _addressInput = '';
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
    final bool isAddress = entity.ref != null && entity.ref!.startsWith('address:');
    final String? normalizedAddress = isAddress ? entity.ref!.substring(8) : null;
    final String? uid = entity.ref != null && entity.ref!.startsWith('user:') ? entity.ref!.substring(5) : null;
    final Map<String, dynamic>? profile = uid != null ? _loadedProfiles[uid] : null;

    final bool isLinked = profile != null || isAddress;
    final String labelText = profile != null ? (profile['displayName'] ?? entity.label) : entity.label;
    final String? subtitleText = isAddress ? normalizedAddress : (profile != null ? '@${profile['username']}' : null);
    final String? photoUrl = profile != null ? profile['photoUrl'] : null;

    return div(
      [
        div(
          [
            div(
              [
                if (isAddress)
                  span([text('pin_drop')], classes: 'material-symbols-outlined text-indigo-600', attributes: const {'style': 'font-size: 18px;'})
                else if (photoUrl != null && photoUrl.isNotEmpty)
                  img(classes: 'user-avatar', src: photoUrl)
                else
                  div(classes: 'user-avatar-placeholder', [text(labelText.isNotEmpty ? labelText[0].toUpperCase() : '?')])
              ],
              classes: 'user-avatar-container',
              attributes: const {
                'style': 'width: 32px; height: 32px; border-radius: 50%; overflow: hidden; background-color: #f1f1f1; flex-shrink: 0; display: flex; align-items: center; justify-content: center; border: 1px solid rgba(0,0,0,0.05);'
              },
            ),
            div(
              [
                div([text(labelText)], classes: 'user-display-name', attributes: const {'style': 'font-size: 13px; font-weight: bold; color: black; line-height: 1.2; text-align: left;'}),
                if (subtitleText != null)
                  div([text(subtitleText)], classes: 'text-xs text-gray', attributes: const {'style': 'color: #555555; font-size: 11px; font-weight: 500; margin-top: 2px; text-align: left;'})
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
            text(isAddress ? 'open_in_new' : 'arrow_forward_ios')
          ])
      ],
      classes: 'hover:shadow-md transition-all',
      attributes: const {
        'style': 'display: flex; flex-direction: row; align-items: center; justify-content: space-between; padding: 16px; margin-bottom: 12px; cursor: pointer; background-color: #ffffff; border: 1px solid #e2e8f0; border-radius: 12px; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.04); width: 100%; box-sizing: border-box;'
      },
      events: {
        'click': (e) => _onEntityTap(entity),
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
                              text('Link "'),
                              span([text(_editingEntity!.label)], attributes: const {'style': 'font-weight: bold; color: #6750A4;'}),
                              text('" to a database profile or places location.')
                            ],
                            attributes: const {'style': 'font-size: 12px; color: #555; line-height: 1.4; margin: 0;'}
                        ),
                        // Toggle Segmented Button for Person vs Place
                        div(
                          attributes: const {
                            'style': 'display: flex; border: 1px solid #ccc; border-radius: 100px; overflow: hidden; margin-top: 14px; background: white;'
                          },
                          [
                            button(
                                [
                                  span([text('person')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px; margin-right: 4px; vertical-align: middle;'}),
                                  text('Person')
                                ],
                                attributes: {
                                  'type': 'button',
                                  'style': 'flex: 1; border: none; padding: 6px; font-size: 11px; font-weight: bold; cursor: pointer; '
                                      'background-color: ${_entityType == 'person' ? '#E8DEF8' : 'transparent'}; '
                                      'color: ${_entityType == 'person' ? '#1D192B' : '#49454F'};'
                                },
                                events: {
                                  'click': (e) => setState(() { _entityType = 'person'; _modalError = null; })
                                }
                            ),
                            div(attributes: const {'style': 'width: 1px; background: #ccc;'}, []),
                            button(
                                [
                                  span([text('pin_drop')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px; margin-right: 4px; vertical-align: middle;'}),
                                  text('Place')
                                ],
                                attributes: {
                                  'type': 'button',
                                  'style': 'flex: 1; border: none; padding: 6px; font-size: 11px; font-weight: bold; cursor: pointer; '
                                      'background-color: ${_entityType == 'place' ? '#E8DEF8' : 'transparent'}; '
                                      'color: ${_entityType == 'place' ? '#1D192B' : '#49454F'};'
                                },
                                events: {
                                  'click': (e) {
                                    setState(() {
                                      _entityType = 'place';
                                      _modalError = null;
                                    });
                                    // Auto-initialize Google places on toggle switch click
                                    Timer(const Duration(milliseconds: 120), () {
                                      initAddressAutocomplete('modal-address-input', (String address) {
                                        setState(() {
                                          _addressInput = address;
                                        });
                                      });
                                    });
                                  }
                                }
                            ),
                          ],
                        ),
                        // Dynamic inputs depending on entityType selected
                        if (_entityType == 'person')
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
                              if (_suggestedHandle != null)
                                div(
                                  [
                                    span([text('Suggested Link:')], attributes: const {'style': 'font-size: 10px; color: #666; margin-bottom: 4px;'}),
                                    button(
                                        [text('@$_suggestedHandle')],
                                        classes: 'profile-btn',
                                        attributes: const {
                                          'type': 'button',
                                          'style': 'padding: 8px 12px; font-size: 12px; border: 1px dashed #6750A4; color: #6750A4; border-radius: 6px; background: rgba(103, 80, 164, 0.05); cursor: pointer; font-weight: bold; width: 100%; text-align: left; display: flex; align-items: center; justify-content: flex-start;'
                                        },
                                        events: {
                                          'click': (e) {
                                            setState(() {
                                              _handleInput = '@$_suggestedHandle';
                                            });
                                          }
                                        }
                                    )
                                  ],
                                  classes: 'flex-col mt-2',
                                  attributes: const {'style': 'display: flex; flex-direction: column; width: 100%; align-items: flex-start; margin-top: 8px;'},
                                ),
                            ],
                            classes: 'flex-col w-full mt-4',
                            attributes: const {'style': 'display: flex; flex-direction: column; width: 100%; margin-top: 14px;'},
                          )
                        else
                          div(
                            [
                              input(
                                  attributes: {
                                    'type': 'text',
                                    'id': 'modal-address-input',
                                    'placeholder': 'Start typing normalized address...',
                                    'value': _addressInput,
                                    'style': 'width: 100%; padding: 10px; border: 1px solid #ccc; border-radius: 8px; box-sizing: border-box; outline: none; background: white;'
                                  },
                                  events: {
                                    'change': (e) {
                                      _addressInput = getInputValue(e);
                                    }
                                  }
                              ),
                            ],
                            classes: 'flex-col w-full mt-4',
                            attributes: const {'style': 'display: flex; flex-direction: column; width: 100%; margin-top: 14px;'},
                          ),
                        if (_modalError != null)
                          p([text(_modalError!)], classes: 'error-msg mt-2', attributes: const {'style': 'font-size: 11px; margin-top: 4px; color: #ef4444;'})
                      ],
                      classes: 'flex-col w-full text-left',
                      attributes: const {'style': 'display: flex; flex-direction: column; text-align: left;'},
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
                                _addressInput = '';
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
                'style': 'max-width: 400px; max-height: 520px; border-radius: 12px; overflow: hidden; position: relative; width: 100%;'
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