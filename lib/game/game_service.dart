import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'game_models.dart';

class GameService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // HELPER: Use correct Public Data Path
  // Path Rule: /artifacts/{appId}/public/data/{collectionName}
  CollectionReference _publicCollection(String collectionName) {
    return _db.collection('artifacts').doc('bqopd').collection('public').doc('data').collection(collectionName);
  }

  // --- Characters ---

  Stream<List<GameCharacter>> getMyCharacters(String userId) {
    return _publicCollection('game_characters')
        .where('ownerId', isEqualTo: userId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => GameCharacter.fromMap(d.id, d.data() as Map<String, dynamic>)).toList());
  }

  Stream<List<GameCharacter>> getPublicCharacters(String currentUserId) {
    return _publicCollection('game_characters')
        .where('ownerId', isNotEqualTo: currentUserId)
        .limit(20)
        .snapshots()
        .map((snap) => snap.docs.map((d) => GameCharacter.fromMap(d.id, d.data() as Map<String, dynamic>)).toList());
  }

  Future<void> createCharacter(String userId, String name) async {
    final rand = Random();
    int roll() => rand.nextInt(6) + 1 + rand.nextInt(6) + 1 + rand.nextInt(6) + 1;

    int str = roll();
    int dex = roll();
    int con = roll();
    int hp = con * 3;

    final char = GameCharacter(
      id: '',
      ownerId: userId,
      name: name,
      bio: 'A wanderer in Terminal, CA',
      str: str,
      dex: dex,
      con: con,
      maxHp: hp,
      currentHp: hp,
    );

    // Save to valid path
    await _publicCollection('game_characters').add(char.toMap());
  }

  Future<void> updateCharacter(GameCharacter char) async {
    await _publicCollection('game_characters').doc(char.id).update(char.toMap());
  }

  // --- Battles ---

  Future<void> saveBattleLog(BattleLog log) async {
    await _publicCollection('game_battles').add(log.toMap());

    // Update W/L records
    if (log.winnerId == log.attackerId) {
      _publicCollection('game_characters').doc(log.attackerId).update({'wins': FieldValue.increment(1)});
      _publicCollection('game_characters').doc(log.defenderId).update({'losses': FieldValue.increment(1)});
    } else if (log.winnerId == log.defenderId) {
      _publicCollection('game_characters').doc(log.defenderId).update({'wins': FieldValue.increment(1)});
      _publicCollection('game_characters').doc(log.attackerId).update({'losses': FieldValue.increment(1)});
    }
  }
}