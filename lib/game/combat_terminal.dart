import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'game_models.dart';
import 'game_service.dart';

class CombatTerminal extends StatefulWidget {
  final GameCharacter? playerChar;
  final GameCharacter? enemyChar;
  final List<String>? playbackLogs; // If provided, we are in playback mode

  const CombatTerminal({
    super.key,
    this.playerChar,
    this.enemyChar,
    this.playbackLogs,
  });

  @override
  State<CombatTerminal> createState() => _CombatTerminalState();
}

class _CombatTerminalState extends State<CombatTerminal> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GameService _service = GameService();

  final List<String> _log = [];
  bool _isPlayback = false;
  bool _isGameOver = false;
  bool _isAutoCombat = false; // Flag to prevent multiple loops

  // Local combat stats (mutable)
  late int _playerHp;
  late int _enemyHp;

  @override
  void initState() {
    super.initState();
    _isPlayback = widget.playbackLogs != null;

    if (_isPlayback) {
      _startPlayback();
    } else {
      // Initialize Combat
      _playerHp = widget.playerChar!.currentHp;
      _enemyHp = widget.enemyChar!.currentHp;
      _print("Welcome to TERMINAL, CA.");
      _print("Connected to sector 7G...");
      _print("Target acquired: ${widget.enemyChar!.name} (Level 1)");
      _print("Type 'kill' to initiate auto-combat.");
      _print(
          "Your status: HP $_playerHp/${widget.playerChar!.maxHp} | STR ${widget.playerChar!.str}");
    }
  }

  void _startPlayback() async {
    _print("--- REPLAYING COMBAT LOG ---");
    for (String line in widget.playbackLogs!) {
      await Future.delayed(
          const Duration(milliseconds: 800)); // Cinematic delay
      if (!mounted) return;
      _print(line);
    }
    _print("--- END OF TRANSMISSION ---");
  }

  void _print(String text) {
    setState(() {
      _log.add(text);
    });
    // Auto scroll
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleCommand(String raw) {
    if (_isPlayback || _isGameOver) return;

    String cmd = raw.trim().toLowerCase();
    _inputController.clear();
    _print("> $raw");

    if (cmd.isEmpty) return;

    if (cmd == 'help') {
      _print("Available commands:");
      _print("  kill [name] - Start Auto-Combat");
      _print("  look        - Inspect room");
      _print("  status      - Check HP");
      _print("  flee        - Run away (Coward)");
      return;
    }

    if (cmd == 'look') {
      _print("You are in a dimly lit server room.");
      _print("Standing opposite you is ${widget.enemyChar!.name}.");
      _print("They look pixelated and angry.");
      return;
    }

    if (cmd == 'status') {
      _print("YOU: $_playerHp HP | ENEMY: $_enemyHp HP");
      return;
    }

    if (cmd.startsWith('kill') || cmd.startsWith('attack') || cmd == 'k') {
      if (!_isAutoCombat) {
        _print("INITIATING COMBAT SEQUENCE...");
        _isAutoCombat = true;
        _combatLoop();
      } else {
        _print("Combat already in progress...");
      }
      return;
    }

    if (cmd == 'flee') {
      _print("You disconnected in a panic.");
      _endGame(null); // No winner
      return;
    }

    _print("Unknown command. Error 404.");
  }

  Future<void> _combatLoop() async {
    final rand = Random();

    while (!_isGameOver && mounted) {
      // 1. Random Pause between turns (1 to 2 seconds)
      int delay = 1000 + rand.nextInt(1000);
      await Future.delayed(Duration(milliseconds: delay));
      if (!mounted) return;

      // 2. Player Turn
      _performPlayerAttack(rand);

      if (_isGameOver) break;

      // Short pause between player attack and enemy response
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      // 3. Enemy Turn
      _performEnemyAttack(rand);
    }
  }

  void _performPlayerAttack(Random rand) {
    int roll = rand.nextInt(20) + 1;
    int attackVal = roll + widget.playerChar!.str;
    int enemyAc = 10 + widget.enemyChar!.dex;

    if (attackVal >= enemyAc) {
      int dmg = rand.nextInt(6) + 1 + (widget.playerChar!.str ~/ 2);
      _enemyHp -= dmg;
      _print("You hit ${widget.enemyChar!.name} for $dmg damage!");
      _print("Enemy HP: $_enemyHp");
    } else {
      _print("You missed! (Rolled $roll)");
    }

    if (_enemyHp <= 0) {
      _print("${widget.enemyChar!.name} crashes to the ground.");
      _print("VICTORY.");
      _endGame(widget.playerChar!.id);
    }
  }

  void _performEnemyAttack(Random rand) {
    _print("${widget.enemyChar!.name} attacks!");

    int roll = rand.nextInt(20) + 1;
    int attackVal = roll + widget.enemyChar!.str;
    int playerAc = 10 + widget.playerChar!.dex;

    if (attackVal >= playerAc) {
      int dmg = rand.nextInt(6) + 1 + (widget.enemyChar!.str ~/ 2);
      _playerHp -= dmg;
      _print("You take $dmg damage!");
      _print("Your HP: $_playerHp");
    } else {
      _print("Enemy missed!");
    }

    if (_playerHp <= 0) {
      _print("You have been de-rezzed.");
      _print("GAME OVER.");
      _endGame(widget.enemyChar!.id);
    }
  }

  void _endGame(String? winnerId) {
    setState(() {
      _isGameOver = true;
      _isAutoCombat = false;
    });

    if (!_isPlayback) {
      // Save log
      final log = BattleLog(
        id: '',
        attackerId: widget.playerChar!.id,
        defenderId: widget.enemyChar!.id,
        attackerName: widget.playerChar!.name,
        defenderName: widget.enemyChar!.name,
        logs: _log,
        winnerId: winnerId ?? 'draw',
        timestamp: DateTime.now(),
      );
      _service.saveBattleLog(log);
      _print("[Log Saved. Session Terminated.]");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Cyberpunk Theme Colors
    const bgColor = Color(0xFF0D0D0D); // Almost black
    const terminalGreen = Color(0xFF00FF41);
    const cursorColor = Color(0xFF008F11);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("TERMINAL, CA",
            style: TextStyle(
                fontFamily: 'Courier',
                color: terminalGreen,
                fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: terminalGreen),
        elevation: 0,
      ),
      body: Column(
        children: [
          // CRT Screen Effect Container
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(
                    color: terminalGreen.withValues(alpha: 0.3), width: 2),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    bgColor,
                    const Color(0xFF112211), // Subtle scanline hint
                  ],
                ),
              ),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _log.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Text(
                      _log[index],
                      style: const TextStyle(
                        color: terminalGreen,
                        fontFamily: 'Courier',
                        fontSize: 14,
                        shadows: [
                          Shadow(color: terminalGreen, blurRadius: 4),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Command Input Line
          if (!_isPlayback)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.black,
              child: Row(
                children: [
                  const Text(">",
                      style: TextStyle(
                          color: terminalGreen,
                          fontFamily: 'Courier',
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      style: const TextStyle(
                          color: terminalGreen,
                          fontFamily: 'Courier',
                          fontSize: 16),
                      cursorColor: cursorColor,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: "Enter command...",
                        hintStyle: TextStyle(color: Color(0xFF004400)),
                      ),
                      onSubmitted: _handleCommand,
                      textInputAction: TextInputAction.send,
                      autofocus: true,
                      enabled: !_isGameOver, // Disable input when game over
                    ),
                  ),
                  if (_isGameOver)
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("EXIT",
                          style: TextStyle(
                              color: Colors.red, fontFamily: 'Courier')),
                    )
                ],
              ),
            ),
        ],
      ),
    );
  }
}
