import 'package:cloud_firestore/cloud_firestore.dart';

class GameCharacter {
  String id;
  String ownerId;
  String name;
  String bio;
  int str;
  int dex;
  int con;
  int maxHp;
  int currentHp;
  int wins;
  int losses;

  GameCharacter({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.bio,
    required this.str,
    required this.dex,
    required this.con,
    required this.maxHp,
    required this.currentHp,
    this.wins = 0,
    this.losses = 0,
  });

  factory GameCharacter.fromMap(String id, Map<String, dynamic> data) {
    return GameCharacter(
      id: id,
      ownerId: data['ownerId'] ?? '',
      name: data['name'] ?? 'Unknown',
      bio: data['bio'] ?? '',
      str: data['str'] ?? 10,
      dex: data['dex'] ?? 10,
      con: data['con'] ?? 10,
      maxHp: data['maxHp'] ?? 50,
      currentHp: data['currentHp'] ?? 50,
      wins: data['wins'] ?? 0,
      losses: data['losses'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ownerId': ownerId,
      'name': name,
      'bio': bio,
      'str': str,
      'dex': dex,
      'con': con,
      'maxHp': maxHp,
      'currentHp': currentHp,
      'wins': wins,
      'losses': losses,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class BattleLog {
  String id;
  String attackerId;
  String defenderId;
  String attackerName;
  String defenderName;
  List<String> logs;
  String winnerId;
  DateTime timestamp;

  BattleLog({
    required this.id,
    required this.attackerId,
    required this.defenderId,
    required this.attackerName,
    required this.defenderName,
    required this.logs,
    required this.winnerId,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'attackerId': attackerId,
      'defenderId': defenderId,
      'attackerName': attackerName,
      'defenderName': defenderName,
      'logs': logs,
      'winnerId': winnerId,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }
}