import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bqopd_core/bqopd_core.dart';

class GameService implements IGameService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference _publicCollection(String collectionName) {
    return _db.collection('artifacts').doc('bqopd').collection('public').doc('data').collection(collectionName);
  }

  @override
  Stream<List<GameCharacter>> getMyCharacters(String userId) {
    return _publicCollection('game_characters')
        .where('ownerId', isEqualTo: userId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => GameCharacter.fromMap(d.id, d.data() as Map<String, dynamic>)).toList());
  }

  @override
  Stream<List<GameCharacter>> getPublicCharacters(String currentUserId) {
    return _publicCollection('game_characters')
        .where('ownerId', isNotEqualTo: currentUserId)
        .limit(20)
        .snapshots()
        .map((snap) => snap.docs.map((d) => GameCharacter.fromMap(d.id, d.data() as Map<String, dynamic>)).toList());
  }

  @override
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

    await _publicCollection('game_characters').add(char.toMap());
  }

  @override
  Future<void> updateCharacter(GameCharacter char) async {
    await _publicCollection('game_characters').doc(char.id).update(char.toMap());
  }

  @override
  Future<void> saveBattleLog(BattleLog log) async {
    await _publicCollection('game_battles').add(log.toMap());

    if (log.winnerId == log.attackerId) {
      _publicCollection('game_characters').doc(log.attackerId).update({'wins': FieldValue.increment(1)});
      _publicCollection('game_characters').doc(log.defenderId).update({'losses': FieldValue.increment(1)});
    } else if (log.winnerId == log.defenderId) {
      _publicCollection('game_characters').doc(log.defenderId).update({'wins': FieldValue.increment(1)});
      _publicCollection('game_characters').doc(log.attackerId).update({'losses': FieldValue.increment(1)});
    }
  }
}