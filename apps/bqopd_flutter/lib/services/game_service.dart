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

  WorldStateSnapshot _canonicalCache = TerminalWorldEngine.seedSector7G();

  @override
  Stream<WorldStateSnapshot> watchCanonicalWorld() =>
      Stream.value(_canonicalCache);

  @override
  Stream<PageEncounter?> watchPageEncounter(String imageId) =>
      Stream.value(TerminalWorldEngine.findEncounter(_canonicalCache, imageId));

  @override
  Stream<WorldRoom?> watchWorldRoom(String roomId) =>
      Stream.value(_canonicalCache.rooms[roomId]);

  @override
  Stream<List<WorldEvent>> watchRoomEvents(String roomId) => Stream.value(
        _canonicalCache.events.where((e) => e.roomId == roomId).toList(),
      );

  @override
  Future<List<String>> executePageAction({
    required String imageId,
    required String actorEntityId,
    required String actionId,
    String? inputCode,
  }) async {
    final seeded = TerminalWorldEngine.ensureActorEntity(
      _canonicalCache,
      actorEntityId: actorEntityId,
      ownerUserId: actorEntityId,
      handle: actorEntityId,
    );
    final res = TerminalWorldEngine.executePageAction(
      state: seeded,
      imageId: imageId,
      actorEntityId: actorEntityId,
      actionId: actionId,
      inputCode: inputCode,
    );
    _canonicalCache = res.state;
    return res.outputLines;
  }

  @override
  Future<List<String>> executeTerminalCommand({
    required String actorEntityId,
    required String rawCommand,
  }) async {
    final seeded = TerminalWorldEngine.ensureActorEntity(
      _canonicalCache,
      actorEntityId: actorEntityId,
      ownerUserId: actorEntityId,
      handle: actorEntityId,
    );
    final res = TerminalWorldEngine.executeCommand(
      state: seeded,
      actorEntityId: actorEntityId,
      rawCommand: rawCommand,
    );
    _canonicalCache = res.state;
    return res.outputLines;
  }

  @override
  Stream<TabletopArSession?> watchTabletopSession(String sessionId) =>
      Stream.value(_canonicalCache.arSessions[sessionId]);

  @override
  Future<List<String>> startTabletopArSession({
    required String anchorPageId,
    required String hostUserId,
    String? sessionId,
  }) async {
    final res = TerminalWorldEngine.startTabletopArSession(
      state: _canonicalCache,
      anchorPageId: anchorPageId,
      hostUserId: hostUserId,
      sessionId: sessionId,
    );
    _canonicalCache = res.state;
    return res.outputLines;
  }

  @override
  Future<List<String>> ingestQrIntoTabletopSession({
    required String sessionId,
    required String scannedQrCode,
    String? fallbackHandle,
  }) async {
    final res = TerminalWorldEngine.ingestQrIntoArSession(
      state: _canonicalCache,
      sessionId: sessionId,
      scannedQrCode: scannedQrCode,
      fallbackEntityHandle: fallbackHandle,
    );
    _canonicalCache = res.state;
    return res.outputLines;
  }

  @override
  Future<List<String>> moveTabletopUnit({
    required String sessionId,
    required String entityId,
    required GridCoordinate targetCoord,
  }) async {
    final res = TerminalWorldEngine.moveTabletopUnit(
      state: _canonicalCache,
      sessionId: sessionId,
      entityId: entityId,
      targetCoord: targetCoord,
    );
    _canonicalCache = res.state;
    return res.outputLines;
  }

  @override
  Future<void> saveCanonicalWorld(WorldStateSnapshot snapshot) async {
    _canonicalCache = snapshot;
  }

  @override
  Future<WorldStateSnapshot> resetCanonicalWorldToSeed() async {
    _canonicalCache = TerminalWorldEngine.seedSector7G();
    return _canonicalCache;
  }
}