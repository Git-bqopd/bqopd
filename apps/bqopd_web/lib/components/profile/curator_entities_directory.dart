import 'dart:convert';
import 'dart:async'; // REQUIRED for scheduleMicrotask
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/firebase_mocks.dart';
import '../../utils/web_utils.dart';

/// Local utility to normalize user-provided names/handles consistently.
String normalizeHandle(String input) {
  return input
      .trim()
      .toLowerCase()
      .replaceAll(' ', '-')
      .replaceAll(RegExp(r'[^a-z0-9_-]'), '');
}

/// A standalone entities list component designed specifically for curators.
/// Supports filtering between 'people' and 'places/addresses' to isolate historical data cleanly.
class CuratorEntitiesDirectory extends StatefulComponent {
  final List<Map<String, dynamic>> userWorks;
  final bool isLoading;

  const CuratorEntitiesDirectory({
    required this.userWorks,
    this.isLoading = false,
    super.key,
  });

  @override
  State<CuratorEntitiesDirectory> createState() => _CuratorEntitiesDirectoryState();
}

class _CuratorEntitiesDirectoryState extends State<CuratorEntitiesDirectory> {
  int _visibleCount = 100;
  String _activeFilter = 'all'; // 'all', 'people', 'places'

  @override
  Component build(BuildContext context) {
    if (component.isLoading) {
      return div(
        [
          span([text('sync')], classes: 'material-symbols-outlined shimmer-bg text-gray-300', attributes: const {'style': 'font-size: 48px; border-radius: 50%; padding: 12px;'}),
          p([text('Synchronizing entities directory...')], classes: 'text-sm text-gray italic mt-4')
        ],
        classes: 'bg-white rounded-lg p-16 shadow-sm text-center border border-gray-100 flex flex-col items-center justify-center w-full mt-4',
      );
    }

    // Parse and aggregate both person name links and places/addresses
    final Map<String, int> entityCounts = {};
    final Map<String, String> entityTypeMap = {}; // 'person' or 'place'

    for (var fz in component.userWorks) {
      if (fz['isLive'] == true) continue;
      final rawEntities = fz['draftEntities'];
      if (rawEntities is List) {
        for (var ent in rawEntities) {
          if (ent != null && ent.toString().trim().isNotEmpty) {
            final String entStr = ent.toString().trim();
            entityCounts[entStr] = (entityCounts[entStr] ?? 0) + 1;

            // Simple robust heuristic classification: if it contains commas/numbers or starts with numbers, treat as address
            final bool looksLikeAddress = entStr.contains(',') ||
                RegExp(r'^\d+').hasMatch(entStr) ||
                entStr.toLowerCase().contains('street') ||
                entStr.toLowerCase().contains('ave') ||
                entStr.toLowerCase().contains('road');
            entityTypeMap[entStr] = looksLikeAddress ? 'place' : 'person';
          }
        }
      }
    }

    if (entityCounts.isEmpty) {
      return div(
        classes: 'bg-white rounded-lg p-16 text-center shadow-sm border border-gray-100 flex flex-col items-center justify-center gap-4 w-full mt-4',
        [
          span([text('fingerprint')], classes: 'material-symbols-outlined text-gray-300', attributes: const {'style': 'font-size: 48px;'}),
          p([text("No entities detected in draft curator pipeline.")], classes: 'text-sm text-gray italic'),
        ],
      );
    }

    // Sort entities dynamically by descending occurrences count
    final sortedNames = entityCounts.keys.toList()
      ..sort((a, b) => entityCounts[b]!.compareTo(entityCounts[a]!));

    // Apply active filter
    final filteredNames = sortedNames.where((name) {
      if (_activeFilter == 'people') return entityTypeMap[name] == 'person';
      if (_activeFilter == 'places') return entityTypeMap[name] == 'place';
      return true;
    }).toList();

    final displayedNames = filteredNames.take(_visibleCount).toList();

    return div(
      classes: 'bg-white rounded-lg p-6 shadow-sm border border-gray-200 w-full mt-4',
      [
        // Control header with Category Filter Tabs
        div(
          attributes: const {'style': 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; border-bottom: 1px solid #f0f0f0; padding-bottom: 12px; flex-wrap: wrap; gap: 12px;'},
          [
            div([
              h2([text("CANONICAL ENTITIES DIRECTORY")], attributes: const {'style': 'margin: 0; font-size: 15px; font-weight: bold; letter-spacing: 0.5px;'}),
              span([text("Manage alternative name aliases, wiki profiles, or normalized address mappings. (showing ${displayedNames.length} of ${filteredNames.length})")], attributes: const {'style': 'font-size: 11px; color: #666;'})
            ]),
            // Interactive Sub-filters
            div(
                attributes: const {'style': 'display: flex; border: 1px solid #ccc; border-radius: 100px; overflow: hidden; background: white;'},
                [
                  _buildFilterButton('all', 'All'),
                  _buildFilterButton('people', 'People'),
                  _buildFilterButton('places', 'Places'),
                ]
            )
          ],
        ),

        table(
          classes: 'stats-table text-left w-full',
          [
            thead([
              tr([
                th([text('Canonical Identity & Aliases')]),
                th([text('Type')]),
                th([text('Total Appearances')]),
                th([text('Mapping Link / Status')]),
                th([text('Actions')]),
              ])
            ]),
            tbody([
              for (var name in displayedNames)
                EntityRowComponent(
                  name: name,
                  count: entityCounts[name]!,
                  isPlace: entityTypeMap[name] == 'place',
                  key: ValueKey('entity_row_$name'),
                )
            ])
          ],
        ),

        if (filteredNames.length > _visibleCount)
          div(
              attributes: const {
                'style': 'display: flex; justify-content: center; margin-top: 20px; border-top: 1px solid #f0f0f0; padding-top: 16px;'
              },
              [
                button(
                    [
                      span([text('expand_more')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px; margin-right: 6px; vertical-align: middle;'}),
                      text('load more (+100)')
                    ],
                    classes: 'profile-btn',
                    attributes: const {
                      'style': 'padding: 8px 24px; font-size: 12px; font-weight: bold; cursor: pointer; border: 1px solid #ccc; background: white; display: inline-flex; align-items: center; justify-content: center;'
                    },
                    events: {
                      'click': (e) {
                        setState(() {
                          _visibleCount += 100;
                        });
                      }
                    }
                )
              ]
          )
      ],
    );
  }

  Component _buildFilterButton(String filterVal, String label) {
    final bool isActive = _activeFilter == filterVal;
    return button(
        [text(label)],
        attributes: {
          'type': 'button',
          'style': 'border: none; padding: 6px 14px; font-size: 11px; font-weight: bold; cursor: pointer; '
              'background-color: ${isActive ? '#E8DEF8' : 'transparent'}; '
              'color: ${isActive ? '#1D192B' : '#49454F'};'
        },
        events: {
          'click': (e) => setState(() {
            _activeFilter = filterVal;
            _visibleCount = 100;
          })
        }
    );
  }
}

/// Stateful row widget that observes its own handle status independently, supporting people & places.
class EntityRowComponent extends StatefulComponent {
  final String name;
  final int count;
  final bool isPlace;

  const EntityRowComponent({
    required this.name,
    required this.count,
    this.isPlace = false,
    super.key,
  });

  @override
  State<EntityRowComponent> createState() => _EntityRowComponentState();
}

class _EntityRowComponentState extends State<EntityRowComponent> {
  bool _loading = true;
  bool _exists = false;
  String? _profileId;
  bool _isAlias = false;
  String? _redirectHandle;

  // Inline inputs state
  bool _showPlaceInput = false;
  String _addressInputText = '';
  List<Map<String, dynamic>> _predictions = [];
  Timer? _debounceTimer;

  bool _showAliasInput = false;
  String _targetAliasInputText = '';

  @override
  void initState() {
    super.initState();
    _fetchStatus();
  }

  @override
  void didUpdateComponent(EntityRowComponent oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.name != component.name) {
      _fetchStatus();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
    });

    try {
      final handle = normalizeHandle(component.name);
      final jsonStr = await fsGetDoc('usernames/$handle');

      scheduleMicrotask(() {
        if (!mounted) return;
        try {
          final doc = jsonDecode(jsonStr);
          if (doc['exists'] == true) {
            final rawData = doc['data'];
            final Map<String, dynamic> data = rawData is Map ? Map<String, dynamic>.from(rawData) : {};
            final bool isAlias = data['isAlias'] == true;

            setState(() {
              _exists = true;
              _isAlias = isAlias;
              _profileId = data['uid'] ?? data['redirect'];
              _redirectHandle = data['redirect'];
              _loading = false;
            });
          } else {
            setState(() {
              _exists = false;
              _isAlias = false;
              _profileId = null;
              _redirectHandle = null;
              _loading = false;
            });
          }
        } catch (e) {
          print("Error parsing username details inside _fetchStatus: $e");
          setState(() => _loading = false);
        }
      });
    } catch (e) {
      print("Error fetching username details: $e");
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // Google Places integration
  void _onAddressInputChanged(String inputVal) {
    _addressInputText = inputVal;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (inputVal.trim().length < 3) {
        setState(() => _predictions = []);
        return;
      }
      try {
        final String resultsJson = await getPlacePredictions(inputVal);
        final List decoded = jsonDecode(resultsJson);
        if (mounted) {
          setState(() {
            _predictions = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          });
        }
      } catch (_) {}
    });
  }

  Future<void> _createProfile() async {
    setState(() => _loading = true);
    try {
      final handle = normalizeHandle(component.name);
      final String profileId = 'profile_managed_${handle}_${DateTime.now().millisecondsSinceEpoch}';
      final uid = getCurrentUserId() ?? 'system';

      String firstName = component.name;
      String lastName = "";
      if (component.name.contains(' ')) {
        final parts = component.name.split(' ');
        firstName = parts.first;
        lastName = parts.sublist(1).join(' ');
      }

      final profileData = {
        'uid': profileId,
        'username': handle,
        'displayName': component.name,
        'firstName': firstName,
        'lastName': lastName,
        'photoUrl': '',
        'bio': 'Managed curator profile page for canonical entity: ${component.name}.',
        'isManaged': true,
        'isCurator': false,
        'managers': [uid],
        'followerCount': 0,
        'followingCount': 0,
        'createdAt': WebFieldValue.serverTimestamp(),
        'updatedAt': WebFieldValue.serverTimestamp()
      };

      await fsSetDoc('profiles/$profileId', jsonEncode(profileData), true);
      await fsSetDoc('usernames/$handle', jsonEncode({
        'uid': profileId,
        'isManaged': true,
        'createdAt': WebFieldValue.serverTimestamp()
      }), true);
      await fsSetDoc('shortcodes/${handle.toUpperCase()}', jsonEncode({
        'type': 'user',
        'contentId': profileId,
        'displayCode': handle,
        'createdAt': WebFieldValue.serverTimestamp()
      }), true);

      _fetchStatus();
    } catch (e) {
      print("Failed creating managed entity profile: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitPlaceLink() async {
    final cleanAddr = _addressInputText.trim();
    if (cleanAddr.isEmpty) return;
    setState(() => _loading = true);

    try {
      final handle = normalizeHandle(component.name);
      // Store the place alias in our usernames mappings referencing the direct normalized string
      await fsSetDoc('usernames/$handle', jsonEncode({
        'redirect': cleanAddr,
        'isAlias': true,
        'isAddress': true,
        'createdAt': WebFieldValue.serverTimestamp()
      }), true);

      setState(() {
        _showPlaceInput = false;
        _predictions = [];
      });
      _fetchStatus();
    } catch (e) {
      print("Failed saving place link alias: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitAliasRedirect() async {
    final cleanTarget = normalizeHandle(_targetAliasInputText);
    if (cleanTarget.isEmpty) return;

    setState(() => _loading = true);
    try {
      final aliasHandle = normalizeHandle(component.name);
      final uid = getCurrentUserId() ?? 'system';

      final checkRes = await fsGetDoc('usernames/$cleanTarget');
      final targetDoc = jsonDecode(checkRes);
      if (targetDoc['exists'] != true) {
        setState(() {
          _loading = false;
          _showAliasInput = false;
        });
        return;
      }

      await fsSetDoc('usernames/$aliasHandle', jsonEncode({
        'redirect': cleanTarget,
        'createdBy': uid,
        'isAlias': true,
        'createdAt': WebFieldValue.serverTimestamp()
      }), true);

      setState(() {
        _showAliasInput = false;
        _targetAliasInputText = '';
      });
      _fetchStatus();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return tr([
        td([span([text(component.name)], attributes: const {'style': 'font-weight: bold; font-size: 13.5px; opacity: 0.5;'})]),
        td([]),
        td([span([text('${component.count} occurrences')], attributes: const {'style': 'color: #999;'})]),
        td([span([text('syncing...')], attributes: const {'style': 'font-style: italic; color: #999;'})]),
        td([]),
      ]);
    }

    final String handle = _isAlias ? (_redirectHandle ?? '') : normalizeHandle(component.name);

    return tr([
      // Canonical Display Label
      td([
        div(classes: 'flex-col gap-1', [
          span([text(component.name)], attributes: const {'style': 'font-weight: bold; font-size: 13.5px; color: black; text-align: left;'}),
          if (_isAlias && _redirectHandle != null)
            span(
                [text(component.isPlace ? 'normalized to: $_redirectHandle' : 'alias redirects to: @$_redirectHandle')],
                attributes: {
                  'style': 'font-size: 11px; color: ${component.isPlace ? "#16a34a" : "#2563eb"}; font-weight: bold;'
                }
            )
        ])
      ]),
      // Entity Type Column
      td([
        span(
            [text(component.isPlace ? 'Place' : 'Person')],
            attributes: const {
              'style': 'font-size: 11px; font-weight: bold; color: black;'
            }
        )
      ]),
      // Appearance instances
      td([
        span([text('${component.count} occurrences')], attributes: const {'style': 'font-size: 12px; font-weight: 500; color: #4b5563;'})
      ]),
      // Linked Profile Mapping Status
      td([
        if (_exists)
          if (component.isPlace)
            a(
                [
                  span([text('pin_drop')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px; margin-right: 4px; vertical-align: middle;'}),
                  text(handle)
                ],
                href: 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(handle)}',
                attributes: const {'target': '_blank', 'style': 'font-size: 12px; font-weight: bold; color: #16a34a; text-decoration: underline;'}
            )
          else
            a(
                [
                  span([text('account_circle')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px; margin-right: 4px;'}),
                  text('@$handle')
                ],
                href: '/@$handle',
                classes: 'text-green-600 hover:underline inline-flex items-center',
                attributes: const {'style': 'font-size: 12px; font-weight: bold; color: #16a34a; text-decoration: none;'}
            )
        else
          span(
              [text('unlinked')],
              attributes: const {'style': 'font-size: 11px; color: #999; font-weight: 500; letter-spacing: 0.5px; text-transform: uppercase;'}
          )
      ]),
      // Interactive Action Triggers
      td([
        if (!_exists)
          div(
              attributes: const {'style': 'display: flex; gap: 8px; align-items: center;'},
              [
                if (!_showAliasInput && !_showPlaceInput) ...[
                  if (component.isPlace)
                    button(
                        [text('normalize')],
                        classes: 'profile-btn',
                        attributes: const {'style': 'padding: 4px 10px; font-size: 11px; background: white; border: 1px solid #ccc; font-weight: bold; border-radius: 0px; cursor: pointer;'},
                        events: {'click': (e) => setState(() => _showPlaceInput = true)}
                    )
                  else ...[
                    button(
                        [text('create')],
                        classes: 'profile-btn',
                        attributes: const {'style': 'padding: 4px 10px; font-size: 11px; background: white; border: 1px solid #ccc; font-weight: bold; border-radius: 0px; cursor: pointer;'},
                        events: {'click': (e) => _createProfile()}
                    ),
                    button(
                        [text('alias')],
                        classes: 'profile-btn',
                        attributes: const {'style': 'padding: 4px 10px; font-size: 11px; background: white; border: 1px solid #ccc; font-weight: bold; border-radius: 0px; cursor: pointer;'},
                        events: {'click': (e) => setState(() => _showAliasInput = true)}
                    ),
                  ]
                ] else if (_showPlaceInput)
                  div(
                      attributes: const {'style': 'display: flex; flex-direction: column; gap: 4px; position: relative; width: 150px;'},
                      [
                        div(
                            attributes: const {'style': 'display: flex; gap: 4px; align-items: center;'},
                            [
                              input(
                                  attributes: {
                                    'type': 'text',
                                    'placeholder': 'Search place...',
                                    'value': _addressInputText,
                                    'style': 'padding: 4px 8px; border: 1px solid #ccc; font-size: 11px; width: 100%; height: 26px; box-sizing: border-box;'
                                  },
                                  events: {
                                    'input': (e) => _onAddressInputChanged(getInputValue(e))
                                  }
                              ),
                              button(
                                  [span([text('close')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px;'})],
                                  attributes: const {'style': 'border: none; background: transparent; color: #ef4444; cursor: pointer;'},
                                  events: {'click': (e) => setState(() { _showPlaceInput = false; _predictions = []; })}
                              )
                            ]
                        ),
                        if (_predictions.isNotEmpty)
                          div(
                              attributes: const {
                                'style': 'position: absolute; top: 28px; left: 0; right: 0; background: white; border: 1px solid #ccc; border-radius: 4px; max-height: 120px; overflow-y: auto; z-index: 1000; box-shadow: 0 4px 6px rgba(0,0,0,0.15);'
                              },
                              [
                                for (var p in _predictions)
                                  div(
                                      [text(p['description'] ?? '')],
                                      classes: 'hover:bg-gray-150 p-1.5 cursor-pointer',
                                      attributes: const {'style': 'font-size: 10px; text-align: left; padding: 6px; border-bottom: 1px solid #eee;'},
                                      events: {
                                        'click': (e) {
                                          _addressInputText = p['description'] ?? '';
                                          _predictions = [];
                                          _submitPlaceLink();
                                        }
                                      }
                                  )
                              ]
                          )
                      ]
                  )
                else
                // Inline alias compositor input
                  div(
                      attributes: const {
                        'style': 'display: flex; gap: 4px; align-items: center;'
                      },
                      [
                        input(
                            attributes: const {
                              'type': 'text',
                              'placeholder': 'target handle...',
                              'style': 'padding: 4px 8px; border: 1px solid #ccc; border-radius: 0px; font-size: 11px; width: 110px; height: 26px; box-sizing: border-box;'
                            },
                            events: {
                              'input': (e) {
                                _targetAliasInputText = getInputValue(e);
                              }
                            }
                        ),
                        button(
                            [span([text('done')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px;'})],
                            attributes: const {'style': 'border: none; background: transparent; padding: 2px; color: #16a34a; cursor: pointer;'},
                            events: {'click': (e) => _submitAliasRedirect()}
                        ),
                        button(
                            [span([text('close')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px;'})],
                            attributes: const {'style': 'border: none; background: transparent; padding: 2px; color: #ef4444; cursor: pointer;'},
                            events: {'click': (e) => setState(() => _showAliasInput = false)}
                        ),
                      ]
                  )
              ]
          )
        else
          span([text('OK')], attributes: const {'style': 'color: #16a34a; font-weight: bold; font-size: 11px; letter-spacing: 0.5px;'})
      ])
    ]);
  }
}