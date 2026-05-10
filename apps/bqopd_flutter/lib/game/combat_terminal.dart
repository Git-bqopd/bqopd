import 'dart:async';
import 'dart:math';

import 'package:bqopd_core/bqopd_core.dart';
import 'package:flutter/material.dart';

class CombatTerminal extends StatefulWidget {
  final GameCharacter? playerChar;
  final GameCharacter? enemyChar;
  final List<String>? playbackLogs;

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
  bool _isAutoCombat = false;

  late int _playerHp;
  late int _enemyHp;

  @override
  void initState() {
    super.initState();
    _isPlayback = widget.playbackLogs != null;

    if (_isPlayback) {
      _startPlayback();
    } else {
      _playerHp = widget.playerChar!.currentHp;
      _enemyHp = widget.enemyChar!.currentHp;
      _print("Welcome to TERMINAL, CA.");
      _print("Connected to sector 7G...");
      _print("Target acquired: ${widget.enemyChar!.name} (Level 1)");
      _print("Type 'kill' to initiate auto-combat.");
    }
  }

  void _startPlayback() async {
    _print("--- REPLAYING COMBAT LOG ---");
    for (String line in widget.playbackLogs!) {
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      _print(line);
    }
  }

  void _print(String text) {
    if (!mounted) return;
    setState(() => _log.add(text));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _handleCommand(String raw) {
    if (_isPlayback || _isGameOver) return;
    String cmd = raw.trim().toLowerCase();
    _inputController.clear();
    _print("> $raw");
    if (cmd.startsWith('kill') || cmd.startsWith('attack') || cmd == 'k') {
      if (!_isAutoCombat) {
        _print("INITIATING COMBAT SEQUENCE...");
        _isAutoCombat = true;
        _combatLoop();
      }
    }
  }

  Future<void> _combatLoop() async {
    final rand = Random();
    while (!_isGameOver && mounted) {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;

      // Player Turn
      int roll = rand.nextInt(20) + 1;
      int attackVal = roll + widget.playerChar!.str;
      int enemyAc = 10 + widget.enemyChar!.dex;

      if (attackVal >= enemyAc) {
        int dmg = rand.nextInt(6) + 1 + (widget.playerChar!.str ~/ 2);
        _enemyHp -= dmg;
        _print("You hit ${widget.enemyChar!.name} for $dmg damage!");
      } else { _print("You missed!"); }

      if (_enemyHp <= 0) {
        _print("VICTORY.");
        _endGame(widget.playerChar!.id);
        break;
      }

      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      // Enemy Turn
      roll = rand.nextInt(20) + 1;
      int eAttackVal = roll + widget.enemyChar!.str;
      int playerAc = 10 + widget.playerChar!.dex;

      if (eAttackVal >= playerAc) {
        int dmg = rand.nextInt(6) + 1 + (widget.enemyChar!.str ~/ 2);
        _playerHp -= dmg;
        _print("You take $dmg damage!");
      } else { _print("Enemy missed!"); }

      if (_playerHp <= 0) {
        _print("GAME OVER.");
        _endGame(widget.enemyChar!.id);
        break;
      }
    }
  }

  void _endGame(String? winnerId) {
    if (!mounted) return;
    setState(() {
      _isGameOver = true;
      _isAutoCombat = false;
    });

    if (!_isPlayback) {
      final log = BattleLog(
        id: '',
        attackerId: widget.playerChar!.id,
        defenderId: widget.enemyChar!.id,
        attackerName: widget.playerChar!.name,
        defenderName: widget.enemyChar!.name,
        logs: List<String>.from(_log),
        winnerId: winnerId ?? 'draw',
        timestamp: DateTime.now(),
      );
      _service.saveBattleLog(log);
      _print("[Log Saved. Session Terminated.]");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(backgroundColor: Colors.black, title: const Text("TERMINAL, CA", style: TextStyle(fontFamily: 'Courier', color: Color(0xFF00FF41)))),
      body: Column(children: [
        Expanded(child: ListView.builder(controller: _scrollController, itemCount: _log.length, itemBuilder: (context, index) => Padding(padding: const EdgeInsets.only(bottom: 4.0), child: Text(_log[index], style: const TextStyle(color: Color(0xFF00FF41), fontFamily: 'Courier'))))),
        if (!_isPlayback) Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), color: Colors.black, child: Row(children: [const Text(">", style: TextStyle(color: Color(0xFF00FF41), fontFamily: 'Courier')), const SizedBox(width: 10), Expanded(child: TextField(controller: _inputController, style: const TextStyle(color: Color(0xFF00FF41), fontFamily: 'Courier'), onSubmitted: _handleCommand, autofocus: true, enabled: !_isGameOver))]))
      ]),
    );
  }
}