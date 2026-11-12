import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';
import '../../repositories/repositories.dart';

enum _TerminalTab {
  encounter,
  webarTabletop,
  subnetConsole,
}

/// Dedicated mobile / inline accordion drawer (`bonusRow`) for `terminal`.
///
/// Triggered when a reader taps the `terminal` social button beneath any fanzine
/// page or 1-page drama advertisement on their smartphone or tablet.
class TerminalRowPanel extends StatelessComponent {
  final String imageId;
  const TerminalRowPanel({required this.imageId, super.key});

  @override
  Component build(BuildContext context) {
    return _TerminalSingleWorldWorkstation(
      imageId: imageId,
      isCompactDrawer: true,
    );
  }
}

/// Dedicated desktop 3rd-column (`bonusColumn`) full-height `terminal` workstation.
class TerminalColumnPanel extends StatelessComponent {
  final String imageId;
  const TerminalColumnPanel({required this.imageId, super.key});

  @override
  Component build(BuildContext context) {
    return _TerminalSingleWorldWorkstation(
      imageId: imageId,
      isCompactDrawer: false,
    );
  }
}

/// Backwards-compatible alias.
typedef TerminalPanel = TerminalColumnPanel;

class _TerminalSingleWorldWorkstation extends StatefulComponent {
  final String imageId;
  final bool isCompactDrawer;

  const _TerminalSingleWorldWorkstation({
    required this.imageId,
    required this.isCompactDrawer,
  });

  @override
  State<_TerminalSingleWorldWorkstation> createState() =>
      _TerminalSingleWorldWorkstationState();
}

class _TerminalSingleWorldWorkstationState
    extends State<_TerminalSingleWorldWorkstation> {
  late final IGameService _gameService;
  late final String _webarContainerId;

  StreamSubscription<WorldStateSnapshot>? _worldSub;
  WorldStateSnapshot _worldState = TerminalWorldEngine.seedSector7G();

  _TerminalTab _activeTab = _TerminalTab.encounter;
  String? _overrideEncounterKey;
  String _lockerCodeInput = '';
  String _qrScanInput = '';
  String _consoleInput = '';
  String? _selectedArEntityId;
  bool _isCameraQrScanning = false;
  bool _isMixtapeAudioPlaying = false;
  bool _isBusy = false;

  final List<String> _consoleLogs = [
    'TERMINAL // SINGLE CANONICAL WORLD [SECTOR 7G]',
    'Zero shards · Zero reboots · Every printed page & SSH session shares state.',
  ];

  @override
  void initState() {
    super.initState();
    _gameService = createGameService();
    _webarContainerId = 'terminal-webar-${identityHashCode(this)}';
    if (kIsWeb) {
      _subscribeCanonicalWorld();
    }
  }

  @override
  void didUpdateComponent(_TerminalSingleWorldWorkstation oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.imageId != component.imageId) {
      // If reader scrolled/switched to a page with its own PageEncounter, focus it automatically
      if (TerminalWorldEngine.findEncounter(_worldState, component.imageId) !=
          null) {
        _overrideEncounterKey = null;
      }
      if (kIsWeb && _activeTab == _TerminalTab.webarTabletop) {
        _syncWebArViewport();
      }
    }
  }

  @override
  void dispose() {
    _worldSub?.cancel();
    if (kIsWeb) {
      disposeTerminalWebAr(_webarContainerId);
      if (_isMixtapeAudioPlaying) {
        playTerminalMixtapeSynth(false);
      }
    }
    super.dispose();
  }

  void _subscribeCanonicalWorld() {
    _worldSub = _gameService.watchCanonicalWorld().listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _worldState = snapshot;
        _ensureDefaultSelectedArUnit();
      });
      if (_activeTab == _TerminalTab.webarTabletop) {
        _syncWebArViewport();
      }
    });
  }

  String _resolveActorId() {
    final uid = getCurrentUserId();
    if (uid != null && uid.isNotEmpty) return uid;
    return 'guest_street_reader';
  }

  PageEncounter _resolveActiveEncounter() {
    if (_overrideEncounterKey != null) {
      final manual = TerminalWorldEngine.findEncounter(
        _worldState,
        _overrideEncounterKey!,
      );
      if (manual != null) return manual;
    }

    final bound = TerminalWorldEngine.findEncounter(
      _worldState,
      component.imageId,
    );
    if (bound != null) return bound;

    // Fallback to the live 1-page Sector 7G Gang Drama Ad so any page can test & jack in
    return _worldState.encounters[TerminalWorldEngine.gangDramaAdPageId] ??
        _worldState.encounters.values.first;
  }

  bool get _hasDirectPageBinding =>
      TerminalWorldEngine.findEncounter(_worldState, component.imageId) != null;

  String _activeSessionId(PageEncounter enc) =>
      'ar_${enc.shortCode.toLowerCase()}';

  void _ensureDefaultSelectedArUnit() {
    final actorId = _resolveActorId();
    if (_selectedArEntityId != null &&
        _worldState.entities.containsKey(_selectedArEntityId)) {
      return;
    }
    if (_worldState.entities.containsKey(actorId)) {
      _selectedArEntityId = actorId;
    } else if (_worldState.entities.containsKey('entity_owner_7g')) {
      _selectedArEntityId = 'entity_owner_7g';
    } else if (_worldState.entities.isNotEmpty) {
      _selectedArEntityId = _worldState.entities.keys.first;
    }
  }

  void _appendLogs(Iterable<String> lines) {
    for (final line in lines) {
      if (line.trim().isNotEmpty) {
        _consoleLogs.add(line);
      }
    }
    if (_consoleLogs.length > 60) {
      _consoleLogs.removeRange(0, _consoleLogs.length - 60);
    }
  }

  // --- Contextual `terminal` Social Button Action Handlers ---

  Future<void> _handleEncounterAction(
    PageEncounter encounter,
    TerminalPageAction action,
  ) async {
    if (_isBusy) return;

    if (action.type == TerminalActionType.scanArTabletop) {
      await _openWebArTabletop(encounter);
      return;
    }

    if (action.type == TerminalActionType.unlockCode &&
        _lockerCodeInput.trim().isEmpty) {
      setState(() {
        _appendLogs([
          'Enter the 4-digit keypad code first (Hint: listen to Razor\'s mixtape!).',
        ]);
      });
      return;
    }

    setState(() => _isBusy = true);
    try {
      final lines = await _gameService.executePageAction(
        imageId: encounter.imageId,
        actorEntityId: _resolveActorId(),
        actionId: action.id,
        inputCode: _lockerCodeInput.trim(),
      );

      if (action.type == TerminalActionType.playMedia && kIsWeb) {
        playTerminalMixtapeSynth(true);
        _isMixtapeAudioPlaying = true;
      }

      if (mounted) {
        setState(() {
          _appendLogs(['> [${encounter.shortCode}] ${action.label}', ...lines]);
          if (action.type == TerminalActionType.unlockCode) {
            _lockerCodeInput = '';
          }
          _isBusy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _appendLogs(['Action error: $e']);
          _isBusy = false;
        });
      }
    }
  }

  // --- Smartphone WebAR Tabletop ("1 Positional Anchor + Max 5 Scan-Once QR") ---

  Future<void> _openWebArTabletop(PageEncounter encounter) async {
    final sessionId = _activeSessionId(encounter);
    final lines = await _gameService.startTabletopArSession(
      anchorPageId: encounter.imageId,
      hostUserId: _resolveActorId(),
      sessionId: sessionId,
    );
    if (!mounted) return;
    setState(() {
      _activeTab = _TerminalTab.webarTabletop;
      _ensureDefaultSelectedArUnit();
      _appendLogs(lines);
    });
    if (kIsWeb) {
      _mountOrUpdateWebAr(forceMount: true);
    }
  }

  String _buildWebArSceneJson(PageEncounter encounter) {
    final room = _worldState.rooms[encounter.roomId] ??
        _worldState.rooms[TerminalWorldEngine.warehouseRoomId];
    final grid = room?.gridSpec;
    final sessionId = _activeSessionId(encounter);
    final session = _worldState.arSessions[sessionId];

    final tilesJson = <Map<String, dynamic>>[];
    if (grid != null) {
      for (final t in grid.tiles) {
        final def = KenneyAssetCatalog.getOrFallback(t.kenneyAssetId);
        tilesJson.add({
          'x': t.coord.x,
          'y': t.coord.y,
          'assetId': t.kenneyAssetId,
          'glbPath': def.model3dGlbPath,
          'blocks': t.blocksMovement,
        });
      }
    }

    final propsJson = <Map<String, dynamic>>[];
    if (room != null) {
      for (final p in room.objects) {
        if (p.gridPos == null) continue;
        final def = KenneyAssetCatalog.getOrFallback(p.kenneyAssetId);
        propsJson.add({
          'id': p.id,
          'name': p.name,
          'x': p.gridPos!.x,
          'y': p.gridPos!.y,
          'glbPath': def.model3dGlbPath,
          'isBoombox': p.id == TerminalWorldEngine.boomboxPropId,
        });
      }
    }

    final unitsJson = <Map<String, dynamic>>[];
    final seenEntityIds = <String>{
      ...?room?.occupantIds,
      ...?session?.unitPositions.keys,
    };
    for (final entId in seenEntityIds) {
      final ent = _worldState.entities[entId];
      if (ent == null) continue;
      final coord = session?.unitPositions[entId] ?? ent.gridPos;
      if (coord == null) continue;
      final def = KenneyAssetCatalog.getOrFallback(ent.kenneyCharacterId);
      unitsJson.add({
        'id': ent.id,
        'handle': ent.handle,
        'x': coord.x,
        'y': coord.y,
        'glbPath': def.model3dGlbPath,
        'isAlive': ent.isAlive,
        'isHostile': ent.role == EntityRole.hiredThug,
        'isSelected': ent.id == _selectedArEntityId,
      });
    }

    return jsonEncode({
      'roomId': room?.id ?? 'room_warehouse_7g_east',
      'width': grid?.width ?? 8,
      'height': grid?.height ?? 10,
      'anchorMarkerId': grid?.anchorMarkerId ?? 'QR-7G-WH01',
      'anchorShortCode': encounter.shortCode,
      'tiles': tilesJson,
      'props': propsJson,
      'units': unitsJson,
    });
  }

  void _mountOrUpdateWebAr({bool forceMount = false}) {
    if (!kIsWeb) return;
    final encounter = _resolveActiveEncounter();
    final sceneJson = _buildWebArSceneJson(encounter);
    if (forceMount) {
      mountTerminalWebAr(
        containerId: _webarContainerId,
        sceneJson: sceneJson,
        onQrDetected: (String qr) {
          _handleIngestQrCode(qr);
        },
        onTileTapped: (int x, int y) {
          _handleMoveArUnitTo(GridCoordinate(x, y));
        },
      );
    } else {
      updateTerminalWebArScene(_webarContainerId, sceneJson);
    }
  }

  void _syncWebArViewport() {
    _mountOrUpdateWebAr(forceMount: false);
  }

  Future<void> _handleIngestQrCode(
    String rawCode, {
    String? fallbackHandle,
  }) async {
    final code = rawCode.trim();
    if (code.isEmpty) return;
    final encounter = _resolveActiveEncounter();
    final sessionId = _activeSessionId(encounter);

    // Ensure anchor session exists first
    if (!_worldState.arSessions.containsKey(sessionId)) {
      await _gameService.startTabletopArSession(
        anchorPageId: encounter.imageId,
        hostUserId: _resolveActorId(),
        sessionId: sessionId,
      );
    }

    final lines = await _gameService.ingestQrIntoTabletopSession(
      sessionId: sessionId,
      scannedQrCode: code,
      fallbackHandle: fallbackHandle,
    );
    if (!mounted) return;
    setState(() {
      _isCameraQrScanning = false;
      _qrScanInput = '';
      _appendLogs(lines);
      // Auto-select newly spawned participant if available
      final updatedSession = _worldState.arSessions[sessionId];
      if (updatedSession != null &&
          updatedSession.ingestedEntityIds.isNotEmpty) {
        _selectedArEntityId = updatedSession.ingestedEntityIds.last;
      }
    });
    _syncWebArViewport();
  }

  Future<void> _handleMoveArUnitTo(GridCoordinate target) async {
    final encounter = _resolveActiveEncounter();
    final sessionId = _activeSessionId(encounter);
    final unitId = _selectedArEntityId ?? _resolveActorId();

    if (!_worldState.arSessions.containsKey(sessionId)) {
      await _gameService.startTabletopArSession(
        anchorPageId: encounter.imageId,
        hostUserId: _resolveActorId(),
        sessionId: sessionId,
      );
    }

    final lines = await _gameService.moveTabletopUnit(
      sessionId: sessionId,
      entityId: unitId,
      targetCoord: target,
    );
    if (!mounted) return;
    setState(() {
      _appendLogs(lines);
    });
    _syncWebArViewport();
  }

  Future<void> _handleStepSelectedUnit(int dx, int dy) async {
    final encounter = _resolveActiveEncounter();
    final session = _worldState.arSessions[_activeSessionId(encounter)];
    final unitId = _selectedArEntityId ?? _resolveActorId();
    final current = session?.unitPositions[unitId] ??
        _worldState.entities[unitId]?.gridPos ??
        const GridCoordinate(3, 8);
    await _handleMoveArUnitTo(GridCoordinate(current.x + dx, current.y + dy));
  }

  // --- MOO / SSH Text Command Execution ---

  Future<void> _handleConsoleSubmit([String? presetCommand]) async {
    final cmd = (presetCommand ?? _consoleInput).trim();
    if (cmd.isEmpty || _isBusy) return;
    setState(() {
      _isBusy = true;
      if (presetCommand == null) _consoleInput = '';
    });
    try {
      final lines = await _gameService.executeTerminalCommand(
        actorEntityId: _resolveActorId(),
        rawCommand: cmd,
      );
      if (cmd.toLowerCase().startsWith('listen') && kIsWeb) {
        playTerminalMixtapeSynth(true);
        _isMixtapeAudioPlaying = true;
      }
      if (mounted) {
        setState(() {
          _appendLogs(['> $cmd', ...lines]);
          _isBusy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _appendLogs(['Console error: $e']);
          _isBusy = false;
        });
      }
    }
  }

  void _switchTab(_TerminalTab nextTab, PageEncounter encounter) {
    if (_activeTab == _TerminalTab.webarTabletop &&
        nextTab != _TerminalTab.webarTabletop &&
        kIsWeb) {
      disposeTerminalWebAr(_webarContainerId);
      _isCameraQrScanning = false;
    }

    if (nextTab == _TerminalTab.webarTabletop) {
      _openWebArTabletop(encounter);
      return;
    }

    setState(() {
      _activeTab = nextTab;
    });
  }

  // ===========================================================================
  // UI BUILDERS
  // ===========================================================================

  @override
  Component build(BuildContext context) {
    final uid = getCurrentUserId();
    final actorId = _resolveActorId();
    final actor = _worldState.entities[actorId];
    final encounter = _resolveActiveEncounter();
    final room = _worldState.rooms[encounter.roomId] ??
        _worldState.rooms[TerminalWorldEngine.warehouseRoomId];

    return div(
      classes: 'terminal-canonical-panel',
      attributes: {
        'style':
            'display:flex;flex-direction:column;gap:${component.isCompactDrawer ? "10px" : "12px"};padding:${component.isCompactDrawer ? "12px" : "16px"};background:#080c14;color:#00FF41;border:1px solid #005522;border-radius:8px;font-family:"Courier New",Courier,monospace;width:100%;box-sizing:border-box;',
      },
      [
        // 1. Top Canonical World Bar + Sign-In / Persona Credits Badge
        div(
          attributes: const {
            'style':
                'display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;gap:8px;border-bottom:1px solid rgba(0,255,65,0.28);padding-bottom:8px;',
          },
          [
            div(
              attributes: const {
                'style': 'display:flex;align-items:center;gap:6px;',
              },
              [
                span(
                  [Component.text('●')],
                  attributes: const {'style': 'color:#00FF41;font-size:10px;'},
                ),
                span(
                  [Component.text('TERMINAL // CANONICAL WORLD')],
                  attributes: const {
                    'style':
                        'font-weight:bold;font-size:12px;letter-spacing:0.6px;color:#00FF41;',
                  },
                ),
                span(
                  [Component.text('TICK #${_worldState.tick}')],
                  attributes: const {
                    'style':
                        'font-size:10px;padding:1px 6px;background:#0f172a;border:1px solid #1e293b;border-radius:4px;color:#94a3b8;',
                  },
                ),
              ],
            ),
            div(
              attributes: const {
                'style': 'display:flex;align-items:center;gap:8px;',
              },
              [
                if (actor != null)
                  span(
                    [
                      Component.text(
                        '${actor.handle} · HP ${actor.currentHp}/${actor.maxHp} · ${actor.credits}c',
                      ),
                    ],
                    attributes: const {
                      'style':
                          'font-size:11px;font-weight:bold;color:#38bdf8;background:rgba(56,189,248,0.1);padding:2px 7px;border-radius:4px;border:1px solid rgba(56,189,248,0.35);',
                    },
                  )
                else
                  span(
                    [Component.text('200c STARTER')],
                    attributes: const {
                      'style': 'font-size:10px;color:#38bdf8;',
                    },
                  ),
                if (_isMixtapeAudioPlaying)
                  button(
                    [Component.text('■ MUTE TAPE')],
                    attributes: const {
                      'type': 'button',
                      'style':
                          'background:#ec4899;color:#fff;border:none;padding:2px 7px;font-size:10px;font-weight:bold;font-family:monospace;border-radius:4px;cursor:pointer;',
                    },
                    events: {
                      'click': (_) {
                        playTerminalMixtapeSynth(false);
                        setState(() => _isMixtapeAudioPlaying = false);
                      },
                    },
                  ),
                if (uid == null)
                  button(
                    [Component.text('SIGN IN')],
                    attributes: const {
                      'type': 'button',
                      'style':
                          'background:#00FF41;color:#000;border:none;padding:3px 8px;font-size:10px;font-weight:bold;font-family:monospace;border-radius:4px;cursor:pointer;',
                    },
                    events: {'click': (_) => GlobalModalBus.show()},
                  ),
              ],
            ),
          ],
        ),

        // 2. 3-Lens Mode Switcher: [PAGE ENCOUNTER] | [WEBAR TABLETOP] | [MOO / SSH]
        div(
          attributes: const {
            'style': 'display:flex;gap:6px;flex-wrap:wrap;',
          },
          [
            _buildTabButton(
              label: '1. PAGE ENCOUNTER',
              selected: _activeTab == _TerminalTab.encounter,
              accentColor: '#00FF41',
              onTap: () => _switchTab(_TerminalTab.encounter, encounter),
            ),
            _buildTabButton(
              label: '2. WEBAR TABLETOP (3D)',
              selected: _activeTab == _TerminalTab.webarTabletop,
              accentColor: '#ec4899',
              onTap: () => _switchTab(_TerminalTab.webarTabletop, encounter),
            ),
            _buildTabButton(
              label: '3. MOO / SSH CONSOLE',
              selected: _activeTab == _TerminalTab.subnetConsole,
              accentColor: '#38bdf8',
              onTap: () => _switchTab(_TerminalTab.subnetConsole, encounter),
            ),
          ],
        ),

        // 3. Digital Twin Node Switcher (shows whether current page is directly bound or browsing Sector 7G nodes)
        _buildNodeSelectorStrip(encounter),

        // 4. Active Tab Body
        if (_activeTab == _TerminalTab.encounter)
          _buildEncounterView(encounter, room, actor)
        else if (_activeTab == _TerminalTab.webarTabletop)
          _buildWebArTabletopView(encounter, room)
        else
          _buildSubnetConsoleView(room),

        // 5. Compact Live Feedback Tail (shown on Encounter & WebAR tabs so every button press shows instant narrative output)
        if (_activeTab != _TerminalTab.subnetConsole && _consoleLogs.isNotEmpty)
          div(
            attributes: const {
              'style':
                  'background:#03060c;border:1px solid #1e293b;border-radius:6px;padding:8px 10px;display:flex;flex-direction:column;gap:3px;max-height:92px;overflow-y:auto;',
            },
            [
              for (final line in _consoleLogs.skip(
                math.max(0, _consoleLogs.length - 4),
              ))
                div(
                  [Component.text(line)],
                  attributes: {
                    'style':
                        'font-size:10px;line-height:1.35;color:${_logColor(line)};',
                  },
                ),
            ],
          ),
      ],
    );
  }

  Component _buildTabButton({
    required String label,
    required bool selected,
    required String accentColor,
    required void Function() onTap,
  }) {
    return button(
      [Component.text(label)],
      attributes: {
        'type': 'button',
        'style':
            'flex:1;min-width:110px;padding:6px 8px;font-family:monospace;font-size:10px;font-weight:bold;border-radius:5px;cursor:pointer;border:1px solid ${selected ? accentColor : "#1e293b"};background:${selected ? accentColor : "#0f172a"};color:${selected ? "#050811" : "#cbd5e1"};',
      },
      events: {'click': (_) => onTap()},
    );
  }

  Component _buildNodeSelectorStrip(PageEncounter active) {
    const presetNodes = [
      ('7GAD01', 'Gang Ad (1p)'),
      ('7GWH01', 'Warehouse Grid'),
      ('7GDS01', 'Crew Dossier'),
    ];

    return div(
      attributes: const {
        'style':
            'display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:6px;padding:6px 8px;background:#0f172a;border:1px solid #1e293b;border-radius:6px;font-size:10px;',
      },
      [
        span(
          [
            Component.text(
              _hasDirectPageBinding && _overrideEncounterKey == null
                  ? 'DIGITAL TWIN BOUND: ${active.shortCode}'
                  : 'SECTOR 7G NODE: ${active.shortCode}',
            ),
          ],
          attributes: const {'style': 'color:#94a3b8;font-weight:bold;'},
        ),
        div(
          attributes: const {'style': 'display:flex;gap:4px;flex-wrap:wrap;'},
          [
            for (final (code, label) in presetNodes)
              button(
                [Component.text(label)],
                attributes: {
                  'type': 'button',
                  'style':
                      'padding:2px 6px;font-family:monospace;font-size:9px;border-radius:3px;cursor:pointer;border:1px solid ${active.shortCode == code ? "#00FF41" : "#334155"};background:${active.shortCode == code ? "rgba(0,255,65,0.18)" : "#080c14"};color:${active.shortCode == code ? "#00FF41" : "#94a3b8"};',
                },
                events: {
                  'click': (_) {
                    setState(() => _overrideEncounterKey = code);
                    if (_activeTab == _TerminalTab.webarTabletop) {
                      _syncWebArViewport();
                    }
                  },
                },
              ),
          ],
        ),
      ],
    );
  }

  // --- TAB 1: CONTEXTUAL PAGE ENCOUNTER (`2026 -> 2099` Evergreen Digital Twin) ---

  Component _buildEncounterView(
    PageEncounter encounter,
    WorldRoom? room,
    WorldEntity? actor,
  ) {
    return div(
      attributes: const {
        'style': 'display:flex;flex-direction:column;gap:10px;',
      },
      [
        // Encounter Header Card
        div(
          attributes: const {
            'style':
                'padding:10px 12px;background:#0f172a;border-left:3px solid #00FF41;border-radius:4px;display:flex;flex-direction:column;gap:4px;',
          },
          [
            div(
              attributes: const {
                'style':
                    'display:flex;justify-content:space-between;align-items:center;gap:6px;flex-wrap:wrap;',
              },
              [
                span(
                  [Component.text(encounter.title)],
                  attributes: const {
                    'style': 'font-weight:bold;font-size:12px;color:#f8fafc;',
                  },
                ),
                span(
                  [
                    Component.text(
                      encounter.isPublic
                          ? 'PUBLIC EVERGREEN TWIN'
                          : 'PRIVATE TURN TWIN',
                    ),
                  ],
                  attributes: {
                    'style':
                        'font-size:9px;padding:2px 6px;border-radius:3px;font-weight:bold;background:${encounter.isPublic ? "rgba(0,255,65,0.15)" : "rgba(236,72,153,0.18)"};color:${encounter.isPublic ? "#00FF41" : "#ec4899"};',
                  },
                ),
              ],
            ),
            if (encounter.subtitle.isNotEmpty)
              div(
                [Component.text(encounter.subtitle)],
                attributes: const {'style': 'font-size:10px;color:#94a3b8;'},
              ),
          ],
        ),

        // Kenney 2D Sprite Strip for Featured NPCs & Stateful MOO Props
        if (room != null) _buildKenneyRoomCards(encounter, room),

        // Contextual Action Buttons (`Buy hand grenades`, `Listen to mixtape`, `Kill gang member`, `WebAR`)
        div(
          attributes: const {
            'style': 'display:flex;flex-direction:column;gap:6px;',
          },
          [
            span(
              [Component.text('CONTEXTUAL TERMINAL ACTIONS')],
              attributes: const {
                'style':
                    'font-size:10px;font-weight:bold;color:#94a3b8;letter-spacing:0.5px;',
              },
            ),
            for (final action in encounter.actions)
              if (action.type == TerminalActionType.unlockCode)
                _buildUnlockActionRow(encounter, action, room)
              else
                _buildActionButton(encounter, action),
          ],
        ),

        // Player Inventory Pills (shows grenades / gear acquired in canonical world)
        if (actor != null && actor.inventory.isNotEmpty)
          div(
            attributes: const {
              'style':
                  'display:flex;flex-wrap:wrap;gap:6px;align-items:center;padding-top:4px;',
            },
            [
              span(
                [Component.text('GEAR:')],
                attributes: const {'style': 'font-size:10px;color:#94a3b8;'},
              ),
              for (final item in actor.inventory)
                div(
                  attributes: const {
                    'style':
                        'display:flex;align-items:center;gap:5px;padding:3px 7px;background:#0f172a;border:1px solid #334155;border-radius:4px;font-size:10px;color:#f8fafc;',
                  },
                  [
                    img(
                      src: KenneyAssetCatalog.getOrFallback(
                        item.kenneyAssetId,
                      ).sprite2dPath,
                      attributes: const {
                        'style':
                            'width:16px;height:16px;image-rendering:pixelated;border-radius:2px;',
                      },
                    ),
                    span([Component.text('${item.name} x${item.quantity}')]),
                  ],
                ),
            ],
          ),
      ],
    );
  }

  Component _buildKenneyRoomCards(PageEncounter encounter, WorldRoom room) {
    final cards = <Component>[];

    for (final entId in encounter.featuredEntityIds) {
      final ent = _worldState.entities[entId];
      if (ent == null) continue;
      final asset = KenneyAssetCatalog.getOrFallback(ent.kenneyCharacterId);
      final alive = ent.isAlive;
      cards.add(
        div(
          attributes: {
            'style':
                'display:flex;align-items:center;gap:8px;padding:7px 9px;background:#050811;border:1px solid ${alive ? "#1e293b" : "#7f1d1d"};border-radius:6px;min-width:190px;flex:1;',
          },
          [
            img(
              src: asset.sprite2dPath,
              attributes: const {
                'style':
                    'width:34px;height:34px;image-rendering:pixelated;border-radius:4px;flex-shrink:0;',
              },
            ),
            div(
              attributes: const {
                'style': 'display:flex;flex-direction:column;gap:2px;min-width:0;',
              },
              [
                span(
                  [Component.text(ent.handle)],
                  attributes: {
                    'style':
                        'font-size:11px;font-weight:bold;color:${alive ? "#f8fafc" : "#ef4444"};',
                  },
                ),
                span(
                  [
                    Component.text(
                      alive
                          ? 'ALIVE · HP ${ent.currentHp}/${ent.maxHp} · Tile ${ent.gridPos ?? "-"}'
                          : 'DEAD IN CANONICAL WORLD · Tile ${ent.gridPos ?? "-"}',
                    ),
                  ],
                  attributes: {
                    'style':
                        'font-size:9px;color:${alive ? "#00FF41" : "#f87171"};',
                  },
                ),
              ],
            ),
          ],
        ),
      );
    }

    for (final prop in room.objects) {
      if (encounter.featuredPropIds.isNotEmpty &&
          !encounter.featuredPropIds.contains(prop.id)) {
        continue;
      }
      final asset = KenneyAssetCatalog.getOrFallback(prop.kenneyAssetId);
      String statusLine = asset.kenneyKit;
      if (prop.state.containsKey('stock')) {
        statusLine =
            'Stock: ${prop.state['stock']} left · ${prop.state['priceCredits']}c ea';
      } else if (prop.state.containsKey('plays')) {
        statusLine = 'Street Plays: ${prop.state['plays']}';
      } else if (prop.state.containsKey('locked')) {
        statusLine = prop.state['locked'] == true
            ? 'KEYPAD LOCKED (4-digit)'
            : 'UNLOCKED & LOOTED';
      }

      cards.add(
        div(
          attributes: const {
            'style':
                'display:flex;align-items:center;gap:8px;padding:7px 9px;background:#050811;border:1px solid #1e293b;border-radius:6px;min-width:190px;flex:1;',
          },
          [
            img(
              src: asset.sprite2dPath,
              attributes: const {
                'style':
                    'width:34px;height:34px;image-rendering:pixelated;border-radius:4px;flex-shrink:0;',
              },
            ),
            div(
              attributes: const {
                'style': 'display:flex;flex-direction:column;gap:2px;min-width:0;',
              },
              [
                span(
                  [Component.text(prop.name)],
                  attributes: const {
                    'style': 'font-size:11px;font-weight:bold;color:#e2e8f0;',
                  },
                ),
                span(
                  [Component.text(statusLine)],
                  attributes: const {'style': 'font-size:9px;color:#38bdf8;'},
                ),
              ],
            ),
          ],
        ),
      );
    }

    return div(
      attributes: const {
        'style': 'display:flex;flex-wrap:wrap;gap:6px;',
      },
      cards,
    );
  }

  Component _buildActionButton(
    PageEncounter encounter,
    TerminalPageAction action,
  ) {
    final bool isKill = action.type == TerminalActionType.attackActor;
    final bool isAr = action.type == TerminalActionType.scanArTabletop;
    final String bg = isKill
        ? 'rgba(239,68,68,0.16)'
        : isAr
            ? 'rgba(236,72,153,0.18)'
            : 'rgba(0,255,65,0.12)';
    final String border = isKill
        ? '#ef4444'
        : isAr
            ? '#ec4899'
            : '#00FF41';
    final String fg = isKill
        ? '#fca5a5'
        : isAr
            ? '#f9a8d4'
            : '#00FF41';

    return button(
      [
        span(
          [Component.text(action.label)],
          attributes: const {'style': 'font-weight:bold;text-align:left;'},
        ),
        span(
          [Component.text('cmd: ${action.commandEquivalent}')],
          attributes: const {'style': 'font-size:9px;opacity:0.75;'},
        ),
      ],
      attributes: {
        'type': 'button',
        'style':
            'display:flex;justify-content:space-between;align-items:center;gap:8px;width:100%;padding:8px 10px;background:$bg;border:1px solid $border;color:$fg;border-radius:6px;font-family:monospace;font-size:11px;cursor:pointer;',
        if (_isBusy) 'disabled': 'true',
      },
      events: {
        'click': (_) => _handleEncounterAction(encounter, action),
      },
    );
  }

  Component _buildUnlockActionRow(
    PageEncounter encounter,
    TerminalPageAction action,
    WorldRoom? room,
  ) {
    final locker = room?.objects
        .where((o) => o.id == action.targetPropId)
        .firstOrNull;
    final bool isLocked = locker == null || locker.state['locked'] == true;

    return div(
      attributes: const {
        'style': 'display:flex;gap:6px;align-items:center;width:100%;',
      },
      [
        input(
          attributes: {
            'type': 'text',
            'maxlength': '6',
            'placeholder': isLocked
                ? '4-digit locker code (e.g. from mixtape)...'
                : 'Locker #42 already unlocked',
            'value': _lockerCodeInput,
            'style':
                'flex:1;padding:7px 9px;background:#050811;border:1px solid #38bdf8;color:#38bdf8;font-family:monospace;font-size:11px;border-radius:5px;outline:none;',
            if (!isLocked) 'disabled': 'true',
          },
          events: {
            'input': (e) =>
                setState(() => _lockerCodeInput = getInputValue(e)),
          },
        ),
        button(
          [Component.text(isLocked ? 'UNLOCK #42' : 'OPENED')],
          attributes: {
            'type': 'button',
            'style':
                'padding:7px 11px;background:${isLocked ? "#38bdf8" : "#1e293b"};color:#050811;border:none;border-radius:5px;font-family:monospace;font-size:11px;font-weight:bold;cursor:pointer;',
            if (!isLocked || _isBusy) 'disabled': 'true',
          },
          events: {
            'click': (_) => _handleEncounterAction(encounter, action),
          },
        ),
      ],
    );
  }

  // --- TAB 2: SMARTPHONE WEBAR TABLETOP (`1 Positional Anchor + Max 5 Scan-Once QR`) ---

  Component _buildWebArTabletopView(
    PageEncounter encounter,
    WorldRoom? room,
  ) {
    final sessionId = _activeSessionId(encounter);
    final session = _worldState.arSessions[sessionId];
    final int scannedCount = session?.ingestedQrCodes.length ?? 0;
    final grid = room?.gridSpec;

    // Collect all units currently placed on the grid
    final unitIds = <String>{
      ...?room?.occupantIds,
      ...?session?.unitPositions.keys,
    };

    const demoQrPresets = [
      ('7GDS01', 'Crew Dossier'),
      ('NYX-02', 'Runner Nyx'),
      ('VEX-03', 'Fixer Vex'),
      ('KAI-04', 'Netrunner Kai'),
      ('ZED-05', 'Solo Zed'),
      ('SIX-06', '6th Test (Cap)'),
    ];

    return div(
      attributes: const {
        'style': 'display:flex;flex-direction:column;gap:10px;',
      },
      [
        // 1. Anchor Tracking Header
        div(
          attributes: const {
            'style':
                'display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:6px;padding:7px 10px;background:#0f172a;border:1px solid #ec4899;border-radius:6px;font-size:10px;',
          },
          [
            span(
              [
                Component.text(
                  '1 POSITIONAL ANCHOR: ${grid?.anchorMarkerId ?? encounter.shortCode} (${grid?.width ?? 8}×${grid?.height ?? 10} Kenney .GLB Grid)',
                ),
              ],
              attributes: const {
                'style': 'color:#f9a8d4;font-weight:bold;',
              },
            ),
            span(
              [
                Component.text(
                  'SCAN-ONCE ROSTER: $scannedCount / ${TabletopArSession.maxScannedParticipants} QR',
                ),
              ],
              attributes: {
                'style':
                    'font-weight:bold;color:${scannedCount >= TabletopArSession.maxScannedParticipants ? "#facc15" : "#00FF41"};',
              },
            ),
          ],
        ),

        // 2. Live Smartphone Camera + Three.js Kenney `.glb` Viewport Container
        div(
          id: _webarContainerId,
          attributes: {
            'style':
                'width:100%;height:${component.isCompactDrawer ? "270px" : "330px"};border-radius:8px;border:1px solid #00FF41;overflow:hidden;position:relative;background:#050811;',
          },
          const [],
        ),

        // 3. Scan-Once (+5 QR) Camera & Shortcode Roster Controls
        div(
          attributes: const {
            'style':
                'padding:9px 10px;background:#0f172a;border:1px solid #1e293b;border-radius:6px;display:flex;flex-direction:column;gap:7px;',
          },
          [
            div(
              attributes: const {
                'style':
                    'display:flex;justify-content:space-between;align-items:center;gap:6px;flex-wrap:wrap;',
              },
              [
                span(
                  [
                    Component.text(
                      'SCAN-ONCE PLAYER / PAGE INGEST (MAX 5 QR — NO MULTI-QR POSE JITTER)',
                    ),
                  ],
                  attributes: const {
                    'style': 'font-size:9px;font-weight:bold;color:#cbd5e1;',
                  },
                ),
                button(
                  [
                    Component.text(
                      _isCameraQrScanning
                          ? '● CANCEL CAMERA SCAN'
                          : '📷 SCAN QR WITH CAMERA',
                    ),
                  ],
                  attributes: {
                    'type': 'button',
                    'style':
                        'padding:4px 8px;background:${_isCameraQrScanning ? "#ef4444" : "#ec4899"};color:#fff;border:none;border-radius:4px;font-family:monospace;font-size:10px;font-weight:bold;cursor:pointer;',
                  },
                  events: {
                    'click': (_) {
                      final next = !_isCameraQrScanning;
                      setState(() => _isCameraQrScanning = next);
                      setTerminalWebArScanMode(_webarContainerId, next);
                    },
                  },
                ),
              ],
            ),
            div(
              attributes: const {'style': 'display:flex;gap:6px;'},
              [
                input(
                  attributes: {
                    'type': 'text',
                    'placeholder': 'Or enter printed QR shortcode (e.g. 7GDS01)...',
                    'value': _qrScanInput,
                    'style':
                        'flex:1;padding:6px 8px;background:#050811;border:1px solid #334155;color:#f8fafc;font-family:monospace;font-size:11px;border-radius:4px;outline:none;',
                  },
                  events: {
                    'input': (e) =>
                        setState(() => _qrScanInput = getInputValue(e)),
                  },
                ),
                button(
                  [Component.text('+ INGEST QR')],
                  attributes: const {
                    'type': 'button',
                    'style':
                        'padding:6px 10px;background:#00FF41;color:#050811;border:none;border-radius:4px;font-family:monospace;font-size:10px;font-weight:bold;cursor:pointer;',
                  },
                  events: {
                    'click': (_) => _handleIngestQrCode(_qrScanInput),
                  },
                ),
              ],
            ),
            // Quick-tap tabletop scenario QR chips for instant testing
            div(
              attributes: const {
                'style': 'display:flex;flex-wrap:wrap;gap:4px;',
              },
              [
                for (final (qr, handle) in demoQrPresets)
                  button(
                    [Component.text('+$qr')],
                    attributes: {
                      'type': 'button',
                      'title': 'Scan $handle ($qr) once into tabletop grid',
                      'style':
                          'padding:2px 6px;background:#080c14;border:1px solid #334155;color:#38bdf8;border-radius:3px;font-family:monospace;font-size:9px;cursor:pointer;',
                    },
                    events: {
                      'click': (_) =>
                          _handleIngestQrCode(qr, fallbackHandle: handle),
                    },
                  ),
              ],
            ),
          ],
        ),

        // 4. Active Tabletop Miniatures & Tap / D-Pad Tactical Movement
        div(
          attributes: const {
            'style':
                'display:flex;flex-direction:column;gap:6px;padding:8px 10px;background:#050811;border:1px solid #1e293b;border-radius:6px;',
          },
          [
            div(
              attributes: const {
                'style':
                    'display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:6px;',
              },
              [
                span(
                  [
                    Component.text(
                      'SELECT MINIATURE (THEN TAP 3D GRID OR STEP):',
                    ),
                  ],
                  attributes: const {
                    'style': 'font-size:9px;font-weight:bold;color:#94a3b8;',
                  },
                ),
                div(
                  attributes: const {'style': 'display:flex;gap:4px;'},
                  [
                    _buildStepBtn('← W', -1, 0),
                    _buildStepBtn('↑ N', 0, -1),
                    _buildStepBtn('↓ S', 0, 1),
                    _buildStepBtn('E →', 1, 0),
                  ],
                ),
              ],
            ),
            div(
              attributes: const {
                'style': 'display:flex;flex-wrap:wrap;gap:5px;',
              },
              [
                for (final id in unitIds)
                  if (_worldState.entities[id] != null)
                    _buildMiniatureChip(
                      _worldState.entities[id]!,
                      session?.unitPositions[id] ??
                          _worldState.entities[id]!.gridPos,
                    ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Component _buildStepBtn(String label, int dx, int dy) {
    return button(
      [Component.text(label)],
      attributes: const {
        'type': 'button',
        'style':
            'padding:3px 7px;background:#0f172a;border:1px solid #00FF41;color:#00FF41;border-radius:4px;font-family:monospace;font-size:10px;font-weight:bold;cursor:pointer;',
      },
      events: {
        'click': (_) => _handleStepSelectedUnit(dx, dy),
      },
    );
  }

  Component _buildMiniatureChip(WorldEntity ent, GridCoordinate? pos) {
    final bool selected = ent.id == _selectedArEntityId;
    final asset = KenneyAssetCatalog.getOrFallback(ent.kenneyCharacterId);
    return button(
      [
        img(
          src: asset.sprite2dPath,
          attributes: const {
            'style':
                'width:16px;height:16px;image-rendering:pixelated;border-radius:2px;',
          },
        ),
        span([
          Component.text(
            '${ent.handle} ${pos ?? ""}${ent.isAlive ? "" : " [DEAD]"}',
          ),
        ]),
      ],
      attributes: {
        'type': 'button',
        'style':
            'display:flex;align-items:center;gap:5px;padding:4px 8px;border-radius:4px;font-family:monospace;font-size:10px;cursor:pointer;border:1px solid ${selected ? "#00FF41" : "#334155"};background:${selected ? "rgba(0,255,65,0.18)" : "#0f172a"};color:${!ent.isAlive ? "#ef4444" : (selected ? "#00FF41" : "#e2e8f0")};',
      },
      events: {
        'click': (_) {
          setState(() => _selectedArEntityId = ent.id);
          _syncWebArViewport();
        },
      },
    );
  }

  // --- TAB 3: REAL-TIME MOO / SSH SUBNET CONSOLE ---

  Component _buildSubnetConsoleView(WorldRoom? room) {
    const quickCmds = [
      'look',
      'examine crate',
      'buy grenade',
      'listen',
      'unlock locker 7742',
      'status',
      'inventory',
      'help',
    ];

    return div(
      attributes: const {
        'style': 'display:flex;flex-direction:column;gap:8px;',
      },
      [
        if (room != null)
          div(
            [
              Component.text(
                'SSH / MOO ROOM BINDING: ${room.title} (${room.id})',
              ),
            ],
            attributes: const {
              'style': 'font-size:10px;color:#38bdf8;font-weight:bold;',
            },
          ),
        div(
          attributes: {
            'style':
                'height:${component.isCompactDrawer ? "190px" : "270px"};overflow-y:auto;background:#03060c;border:1px solid #005522;padding:10px;border-radius:6px;display:flex;flex-direction:column;gap:4px;font-size:11px;line-height:1.4;',
          },
          [
            for (final line in _consoleLogs)
              div(
                [Component.text(line)],
                attributes: {
                  'style': 'color:${_logColor(line)};white-space:pre-wrap;',
                },
              ),
          ],
        ),
        div(
          attributes: const {'style': 'display:flex;flex-wrap:wrap;gap:4px;'},
          [
            for (final cmd in quickCmds)
              button(
                [Component.text(cmd)],
                attributes: const {
                  'type': 'button',
                  'style':
                      'padding:2px 7px;background:#0f172a;border:1px solid #1e293b;color:#94a3b8;border-radius:3px;font-family:monospace;font-size:9px;cursor:pointer;',
                },
                events: {
                  'click': (_) => _handleConsoleSubmit(cmd),
                },
              ),
          ],
        ),
        div(
          attributes: const {
            'style': 'display:flex;gap:6px;align-items:center;',
          },
          [
            span(
              [Component.text('>')],
              attributes: const {
                'style': 'font-weight:bold;color:#00FF41;font-size:13px;',
              },
            ),
            input(
              attributes: {
                'type': 'text',
                'placeholder':
                    'Enter MOO/SSH command (look, buy grenade, listen, kill razor)...',
                'value': _consoleInput,
                'style':
                    'flex:1;padding:7px 10px;background:#03060c;border:1px solid #00FF41;color:#00FF41;font-family:monospace;font-size:11px;border-radius:5px;outline:none;',
              },
              events: {
                'input': (e) =>
                    setState(() => _consoleInput = getInputValue(e)),
              },
            ),
            button(
              [Component.text('SEND')],
              attributes: {
                'type': 'button',
                'style':
                    'padding:7px 12px;background:#00FF41;color:#050811;border:none;border-radius:5px;font-family:monospace;font-size:11px;font-weight:bold;cursor:pointer;',
                if (_isBusy) 'disabled': 'true',
              },
              events: {
                'click': (_) => _handleConsoleSubmit(),
              },
            ),
          ],
        ),
      ],
    );
  }

  String _logColor(String line) {
    if (line.contains('TARGET DOWN') ||
        line.contains('DEAD') ||
        line.contains('DENIED') ||
        line.contains('SOLD OUT')) {
      return '#f87171';
    }
    if (line.startsWith('>')) {
      return '#38bdf8';
    }
    if (line.contains('NOW PLAYING') || line.contains('WEBAR')) {
      return '#f472b6';
    }
    if (line.contains('CLACK-HISS') || line.contains('Purchased')) {
      return '#00FF41';
    }
    return '#a7f3d0';
  }
}
