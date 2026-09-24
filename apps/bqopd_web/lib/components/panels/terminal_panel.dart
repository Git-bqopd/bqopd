import 'dart:async';
import 'dart:math';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';
import '../../repositories/repositories.dart';

/// Dedicated inline drawer (bonusRow) terminal panel.
class TerminalRowPanel extends StatefulComponent {
  final String imageId;
  const TerminalRowPanel({required this.imageId, super.key});

  @override
  State<TerminalRowPanel> createState() => _TerminalRowPanelState();
}

class _TerminalRowPanelState extends State<TerminalRowPanel> {
  late final IGameService _gameService;
  StreamSubscription? _myCharSub;
  StreamSubscription? _publicCharSub;
  List<GameCharacter> _publicTargets = [];
  GameCharacter? _selectedMyChar;
  GameCharacter? _selectedEnemyChar;
  bool _inCombatMode = false;
  bool _isAutoCombat = false;
  bool _isGameOver = false;
  final List<String> _terminalLogs = [];
  int _playerHp = 0;
  int _enemyHp = 0;

  @override
  void initState() {
    super.initState();
    _gameService = createGameService();
    if (kIsWeb) {
      _initGameData();
    }
  }

  @override
  void dispose() {
    _myCharSub?.cancel();
    _publicCharSub?.cancel();
    super.dispose();
  }

  void _initGameData() {
    final uid = getCurrentUserId();
    if (uid == null) return;
    _myCharSub = _gameService.getMyCharacters(uid).listen((chars) {
      if (mounted) {
        setState(() {
          if (_selectedMyChar == null && chars.isNotEmpty) {
            _selectedMyChar = chars.first;
          }
        });
      }
    });
    _publicCharSub = _gameService.getPublicCharacters(uid).listen((targets) {
      if (mounted) {
        setState(() {
          _publicTargets = targets;
        });
      }
    });
  }

  void _startCombatSession(GameCharacter targetEnemy) {
    if (_selectedMyChar == null) return;
    setState(() {
      _selectedEnemyChar = targetEnemy;
      _playerHp = _selectedMyChar!.maxHp;
      _enemyHp = targetEnemy.maxHp;
      _inCombatMode = true;
      _isAutoCombat = false;
      _isGameOver = false;
      _terminalLogs.clear();
      _terminalLogs.add("Welcome to TERMINAL, CA.");
      _terminalLogs.add("Connected to sector 7G...");
      _terminalLogs.add("Target acquired: ${targetEnemy.name} (Level 1)");
      _terminalLogs.add("Type 'kill' or click ATTACK to initiate combat.");
    });
  }

  void _executeCommand(String rawCmd) {
    if (!_inCombatMode || _isGameOver) return;
    final cmd = rawCmd.trim().toLowerCase();
    setState(() {
      _terminalLogs.add("> $rawCmd");
    });
    if (cmd == 'kill' || cmd == 'attack' || cmd == 'k') {
      if (!_isAutoCombat) {
        setState(() => _isAutoCombat = true);
        _terminalLogs.add("INITIATING COMBAT SEQUENCE...");
        _runCombatLoop();
      }
    } else if (cmd == 'exit' || cmd == 'quit') {
      setState(() {
        _inCombatMode = false;
        _isAutoCombat = false;
      });
    }
  }

  Future<void> _runCombatLoop() async {
    final rand = Random();
    final player = _selectedMyChar!;
    final enemy = _selectedEnemyChar!;

    while (!_isGameOver && mounted) {
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;

      int roll = rand.nextInt(20) + 1;
      int attackVal = roll + player.str;
      int enemyAc = 10 + enemy.dex;

      if (attackVal >= enemyAc) {
        int dmg = rand.nextInt(6) + 1 + (player.str ~/ 2);
        _enemyHp = max(0, _enemyHp - dmg);
        setState(() => _terminalLogs.add("You hit ${enemy.name} for $dmg damage! [HP: $_enemyHp/${enemy.maxHp}]"));
      } else {
        setState(() => _terminalLogs.add("You missed ${enemy.name}!"));
      }

      if (_enemyHp <= 0) {
        setState(() {
          _terminalLogs.add(">>> VICTORY IS YOURS! Target defeated.");
          _isGameOver = true;
          _isAutoCombat = false;
        });
        _gameService.saveBattleLog(BattleLog(
          id: '',
          attackerId: player.id,
          defenderId: enemy.id,
          attackerName: player.name,
          defenderName: enemy.name,
          logs: List.from(_terminalLogs),
          winnerId: player.id,
          timestamp: DateTime.now(),
        ));
        break;
      }

      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      roll = rand.nextInt(20) + 1;
      int eAttackVal = roll + enemy.str;
      int playerAc = 10 + player.dex;

      if (eAttackVal >= playerAc) {
        int dmg = rand.nextInt(6) + 1 + (enemy.str ~/ 2);
        _playerHp = max(0, _playerHp - dmg);
        setState(() => _terminalLogs.add("WARNING: ${enemy.name} hit you for $dmg damage! [HP: $_playerHp/${player.maxHp}]"));
      } else {
        setState(() => _terminalLogs.add("${enemy.name} missed you!"));
      }

      if (_playerHp <= 0) {
        setState(() {
          _terminalLogs.add(">>> CRITICAL FAILURE. You were defeated.");
          _isGameOver = true;
          _isAutoCombat = false;
        });
        _gameService.saveBattleLog(BattleLog(
          id: '',
          attackerId: player.id,
          defenderId: enemy.id,
          attackerName: player.name,
          defenderName: enemy.name,
          logs: List.from(_terminalLogs),
          winnerId: enemy.id,
          timestamp: DateTime.now(),
        ));
        break;
      }
    }
  }

  @override
  Component build(BuildContext context) {
    final uid = getCurrentUserId();
    if (uid == null) {
      return div(
        classes: 'p-6 text-center flex-col items-center justify-center gap-3',
        attributes: const {'style': 'display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 24px; background: #0d0d0d; color: #00FF41; border-radius: 8px; font-family: monospace;'},
        [
          span([Component.text('terminal')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 42px; color: #00FF41;'}),
          p([Component.text('CA COMBAT TERMINAL ACCESS RESTRICTED')]),
          button(
            [Component.text('SIGN IN / REGISTER')],
            classes: 'btn-primary mt-2',
            attributes: const {'style': 'background-color: #00FF41; color: #000; border: none; padding: 8px 16px; font-weight: bold; border-radius: 4px; cursor: pointer; font-family: monospace;'},
            events: {'click': (e) => GlobalModalBus.show()},
          )
        ],
      );
    }

    return div(
        classes: 'terminal-inline-box',
        attributes: const {
          'style': 'padding: 14px; background: #0d0d0d; color: #00FF41; border-radius: 8px; font-family: "Courier New", Courier, monospace; width: 100%; box-sizing: border-box;'
        },
        [
          div([Component.text('TERMINAL, CA // INLINE CONSOLE')], attributes: const {'style': 'font-weight: bold; font-size: 12px; margin-bottom: 8px;'}),
          if (_inCombatMode)
            div([
              div([Component.text('${_selectedMyChar?.name} (HP: $_playerHp) VS ${_selectedEnemyChar?.name} (HP: $_enemyHp)')], attributes: const {'style': 'font-weight: bold; font-size: 11px; margin-bottom: 6px;'}),
              div([
                for (var line in _terminalLogs.skip(max(0, _terminalLogs.length - 6)))
                  div([Component.text(line)], attributes: const {'style': 'font-size: 10px; line-height: 1.3;'}),
              ]),
              div([
                button([Component.text('ATTACK')], attributes: const {'style': 'background: #00FF41; color: #000; border: none; padding: 4px 8px; font-weight: bold; font-size: 10px; cursor: pointer; border-radius: 2px; margin-top: 6px;'}, events: {'click': (e) => _executeCommand('kill')}),
                span([], attributes: const {'style': 'display: inline-block; width: 8px;'}),
                button([Component.text('EXIT')], attributes: const {'style': 'background: #333; color: #fff; border: 1px solid #666; padding: 4px 8px; font-size: 10px; cursor: pointer; border-radius: 2px;'}, events: {'click': (e) => setState(() => _inCombatMode = false)}),
              ], attributes: const {'style': 'margin-top: 6px;'}),
            ])
          else
            div([
              if (_publicTargets.isNotEmpty)
                div([
                  span([Component.text('Target: ${_publicTargets.first.name}')], attributes: const {'style': 'font-size: 11px;'}),
                  span([], attributes: const {'style': 'display: inline-block; width: 12px;'}),
                  button([Component.text('FIGHT')], attributes: const {'style': 'background: #ff5252; color: #fff; border: none; padding: 3px 8px; font-size: 10px; cursor: pointer; font-weight: bold; border-radius: 2px;'}, events: {'click': (e) => _startCombatSession(_publicTargets.first)}),
                ])
              else
                p([Component.text('No combat targets detected.')], attributes: const {'style': 'font-size: 11px; color: #888;'}),
            ])
        ]
    );
  }
}

/// Dedicated desktop 3rd column (bonusColumn) full-height CRT console workstation.
class TerminalColumnPanel extends StatefulComponent {
  final String imageId;
  const TerminalColumnPanel({required this.imageId, super.key});

  @override
  State<TerminalColumnPanel> createState() => _TerminalColumnPanelState();
}

class _TerminalColumnPanelState extends State<TerminalColumnPanel> {
  late final IGameService _gameService;
  StreamSubscription? _myCharSub;
  StreamSubscription? _publicCharSub;
  List<GameCharacter> _myCharacters = [];
  List<GameCharacter> _publicTargets = [];
  GameCharacter? _selectedMyChar;
  GameCharacter? _selectedEnemyChar;
  bool _inCombatMode = false;
  bool _isAutoCombat = false;
  bool _isGameOver = false;
  bool _isCreatingChar = false;
  String _newCharName = '';
  String _commandInput = '';
  final List<String> _terminalLogs = [];
  int _playerHp = 0;
  int _enemyHp = 0;

  @override
  void initState() {
    super.initState();
    _gameService = createGameService();
    if (kIsWeb) {
      _initGameData();
    }
  }

  @override
  void dispose() {
    _myCharSub?.cancel();
    _publicCharSub?.cancel();
    super.dispose();
  }

  void _initGameData() {
    final uid = getCurrentUserId();
    if (uid == null) return;
    _myCharSub = _gameService.getMyCharacters(uid).listen((chars) {
      if (mounted) {
        setState(() {
          _myCharacters = chars;
          if (_selectedMyChar == null && chars.isNotEmpty) {
            _selectedMyChar = chars.first;
          }
        });
      }
    });
    _publicCharSub = _gameService.getPublicCharacters(uid).listen((targets) {
      if (mounted) {
        setState(() {
          _publicTargets = targets;
        });
      }
    });
  }

  Future<void> _handleCreateCharacter() async {
    final name = _newCharName.trim();
    if (name.isEmpty) return;
    final uid = getCurrentUserId();
    if (uid == null) {
      GlobalModalBus.show();
      return;
    }
    setState(() => _isCreatingChar = true);
    try {
      await _gameService.createCharacter(uid, name);
      if (mounted) {
        setState(() {
          _newCharName = '';
          _isCreatingChar = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isCreatingChar = false);
    }
  }

  void _startCombatSession(GameCharacter targetEnemy) {
    if (_selectedMyChar == null) return;
    setState(() {
      _selectedEnemyChar = targetEnemy;
      _playerHp = _selectedMyChar!.maxHp;
      _enemyHp = targetEnemy.maxHp;
      _inCombatMode = true;
      _isAutoCombat = false;
      _isGameOver = false;
      _terminalLogs.clear();
      _terminalLogs.add("Welcome to TERMINAL, CA.");
      _terminalLogs.add("Connected to sector 7G...");
      _terminalLogs.add("Target acquired: ${targetEnemy.name} (Level 1)");
      _terminalLogs.add("Type 'kill' or click ATTACK to initiate combat sequence.");
    });
  }

  void _executeCommand(String rawCmd) {
    if (!_inCombatMode || _isGameOver) return;
    final cmd = rawCmd.trim().toLowerCase();
    setState(() {
      _terminalLogs.add("> $rawCmd");
      _commandInput = '';
    });
    if (cmd == 'kill' || cmd == 'attack' || cmd == 'k' || cmd == 'fight') {
      if (!_isAutoCombat) {
        setState(() => _isAutoCombat = true);
        _terminalLogs.add("INITIATING COMBAT SEQUENCE...");
        _runCombatLoop();
      }
    } else if (cmd == 'exit' || cmd == 'quit') {
      setState(() {
        _inCombatMode = false;
        _isAutoCombat = false;
      });
    } else if (cmd == 'help') {
      setState(() {
        _terminalLogs.add("AVAILABLE COMMANDS:");
        _terminalLogs.add("  kill / attack / k - Start turn-based combat");
        _terminalLogs.add("  exit / quit       - Abort combat session");
      });
    } else {
      setState(() => _terminalLogs.add("Unknown command '$cmd'. Type 'kill' or 'help'."));
    }
  }

  Future<void> _runCombatLoop() async {
    final rand = Random();
    final player = _selectedMyChar!;
    final enemy = _selectedEnemyChar!;

    while (!_isGameOver && mounted) {
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!mounted) return;

      int roll = rand.nextInt(20) + 1;
      int attackVal = roll + player.str;
      int enemyAc = 10 + enemy.dex;

      if (attackVal >= enemyAc) {
        int dmg = rand.nextInt(6) + 1 + (player.str ~/ 2);
        _enemyHp = max(0, _enemyHp - dmg);
        setState(() => _terminalLogs.add("You hit ${enemy.name} for $dmg damage! [Target HP: $_enemyHp/${enemy.maxHp}]"));
      } else {
        setState(() => _terminalLogs.add("You missed ${enemy.name}! (Roll: $roll)"));
      }

      if (_enemyHp <= 0) {
        setState(() {
          _terminalLogs.add(">>> VICTORY IS YOURS! Target incapacitated.");
          _isGameOver = true;
          _isAutoCombat = false;
        });
        _gameService.saveBattleLog(BattleLog(
          id: '',
          attackerId: player.id,
          defenderId: enemy.id,
          attackerName: player.name,
          defenderName: enemy.name,
          logs: List.from(_terminalLogs),
          winnerId: player.id,
          timestamp: DateTime.now(),
        ));
        break;
      }

      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;

      roll = rand.nextInt(20) + 1;
      int eAttackVal = roll + enemy.str;
      int playerAc = 10 + player.dex;

      if (eAttackVal >= playerAc) {
        int dmg = rand.nextInt(6) + 1 + (enemy.str ~/ 2);
        _playerHp = max(0, _playerHp - dmg);
        setState(() => _terminalLogs.add("WARNING: ${enemy.name} hit you for $dmg damage! [Your HP: $_playerHp/${player.maxHp}]"));
      } else {
        setState(() => _terminalLogs.add("${enemy.name} missed you! (Roll: $roll)"));
      }

      if (_playerHp <= 0) {
        setState(() {
          _terminalLogs.add(">>> CRITICAL FAILURE. You were defeated.");
          _isGameOver = true;
          _isAutoCombat = false;
        });
        _gameService.saveBattleLog(BattleLog(
          id: '',
          attackerId: player.id,
          defenderId: enemy.id,
          attackerName: player.name,
          defenderName: enemy.name,
          logs: List.from(_terminalLogs),
          winnerId: enemy.id,
          timestamp: DateTime.now(),
        ));
        break;
      }
    }
  }

  @override
  Component build(BuildContext context) {
    final uid = getCurrentUserId();
    if (uid == null) {
      return div(
        classes: 'p-6 text-center flex-col items-center justify-center gap-3',
        attributes: const {'style': 'display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 24px; background: #0d0d0d; color: #00FF41; border-radius: 8px; font-family: monospace;'},
        [
          span([Component.text('terminal')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 42px; color: #00FF41;'}),
          p([Component.text('CA COMBAT TERMINAL ACCESS RESTRICTED')]),
          button(
            [Component.text('SIGN IN / REGISTER')],
            classes: 'btn-primary mt-2',
            attributes: const {'style': 'background-color: #00FF41; color: #000; border: none; padding: 8px 16px; font-weight: bold; border-radius: 4px; cursor: pointer; font-family: monospace;'},
            events: {'click': (e) => GlobalModalBus.show()},
          )
        ],
      );
    }

    if (_inCombatMode) {
      return div(
        classes: 'terminal-combat-container flex-col gap-3',
        attributes: const {
          'style': 'display: flex; flex-direction: column; gap: 12px; padding: 16px; background: #0d0d0d; color: #00FF41; border-radius: 8px; font-family: "Courier New", Courier, monospace; box-sizing: border-box; width: 100%;'
        },
        [
          div(
            attributes: const {'style': 'display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #00FF41; padding-bottom: 8px;'},
            [
              div([
                span([Component.text('${_selectedMyChar?.name} ')], attributes: const {'style': 'font-weight: bold; color: #00FF41;'}),
                span([Component.text('HP: $_playerHp/${_selectedMyChar?.maxHp}')], attributes: const {'style': 'font-size: 11px; color: #00CC33;'}),
              ]),
              span([Component.text('VS')], attributes: const {'style': 'font-weight: bold; color: #888; font-size: 10px;'}),
              div([
                span([Component.text('${_selectedEnemyChar?.name} ')], attributes: const {'style': 'font-weight: bold; color: #ff5252;'}),
                span([Component.text('HP: $_enemyHp/${_selectedEnemyChar?.maxHp}')], attributes: const {'style': 'font-size: 11px; color: #ff8888;'}),
              ]),
            ],
          ),
          div(
            attributes: const {
              'style': 'height: 280px; overflow-y: auto; background: #000; border: 1px solid #005511; padding: 10px; border-radius: 4px; display: flex; flex-direction: column; gap: 4px; font-size: 11px; line-height: 1.4;'
            },
            [
              for (var line in _terminalLogs)
                div(
                  [Component.text(line)],
                  attributes: {
                    'style': 'color: ${line.startsWith("WARNING") || line.contains("DEFEATED") ? "#ff5252" : (line.contains("VICTORY") ? "#00FF41" : "#00CC33")};'
                  },
                ),
            ],
          ),
          div(
            attributes: const {'style': 'display: flex; gap: 8px; align-items: center;'},
            [
              span([Component.text('>')], attributes: const {'style': 'font-weight: bold; color: #00FF41;'}),
              input(
                attributes: {
                  'type': 'text',
                  'placeholder': "type 'kill' or click attack...",
                  'value': _commandInput,
                  'style': 'flex: 1; padding: 6px 10px; background: #000; border: 1px solid #00FF41; color: #00FF41; font-family: monospace; font-size: 12px; border-radius: 4px; outline: none;',
                  if (_isGameOver) 'disabled': 'true',
                },
                events: {
                  'input': (e) => _commandInput = getInputValue(e),
                },
              ),
              if (!_isAutoCombat && !_isGameOver)
                button(
                  [Component.text('ATTACK')],
                  attributes: const {
                    'type': 'button',
                    'style': 'background: #00FF41; color: #000; border: none; padding: 6px 14px; font-weight: bold; font-family: monospace; font-size: 11px; cursor: pointer; border-radius: 4px;'
                  },
                  events: {
                    'click': (e) => _executeCommand('kill')
                  },
                ),
              button(
                [Component.text(_isGameOver ? 'EXIT' : 'ABORT')],
                attributes: const {
                  'type': 'button',
                  'style': 'background: #333; color: #fff; border: 1px solid #666; padding: 6px 12px; font-weight: bold; font-family: monospace; font-size: 11px; cursor: pointer; border-radius: 4px;'
                },
                events: {
                  'click': (e) => setState(() {
                    _inCombatMode = false;
                    _isAutoCombat = false;
                  })
                },
              )
            ],
          )
        ],
      );
    }

    return div(
      classes: 'terminal-lobby-container flex-col gap-4',
      attributes: const {
        'style': 'display: flex; flex-direction: column; gap: 16px; padding: 16px; background: #0d0d0d; color: #00FF41; border-radius: 8px; font-family: "Courier New", Courier, monospace; box-sizing: border-box; width: 100%;'
      },
      [
        div(
          attributes: const {'style': 'display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #00FF41; padding-bottom: 8px;'},
          [
            span([Component.text('TERMINAL, CA // LOBBY')], attributes: const {'style': 'font-weight: bold; font-size: 14px; letter-spacing: 1px;'}),
            span([Component.text('SECTOR 7G')], attributes: const {'style': 'font-size: 10px; color: #00CC33;'}),
          ],
        ),
        div(
          classes: 'flex-col gap-2',
          attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px;'},
          [
            span([Component.text('MY PERSONAS')], attributes: const {'style': 'font-size: 11px; font-weight: bold; text-transform: uppercase;'}),
            if (_myCharacters.isNotEmpty)
              div(
                attributes: const {'style': 'display: flex; gap: 8px; overflow-x: auto; padding-bottom: 4px;'},
                [
                  for (var char in _myCharacters)
                    div(
                      attributes: {
                        'style': 'padding: 8px 12px; background: ${_selectedMyChar?.id == char.id ? "rgba(0, 255, 65, 0.15)" : "#000"}; border: 1px solid ${_selectedMyChar?.id == char.id ? "#00FF41" : "#005511"}; border-radius: 4px; cursor: pointer; min-width: 130px; box-sizing: border-box;',
                      },
                      events: {
                        'click': (e) => setState(() => _selectedMyChar = char)
                      },
                      [
                        div([Component.text(char.name)], attributes: const {'style': 'font-weight: bold; font-size: 12px; color: #00FF41;'}),
                        div([Component.text('HP: ${char.maxHp} | W:${char.wins} L:${char.losses}')], attributes: const {'style': 'font-size: 9px; color: #00CC33; margin-top: 2px;'}),
                      ],
                    ),
                ],
              ),
            div(
              attributes: const {'style': 'display: flex; gap: 8px; margin-top: 4px;'},
              [
                input(
                  attributes: {
                    'type': 'text',
                    'placeholder': 'New character name...',
                    'value': _newCharName,
                    'style': 'flex: 1; padding: 6px 10px; background: #000; border: 1px solid #00FF41; color: #00FF41; font-family: monospace; font-size: 12px; border-radius: 4px; outline: none;',
                  },
                  events: {
                    'input': (e) => setState(() => _newCharName = getInputValue(e))
                  },
                ),
                button(
                  [Component.text(_isCreatingChar ? 'ROLLING...' : '+ CREATE')],
                  attributes: {
                    'type': 'button',
                    'style': 'background: #00FF41; color: #000; border: none; padding: 6px 12px; font-size: 11px; font-weight: bold; font-family: monospace; cursor: pointer; border-radius: 4px;',
                    if (_isCreatingChar) 'disabled': 'true',
                  },
                  events: {
                    'click': (e) => _handleCreateCharacter()
                  },
                )
              ],
            ),
          ],
        ),
        div([], attributes: const {'style': 'height: 1px; background-color: rgba(0, 255, 65, 0.2); margin: 4px 0;'}),
        div(
          classes: 'flex-col gap-2',
          attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px;'},
          [
            span([Component.text('DETECTED TARGETS')], attributes: const {'style': 'font-size: 11px; font-weight: bold; text-transform: uppercase;'}),
            for (var enemy in _publicTargets)
              div(
                attributes: const {
                  'style': 'display: flex; align-items: center; justify-content: space-between; padding: 8px 12px; background: #000; border: 1px solid rgba(0, 255, 65, 0.2); border-radius: 4px;'
                },
                [
                  span([Component.text(enemy.name)], attributes: const {'style': 'font-weight: bold; font-size: 12px; color: #00FF41;'}),
                  button(
                    [Component.text('ATTACK')],
                    attributes: const {
                      'type': 'button',
                      'style': 'background: #ff5252; color: #fff; border: none; padding: 4px 10px; font-size: 10px; font-weight: bold; font-family: monospace; cursor: pointer; border-radius: 3px;'
                    },
                    events: {
                      'click': (e) => _startCombatSession(enemy)
                    },
                  )
                ],
              )
          ],
        )
      ],
    );
  }
}

/// Backwards-compatible alias
typedef TerminalPanel = TerminalColumnPanel;