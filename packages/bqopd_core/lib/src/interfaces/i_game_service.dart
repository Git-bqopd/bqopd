import '../models/game_models.dart';

/// Unified interface for interacting with the single canonical `terminal` world
/// across Web (`bqopd_web`), Mobile (`bqopd_flutter`), Tabletop WebAR, and SSH.
abstract class IGameService {
  // --- Legacy compatibility methods ---
  Stream<List<GameCharacter>> getMyCharacters(String userId);
  Stream<List<GameCharacter>> getPublicCharacters(String currentUserId);
  Future<void> createCharacter(String userId, String name);
  Future<void> updateCharacter(GameCharacter char);
  Future<void> saveBattleLog(BattleLog log);

  // --- Canonical Single-World `terminal` API (Phase 1 & Phase 2) ---

  /// Streams the complete live [WorldStateSnapshot] for the single canonical world.
  Stream<WorldStateSnapshot> watchCanonicalWorld() =>
      Stream.value(const WorldStateSnapshot());

  /// Streams the live [PageEncounter] bound to a specific fanzine page or ad [imageId].
  Stream<PageEncounter?> watchPageEncounter(String imageId) =>
      Stream.value(null);

  /// Streams the live [WorldRoom] state (occupants, props, grid spec).
  Stream<WorldRoom?> watchWorldRoom(String roomId) => Stream.value(null);

  /// Streams recent canonical [WorldEvent] logs for [roomId].
  Stream<List<WorldEvent>> watchRoomEvents(String roomId) =>
      Stream.value(const []);

  /// Executes a contextual `terminal` social-button action on [imageId]
  /// (e.g., `Buy hand grenades`, `Listen to mixtape`, `Kill gang member`, `Unlock locker`).
  Future<List<String>> executePageAction({
    required String imageId,
    required String actorEntityId,
    required String actionId,
    String? inputCode,
  }) async => const [];

  /// Executes a raw MOO / SSH text command (`look`, `buy`, `listen`, `kill`, `unlock`, `go`, `say`)
  /// against the single canonical world.
  Future<List<String>> executeTerminalCommand({
    required String actorEntityId,
    required String rawCommand,
  }) async => const [];

  /// Starts or attaches to a Smartphone WebAR Tabletop session anchored to [anchorPageId]
  /// (1 positional anchor + up to 5 scan-once QR participants).
  Stream<TabletopArSession?> watchTabletopSession(String sessionId) =>
      Stream.value(null);

  /// Locks the single positional Overhead Grid Map anchor for Smartphone WebAR.
  Future<List<String>> startTabletopArSession({
    required String anchorPageId,
    required String hostUserId,
    String? sessionId,
  }) async => const [];

  /// Scans a secondary player/item QR code **once** into [sessionId] (up to 5 participants).
  Future<List<String>> ingestQrIntoTabletopSession({
    required String sessionId,
    required String scannedQrCode,
    String? fallbackHandle,
  }) async => const [];

  /// Moves a character miniature to [targetCoord] on the WebAR tactical grid.
  Future<List<String>> moveTabletopUnit({
    required String sessionId,
    required String entityId,
    required GridCoordinate targetCoord,
  }) async => const [];

  /// Persists an administrator-edited [WorldStateSnapshot] directly to the canonical world.
  Future<void> saveCanonicalWorld(WorldStateSnapshot snapshot) async {}

  /// Resets the canonical single world back to the baseline Sector 7G seed.
  Future<WorldStateSnapshot> resetCanonicalWorldToSeed() async =>
      const WorldStateSnapshot();
}
