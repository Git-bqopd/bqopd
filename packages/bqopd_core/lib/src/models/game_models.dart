import 'package:equatable/equatable.dart';
import '../config/kenney_asset_catalog.dart';

// =============================================================================
// 1. SPATIAL GRID & KENNEY 2D/3D OVERHEAD MAP MODELS
// =============================================================================

/// Discrete 0-indexed `(x, y)` coordinate on a `terminal` overhead tactical grid.
class GridCoordinate extends Equatable {
  final int x;
  final int y;

  const GridCoordinate(this.x, this.y);

  factory GridCoordinate.fromMap(Map<String, dynamic> map) {
    return GridCoordinate(
      (map['x'] as num?)?.toInt() ?? 0,
      (map['y'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {'x': x, 'y': y};

  int manhattanDistanceTo(GridCoordinate other) =>
      (x - other.x).abs() + (y - other.y).abs();

  @override
  String toString() => '($x, $y)';

  @override
  List<Object?> get props => [x, y];
}

/// A structural or decorative cell on an [OverheadGridSpec] (wall, door, cover pallet).
class GridTileNode extends Equatable {
  final GridCoordinate coord;
  final String kenneyAssetId;
  final String? label;
  final bool? blocksMovementOverride;
  final bool? providesCoverOverride;

  const GridTileNode({
    required this.coord,
    required this.kenneyAssetId,
    this.label,
    this.blocksMovementOverride,
    this.providesCoverOverride,
  });

  bool get blocksMovement =>
      blocksMovementOverride ??
      KenneyAssetCatalog.getOrFallback(kenneyAssetId).blocksMovement;

  bool get providesCover =>
      providesCoverOverride ??
      KenneyAssetCatalog.getOrFallback(kenneyAssetId).providesCover;

  factory GridTileNode.fromMap(Map<String, dynamic> map) {
    return GridTileNode(
      coord: GridCoordinate.fromMap(
        Map<String, dynamic>.from((map['coord'] as Map?) ?? const {}),
      ),
      kenneyAssetId:
          map['kenneyAssetId']?.toString() ?? 'tile_floor_concrete',
      label: map['label']?.toString(),
      blocksMovementOverride: map['blocksMovement'] as bool?,
      providesCoverOverride: map['providesCover'] as bool?,
    );
  }

  Map<String, dynamic> toMap() => {
    'coord': coord.toMap(),
    'kenneyAssetId': kenneyAssetId,
    if (label != null) 'label': label,
    if (blocksMovementOverride != null)
      'blocksMovement': blocksMovementOverride,
    if (providesCoverOverride != null) 'providesCover': providesCoverOverride,
  };

  @override
  List<Object?> get props => [
    coord,
    kenneyAssetId,
    label,
    blocksMovementOverride,
    providesCoverOverride,
  ];
}

/// Canonical specification for an overhead tactical grid (Apartment, HQ, Rented Warehouse).
///
/// Used both to typeset the printed `terminal_grid_map` fanzine page and as the
/// **1 Positional WebAR Anchor** when laid flat on a physical tabletop.
class OverheadGridSpec extends Equatable {
  final int width;
  final int height;
  final double cellSizeMeters;
  final String anchorMarkerId;
  final List<GridTileNode> tiles;
  final List<GridCoordinate> visitorSpawnPoints;

  const OverheadGridSpec({
    this.width = 8,
    this.height = 10,
    this.cellSizeMeters = 1.5,
    required this.anchorMarkerId,
    this.tiles = const [],
    this.visitorSpawnPoints = const [],
  });

  bool isInBounds(GridCoordinate c) =>
      c.x >= 0 && c.x < width && c.y >= 0 && c.y < height;

  GridTileNode? tileAt(GridCoordinate c) {
    for (final t in tiles) {
      if (t.coord == c) return t;
    }
    return null;
  }

  bool isWalkable(GridCoordinate c) {
    if (!isInBounds(c)) return false;
    final tile = tileAt(c);
    return tile == null || !tile.blocksMovement;
  }

  factory OverheadGridSpec.fromMap(Map<String, dynamic> map) {
    return OverheadGridSpec(
      width: (map['width'] as num?)?.toInt() ?? 8,
      height: (map['height'] as num?)?.toInt() ?? 10,
      cellSizeMeters: (map['cellSizeMeters'] as num?)?.toDouble() ?? 1.5,
      anchorMarkerId: map['anchorMarkerId']?.toString() ?? 'ar_anchor_default',
      tiles: ((map['tiles'] as List?) ?? const [])
          .map((e) => GridTileNode.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      visitorSpawnPoints: ((map['visitorSpawnPoints'] as List?) ?? const [])
          .map(
            (e) => GridCoordinate.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'width': width,
    'height': height,
    'cellSizeMeters': cellSizeMeters,
    'anchorMarkerId': anchorMarkerId,
    'tiles': tiles.map((t) => t.toMap()).toList(),
    'visitorSpawnPoints': visitorSpawnPoints.map((c) => c.toMap()).toList(),
  };

  @override
  List<Object?> get props => [
    width,
    height,
    cellSizeMeters,
    anchorMarkerId,
    tiles,
    visitorSpawnPoints,
  ];
}

// =============================================================================
// 2. INTERACTIVE ROOM PROPS (MOO OBJECTS) & WORLD ENTITIES
// =============================================================================

/// An interactive, stateful prop inside a [WorldRoom] (e.g., a grenade crate,
/// boombox mixtape deck, encrypted dead-drop locker, or subnet terminal).
///
/// Works identically across SSH commands (`examine crate`, `buy grenade`),
/// the `terminal` social button on a fanzine page, and Smartphone WebAR.
class MooObject extends Equatable {
  final String id;
  final String name;
  final List<String> aliases;
  final String description;
  final String kenneyAssetId;
  final GridCoordinate? gridPos;
  final List<String> verbs;
  final Map<String, dynamic> state;

  const MooObject({
    required this.id,
    required this.name,
    this.aliases = const [],
    required this.description,
    required this.kenneyAssetId,
    this.gridPos,
    this.verbs = const ['look'],
    this.state = const {},
  });

  bool matchesTarget(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return false;
    if (id.toLowerCase() == q || name.toLowerCase().contains(q)) return true;
    return aliases.any((a) => a.toLowerCase() == q || a.toLowerCase().contains(q));
  }

  MooObject copyWith({
    String? id,
    String? name,
    List<String>? aliases,
    String? description,
    String? kenneyAssetId,
    GridCoordinate? gridPos,
    List<String>? verbs,
    Map<String, dynamic>? state,
  }) {
    return MooObject(
      id: id ?? this.id,
      name: name ?? this.name,
      aliases: aliases ?? this.aliases,
      description: description ?? this.description,
      kenneyAssetId: kenneyAssetId ?? this.kenneyAssetId,
      gridPos: gridPos ?? this.gridPos,
      verbs: verbs ?? this.verbs,
      state: state ?? this.state,
    );
  }

  factory MooObject.fromMap(Map<String, dynamic> map) {
    return MooObject(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Object',
      aliases: List<String>.from((map['aliases'] as List?) ?? const []),
      description: map['description']?.toString() ?? '',
      kenneyAssetId:
          map['kenneyAssetId']?.toString() ?? 'prop_cargo_pallet',
      gridPos: map['gridPos'] is Map
          ? GridCoordinate.fromMap(
              Map<String, dynamic>.from(map['gridPos'] as Map),
            )
          : null,
      verbs: List<String>.from((map['verbs'] as List?) ?? const ['look']),
      state: Map<String, dynamic>.from((map['state'] as Map?) ?? const {}),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'aliases': aliases,
    'description': description,
    'kenneyAssetId': kenneyAssetId,
    if (gridPos != null) 'gridPos': gridPos!.toMap(),
    'verbs': verbs,
    'state': state,
  };

  @override
  List<Object?> get props => [
    id,
    name,
    aliases,
    description,
    kenneyAssetId,
    gridPos,
    verbs,
    state,
  ];
}

/// Self-explanatory alias for [MooObject] representing a stateful interactive prop in a room.
typedef WorldProp = MooObject;

enum EntityRole {
  player,
  hiredThug,
  vendor,
  npc;

  static EntityRole fromString(String? raw) {
    for (final v in EntityRole.values) {
      if (v.name == raw) return v;
    }
    return EntityRole.player;
  }
}

enum EntityCondition {
  alive,
  wounded,
  dead;

  static EntityCondition fromString(String? raw) {
    for (final v in EntityCondition.values) {
      if (v.name == raw) return v;
    }
    return EntityCondition.alive;
  }
}

class InventoryItem extends Equatable {
  final String id;
  final String name;
  final int quantity;
  final String kenneyAssetId;

  const InventoryItem({
    required this.id,
    required this.name,
    this.quantity = 1,
    this.kenneyAssetId = 'weapon_frag_grenade',
  });

  InventoryItem copyWith({
    String? id,
    String? name,
    int? quantity,
    String? kenneyAssetId,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      kenneyAssetId: kenneyAssetId ?? this.kenneyAssetId,
    );
  }

  factory InventoryItem.fromMap(Map<String, dynamic> map) {
    return InventoryItem(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Item',
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      kenneyAssetId:
          map['kenneyAssetId']?.toString() ?? 'weapon_frag_grenade',
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'quantity': quantity,
    'kenneyAssetId': kenneyAssetId,
  };

  @override
  List<Object?> get props => [id, name, quantity, kenneyAssetId];
}

/// Canonical persistent actor in the single `terminal` world (player persona,
/// hired warehouse gang member, vendor, or street NPC).
class WorldEntity extends Equatable {
  final String id;
  final String ownerId;
  final String handle;
  final String bio;
  final EntityRole role;
  final EntityCondition condition;
  final String currentRoomId;
  final GridCoordinate? gridPos;
  final String kenneyCharacterId;
  final int str;
  final int dex;
  final int con;
  final int maxHp;
  final int currentHp;
  final int credits;
  final int wins;
  final int losses;
  final String factionId;
  final String? mixtapeTitle;
  final String? mixtapeUrl;
  final String? dialogue;
  final List<InventoryItem> inventory;
  final List<String> knownCodes;
  final String? pendingWeeklyOrder;

  const WorldEntity({
    required this.id,
    required this.ownerId,
    required this.handle,
    this.bio = '',
    this.role = EntityRole.player,
    this.condition = EntityCondition.alive,
    this.currentRoomId = 'room_warehouse_7g_east',
    this.gridPos,
    this.kenneyCharacterId = 'char_player_runner',
    this.str = 10,
    this.dex = 10,
    this.con = 10,
    this.maxHp = 30,
    this.currentHp = 30,
    this.credits = 200,
    this.wins = 0,
    this.losses = 0,
    this.factionId = 'independent',
    this.mixtapeTitle,
    this.mixtapeUrl,
    this.dialogue,
    this.inventory = const [],
    this.knownCodes = const [],
    this.pendingWeeklyOrder,
  });

  bool get isAlive => condition != EntityCondition.dead && currentHp > 0;
  int get armorClass => 10 + ((dex - 10) ~/ 2);

  WorldEntity copyWith({
    String? id,
    String? ownerId,
    String? handle,
    String? bio,
    EntityRole? role,
    EntityCondition? condition,
    String? currentRoomId,
    GridCoordinate? gridPos,
    String? kenneyCharacterId,
    int? str,
    int? dex,
    int? con,
    int? maxHp,
    int? currentHp,
    int? credits,
    int? wins,
    int? losses,
    String? factionId,
    String? mixtapeTitle,
    String? mixtapeUrl,
    String? dialogue,
    List<InventoryItem>? inventory,
    List<String>? knownCodes,
    String? pendingWeeklyOrder,
  }) {
    return WorldEntity(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      handle: handle ?? this.handle,
      bio: bio ?? this.bio,
      role: role ?? this.role,
      condition: condition ?? this.condition,
      currentRoomId: currentRoomId ?? this.currentRoomId,
      gridPos: gridPos ?? this.gridPos,
      kenneyCharacterId: kenneyCharacterId ?? this.kenneyCharacterId,
      str: str ?? this.str,
      dex: dex ?? this.dex,
      con: con ?? this.con,
      maxHp: maxHp ?? this.maxHp,
      currentHp: currentHp ?? this.currentHp,
      credits: credits ?? this.credits,
      wins: wins ?? this.wins,
      losses: losses ?? this.losses,
      factionId: factionId ?? this.factionId,
      mixtapeTitle: mixtapeTitle ?? this.mixtapeTitle,
      mixtapeUrl: mixtapeUrl ?? this.mixtapeUrl,
      dialogue: dialogue ?? this.dialogue,
      inventory: inventory ?? this.inventory,
      knownCodes: knownCodes ?? this.knownCodes,
      pendingWeeklyOrder: pendingWeeklyOrder ?? this.pendingWeeklyOrder,
    );
  }

  factory WorldEntity.fromMap(String id, Map<String, dynamic> data) {
    final int maxHp = (data['maxHp'] as num?)?.toInt() ?? 30;
    final int currentHp = (data['currentHp'] as num?)?.toInt() ?? maxHp;
    return WorldEntity(
      id: id,
      ownerId: data['ownerId']?.toString() ?? '',
      handle: (data['handle'] ?? data['name'])?.toString() ?? 'Unknown',
      bio: data['bio']?.toString() ?? '',
      role: EntityRole.fromString(data['role']?.toString()),
      condition: currentHp <= 0
          ? EntityCondition.dead
          : EntityCondition.fromString(data['condition']?.toString()),
      currentRoomId:
          data['currentRoomId']?.toString() ?? 'room_warehouse_7g_east',
      gridPos: data['gridPos'] is Map
          ? GridCoordinate.fromMap(
              Map<String, dynamic>.from(data['gridPos'] as Map),
            )
          : null,
      kenneyCharacterId:
          data['kenneyCharacterId']?.toString() ?? 'char_player_runner',
      str: (data['str'] as num?)?.toInt() ?? 10,
      dex: (data['dex'] as num?)?.toInt() ?? 10,
      con: (data['con'] as num?)?.toInt() ?? 10,
      maxHp: maxHp,
      currentHp: currentHp,
      credits: (data['credits'] as num?)?.toInt() ?? 200,
      wins: (data['wins'] as num?)?.toInt() ?? 0,
      losses: (data['losses'] as num?)?.toInt() ?? 0,
      factionId: data['factionId']?.toString() ?? 'independent',
      mixtapeTitle: data['mixtapeTitle']?.toString(),
      mixtapeUrl: data['mixtapeUrl']?.toString(),
      dialogue: data['dialogue']?.toString(),
      inventory: ((data['inventory'] as List?) ?? const [])
          .map(
            (e) => InventoryItem.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      knownCodes: List<String>.from((data['knownCodes'] as List?) ?? const []),
      pendingWeeklyOrder: data['pendingWeeklyOrder']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'ownerId': ownerId,
    'handle': handle,
    'name': handle, // Backwards-compatible field alias
    'bio': bio,
    'role': role.name,
    'condition': condition.name,
    'currentRoomId': currentRoomId,
    if (gridPos != null) 'gridPos': gridPos!.toMap(),
    'kenneyCharacterId': kenneyCharacterId,
    'str': str,
    'dex': dex,
    'con': con,
    'maxHp': maxHp,
    'currentHp': currentHp,
    'credits': credits,
    'wins': wins,
    'losses': losses,
    'factionId': factionId,
    if (mixtapeTitle != null) 'mixtapeTitle': mixtapeTitle,
    if (mixtapeUrl != null) 'mixtapeUrl': mixtapeUrl,
    if (dialogue != null) 'dialogue': dialogue,
    'inventory': inventory.map((i) => i.toMap()).toList(),
    'knownCodes': knownCodes,
    if (pendingWeeklyOrder != null) 'pendingWeeklyOrder': pendingWeeklyOrder,
  };

  @override
  List<Object?> get props => [
    id,
    ownerId,
    handle,
    bio,
    role,
    condition,
    currentRoomId,
    gridPos,
    kenneyCharacterId,
    str,
    dex,
    con,
    maxHp,
    currentHp,
    credits,
    wins,
    losses,
    factionId,
    mixtapeTitle,
    mixtapeUrl,
    dialogue,
    inventory,
    knownCodes,
    pendingWeeklyOrder,
  ];
}

// =============================================================================
// 3. CANONICAL ROOMS, PAGE ENCOUNTERS (2026->2099), WEBAR SESSIONS & EVENTS
// =============================================================================

/// A persistent spatial location in the single `terminal` world.
/// Simultaneously powers SSH MUD traversal, contextual Fanzine encounters, and WebAR grids.
class WorldRoom extends Equatable {
  final String id;
  final String sectorId;
  final String title;
  final String description;

  /// Exits mapping direction/verb (`north`, `out`, `alley`, `subnet`) -> target `roomId`.
  final Map<String, String> exits;
  final List<String> linkedPageIds;
  final OverheadGridSpec? gridSpec;
  final List<MooObject> objects;
  final List<String> occupantIds;
  final String? ownerCrewId;

  const WorldRoom({
    required this.id,
    required this.sectorId,
    required this.title,
    required this.description,
    this.exits = const {},
    this.linkedPageIds = const [],
    this.gridSpec,
    this.objects = const [],
    this.occupantIds = const [],
    this.ownerCrewId,
  });

  WorldRoom copyWith({
    String? id,
    String? sectorId,
    String? title,
    String? description,
    Map<String, String>? exits,
    List<String>? linkedPageIds,
    OverheadGridSpec? gridSpec,
    List<MooObject>? objects,
    List<String>? occupantIds,
    String? ownerCrewId,
  }) {
    return WorldRoom(
      id: id ?? this.id,
      sectorId: sectorId ?? this.sectorId,
      title: title ?? this.title,
      description: description ?? this.description,
      exits: exits ?? this.exits,
      linkedPageIds: linkedPageIds ?? this.linkedPageIds,
      gridSpec: gridSpec ?? this.gridSpec,
      objects: objects ?? this.objects,
      occupantIds: occupantIds ?? this.occupantIds,
      ownerCrewId: ownerCrewId ?? this.ownerCrewId,
    );
  }

  factory WorldRoom.fromMap(String id, Map<String, dynamic> map) {
    return WorldRoom(
      id: id,
      sectorId: map['sectorId']?.toString() ?? 'sector_7g',
      title: map['title']?.toString() ?? 'Unnamed Node',
      description: map['description']?.toString() ?? '',
      exits: Map<String, String>.from((map['exits'] as Map?) ?? const {}),
      linkedPageIds: List<String>.from(
        (map['linkedPageIds'] as List?) ?? const [],
      ),
      gridSpec: map['gridSpec'] is Map
          ? OverheadGridSpec.fromMap(
              Map<String, dynamic>.from(map['gridSpec'] as Map),
            )
          : null,
      objects: (((map['objects'] ?? map['props']) as List?) ?? const [])
          .map<MooObject>(
            (e) => MooObject.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      occupantIds: List<String>.from((map['occupantIds'] as List?) ?? const []),
      ownerCrewId: map['ownerCrewId']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'sectorId': sectorId,
    'title': title,
    'description': description,
    'exits': exits,
    'linkedPageIds': linkedPageIds,
    if (gridSpec != null) 'gridSpec': gridSpec!.toMap(),
    'objects': objects.map((p) => p.toMap()).toList(),
    'occupantIds': occupantIds,
    if (ownerCrewId != null) 'ownerCrewId': ownerCrewId,
  };

  @override
  List<Object?> get props => [
    id,
    sectorId,
    title,
    description,
    exits,
    linkedPageIds,
    gridSpec,
    objects,
    occupantIds,
    ownerCrewId,
  ];
}

enum TerminalActionType {
  buyItem,
  playMedia,
  attackActor,
  unlockCode,
  submitTurnOrder,
  scanArTabletop;

  static TerminalActionType fromString(String? raw) {
    for (final v in TerminalActionType.values) {
      if (v.name == raw) return v;
    }
    return TerminalActionType.playMedia;
  }
}

/// Contextual option presented when a reader clicks the `terminal` social button
/// on a fanzine turn page or 1-page drama advertisement.
class TerminalPageAction extends Equatable {
  final String id;
  final String label;
  final TerminalActionType type;
  final String commandEquivalent;
  final String? targetEntityId;
  final String? targetPropId;
  final int costCredits;
  final Map<String, dynamic> payload;

  const TerminalPageAction({
    required this.id,
    required this.label,
    required this.type,
    required this.commandEquivalent,
    this.targetEntityId,
    this.targetPropId,
    this.costCredits = 0,
    this.payload = const {},
  });

  factory TerminalPageAction.fromMap(Map<String, dynamic> map) {
    return TerminalPageAction(
      id: map['id']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      type: TerminalActionType.fromString(map['type']?.toString()),
      commandEquivalent: map['commandEquivalent']?.toString() ?? 'look',
      targetEntityId: map['targetEntityId']?.toString(),
      targetPropId: map['targetPropId']?.toString(),
      costCredits: (map['costCredits'] as num?)?.toInt() ?? 0,
      payload: Map<String, dynamic>.from((map['payload'] as Map?) ?? const {}),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'type': type.name,
    'commandEquivalent': commandEquivalent,
    if (targetEntityId != null) 'targetEntityId': targetEntityId,
    if (targetPropId != null) 'targetPropId': targetPropId,
    'costCredits': costCredits,
    'payload': payload,
  };

  @override
  List<Object?> get props => [
    id,
    label,
    type,
    commandEquivalent,
    targetEntityId,
    targetPropId,
    costCredits,
    payload,
  ];
}

/// Evergreen Digital-Twin binding between a Fanzine Page (`imageId` / `shortCode`)
/// and the live canonical `terminal` world (valid whether opened in 2026 or 2099).
class PageEncounter extends Equatable {
  final String imageId;
  final String shortCode;
  final String templateId;
  final String roomId;
  final String ownerUserId;

  /// Mirrors `bqopd`'s Private-until-Public rule: private mailed turns stay hidden
  /// from public profile browsing until the owner flips them public, whereas 1p Ads
  /// distributed into other readers' zines are immediately interactive.
  final bool isPublic;
  final String title;
  final String subtitle;
  final List<String> featuredEntityIds;
  final List<String> featuredPropIds;
  final List<TerminalPageAction> actions;
  final String createdWeekId;

  const PageEncounter({
    required this.imageId,
    required this.shortCode,
    required this.templateId,
    required this.roomId,
    required this.ownerUserId,
    this.isPublic = false,
    required this.title,
    this.subtitle = '',
    this.featuredEntityIds = const [],
    this.featuredPropIds = const [],
    this.actions = const [],
    this.createdWeekId = '2026-W44',
  });

  PageEncounter copyWith({
    String? imageId,
    String? shortCode,
    String? templateId,
    String? roomId,
    String? ownerUserId,
    bool? isPublic,
    String? title,
    String? subtitle,
    List<String>? featuredEntityIds,
    List<String>? featuredPropIds,
    List<TerminalPageAction>? actions,
    String? createdWeekId,
  }) {
    return PageEncounter(
      imageId: imageId ?? this.imageId,
      shortCode: shortCode ?? this.shortCode,
      templateId: templateId ?? this.templateId,
      roomId: roomId ?? this.roomId,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      isPublic: isPublic ?? this.isPublic,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      featuredEntityIds: featuredEntityIds ?? this.featuredEntityIds,
      featuredPropIds: featuredPropIds ?? this.featuredPropIds,
      actions: actions ?? this.actions,
      createdWeekId: createdWeekId ?? this.createdWeekId,
    );
  }

  factory PageEncounter.fromMap(String imageId, Map<String, dynamic> map) {
    return PageEncounter(
      imageId: imageId,
      shortCode: map['shortCode']?.toString() ?? imageId,
      templateId: map['templateId']?.toString() ?? 'terminal_drama_ad',
      roomId: map['roomId']?.toString() ?? 'room_warehouse_7g_east',
      ownerUserId: map['ownerUserId']?.toString() ?? '',
      isPublic: map['isPublic'] == true,
      title: map['title']?.toString() ?? 'Terminal Encounter',
      subtitle: map['subtitle']?.toString() ?? '',
      featuredEntityIds: List<String>.from(
        (map['featuredEntityIds'] as List?) ?? const [],
      ),
      featuredPropIds: List<String>.from(
        (map['featuredPropIds'] as List?) ?? const [],
      ),
      actions: ((map['actions'] as List?) ?? const [])
          .map(
            (e) =>
                TerminalPageAction.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      createdWeekId: map['createdWeekId']?.toString() ?? '2026-W44',
    );
  }

  Map<String, dynamic> toMap() => {
    'shortCode': shortCode,
    'templateId': templateId,
    'roomId': roomId,
    'ownerUserId': ownerUserId,
    'isPublic': isPublic,
    'title': title,
    'subtitle': subtitle,
    'featuredEntityIds': featuredEntityIds,
    'featuredPropIds': featuredPropIds,
    'actions': actions.map((a) => a.toMap()).toList(),
    'createdWeekId': createdWeekId,
  };

  @override
  List<Object?> get props => [
    imageId,
    shortCode,
    templateId,
    roomId,
    ownerUserId,
    isPublic,
    title,
    subtitle,
    featuredEntityIds,
    featuredPropIds,
    actions,
    createdWeekId,
  ];
}

/// Active Smartphone WebAR Tabletop session implementing the
/// **"1 Positional Anchor + up to 5 Scan-Once QR Ingest"** wargame/TTRPG model.
class TabletopArSession extends Equatable {
  static const int maxScannedParticipants = 5;

  final String sessionId;

  /// The single Overhead Grid Map page laid flat on the table and tracked by camera.
  final String anchorPageId;
  final String roomId;
  final String hostUserId;

  /// Up to 5 other players' or items' QR codes scanned once ("learned about")
  /// without requiring continuous multi-QR camera pose tracking.
  final List<String> ingestedQrCodes;
  final List<String> ingestedEntityIds;
  final Map<String, GridCoordinate> unitPositions;
  final int roundNumber;
  final bool isActive;

  const TabletopArSession({
    required this.sessionId,
    required this.anchorPageId,
    required this.roomId,
    required this.hostUserId,
    this.ingestedQrCodes = const [],
    this.ingestedEntityIds = const [],
    this.unitPositions = const {},
    this.roundNumber = 1,
    this.isActive = true,
  });

  bool get canIngestMore => ingestedQrCodes.length < maxScannedParticipants;

  TabletopArSession copyWith({
    String? sessionId,
    String? anchorPageId,
    String? roomId,
    String? hostUserId,
    List<String>? ingestedQrCodes,
    List<String>? ingestedEntityIds,
    Map<String, GridCoordinate>? unitPositions,
    int? roundNumber,
    bool? isActive,
  }) {
    return TabletopArSession(
      sessionId: sessionId ?? this.sessionId,
      anchorPageId: anchorPageId ?? this.anchorPageId,
      roomId: roomId ?? this.roomId,
      hostUserId: hostUserId ?? this.hostUserId,
      ingestedQrCodes: ingestedQrCodes ?? this.ingestedQrCodes,
      ingestedEntityIds: ingestedEntityIds ?? this.ingestedEntityIds,
      unitPositions: unitPositions ?? this.unitPositions,
      roundNumber: roundNumber ?? this.roundNumber,
      isActive: isActive ?? this.isActive,
    );
  }

  factory TabletopArSession.fromMap(String id, Map<String, dynamic> map) {
    final rawPositions = (map['unitPositions'] as Map?) ?? const {};
    final parsedPositions = <String, GridCoordinate>{};
    rawPositions.forEach((key, value) {
      if (value is Map) {
        parsedPositions[key.toString()] = GridCoordinate.fromMap(
          Map<String, dynamic>.from(value),
        );
      }
    });

    return TabletopArSession(
      sessionId: id,
      anchorPageId: map['anchorPageId']?.toString() ?? '',
      roomId: map['roomId']?.toString() ?? 'room_warehouse_7g_east',
      hostUserId: map['hostUserId']?.toString() ?? '',
      ingestedQrCodes: List<String>.from(
        (map['ingestedQrCodes'] as List?) ?? const [],
      ),
      ingestedEntityIds: List<String>.from(
        (map['ingestedEntityIds'] as List?) ?? const [],
      ),
      unitPositions: parsedPositions,
      roundNumber: (map['roundNumber'] as num?)?.toInt() ?? 1,
      isActive: map['isActive'] != false,
    );
  }

  Map<String, dynamic> toMap() => {
    'anchorPageId': anchorPageId,
    'roomId': roomId,
    'hostUserId': hostUserId,
    'ingestedQrCodes': ingestedQrCodes,
    'ingestedEntityIds': ingestedEntityIds,
    'unitPositions': unitPositions.map((k, v) => MapEntry(k, v.toMap())),
    'roundNumber': roundNumber,
    'isActive': isActive,
  };

  @override
  List<Object?> get props => [
    sessionId,
    anchorPageId,
    roomId,
    hostUserId,
    ingestedQrCodes,
    ingestedEntityIds,
    unitPositions,
    roundNumber,
    isActive,
  ];
}

/// Append-only canonical event log entry powering both real-time SSH/Web feeds
/// and weekly `terminal_screamsheet` newspaper compilation in `/publisher`.
class WorldEvent extends Equatable {
  final String id;
  final DateTime timestamp;
  final String weekId;
  final String roomId;
  final String? sourcePageId;
  final List<String> actorIds;
  final String verb;
  final bool isHeadlineWorthy;
  final String? headline;
  final String narrative;

  const WorldEvent({
    required this.id,
    required this.timestamp,
    required this.weekId,
    required this.roomId,
    this.sourcePageId,
    this.actorIds = const [],
    required this.verb,
    this.isHeadlineWorthy = false,
    this.headline,
    required this.narrative,
  });

  factory WorldEvent.fromMap(String id, Map<String, dynamic> map) {
    return WorldEvent(
      id: id,
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      weekId: map['weekId']?.toString() ?? '2026-W44',
      roomId: map['roomId']?.toString() ?? 'room_warehouse_7g_east',
      sourcePageId: map['sourcePageId']?.toString(),
      actorIds: List<String>.from((map['actorIds'] as List?) ?? const []),
      verb: map['verb']?.toString() ?? 'event',
      isHeadlineWorthy: map['isHeadlineWorthy'] == true,
      headline: map['headline']?.toString(),
      narrative: map['narrative']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'timestamp': timestamp.toIso8601String(),
    'weekId': weekId,
    'roomId': roomId,
    if (sourcePageId != null) 'sourcePageId': sourcePageId,
    'actorIds': actorIds,
    'verb': verb,
    'isHeadlineWorthy': isHeadlineWorthy,
    if (headline != null) 'headline': headline,
    'narrative': narrative,
  };

  @override
  List<Object?> get props => [
    id,
    timestamp,
    weekId,
    roomId,
    sourcePageId,
    actorIds,
    verb,
    isHeadlineWorthy,
    headline,
    narrative,
  ];
}

/// Complete deterministic snapshot of the single canonical `terminal` world.
class WorldStateSnapshot extends Equatable {
  final String worldId;
  final String currentWeekId;
  final int tick;
  final Map<String, WorldRoom> rooms;
  final Map<String, WorldEntity> entities;
  final Map<String, PageEncounter> encounters;
  final Map<String, TabletopArSession> arSessions;
  final List<WorldEvent> events;

  const WorldStateSnapshot({
    this.worldId = 'terminal_canonical_prime',
    this.currentWeekId = '2026-W44',
    this.tick = 1,
    this.rooms = const {},
    this.entities = const {},
    this.encounters = const {},
    this.arSessions = const {},
    this.events = const [],
  });

  WorldStateSnapshot copyWith({
    String? worldId,
    String? currentWeekId,
    int? tick,
    Map<String, WorldRoom>? rooms,
    Map<String, WorldEntity>? entities,
    Map<String, PageEncounter>? encounters,
    Map<String, TabletopArSession>? arSessions,
    List<WorldEvent>? events,
  }) {
    return WorldStateSnapshot(
      worldId: worldId ?? this.worldId,
      currentWeekId: currentWeekId ?? this.currentWeekId,
      tick: tick ?? this.tick,
      rooms: rooms ?? this.rooms,
      entities: entities ?? this.entities,
      encounters: encounters ?? this.encounters,
      arSessions: arSessions ?? this.arSessions,
      events: events ?? this.events,
    );
  }

  factory WorldStateSnapshot.fromMap(Map<String, dynamic> map) {
    final rawRooms = (map['rooms'] as Map?) ?? const {};
    final parsedRooms = <String, WorldRoom>{};
    rawRooms.forEach((k, v) {
      if (v is Map) {
        parsedRooms[k.toString()] = WorldRoom.fromMap(
          k.toString(),
          Map<String, dynamic>.from(v),
        );
      }
    });

    final rawEntities = (map['entities'] as Map?) ?? const {};
    final parsedEntities = <String, WorldEntity>{};
    rawEntities.forEach((k, v) {
      if (v is Map) {
        parsedEntities[k.toString()] = WorldEntity.fromMap(
          k.toString(),
          Map<String, dynamic>.from(v),
        );
      }
    });

    final rawEncounters = (map['encounters'] as Map?) ?? const {};
    final parsedEncounters = <String, PageEncounter>{};
    rawEncounters.forEach((k, v) {
      if (v is Map) {
        parsedEncounters[k.toString()] = PageEncounter.fromMap(
          k.toString(),
          Map<String, dynamic>.from(v),
        );
      }
    });

    final rawSessions = (map['arSessions'] as Map?) ?? const {};
    final parsedSessions = <String, TabletopArSession>{};
    rawSessions.forEach((k, v) {
      if (v is Map) {
        parsedSessions[k.toString()] = TabletopArSession.fromMap(
          k.toString(),
          Map<String, dynamic>.from(v),
        );
      }
    });

    final rawEvents = (map['events'] as List?) ?? const [];
    final parsedEvents = <WorldEvent>[];
    for (int i = 0; i < rawEvents.length; i++) {
      final item = rawEvents[i];
      if (item is Map) {
        final itemMap = Map<String, dynamic>.from(item);
        final id = itemMap['id']?.toString() ?? 'evt_$i';
        parsedEvents.add(WorldEvent.fromMap(id, itemMap));
      }
    }

    return WorldStateSnapshot(
      worldId: map['worldId']?.toString() ?? 'terminal_canonical_prime',
      currentWeekId: map['currentWeekId']?.toString() ?? '2026-W44',
      tick: (map['tick'] as num?)?.toInt() ?? 1,
      rooms: parsedRooms,
      entities: parsedEntities,
      encounters: parsedEncounters,
      arSessions: parsedSessions,
      events: parsedEvents,
    );
  }

  Map<String, dynamic> toMap() => {
    'worldId': worldId,
    'currentWeekId': currentWeekId,
    'tick': tick,
    'rooms': rooms.map((k, v) => MapEntry(k, v.toMap())),
    'entities': entities.map((k, v) => MapEntry(k, v.toMap())),
    'encounters': encounters.map((k, v) => MapEntry(k, v.toMap())),
    'arSessions': arSessions.map((k, v) => MapEntry(k, v.toMap())),
    'events': events
        .map((e) => {'id': e.id, ...e.toMap()})
        .toList(),
  };

  @override
  List<Object?> get props => [
    worldId,
    currentWeekId,
    tick,
    rooms,
    entities,
    encounters,
    arSessions,
    events,
  ];
}

// =============================================================================
// 4. WEEKLY GAME TURN PACKET MODELS (FOR `/publisher` BLUEPRINTS)
// =============================================================================

/// Represents a single compiled `terminal` page inside a player's weekly turn
/// or a spin-off 1-page drama advertisement for other readers' fanzines.
class TerminalTurnPageSpec extends Equatable {
  final String imageId;
  final String shortCode;
  final String templateId;
  final String title;
  final String sidePreference; // 'left', 'right', 'either'
  final String bodyMarkdown;
  final String previewSvgDataUri;
  final PageEncounter encounter;
  final List<String> hashtags;

  const TerminalTurnPageSpec({
    required this.imageId,
    required this.shortCode,
    required this.templateId,
    required this.title,
    this.sidePreference = 'either',
    required this.bodyMarkdown,
    required this.previewSvgDataUri,
    required this.encounter,
    this.hashtags = const ['terminal'],
  });

  @override
  List<Object?> get props => [
    imageId,
    shortCode,
    templateId,
    title,
    sidePreference,
    bodyMarkdown,
    previewSvgDataUri,
    encounter,
    hashtags,
  ];
}

/// Atomic weekly `terminal` output generated per active player (`(userId, weekId)`):
/// - `turnPages`: The 4-page turn sequence (`[Grid Map | Dossier | Screamsheet | Sector Ad]`)
///   packed into the owner's private 24-page fanzine.
/// - `spinOffDramaAds`: 1-page interactive encounter ads spun off from the player's
///   turf/gang to be packed into *other* subscribers' fanzines!
class TerminalTurnPacket extends Equatable {
  final String userId;
  final String weekId;
  final List<TerminalTurnPageSpec> turnPages;
  final List<TerminalTurnPageSpec> spinOffDramaAds;

  const TerminalTurnPacket({
    required this.userId,
    required this.weekId,
    required this.turnPages,
    this.spinOffDramaAds = const [],
  });

  @override
  List<Object?> get props => [userId, weekId, turnPages, spinOffDramaAds];
}

// =============================================================================
// 5. LEGACY COMPATIBILITY BRIDGES (Maintains clean builds prior to Phase 2 UI swap)
// =============================================================================

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

  factory GameCharacter.fromWorldEntity(WorldEntity entity) {
    return GameCharacter(
      id: entity.id,
      ownerId: entity.ownerId,
      name: entity.handle,
      bio: entity.bio,
      str: entity.str,
      dex: entity.dex,
      con: entity.con,
      maxHp: entity.maxHp,
      currentHp: entity.currentHp,
      wins: entity.wins,
      losses: entity.losses,
    );
  }

  WorldEntity toWorldEntity({
    String currentRoomId = 'room_warehouse_7g_east',
  }) {
    return WorldEntity(
      id: id,
      ownerId: ownerId,
      handle: name,
      bio: bio,
      currentRoomId: currentRoomId,
      str: str,
      dex: dex,
      con: con,
      maxHp: maxHp,
      currentHp: currentHp,
      wins: wins,
      losses: losses,
    );
  }

  factory GameCharacter.fromMap(String id, Map<String, dynamic> data) {
    return GameCharacter(
      id: id,
      ownerId: data['ownerId']?.toString() ?? '',
      name: (data['handle'] ?? data['name'])?.toString() ?? 'Unknown',
      bio: data['bio']?.toString() ?? '',
      str: (data['str'] as num?)?.toInt() ?? 10,
      dex: (data['dex'] as num?)?.toInt() ?? 10,
      con: (data['con'] as num?)?.toInt() ?? 10,
      maxHp: (data['maxHp'] as num?)?.toInt() ?? 50,
      currentHp: (data['currentHp'] as num?)?.toInt() ?? 50,
      wins: (data['wins'] as num?)?.toInt() ?? 0,
      losses: (data['losses'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ownerId': ownerId,
      'name': name,
      'handle': name,
      'bio': bio,
      'str': str,
      'dex': dex,
      'con': con,
      'maxHp': maxHp,
      'currentHp': currentHp,
      'wins': wins,
      'losses': losses,
      'updatedAt': DateTime.now(),
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
      'timestamp': DateTime.now(),
    };
  }
}
