import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bqopd_core/bqopd_core.dart';
import 'game_models.dart';
import 'game_service.dart';

enum LobbyView { main, create, logs }

class GameLobby extends StatefulWidget {
  final Function(GameCharacter me, GameCharacter enemy) onStartCombat;
  final Function(List<String> logs) onWatchPlayback;

  const GameLobby({
    super.key,
    required this.onStartCombat,
    required this.onWatchPlayback,
  });

  @override
  State<GameLobby> createState() => _GameLobbyState();
}

class _GameLobbyState extends State<GameLobby> {
  final GameService _service = GameService();
  GameCharacter? _selectedMyChar;

  LobbyView _currentView = LobbyView.main;
  GameCharacter? _logTarget;
  bool _isCreating = false;
  final TextEditingController _createController = TextEditingController();

  @override
  void dispose() {
    _createController.dispose();
    super.dispose();
  }

  void _startCombat(GameCharacter enemy) {
    if (_selectedMyChar == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Create or select your character first!")));
      return;
    }
    widget.onStartCombat(_selectedMyChar!, enemy);
  }

  void _watchPlayback(BattleLog log) {
    widget.onWatchPlayback(List<String>.from(log.logs));
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

    final q1 = await colRef
        .where('attackerId', isEqualTo: myId)
        .where('defenderId', isEqualTo: enemyId)
        .get();

    final q2 = await colRef
        .where('attackerId', isEqualTo: enemyId)
        .where('defenderId', isEqualTo: myId)
        .get();

    final allDocs = [...q1.docs, ...q2.docs];

    final logs = allDocs.map((d) => _mapToLog(d.id, d.data())).toList();
    logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return logs;
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final userId = userProvider.currentUserId;

    if (userId == null) {
      return const Center(
          child: Text("Authentication required for Terminal access.",
              style: TextStyle(color: Colors.white)));
    }

    return Container(
      color: const Color(0xFF1a1a1a),
      child: _buildCurrentView(userId),
    );
  }

  Widget _buildCurrentView(String userId) {
    switch (_currentView) {
      case LobbyView.create:
        return _buildCreateView(userId);
      case LobbyView.logs:
        return _buildLogsView();
      case LobbyView.main:
      default:
        return _buildMainLobby(userId);
    }
  }

  Widget _buildCreateView(String userId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.black54,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.green, size: 20),
                onPressed: () {
                  _createController.clear();
                  setState(() => _currentView = LobbyView.main);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              const Text("INITIALIZE NEW PERSONA",
                  style: TextStyle(
                      color: Colors.green,
                      fontFamily: 'Courier',
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _createController,
                style: const TextStyle(color: Colors.white, fontFamily: 'Courier'),
                decoration: const InputDecoration(
                  hintText: "Enter character name...",
                  hintStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.green)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.greenAccent)),
                ),
              ),
              const SizedBox(height: 32),
              if (_isCreating)
                const LinearProgressIndicator(
                    color: Colors.green, backgroundColor: Colors.black)
              else
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.green,
                    side: const BorderSide(color: Colors.green),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () async {
                    if (_createController.text.trim().isNotEmpty) {
                      setState(() => _isCreating = true);
                      try {
                        await _service.createCharacter(
                            userId, _createController.text.trim());
                        _createController.clear();
                        if (mounted) {
                          setState(() {
                            _isCreating = false;
                            _currentView = LobbyView.main;
                          });
                        }
                      } catch (e) {
                        if (mounted) {
                          setState(() => _isCreating = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Error: $e")));
                        }
                      }
                    }
                  },
                  child: const Text("INITIALIZE",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Courier',
                          fontSize: 16)),
                )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLogsView() {
    if (_logTarget == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.black54,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.green, size: 20),
                onPressed: () => setState(() {
                  _logTarget = null;
                  _currentView = LobbyView.main;
                }),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              Text(
                  "${_selectedMyChar?.name ?? 'YOU'} vs ${_logTarget!.name}",
                  style: const TextStyle(
                      color: Colors.green,
                      fontFamily: 'Courier',
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const Divider(color: Colors.green, height: 1),
        Expanded(
          child: _buildHeadToHeadList(_logTarget!),
        ),
      ],
    );
  }

  Widget _buildMainLobby(String userId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                onTap: () => setState(() => _currentView = LobbyView.create),
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
                            ? Colors.green.withOpacity(0.2)
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

        const Divider(color: Colors.green, height: 1),

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

              if (chars.isEmpty) {
                return const Center(
                    child: Text("No targets online.",
                        style: TextStyle(color: Colors.grey)));
              }

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
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.green,
                            side: const BorderSide(color: Colors.green),
                            padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                            minimumSize: const Size(60, 32),
                          ),
                          onPressed: () => setState(() {
                            _logTarget = enemy;
                            _currentView = LobbyView.logs;
                          }),
                          child: const Text("LOGS",
                              style: TextStyle(
                                  fontFamily: 'Courier',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.black,
                            padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                            minimumSize: const Size(60, 32),
                          ),
                          onPressed: () => _startCombat(enemy),
                          child: const Text("ATTACK",
                              style: TextStyle(
                                  fontFamily: 'Courier',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11)),
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
    );
  }
}