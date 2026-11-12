import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';

/// Concrete web implementation of [IGameService] backed by a shared canonical
/// single-world reactive store synchronized with Firestore (`canonical_prime`).
class WebGameService implements IGameService {
  static const String _charPath = 'artifacts/bqopd/public/data/game_characters';
  static const String _battlePath = 'artifacts/bqopd/public/data/game_battles';
  static const String _canonicalWorldDocPath =
      'artifacts/bqopd/public/data/terminal_world/canonical_prime';

  // Shared process-wide canonical single-world bus so every inline drawer,
  // desktop column, and WebAR tabletop view sees mutations instantaneously.
  static WorldStateSnapshot _canonicalState = TerminalWorldEngine.seedSector7G();
  static final StreamController<WorldStateSnapshot> _worldController =
      StreamController<WorldStateSnapshot>.broadcast();
  static FirebaseSubscription? _firestoreWorldSub;
  static bool _firestoreSyncStarted = false;

  static void _ensureCanonicalSync() {
    if (_firestoreSyncStarted) return;
    _firestoreSyncStarted = true;

    try {
      _firestoreWorldSub = fsListenDoc(_canonicalWorldDocPath, (String jsonStr) {
        try {
          final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
          if (decoded['exists'] == true && decoded['data'] is Map) {
            final data = Map<String, dynamic>.from(decoded['data'] as Map);
            final remote = WorldStateSnapshot.fromMap(data);
            if (remote.rooms.isNotEmpty) {
              _canonicalState = remote;
              if (!_worldController.isClosed) {
                _worldController.add(_canonicalState);
              }
            }
          } else {
            // Seed Firestore with Sector 7G if not yet initialized
            _persistCanonicalState(_canonicalState);
          }
        } catch (e) {
          print('[WebGameService canonical sync parse warning] $e');
        }
      });
    } catch (_) {
      // Safe fallback to in-memory single-world state in non-Firebase environments
    }
  }

  static Future<void> _persistCanonicalState(WorldStateSnapshot next) async {
    _canonicalState = next;
    if (!_worldController.isClosed) {
      _worldController.add(_canonicalState);
    }
    try {
      await fsSetDoc(
        _canonicalWorldDocPath,
        jsonEncode(next.toMap()),
        true,
      );
    } catch (e) {
      // Allow local/guest interaction to proceed smoothly even if Firestore rules block writes
      print('[WebGameService persist info] $e');
    }
  }

  static Stream<T> _watchDerived<T>(
    T Function(WorldStateSnapshot state) selector,
  ) {
    _ensureCanonicalSync();
    late final StreamController<T> controller;
    StreamSubscription<WorldStateSnapshot>? sub;

    controller = StreamController<T>.broadcast(
      onListen: () {
        controller.add(selector(_canonicalState));
        sub = _worldController.stream.listen((snap) {
          if (!controller.isClosed) {
            controller.add(selector(snap));
          }
        });
      },
      onCancel: () {
        sub?.cancel();
      },
    );
    return controller.stream;
  }

  static String _cleanHandleForActor(String actorEntityId) {
    final email = getCurrentUserEmail();
    if (email != null && email.contains('@')) {
      return email.split('@').first;
    }
    if (actorEntityId.length > 8) {
      return 'Runner_${actorEntityId.substring(0, 6)}';
    }
    return actorEntityId;
  }

  // --- Legacy Character & Battle Log Compatibility ---

  @override
  Stream<List<GameCharacter>> getMyCharacters(String userId) {
    if (userId.isEmpty) return Stream.value([]);
    final controller = StreamController<List<GameCharacter>>.broadcast();

    final unsub = fsListenQuery(
      _charPath,
      'ownerId',
      '==',
      jsonEncode(userId),
      '',
      false,
      (String jsonStr) {
        try {
          final List decoded = jsonDecode(jsonStr) as List;
          final chars = decoded.map((d) {
            final data = Map<String, dynamic>.from(d['data'] as Map);
            return GameCharacter.fromMap(d['id'] as String, data);
          }).toList();
          if (!controller.isClosed) {
            controller.add(chars);
          }
        } catch (e) {
          print('[WebGameService getMyCharacters Error] $e');
          if (!controller.isClosed) {
            controller.add([]);
          }
        }
      },
    );

    controller.onCancel = () {
      unsub.callAsFunction();
    };
    return controller.stream;
  }

  @override
  Stream<List<GameCharacter>> getPublicCharacters(String currentUserId) {
    final controller = StreamController<List<GameCharacter>>.broadcast();

    final unsub = fsListenQuery(
      _charPath,
      '',
      '',
      '',
      '',
      false,
      (String jsonStr) {
        try {
          final List decoded = jsonDecode(jsonStr) as List;
          final chars = decoded
              .map((d) {
                final data = Map<String, dynamic>.from(d['data'] as Map);
                return GameCharacter.fromMap(d['id'] as String, data);
              })
              .where((c) => c.ownerId != currentUserId)
              .toList();

          if (!controller.isClosed) {
            controller.add(chars);
          }
        } catch (e) {
          print('[WebGameService getPublicCharacters Error] $e');
          if (!controller.isClosed) {
            controller.add([]);
          }
        }
      },
    );

    controller.onCancel = () {
      unsub.callAsFunction();
    };
    return controller.stream;
  }

  @override
  Future<void> createCharacter(String userId, String name) async {
    if (userId.isEmpty || name.trim().isEmpty) return;

    final rand = Random();
    int roll3d6() =>
        rand.nextInt(6) + 1 + rand.nextInt(6) + 1 + rand.nextInt(6) + 1;

    final int str = roll3d6();
    final int dex = roll3d6();
    final int con = roll3d6();
    final int hp = con * 3;

    final char = GameCharacter(
      id: '',
      ownerId: userId,
      name: name.trim(),
      bio: 'A wanderer in Terminal, CA',
      str: str,
      dex: dex,
      con: con,
      maxHp: hp,
      currentHp: hp,
      wins: 0,
      losses: 0,
    );

    await fsAddDoc(_charPath, jsonEncode(char.toMap()));
  }

  @override
  Future<void> updateCharacter(GameCharacter char) async {
    if (char.id.isEmpty) return;
    await fsUpdateDoc('$_charPath/${char.id}', jsonEncode(char.toMap()));
  }

  @override
  Future<void> saveBattleLog(BattleLog log) async {
    await fsAddDoc(_battlePath, jsonEncode(log.toMap()));

    if (log.winnerId == log.attackerId && log.attackerId.isNotEmpty) {
      await fsUpdateDoc(
        '$_charPath/${log.attackerId}',
        jsonEncode({'wins': WebFieldValue.increment(1)}),
      );
      if (log.defenderId.isNotEmpty) {
        await fsUpdateDoc(
          '$_charPath/${log.defenderId}',
          jsonEncode({'losses': WebFieldValue.increment(1)}),
        );
      }
    } else if (log.winnerId == log.defenderId && log.defenderId.isNotEmpty) {
      await fsUpdateDoc(
        '$_charPath/${log.defenderId}',
        jsonEncode({'wins': WebFieldValue.increment(1)}),
      );
      if (log.attackerId.isNotEmpty) {
        await fsUpdateDoc(
          '$_charPath/${log.attackerId}',
          jsonEncode({'losses': WebFieldValue.increment(1)}),
        );
      }
    }
  }

  // --- Canonical Single-World `terminal` API (Phase 2 Live Sync) ---

  @override
  Stream<WorldStateSnapshot> watchCanonicalWorld() =>
      _watchDerived((snap) => snap);

  @override
  Stream<PageEncounter?> watchPageEncounter(String imageId) =>
      _watchDerived((snap) => TerminalWorldEngine.findEncounter(snap, imageId));

  @override
  Stream<WorldRoom?> watchWorldRoom(String roomId) =>
      _watchDerived((snap) => snap.rooms[roomId]);

  @override
  Stream<List<WorldEvent>> watchRoomEvents(String roomId) => _watchDerived(
        (snap) => snap.events.where((e) => e.roomId == roomId).toList(),
      );

  @override
  Future<List<String>> executePageAction({
    required String imageId,
    required String actorEntityId,
    required String actionId,
    String? inputCode,
  }) async {
    _ensureCanonicalSync();
    final seeded = TerminalWorldEngine.ensureActorEntity(
      _canonicalState,
      actorEntityId: actorEntityId,
      ownerUserId: actorEntityId,
      handle: _cleanHandleForActor(actorEntityId),
    );
    final res = TerminalWorldEngine.executePageAction(
      state: seeded,
      imageId: imageId,
      actorEntityId: actorEntityId,
      actionId: actionId,
      inputCode: inputCode,
    );
    await _persistCanonicalState(res.state);
    return res.outputLines;
  }

  @override
  Future<List<String>> executeTerminalCommand({
    required String actorEntityId,
    required String rawCommand,
  }) async {
    _ensureCanonicalSync();
    final seeded = TerminalWorldEngine.ensureActorEntity(
      _canonicalState,
      actorEntityId: actorEntityId,
      ownerUserId: actorEntityId,
      handle: _cleanHandleForActor(actorEntityId),
    );
    final res = TerminalWorldEngine.executeCommand(
      state: seeded,
      actorEntityId: actorEntityId,
      rawCommand: rawCommand,
    );
    await _persistCanonicalState(res.state);
    return res.outputLines;
  }

  @override
  Stream<TabletopArSession?> watchTabletopSession(String sessionId) =>
      _watchDerived((snap) => snap.arSessions[sessionId]);

  @override
  Future<List<String>> startTabletopArSession({
    required String anchorPageId,
    required String hostUserId,
    String? sessionId,
  }) async {
    _ensureCanonicalSync();
    final seeded = TerminalWorldEngine.ensureActorEntity(
      _canonicalState,
      actorEntityId: hostUserId,
      ownerUserId: hostUserId,
      handle: _cleanHandleForActor(hostUserId),
    );
    final res = TerminalWorldEngine.startTabletopArSession(
      state: seeded,
      anchorPageId: anchorPageId,
      hostUserId: hostUserId,
      sessionId: sessionId,
    );
    await _persistCanonicalState(res.state);
    return res.outputLines;
  }

  @override
  Future<List<String>> ingestQrIntoTabletopSession({
    required String sessionId,
    required String scannedQrCode,
    String? fallbackHandle,
  }) async {
    _ensureCanonicalSync();
    final res = TerminalWorldEngine.ingestQrIntoArSession(
      state: _canonicalState,
      sessionId: sessionId,
      scannedQrCode: scannedQrCode,
      fallbackEntityHandle: fallbackHandle,
    );
    await _persistCanonicalState(res.state);
    return res.outputLines;
  }

  @override
  Future<List<String>> moveTabletopUnit({
    required String sessionId,
    required String entityId,
    required GridCoordinate targetCoord,
  }) async {
    _ensureCanonicalSync();
    final res = TerminalWorldEngine.moveTabletopUnit(
      state: _canonicalState,
      sessionId: sessionId,
      entityId: entityId,
      targetCoord: targetCoord,
    );
    await _persistCanonicalState(res.state);
    return res.outputLines;
  }

  @override
  Future<void> saveCanonicalWorld(WorldStateSnapshot snapshot) async {
    _ensureCanonicalSync();
    await _persistCanonicalState(snapshot);
  }

  @override
  Future<WorldStateSnapshot> resetCanonicalWorldToSeed() async {
    _ensureCanonicalSync();
    final seed = TerminalWorldEngine.seedSector7G();
    await _persistCanonicalState(seed);
    return seed;
  }

  /// Disposes static listener if ever needed during teardown.
  static void disposeStaticSync() {
    _firestoreWorldSub?.callAsFunction();
    _firestoreWorldSub = null;
    _firestoreSyncStarted = false;
  }
}
