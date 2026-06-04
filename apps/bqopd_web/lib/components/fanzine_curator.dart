import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../repositories/repositories.dart';
import '../utils/web_firebase_interop.dart';
import './editor/settings_tab.dart';
import './editor/order_tab.dart';
import './editor/upload_tab.dart';

/// Local utility to normalize handles inside the curator scope.
String normalizeHandle(String input) {
  return input.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
}

/// A standalone, 4-tab workstation editor specifically designed for curators.
/// Separated from FanzineEditor to avoid architectural overlap and regressions.
class FanzineCurator extends StatefulComponent {
  final String frefFanzineId;
  final String? shortCode;
  final Map<String, dynamic>? fanzineData;
  final Map<String, Map<String, dynamic>> creatorProfiles;
  final Map<String, Map<String, dynamic>> imageStats;
  final List<Map<String, dynamic>> pageStructure;
  final AuthState? authState;
  final AuthBloc? authBloc;
  final bool? twoPage;
  final void Function(bool)? onTwoPageChanged;

  const FanzineCurator({
    required this.frefFanzineId,
    this.shortCode,
    this.fanzineData,
    this.creatorProfiles = const {},
    this.imageStats = const {},
    this.pageStructure = const [],
    this.authState,
    this.authBloc,
    this.twoPage,
    this.onTwoPageChanged,
    super.key,
  });

  @override
  State<FanzineCurator> createState() => _FanzineCuratorState();
}

class _FanzineCuratorState extends State<FanzineCurator> {
  late final FanzineEditorBloc _bloc;
  StreamSubscription<FanzineEditorState>? _blocSubscription;
  FanzineEditorState _blocState = FanzineEditorInitial();
  int _activeTab = 0; // 0: settings, 1: order, 2: upload, 3: ocr/ent

  @override
  void initState() {
    super.initState();
    _bloc = FanzineEditorBloc(
      repository: createFanzineRepository(),
      pipelineRepository: createPipelineRepository(),
      fanzineId: _frefFrefFanzineIdSafe,
    );
    _bloc.add(LoadFanzineRequested(_frefFrefFanzineIdSafe));
    _blocSubscription = _bloc.stream.listen((state) {
      if (mounted) {
        setState(() {
          _blocState = state;
        });
        if (state is FanzineEditorLoaded && component.onTwoPageChanged != null) {
          component.onTwoPageChanged!(state.fanzine.twoPage);
        }
      }
    });
  }

  String get _frefFrefFanzineIdSafe => component.frefFanzineId;

  @override
  void dispose() {
    _blocSubscription?.cancel();
    _bloc.close();
    super.dispose();
  }

  Component _buildTabButton(String label, int index) {
    final isActive = _activeTab == index;
    return span(
      classes: 'text-xs cursor-pointer ${isActive ? 'font-bold' : 'text-gray'}',
      events: {'click': (e) => setState(() => _activeTab = index)},
      [text(label)],
    );
  }

  @override
  Component build(BuildContext context) {
    final state = _blocState;
    if (state is FanzineEditorLoading || state is FanzineEditorInitial) {
      return div(
        [
          p([text("Synchronizing curator workspace...")])
        ],
        classes: 'white-sticker-flexible w-full mt-2 p-8 text-center text-gray italic',
      );
    }
    if (state is FanzineEditorFailure) {
      return div(
        [
          h3([text("Curator Interface Failure")], attributes: const {'style': 'color: #ff5252; margin: 0 0 8px 0;'}),
          p([text(state.message)], attributes: const {'style': 'font-size: 13px; margin: 0;'})
        ],
        classes: 'white-sticker-flexible w-full mt-2 p-8 text-center',
      );
    }
    if (state is FanzineEditorLoaded) {
      final fanzine = state.fanzine;
      final pages = state.pages;
      final isProcessing = state.isProcessing;
      return div(
        [
          div(
            [
              _buildTabButton('settings', 0),
              span([text('|')], classes: 'px-4 text-gray text-xs'),
              _buildTabButton('order', 1),
              span([text('|')], classes: 'px-4 text-gray text-xs'),
              _buildTabButton('upload', 2),
              span([text('|')], classes: 'px-4 text-gray text-xs'),
              _buildTabButton('OCR / Ent', 3),
            ],
            classes: 'flex-row justify-center items-center py-2 bg-gray-100',
          ),
          div(
            [
              if (_activeTab == 0)
                EditorSettingsTab(fanzine: fanzine, pages: pages, bloc: _bloc, isSaving: isProcessing),
              if (_activeTab == 1)
                EditorOrderTab(fanzine: fanzine, pages: pages, bloc: _bloc),
              if (_activeTab == 2)
                UploadTab(fanzine: fanzine, pages: pages, bloc: _bloc, isUploading: isProcessing),
              if (_activeTab == 3)
                EditorOcrEntitiesTab(frefFanzineId: _frefFrefFanzineIdSafe, fanzine: fanzine, pages: pages, bloc: _bloc),
            ],
            classes: 'flex-col p-4',
          ),
        ],
        classes: 'white-sticker-flexible w-full mt-2',
      );
    }
    return div([]);
  }
}

/// Dynamic Tab Component supporting automated pipeline statistics and direct callable trigger actions.
class EditorOcrEntitiesTab extends StatefulComponent {
  final String frefFanzineId;
  final Fanzine fanzine;
  final List<FanzinePage> pages;
  final FanzineEditorBloc bloc;

  const EditorOcrEntitiesTab({
    required this.frefFanzineId,
    required this.fanzine,
    required this.pages,
    required this.bloc,
    super.key,
  });

  @override
  State<EditorOcrEntitiesTab> createState() => _EditorOcrEntitiesTabState();
}

class _EditorOcrEntitiesTabState extends State<EditorOcrEntitiesTab> {
  int _rawDone = 0;
  int _masterVerified = 0;
  int _linkedPending = 0;
  bool _calculating = true;
  FirebaseSubscription? _imagesSub;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _listenToOcrProgress();
    }
  }

  @override
  void didUpdateComponent(EditorOcrEntitiesTab oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.frefFanzineId != component.frefFanzineId && kIsWeb) {
      _imagesSub?.callAsFunction();
      _listenToOcrProgress();
    }
  }

  @override
  void dispose() {
    _imagesSub?.callAsFunction();
    super.dispose();
  }

  void _listenToOcrProgress() {
    setState(() => _calculating = true);
    _imagesSub = fsListenQuery('images', 'usedInFanzines', 'array-contains', jsonEncode(component.frefFanzineId), '', false, (jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        int raw = 0;
        int master = 0;
        int linked = 0;

        for (var doc in decoded) {
          final data = doc['data'] as Map<String, dynamic>? ?? {};
          final rawText = data['text_raw']?.toString() ?? '';
          final correctedText = data['text_corrected']?.toString() ?? '';
          final needsAi = data['needs_ai_cleaning'] == true;
          final needsLink = data['needs_linking'] == true;

          if (rawText.isNotEmpty && rawText != "[No text detected]") raw++;
          if (correctedText.isNotEmpty && !needsAi) master++;
          if (needsLink) linked++;
        }

        if (mounted) {
          setState(() {
            _rawDone = raw;
            _masterVerified = master;
            _linkedPending = linked;
            _calculating = false;
          });
        }
      } catch (e) {
        print("Error streaming OCR stats: $e");
        if (mounted) setState(() => _calculating = false);
      }
    });
  }

  @override
  Component build(BuildContext context) {
    final draftEntities = component.fanzine.draftEntities;

    return div(
      classes: 'flex-col text-left gap-4',
      attributes: const {'style': 'display: flex; flex-direction: column; gap: 16px;'},
      [
        div(
          classes: 'flex-row justify-around items-center py-2 bg-gray-50 rounded-md border border-gray-150',
          attributes: const {'style': 'display: flex; flex-direction: row; justify-content: space-around; align-items: center; padding: 12px 0;'},
          [
            _buildCounterSquare("Raw Done", _rawDone, '#2563eb'),
            _buildCounterSquare("Master Verified", _masterVerified, '#16a34a'),
            _buildCounterSquare("Linked Pending", _linkedPending, '#ea580c'),
          ],
        ),

        div(
          classes: 'flex-row gap-3 mt-2',
          attributes: const {'style': 'display: flex; flex-direction: row; gap: 12px; justify-content: center;'},
          [
            button(
              [
                span([text('auto_fix_high')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px; margin-right: 6px;'}),
                text("Step 2: AI Clean")
              ],
              classes: 'profile-btn',
              attributes: const {'style': 'height: 36px; display: inline-flex; align-items: center; justify-content: center; padding: 0 16px; font-weight: bold; border-radius: 18px; border: 1px solid #16a34a; color: #16a34a; background: white; cursor: pointer;'},
              events: {'click': (e) => component.bloc.add(TriggerAiCleanRequested())},
            ),
            button(
              [
                span([text('link')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px; margin-right: 6px;'}),
                text("Step 3: Generate Links")
              ],
              classes: 'profile-btn',
              attributes: const {'style': 'height: 36px; display: inline-flex; align-items: center; justify-content: center; padding: 0 16px; font-weight: bold; border-radius: 18px; border: 1px solid #ea580c; color: #ea580c; background: white; cursor: pointer;'},
              events: {'click': (e) => component.bloc.add(TriggerGenerateLinksRequested())},
            ),
          ],
        ),

        div([], attributes: const {'style': 'height: 1px; background-color: #eee; margin: 8px 0;'}),

        h3([text("Detected Entities Archive")], classes: 'text-xs font-bold text-gray uppercase tracking-wider mb-1'),
        if (draftEntities.isEmpty)
          p([text("No entities registered in this issue's index pipeline yet.")], classes: 'text-xs text-gray italic text-center py-4')
        else
          div(
            classes: 'flex-col gap-2',
            attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px;'},
            [
              for (var entity in draftEntities)
                OcrWorkspaceEntityRow(name: entity, key: ValueKey(entity)),
            ],
          ),
      ],
    );
  }

  Component _buildCounterSquare(String label, int val, String color) {
    return div(
      attributes: const {'style': 'display: flex; flex-direction: column; align-items: center;'},
      [
        span([text(_calculating ? "..." : "$val")], attributes: {
          'style': 'font-size: 24px; font-weight: 900; color: $color; line-height: 1;'
        }),
        span([text(label.toLowerCase())], attributes: const {
          'style': 'font-size: 10px; color: #666; font-weight: bold; margin-top: 4px;'
        }),
      ],
    );
  }
}

/// Stateful row widget observing username registration hooks in real-time.
class OcrWorkspaceEntityRow extends StatefulComponent {
  final String name;

  const OcrWorkspaceEntityRow({required this.name, super.key});

  @override
  State<OcrWorkspaceEntityRow> createState() => _OcrWorkspaceEntityRowState();
}

class _OcrWorkspaceEntityRowState extends State<OcrWorkspaceEntityRow> {
  bool _loading = true;
  bool _exists = false;
  String? _profileId;
  bool _isAlias = false;
  String? _redirectHandle;
  FirebaseSubscription? _listener;

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
  void dispose() {
    _listener?.callAsFunction();
    super.dispose();
  }

  void _startObserver() {
    final handle = normalizeHandle(component.name);
    _listener = fsListenDoc('usernames/$handle', (jsonStr) {
      try {
        final doc = jsonDecode(jsonStr);
        if (doc['exists'] == true) {
          final data = doc['data'] as Map<String, dynamic>? ?? {};
          if (mounted) {
            setState(() {
              _exists = true;
              _isAlias = data['isAlias'] == true;
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
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
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

      await fsSetDoc('profiles/$profileId', jsonEncode({
        'uid': profileId,
        'username': handle,
        'displayName': component.name,
        'firstName': firstName,
        'lastName': lastName,
        'photoUrl': '',
        'bio': 'Managed curator profile page for canonical entity: ${component.name}.',
        'isManaged': true,
        'isCurator': false,
        'isAdmin': false,
        'managers': [uid],
        'followerCount': 0,
        'followingCount': 0,
        'createdAt': WebFieldValue.serverTimestamp(),
        'updatedAt': WebFieldValue.serverTimestamp()
      }), true);

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
    } catch (e) {
      print("Error creating entity profile: $e");
    } finally {
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
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(
          [span([text("syncing... @${normalizeHandle(component.name)}")], attributes: const {'style': 'font-style: italic; color: #999; font-size: 12px;'})],
          attributes: const {'style': 'padding: 8px;'}
      );
    }

    return div(
      classes: 'flex-row justify-between items-center bg-gray-50 border border-gray-150 p-2 rounded-md',
      attributes: const {'style': 'display: flex; align-items: center; justify-content: space-between; padding: 10px 12px; background-color: #f9f9f9; border: 1px solid #eee; border-radius: 6px; box-sizing: border-box; width: 100%; margin-bottom: 6px;'},
      [
        div(
          classes: 'flex-col',
          attributes: const {'style': 'display: flex; flex-direction: column; gap: 2px;'},
          [
            span([text(component.name)], attributes: const {'style': 'font-weight: bold; font-size: 13px; color: black;'}),
            if (_isAlias && _redirectHandle != null)
              span([text("aliases to @$_redirectHandle")], attributes: const {'style': 'font-size: 10px; color: #2563eb; font-weight: bold;'})
          ],
        ),

        div(
          [
            if (_exists)
              a(
                  [
                    span([text('account_circle')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px; margin-right: 4px; vertical-align: middle;'}),
                    text("view profile")
                  ],
                  href: '/profile?userId=$_profileId',
                  attributes: const {'style': 'font-size: 11px; font-weight: bold; color: #16a34a; text-decoration: none; display: inline-flex; align-items: center;'}
              )
            else if (!_showAliasInput) ...[
              button(
                  [text("create")],
                  classes: 'profile-btn',
                  attributes: const {'style': 'padding: 4px 8px; font-size: 10px; font-weight: bold; background: white; border: 1px solid #ccc; cursor: pointer;'},
                  events: {'click': (e) => _createProfile()}
              ),
              span([], attributes: const {'style': 'display: inline-block; width: 6px;'}),
              button(
                  [text("alias")],
                  classes: 'profile-btn',
                  attributes: const {'style': 'padding: 4px 8px; font-size: 10px; font-weight: bold; background: white; border: 1px solid #ccc; cursor: pointer;'},
                  events: {'click': (e) => setState(() => _showAliasInput = true)}
              ),
            ] else
              div(
                attributes: const {'style': 'display: flex; gap: 4px; align-items: center;'},
                [
                  input(
                      type: InputType.text,
                      attributes: const {
                        'placeholder': 'target handle...',
                        'style': 'padding: 4px 6px; border: 1px solid #ccc; font-size: 10px; width: 100px; height: 24px; box-sizing: border-box;'
                      },
                      events: {
                        'input': (e) {
                          _targetAliasInputText = (e.target as dynamic).value ?? '';
                        }
                      }
                  ),
                  button(
                      [span([text('done')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 13px;'})],
                      attributes: const {'style': 'border: none; background: transparent; color: #16a34a; cursor: pointer;'},
                      events: {'click': (e) => _submitAliasRedirect()}
                  ),
                  button(
                      [span([text('close')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 13px;'})],
                      attributes: const {'style': 'border: none; background: transparent; color: #ef4444; cursor: pointer;'},
                      events: {'click': (e) => setState(() => _showAliasInput = false)}
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}