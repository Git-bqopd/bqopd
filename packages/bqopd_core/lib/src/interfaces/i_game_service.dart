import '../models/game_models.dart';

abstract class IGameService {
  Stream<List<GameCharacter>> getMyCharacters(String userId);
  Stream<List<GameCharacter>> getPublicCharacters(String currentUserId);
  Future<void> createCharacter(String userId, String name);
  Future<void> updateCharacter(GameCharacter char);
  Future<void> saveBattleLog(BattleLog log);
}