import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/user_provider.dart';
import 'game_models.dart';
import 'game_service.dart';
import 'combat_terminal.dart';

class GameLobby extends StatefulWidget {
  const GameLobby({super.key});

  @override
  State<GameLobby> createState() => _GameLobbyState();
}

class _GameLobbyState extends State<GameLobby> {
  final GameService _service = GameService();
  GameCharacter? _selectedMyChar;

  void _showCreateDialog(String userId) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool isCreating = false;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text("New Persona",
                style: TextStyle(color: Colors.green, fontFamily: 'Courier')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: "Enter character name",
                    hintStyle: TextStyle(color: Colors.grey),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.green)),
                  ),
                ),
                if (isCreating)
                  const Padding(
                    padding: EdgeInsets.only(top: 16.0),
                    child: LinearProgressIndicator(
                        color: Colors.green, backgroundColor: Colors.black),
                  ),
              ],
            ),
            actions: [
              if (!isCreating)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CANCEL",
                      style: TextStyle(color: Colors.grey)),
                ),
              if (!isCreating)
                TextButton(
                  onPressed: () async {
                    if (controller.text.trim().isNotEmpty) {
                      setState(() => isCreating = true);
                      try {
                        await _service.createCharacter(
                            userId, controller.text.trim());
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        setState(() => isCreating = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Error: $e")));
                        }
                      }
                    }
                  },
                  child: const Text("INITIALIZE",
                      style: TextStyle(
                          color: Colors.green, fontWeight: FontWeight.bold)),
                )
            ],
          ),
        );
      },
    );
  }

  void _startCombat(GameCharacter enemy) {
    if (_selectedMyChar == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Create or select your character first!")));
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => CombatTerminal(
          playerChar: _selectedMyChar,
          enemyChar: enemy,
        ),
      ),
    );
  }

  void _watchPlayback(BattleLog log) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => CombatTerminal(
          playbackLogs: List<String>.from(log.logs),
        ),
      ),
    );
  }

  /// Shows logs Head-to-Head for the selected target.
  void _showLogsModal({required GameCharacter target}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      isScrollControlled: true, // Allow it to take more height if needed
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.8,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                    "${_selectedMyChar?.name ?? 'YOU'} vs ${target.name}",
                    style: const TextStyle(
                        color: Colors.green,
                        fontFamily: 'Courier',
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
              const Divider(color: Colors.green, height: 1),
              Expanded(
                child: _buildHeadToHeadList(target),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeadToHeadList(GameCharacter target) {
    if (_selectedMyChar == null) {
      return const Center(
          child: Text("Select a character first.",
              style: TextStyle(color: Colors.red, fontFamily: 'Courier')));
    }

    return FutureBuilder<List<BattleLog>>(
      future: _fetchHeadToHeadLogs(_selectedMyChar!.id, target.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.green));
        }

        final logs = snapshot.data ?? [];
        if (logs.isEmpty) {
          return const Center(
              child: Text("No records found.",
                  style: TextStyle(color: Colors.grey, fontFamily: 'Courier')));
        }

        return ListView.separated(
          separatorBuilder: (c, i) =>
              const Divider(height: 1, color: Colors.white24),
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final log = logs[index];
            final iWon = log.winnerId == _selectedMyChar!.id;
            return ListTile(
              title: Text(iWon ? "VICTORY" : "DEFEAT",
                  style: TextStyle(
                      color: iWon ? Colors.green : Colors.red,
                      fontFamily: 'Courier',
                      fontWeight: FontWeight.bold)),
              subtitle: Text(log.timestamp.toString().split('.')[0],
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 10, fontFamily: 'Courier')),
              trailing: IconButton(
                icon: const Icon(Icons.remove_red_eye, color: Colors.green),
                onPressed: () => _watchPlayback(log),
              ),
            );
          },
        );
      },
    );
  }

  BattleLog _mapToLog(String id, Map<String, dynamic> data) {
    return BattleLog(
      id: id,
      attackerId: data['attackerId'],
      defenderId: data['defenderId'],
      attackerName: data['attackerName'] ?? 'Unknown',
      defenderName: data['defenderName'] ?? 'Unknown',
      logs: List<String>.from(data['logs'] ?? []),
      winnerId: data['winnerId'],
      timestamp: (data['timestamp'] as Timestamp).toDate(),
    );
  }

  Future<List<BattleLog>> _fetchHeadToHeadLogs(
      String myId, String enemyId) async {
    final db = FirebaseFirestore.instance;
    final colRef = db
        .collection('artifacts')
        .doc('bqopd')
        .collection('public')
        .doc('data')
        .collection('game_battles');

    // NOTE: Removed .orderBy() to avoid needing composite indexes on the server.
    // We sort in memory instead.

    // 1. Battles where I attacked them
    final q1 = await colRef
        .where('attackerId', isEqualTo: myId)
        .where('defenderId', isEqualTo: enemyId)
        .get();

    // 2. Battles where they attacked me
    final q2 = await colRef
        .where('attackerId', isEqualTo: enemyId)
        .where('defenderId', isEqualTo: myId)
        .get();

    final allDocs = [...q1.docs, ...q2.docs];

    final logs = allDocs.map((d) => _mapToLog(d.id, d.data())).toList();
    // Sort descending by timestamp
    logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return logs;
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final userId = userProvider.currentUserId;

    if (userId == null) {
      return const Center(
          child: Text("Authentication required for Terminal access."));
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a1a),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("TERMINAL, CA // LOBBY",
            style: TextStyle(color: Colors.white, fontFamily: 'Courier')),
        // Actions removed
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. My Characters Section
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.black54,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("MY PERSONAS",
                    style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Courier')),
                GestureDetector(
                  onTap: () => _showCreateDialog(userId),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration:
                        BoxDecoration(border: Border.all(color: Colors.green)),
                    child: const Text("+ CREATE",
                        style: TextStyle(color: Colors.green, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(
            height: 120,
            child: StreamBuilder<List<GameCharacter>>(
              stream: _service.getMyCharacters(userId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: Colors.green));
                }

                final chars = snapshot.data ?? [];

                if (chars.isEmpty) {
                  return const Center(
                      child: Text("No personas found. Initialize one.",
                          style: TextStyle(color: Colors.grey)));
                }

                if (_selectedMyChar == null && chars.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _selectedMyChar = chars.first);
                  });
                }

                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: chars.length,
                  itemBuilder: (context, index) {
                    final c = chars[index];
                    final isSelected = _selectedMyChar?.id == c.id;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedMyChar = c),
                      child: Container(
                        width: 140,
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.green.withValues(alpha: 0.2)
                              : Colors.black,
                          border: Border.all(
                              color: isSelected ? Colors.green : Colors.grey),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(c.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Courier'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text("HP: ${c.maxHp}",
                                style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 10,
                                    fontFamily: 'Courier')),
                            Text("W:${c.wins} L:${c.losses}",
                                style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 10,
                                    fontFamily: 'Courier')),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          const Divider(color: Colors.green),

          // 2. Public List Header (Removed Global Feed Button)
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.black54,
            child: const Text("DETECTED SIGNALS (TARGETS)",
                style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Courier')),
          ),

          Expanded(
            child: StreamBuilder<List<GameCharacter>>(
              stream: _service.getPublicCharacters(userId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: Colors.green));
                }
                final chars = snapshot.data ?? [];

                return ListView.separated(
                  itemCount: chars.length,
                  separatorBuilder: (c, i) =>
                      const Divider(height: 1, color: Colors.grey),
                  itemBuilder: (context, index) {
                    final enemy = chars[index];
                    return ListTile(
                      tileColor: Colors.black,
                      leading:
                          const Icon(Icons.person_outline, color: Colors.green),
                      title: Text(enemy.name,
                          style: const TextStyle(
                              color: Colors.white, fontFamily: 'Courier')),
                      subtitle: Text("Str: ${enemy.str} | HP: ${enemy.maxHp}",
                          style: const TextStyle(
                              color: Colors.grey,
                              fontFamily: 'Courier',
                              fontSize: 12)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // LOGS Button (Specific)
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.green,
                              side: const BorderSide(color: Colors.green),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            onPressed: () => _showLogsModal(target: enemy),
                            child: const Text("LOGS",
                                style: TextStyle(
                                    fontFamily: 'Courier',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          // ATTACK Button
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.black,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            onPressed: () => _startCombat(enemy),
                            child: const Text("ATTACK",
                                style: TextStyle(
                                    fontFamily: 'Courier',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
