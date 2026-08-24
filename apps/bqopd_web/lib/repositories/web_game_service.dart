import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';

/// Concrete web implementation of [IGameService] using Firebase JS SDK Interop.
class WebGameService implements IGameService {
  static const String _charPath = 'artifacts/bqopd/public/data/game_characters';
  static const String _battlePath = 'artifacts/bqopd/public/data/game_battles';

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
}