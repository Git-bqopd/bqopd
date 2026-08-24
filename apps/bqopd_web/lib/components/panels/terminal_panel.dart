import 'dart:async';
import 'dart:math';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';
import '../../repositories/repositories.dart';

/// Full-featured Jaspr Web Terminal Game Component.
/// Replicates the mobile CA Combat Terminal experience with a retro green-on-black CRT theme.
class TerminalPanel extends StatefulComponent {
  final String imageId;

  const TerminalPanel({required this.imageId, super.key});

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  late final IGameService _gameService;

  // Streams & Subscriptions
  StreamSubscription? _myCharSub;
  StreamSubscription? _publicCharSub;

  List<GameCharacter> _myCharacters = [];
  List<GameCharacter> _publicTargets = [];

  GameCharacter? _selectedMyChar;
  GameCharacter? _selectedEnemyChar;

  // Combat Terminal UI State
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

    _myCharSub?.cancel();
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

    _publicCharSub?.cancel();
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
    } catch (e) {
      print('[TerminalPanel createCharacter Error] $e');
      if (mounted) {
        setState(() => _isCreatingChar = false);
      }
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

  void _appendLog(String line) {
    if (!mounted) return;
    setState(() {
      _terminalLogs.add(line);
    });
  }

  void _executeCommand(String rawCmd) {
    if (!_inCombatMode || _isGameOver) return;
    final cmd = rawCmd.trim().toLowerCase();
    _appendLog("> $rawCmd");
    setState(() => _commandInput = '');

    if (cmd == 'kill' || cmd == 'attack' || cmd == 'k' || cmd == 'fight') {
      if (!_isAutoCombat) {
        setState(() => _isAutoCombat = true);
        _appendLog("INITIATING COMBAT SEQUENCE...");
        _runCombatLoop();
      }
    } else if (cmd == 'exit' || cmd == 'quit') {
      setState(() {
        _inCombatMode = false;
        _isAutoCombat = false;
      });
    } else if (cmd == 'help') {
      _appendLog("AVAILABLE COMMANDS:");
      _appendLog("  kill / attack / k - Start turn-based combat");
      _appendLog("  exit / quit       - Abort combat session");
    } else {
      _appendLog("Unknown command '$cmd'. Type 'kill' or 'help'.");
    }
  }

  Future<void> _runCombatLoop() async {
    final rand = Random();
    final player = _selectedMyChar!;
    final enemy = _selectedEnemyChar!;

    while (!_isGameOver && mounted) {
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!mounted) return;

      // --- PLAYER TURN ---
      int roll = rand.nextInt(20) + 1;
      int attackVal = roll + player.str;
      int enemyAc = 10 + enemy.dex;

      if (attackVal >= enemyAc) {
        int dmg = rand.nextInt(6) + 1 + (player.str ~/ 2);
        _enemyHp = max(0, _enemyHp - dmg);
        _appendLog("You hit ${enemy.name} for $dmg damage! [Target HP: $_enemyHp/${enemy.maxHp}]");
      } else {
        _appendLog("You missed ${enemy.name}! (Roll: $roll)");
      }

      if (_enemyHp <= 0) {
        _appendLog(">>> VICTORY IS YOURS! Target incapacitated.");
        _endCombat(winnerId: player.id);
        break;
      }

      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;

      // --- ENEMY TURN ---
      roll = rand.nextInt(20) + 1;
      int eAttackVal = roll + enemy.str;
      int playerAc = 10 + player.dex;

      if (eAttackVal >= playerAc) {
        int dmg = rand.nextInt(6) + 1 + (enemy.str ~/ 2);
        _playerHp = max(0, _playerHp - dmg);
        _appendLog("WARNING: ${enemy.name} hit you for $dmg damage! [Your HP: $_playerHp/${player.maxHp}]");
      } else {
        _appendLog("${enemy.name} missed you! (Roll: $roll)");
      }

      if (_playerHp <= 0) {
        _appendLog(">>> CRITICAL FAILURE. You were defeated.");
        _endCombat(winnerId: enemy.id);
        break;
      }
    }
  }

  void _endCombat({required String winnerId}) {
    if (!mounted) return;
    setState(() {
      _isGameOver = true;
      _isAutoCombat = false;
    });

    final battleLog = BattleLog(
      id: '',
      attackerId: _selectedMyChar!.id,
      defenderId: _selectedEnemyChar!.id,
      attackerName: _selectedMyChar!.name,
      defenderName: _selectedEnemyChar!.name,
      logs: List<String>.from(_terminalLogs),
      winnerId: winnerId,
      timestamp: DateTime.now(),
    );

    _gameService.saveBattleLog(battleLog);
    _appendLog("[Log saved to central database. Combat session ended.]");
  }

  @override
  Component build(BuildContext context) {
    final uid = getCurrentUserId();
    if (uid == null) {
      return div(
        classes: 'p-6 text-center flex-col items-center justify-center gap-3',
        attributes: const {'style': 'display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 24px; background: #0d0d0d; color: #00FF41; border-radius: 8px; font-family: monospace;'},
        [
          span([text('terminal')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 42px; color: #00FF41;'}),
          p([text('CA COMBAT TERMINAL ACCESS RESTRICTED')]),
          p([text('Authentication required to enter sector 7G combat network.')], attributes: const {'style': 'font-size: 11px; color: #00CC33;'}),
          button(
            [text('SIGN IN / REGISTER')],
            classes: 'btn-primary mt-2',
            attributes: const {'style': 'background-color: #00FF41; color: #000; border: none; padding: 8px 16px; font-weight: bold; border-radius: 4px; cursor: pointer; font-family: monospace;'},
            events: {'click': (e) => GlobalModalBus.show()},
          )
        ],
      );
    }

    if (_inCombatMode) {
      return _buildCombatScreen();
    }

    return _buildLobbyScreen();
  }

  Component _buildLobbyScreen() {
    return div(
      classes: 'terminal-lobby-container flex-col gap-4',
      attributes: const {
        'style': 'display: flex; flex-direction: column; gap: 16px; padding: 16px; background: #0d0d0d; color: #00FF41; border-radius: 8px; font-family: "Courier New", Courier, monospace; box-sizing: border-box; width: 100%;'
      },
      [
        // Header Banner
        div(
          attributes: const {'style': 'display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #00FF41; padding-bottom: 8px;'},
          [
            span([text('TERMINAL, CA // LOBBY')], attributes: const {'style': 'font-weight: bold; font-size: 14px; letter-spacing: 1px;'}),
            span([text('SECTOR 7G')], attributes: const {'style': 'font-size: 10px; color: #00CC33;'}),
          ],
        ),

        // Section 1: My Personas
        div(
          classes: 'flex-col gap-2',
          attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px;'},
          [
            div(
              attributes: const {'style': 'display: flex; justify-content: space-between; align-items: center;'},
              [
                span([text('MY PERSONAS')], attributes: const {'style': 'font-size: 11px; font-weight: bold; text-transform: uppercase;'}),
              ],
            ),
            if (_myCharacters.isEmpty)
              p([text('No personas registered. Create one below.')], attributes: const {'style': 'font-size: 11px; color: #888; font-style: italic;'})
            else
              div(
                attributes: const {'style': 'display: flex; gap: 8px; overflow-x: auto; padding-bottom: 4px;'},
                [
                  for (var char in _myCharacters)
                    _buildPersonaCard(char),
                ],
              ),
            // Inline Character Creation Input
            div(
              attributes: const {'style': 'display: flex; gap: 8px; margin-top: 4px;'},
              [
                input(
                  attributes: {
                    'type': 'text',
                    'placeholder': 'New character name...',
                    'value': _newCharName,
                    'style': 'flex: 1; padding: 6px 10px; background: #000; border: 1px solid #00FF41; color: #00FF41; font-family: monospace; font-size: 12px; border-radius: 4px; outline: none;'
                  },
                  events: {
                    'input': (e) => setState(() => _newCharName = getInputValue(e))
                  },
                ),
                button(
                  [text(_isCreatingChar ? 'ROLLING...' : '+ CREATE')],
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

        // Section 2: Detected Targets
        div(
          classes: 'flex-col gap-2',
          attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px;'},
          [
            span([text('DETECTED SIGNALS (PUBLIC TARGETS)')], attributes: const {'style': 'font-size: 11px; font-weight: bold; text-transform: uppercase;'}),
            if (_publicTargets.isEmpty)
              p([text('No public signals detected in this sector.')], attributes: const {'style': 'font-size: 11px; color: #888; font-style: italic;'})
            else
              div(
                classes: 'flex-col gap-2',
                attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px; max-height: 280px; overflow-y: auto;'},
                [
                  for (var enemy in _publicTargets)
                    _buildTargetRow(enemy),
                ],
              )
          ],
        )
      ],
    );
  }

  Component _buildPersonaCard(GameCharacter char) {
    final bool isSelected = _selectedMyChar?.id == char.id;
    return div(
      attributes: {
        'style': 'padding: 8px 12px; background: ${isSelected ? "rgba(0, 255, 65, 0.15)" : "#000"}; border: 1px solid ${isSelected ? "#00FF41" : "#005511"}; border-radius: 4px; cursor: pointer; min-width: 130px; box-sizing: border-box;',
      },
      events: {
        'click': (e) => setState(() => _selectedMyChar = char)
      },
      [
        div([text(char.name)], attributes: const {'style': 'font-weight: bold; font-size: 12px; color: #00FF41;'}),
        div([text('STR:${char.str} DEX:${char.dex} CON:${char.con}')], attributes: const {'style': 'font-size: 9px; color: #888; margin-top: 2px;'}),
        div([text('HP: ${char.maxHp} | W:${char.wins} L:${char.losses}')], attributes: const {'style': 'font-size: 9px; color: #00CC33; margin-top: 2px;'}),
      ],
    );
  }

  Component _buildTargetRow(GameCharacter enemy) {
    return div(
      attributes: const {
        'style': 'display: flex; align-items: center; justify-content: space-between; padding: 8px 12px; background: #000; border: 1px solid rgba(0, 255, 65, 0.2); border-radius: 4px;'
      },
      [
        div(
          attributes: const {'style': 'display: flex; flex-direction: column; gap: 2px;'},
          [
            span([text(enemy.name)], attributes: const {'style': 'font-weight: bold; font-size: 12px; color: #00FF41;'}),
            span([text('STR:${enemy.str} DEX:${enemy.dex} | HP:${enemy.maxHp}')], attributes: const {'style': 'font-size: 10px; color: #888;'}),
          ],
        ),
        button(
          [text('ATTACK')],
          attributes: const {
            'type': 'button',
            'style': 'background: #ff5252; color: #fff; border: none; padding: 4px 10px; font-size: 10px; font-weight: bold; font-family: monospace; cursor: pointer; border-radius: 3px;'
          },
          events: {
            'click': (e) => _startCombatSession(enemy)
          },
        )
      ],
    );
  }

  Component _buildCombatScreen() {
    return div(
      classes: 'terminal-combat-container flex-col gap-3',
      attributes: const {
        'style': 'display: flex; flex-direction: column; gap: 12px; padding: 16px; background: #0d0d0d; color: #00FF41; border-radius: 8px; font-family: "Courier New", Courier, monospace; box-sizing: border-box; width: 100%;'
      },
      [
        // Combat Status Bar
        div(
          attributes: const {'style': 'display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #00FF41; padding-bottom: 8px;'},
          [
            div([
              span([text('${_selectedMyChar?.name} ')], attributes: const {'style': 'font-weight: bold; color: #00FF41;'}),
              span([text('HP: $_playerHp/${_selectedMyChar?.maxHp}')], attributes: const {'style': 'font-size: 11px; color: #00CC33;'}),
            ]),
            span([text('VS')], attributes: const {'style': 'font-weight: bold; color: #888; font-size: 10px;'}),
            div([
              span([text('${_selectedEnemyChar?.name} ')], attributes: const {'style': 'font-weight: bold; color: #ff5252;'}),
              span([text('HP: $_enemyHp/${_selectedEnemyChar?.maxHp}')], attributes: const {'style': 'font-size: 11px; color: #ff8888;'}),
            ]),
          ],
        ),

        // Terminal Log Window
        div(
          attributes: const {
            'style': 'height: 220px; overflow-y: auto; background: #000; border: 1px solid #005511; padding: 10px; border-radius: 4px; display: flex; flex-direction: column; gap: 4px; font-size: 11px; line-height: 1.4;'
          },
          [
            for (var line in _terminalLogs)
              div(
                [text(line)],
                attributes: {
                  'style': 'color: ${line.startsWith("WARNING") || line.contains("DEFEATED") ? "#ff5252" : (line.contains("VICTORY") ? "#00FF41" : "#00CC33")};'
                },
              ),
          ],
        ),

        // Action / Input Command Bar
        div(
          attributes: const {'style': 'display: flex; gap: 8px; align-items: center;'},
          [
            span([text('>')], attributes: const {'style': 'font-weight: bold; color: #00FF41;'}),
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
                'keydown': (dynamic e) {
                  if (e is Map && e['key'] == 'Enter') {
                    _executeCommand(_commandInput);
                  }
                }
              },
            ),
            if (!_isAutoCombat && !_isGameOver)
              button(
                [text('ATTACK')],
                attributes: const {
                  'type': 'button',
                  'style': 'background: #00FF41; color: #000; border: none; padding: 6px 14px; font-weight: bold; font-family: monospace; font-size: 11px; cursor: pointer; border-radius: 4px;'
                },
                events: {
                  'click': (e) => _executeCommand('kill')
                },
              ),
            button(
              [text(_isGameOver ? 'EXIT' : 'ABORT')],
              attributes: const {
                'type': 'button',
                'style': 'background: #333; color: #fff; border: 1px solid #666; padding: 6px 12px; font-weight: bold; font-family: monospace; font-size: 11px; cursor: pointer; border-radius: 4px;'
              },
              events: {
                'click': (e) {
                  setState(() {
                    _inCombatMode = false;
                    _isAutoCombat = false;
                  });
                }
              },
            )
          ],
        )
      ],
    );
  }
}