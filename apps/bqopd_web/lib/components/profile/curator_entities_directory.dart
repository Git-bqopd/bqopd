import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/firebase_mocks.dart';
import '../../utils/web_utils.dart'; // REQUIRED for getInputValue!

/// Local utility to normalize user-provided names/handles by converting them to lowercase
/// and removing any whitespace or special characters to match standard database indexes.
String normalizeHandle(String input) {
  return input.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
}

/// A standalone entities list component designed specifically for curators.
/// Safely manages loading and empty layout states to prevent blank workspace renders.
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

    final Map<String, int> entityCounts = {};
    for (var fz in component.userWorks) {
      // Pull only from draft fanzines (isLive != true)
      if (fz['isLive'] == true) continue;
      final List entities = fz['draftEntities'] ?? [];
      for (var ent in entities) {
        if (ent != null) {
          entityCounts[ent.toString()] = (entityCounts[ent.toString()] ?? 0) + 1;
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

    return div(
      classes: 'bg-white rounded-lg p-6 shadow-sm border border-gray-200 w-full mt-4',
      [
        // Control header
        div(
          attributes: const {'style': 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; border-bottom: 1px solid #f0f0f0; padding-bottom: 12px;'},
          [
            div([
              h2([text("CANONICAL ENTITIES DIRECTORY")], attributes: const {'style': 'margin: 0; font-size: 15px; font-weight: bold; letter-spacing: 0.5px;'}),
              span([text("Manage alternative name aliases and create curator-owned wiki profile pages.")], attributes: const {'style': 'font-size: 11px; color: #666;'})
            ]),
          ],
        ),
        table(
          classes: 'stats-table text-left w-full',
          [
            thead([
              tr([
                th([text('Canonical Identity & Aliases')]),
                th([text('Total Appearances')]),
                th([text('Profile Status')]),
                th([text('Actions')]),
              ])
            ]),
            tbody([
              for (var name in sortedNames)
                EntityRowComponent(
                  name: name,
                  count: entityCounts[name]!,
                  key: ValueKey('entity_row_$name'),
                )
            ])
          ],
        )
      ],
    );
  }
}

/// Stateful row widget that observes its own handle status independently, preventing master UI locks.
class EntityRowComponent extends StatefulComponent {
  final String name;
  final int count;

  const EntityRowComponent({
    required this.name,
    required this.count,
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

  // Real-time listener subscription hook
  FirebaseSubscription? _listener;

  // Inline alias editor toggle state
  bool _showAliasInput = false;
  String _targetAliasInputText = '';

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _startObserver();
    }
  }

  @override
  void didUpdateComponent(EntityRowComponent oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.name != component.name && kIsWeb) {
      _listener?.callAsFunction();
      _startObserver();
    }
  }

  @override
  void dispose() {
    _listener?.callAsFunction();
    super.dispose();
  }

  void _startObserver() {
    final handle = normalizeHandle(component.name);
    setState(() => _loading = true);
    _listener = fsListenDoc('usernames/$handle', (jsonStr) {
      try {
        final doc = jsonDecode(jsonStr);
        if (doc['exists'] == true) {
          final data = doc['data'] as Map<String, dynamic>? ?? {};
          final bool isAlias = data['isAlias'] == true;
          if (mounted) {
            setState(() {
              _exists = true;
              _isAlias = isAlias;
              _profileId = data['uid'];
              _redirectHandle = data['redirect'];
              _loading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _exists = false;
              _isAlias = false;
              _profileId = null;
              _redirectHandle = null;
              _loading = false;
            });
          }
        }
      } catch (e) {
        print("Error observing username details: $e");
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  /// Triggers managed profile generation and maps registration hooks, matching Flutter's workflow
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

      final usernameData = {
        'uid': profileId,
        'isManaged': true,
        'createdAt': WebFieldValue.serverTimestamp()
      };

      final shortcodeData = {
        'type': 'user',
        'contentId': profileId,
        'displayCode': handle,
        'createdAt': WebFieldValue.serverTimestamp()
      };

      await fsSetDoc('profiles/$profileId', jsonEncode(profileData), true);
      await fsSetDoc('usernames/$handle', jsonEncode(usernameData), true);
      await fsSetDoc('shortcodes/${handle.toUpperCase()}', jsonEncode(shortcodeData), true);
    } catch (e) {
      print("Failed creating managed entity profile: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Directs alias triggers to point to another profile handle
  Future<void> _submitAliasRedirect() async {
    final cleanTarget = normalizeHandle(_targetAliasInputText);
    if (cleanTarget.isEmpty) return;

    setState(() => _loading = true);
    try {
      final aliasHandle = normalizeHandle(component.name);
      final uid = getCurrentUserId() ?? 'system';

      // Check if target exists first
      final checkRes = await fsGetDoc('usernames/$cleanTarget');
      final targetDoc = jsonDecode(checkRes);
      if (targetDoc['exists'] != true) {
        print("[ERROR] Target handle @$cleanTarget does not exist.");
        setState(() {
          _loading = false;
          _showAliasInput = false;
        });
        return;
      }

      final aliasData = {
        'redirect': cleanTarget,
        'createdBy': uid,
        'isAlias': true,
        'createdAt': WebFieldValue.serverTimestamp()
      };

      await fsSetDoc('usernames/$aliasHandle', jsonEncode(aliasData), true);
      setState(() {
        _showAliasInput = false;
        _targetAliasInputText = '';
      });
    } catch (e) {
      print("Failed submitting alias redirection: $e");
    } finally {
      if (mounted) setState(() => _loadingValue());
    }
  }

  void _loadingValue() {
    if (mounted) setState(() => _loading = false);
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return tr([
        td([span([text(component.name)], attributes: const {'style': 'font-weight: bold; font-size: 13.5px; opacity: 0.5;'})]),
        td([span([text('${component.count} occurrences')], attributes: const {'style': 'color: #999;'})]),
        td([span([text('syncing...')], attributes: const {'style': 'font-style: italic; color: #999;'})]),
        td([]),
      ]);
    }

    return tr([
      // Canonical Display Label
      td([
        div(classes: 'flex-col gap-1', [
          span([text(component.name)], attributes: const {'style': 'font-weight: bold; font-size: 13.5px; color: black;'}),
          if (_isAlias && _redirectHandle != null)
            span(
                [text('alias redirects to: @$_redirectHandle')],
                attributes: const {'style': 'font-size: 11px; color: #2563eb; font-weight: bold;'}
            )
        ])
      ]),
      // Appearance instances
      td([
        span([text('${component.count} occurrences')], attributes: const {'style': 'font-size: 12px; font-weight: 500; color: #4b5563;'})
      ]),
      // Linked Profile mapping Status
      td([
        if (_exists && _profileId != null)
          a(
              [
                span([text('account_circle')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px; margin-right: 4px;'}),
                text(_isAlias ? 'view target profile' : 'view profile')
              ],
              href: '/profile?userId=$_profileId',
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
                if (!_showAliasInput) ...[
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
                ] else
                // Inline alias compositor input
                  div(
                      attributes: const {'style': 'display: flex; gap: 4px; align-items: center;'},
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