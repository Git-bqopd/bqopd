import 'package:flutter/material.dart';
import '../../game/game_lobby.dart';
import '../../game/combat_terminal.dart';
import '../../game/game_models.dart';

enum TerminalViewState { lobby, combat, replay }

/// A host panel that manages the Game UI state without using Navigation pushes.
class TerminalPanel extends StatefulWidget {
  const TerminalPanel({super.key});

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  TerminalViewState _viewState = TerminalViewState.lobby;

  GameCharacter? _myChar;
  GameCharacter? _enemyChar;
  List<String>? _playbackLogs;

  void _enterCombat(GameCharacter me, GameCharacter enemy) {
    setState(() {
      _myChar = me;
      _enemyChar = enemy;
      _viewState = TerminalViewState.combat;
    });
  }

  void _watchReplay(List<String> logs) {
    setState(() {
      _playbackLogs = logs;
      _viewState = TerminalViewState.replay;
    });
  }

  void _exitToLobby() {
    setState(() {
      _myChar = null;
      _enemyChar = null;
      _playbackLogs = null;
      _viewState = TerminalViewState.lobby;
    });
  }

  @override
  Widget build(BuildContext context) {
    // We enforce a fixed height so the ListView/ScrollViews inside the game
    // don't cause UnboundedHeight exceptions when embedded inside the Reader's list view.
    return SizedBox(
      height: 500,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _buildCurrentView(),
      ),
    );
  }

  Widget _buildCurrentView() {
    switch (_viewState) {
      case TerminalViewState.lobby:
        return GameLobby(
          onStartCombat: _enterCombat,
          onWatchPlayback: _watchReplay,
        );
      case TerminalViewState.combat:
        return CombatTerminal(
          playerChar: _myChar,
          enemyChar: _enemyChar,
          onExit: _exitToLobby,
        );
      case TerminalViewState.replay:
        return CombatTerminal(
          playbackLogs: _playbackLogs,
          onExit: _exitToLobby,
        );
    }
  }
}