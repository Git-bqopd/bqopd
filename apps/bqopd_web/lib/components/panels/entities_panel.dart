import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_utils.dart';
import '../../repositories/repositories.dart';
import '../profile/profile_mini_card.dart';

/// Represents a parsed `[[...]]` entity token which can be:
/// - Person-only: `[[Phil Seuling|user:<uid>]]` -> navigates to `/@username`
/// - Place-only: `[[123 Main Street, City, St 12345|address:<addr>]]` -> opens Google Maps
/// - Combined Person + Address: `[[Phil Seuling|user:<uid>|address:<addr>]]` ->
///   drops a map pin in [EntitiesColumnPanelHeader], displays 3 rows
///   (`Phil Seuling` / `123 Main Street` / `City, St 12345`), and navigates to `/@username`.
class EntityLink {
  final String label; // Display Name (or standalone address label)
  final String? userRef; // UID or handle (without `user:` prefix)
  final String? addressRef; // Full address string (without `address:` prefix)
  final String rawMatch;

  const EntityLink({
    required this.label,
    this.userRef,
    this.addressRef,
    required this.rawMatch,
  });

  bool get isAddressOnly =>
      (userRef == null || userRef!.isEmpty) &&
          (addressRef != null && addressRef!.isNotEmpty);

  bool get hasUser => userRef != null && userRef!.isNotEmpty;

  bool get hasAddress => addressRef != null && addressRef!.isNotEmpty;

  /// Canonical lookup key used in `_loadedProfiles` for this entity.
  String get profileLookupKey =>
      hasUser ? userRef!.trim() : 'label:${label.trim().toLowerCase()}';

  /// Legacy compatibility helper returning primary reference string if present.
  String? get ref {
    if (hasUser) return 'user:$userRef';
    if (hasAddress) return 'address:$addressRef';
    return null;
  }
}

/// Normalizes handle strings into underscore-separated lowercase handles
/// (e.g. `"Phil Seuling"` -> `"phil_seuling"`).
String normalizeEntityHandle(String input) {
  return input
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^a-z0-9_-]'), '')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

/// Generates plausible handle candidates from a display name or handle
/// (e.g. `"Phil Seuling"` -> `["phil_seuling", "phil-seuling", "philseuling"]`).
List<String> _handleCandidatesFromLabel(String input) {
  final clean = input.trim().replaceAll('@', '');
  if (clean.isEmpty) return const [];

  final seen = <String>{};
  final list = <String>[];

  void addCand(String v) {
    if (v.isNotEmpty && seen.add(v)) {
      list.add(v);
    }
  }

  addCand(normalizeEntityHandle(clean));
  addCand(
    clean
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), ''),
  );
  addCand(clean.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''));

  final words = clean
      .split(RegExp(r'\s+'))
      .map((w) => w.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase())
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.length >= 3) {
    final firstLast = '${words.first} ${words.last}';
    addCand(normalizeEntityHandle(firstLast));
    addCand(firstLast.replaceAll(' ', '-'));
    addCand(firstLast.replaceAll(' ', ''));
  }

  return list;
}

/// Returns true when [label] looks like a street/city address rather than a person's name.
bool _looksLikeStreetOrCityOnly(String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) return true;
  if (RegExp(r'^\d+\s+').hasMatch(trimmed)) return true;
  if (RegExp(r',\s*[A-Z]{2}(?:\s+\d{5})?$').hasMatch(trimmed)) return true;
  return false;
}

/// Formats an address string or profile address fields into display rows:
/// e.g. `["123 Main Street", "City, St 12345"]` or `["City, St"]`.
List<String> _formatAddressLinesFromString(String rawAddress) {
  final clean = rawAddress.trim();
  if (clean.isEmpty) return const [];

  final parts = clean
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  if (parts.length >= 3) {
    final streetLine = parts[0];
    final cityStateZipLine = parts.sublist(1).join(', ');
    return [streetLine, cityStateZipLine];
  }

  if (parts.length == 2) {
    // If the first part begins with a street number (e.g. "123 Main Street, Milwaukee WI 53202"),
    // split across two rows; otherwise keep "City, St" on one row.
    if (RegExp(r'^\d+\s+').hasMatch(parts[0])) {
      return [parts[0], parts[1]];
    }
    return ['${parts[0]}, ${parts[1]}'];
  }

  return [clean];
}

/// Extracts structured address rows (`[streetLine, cityStateZipLine]`) and a single
/// geocodable full address string from a Firestore `/profiles/{uid}` document,
/// falling back to [explicitAddressRef] if the profile has no public address fields.
({List<String> lines, String fullAddress}) _resolveEntityAddress(
    Map<String, dynamic>? profile,
    String? explicitAddressRef,
    ) {
  if (profile != null) {
    final street1 = (profile['street1'] ?? '').toString().trim();
    final street2 = (profile['street2'] ?? '').toString().trim();
    final city = (profile['city'] ?? '').toString().trim();
    final state = (profile['state'] ?? '').toString().trim();
    final zipCode = (profile['zipCode'] ?? '').toString().trim();
    final location = (profile['location'] ?? '').toString().trim();
    final geo = profile['geo'] is Map ? (profile['geo'] as Map) : null;
    final geoFormatted = geo?['formatted']?.toString().trim() ?? '';

    final streetLine = [
      if (street1.isNotEmpty) street1,
      if (street2.isNotEmpty) street2,
    ].join(', ');

    final cityState = [
      if (city.isNotEmpty) city,
      if (state.isNotEmpty) state,
    ].join(', ');

    final cityStateZip = zipCode.isNotEmpty
        ? (cityState.isNotEmpty ? '$cityState $zipCode' : zipCode)
        : cityState;

    if (streetLine.isNotEmpty || cityStateZip.isNotEmpty) {
      final lines = <String>[
        if (streetLine.isNotEmpty) streetLine,
        if (cityStateZip.isNotEmpty) cityStateZip,
      ];
      return (lines: lines, fullAddress: lines.join(', '));
    }

    if (geoFormatted.isNotEmpty) {
      final lines = _formatAddressLinesFromString(geoFormatted);
      return (lines: lines, fullAddress: geoFormatted);
    }

    if (location.isNotEmpty) {
      final lines = _formatAddressLinesFromString(location);
      return (lines: lines, fullAddress: location);
    }
  }

  final fallback = (explicitAddressRef ?? '').trim();
  if (fallback.isNotEmpty) {
    final lines = _formatAddressLinesFromString(fallback);
    return (lines: lines, fullAddress: fallback);
  }

  return (lines: const [], fullAddress: '');
}

/// Parses `[[...]]` entity tokens from raw page text into deduplicated [EntityLink] entries,
/// supporting standalone person links (`[[Name|user:...]]`), standalone place links
/// (`[[Address|address:...]]`), and combined person+address links (`[[Name|user:...|address:...]]`).
List<EntityLink> _parseEntityLinks(String rawFullText) {
  final regex = RegExp(r'\[\[(.*?)\]\]');
  final matches = regex.allMatches(rawFullText);
  final Map<String, EntityLink> uniqueEntities = {};

  for (final m in matches) {
    final content = m.group(1) ?? '';
    final parts = content.split('|');
    final raw = m.group(0) ?? '';

    final List<String> labelParts = [];
    String? userRef;
    String? addressRef;

    for (final rawPart in parts) {
      final p = rawPart.trim();
      if (p.isEmpty) continue;
      if (p.startsWith('user:')) {
        userRef = p.substring(5).trim();
      } else if (p.startsWith('address:')) {
        addressRef = p.substring(8).trim();
      } else if (p.startsWith('@') && p.length > 1) {
        userRef ??= p.substring(1).trim();
        labelParts.add(p);
      } else {
        labelParts.add(p);
      }
    }

    if (labelParts.isEmpty) continue;
    final String canonical = labelParts[0];
    final String key = (userRef != null && userRef.isNotEmpty)
        ? 'user:${userRef.toLowerCase()}'
        : canonical.toLowerCase();

    final existing = uniqueEntities[key];
    if (existing == null) {
      uniqueEntities[key] = EntityLink(
        label: canonical,
        userRef: userRef,
        addressRef: addressRef,
        rawMatch: raw,
      );
    } else {
      uniqueEntities[key] = EntityLink(
        label: existing.label,
        userRef: (userRef != null && userRef.isNotEmpty) ? userRef : existing.userRef,
        addressRef: (addressRef != null && addressRef.isNotEmpty)
            ? addressRef
            : existing.addressRef,
        rawMatch: raw,
      );
    }
  }

  return uniqueEntities.values.toList();
}

/// Resolves a `user:<uidOrHandle>` identifier directly via Firestore documents/queries
/// (by UID, `usernames/{handle}` + alias redirects, `shortcodes/{HANDLE}`, or `profiles.username`),
/// avoiding stream hangs when a document ID does not exist.
Future<Map<String, dynamic>?> _resolveProfileByUidOrHandle(
    String uidOrHandle,
    IUserRepository userRepo,
    ) async {
  final clean = uidOrHandle.trim().replaceAll('@', '');
  if (clean.isEmpty) return null;

  // 1. Direct UID lookup in `profiles/{uid}`
  try {
    final directRes = await fsGetDoc('profiles/$clean');
    final directDoc = jsonDecode(directRes);
    if (directDoc['exists'] == true && directDoc['data'] is Map) {
      final data = Map<String, dynamic>.from(directDoc['data'] as Map);
      data['uid'] ??= clean;
      return data;
    }
  } catch (_) {}

  // 2. Handle lookup across candidate handle normalizations in `usernames/{handle}` & `shortcodes/{HANDLE}`
  final candidates = _handleCandidatesFromLabel(clean);
  if (!candidates.contains(clean.toLowerCase())) {
    candidates.insert(0, clean.toLowerCase());
  }

  for (final handleKey in candidates) {
    try {
      final usernameRes = await fsGetDoc('usernames/$handleKey');
      final doc = jsonDecode(usernameRes);
      if (doc['exists'] == true && doc['data'] is Map) {
        Map<String, dynamic> uData =
        Map<String, dynamic>.from(doc['data'] as Map);
        if (uData['isAlias'] == true && uData['redirect'] != null) {
          final redir = uData['redirect'].toString().trim().toLowerCase();
          if (redir.isNotEmpty) {
            final redirRes = await fsGetDoc('usernames/$redir');
            final redirDoc = jsonDecode(redirRes);
            if (redirDoc['exists'] == true && redirDoc['data'] is Map) {
              uData = Map<String, dynamic>.from(redirDoc['data'] as Map);
            }
          }
        }
        final resolvedUid = uData['uid']?.toString().trim() ?? '';
        if (resolvedUid.isNotEmpty) {
          final profileRes = await fsGetDoc('profiles/$resolvedUid');
          final profileDoc = jsonDecode(profileRes);
          if (profileDoc['exists'] == true && profileDoc['data'] is Map) {
            final data = Map<String, dynamic>.from(profileDoc['data'] as Map);
            data['uid'] ??= resolvedUid;
            data['username'] ??= handleKey;
            return data;
          }
        }
      }
    } catch (_) {}

    try {
      final scRes = await fsGetDoc('shortcodes/${handleKey.toUpperCase()}');
      final scDoc = jsonDecode(scRes);
      if (scDoc['exists'] == true && scDoc['data'] is Map) {
        final scData = scDoc['data'] as Map;
        if (scData['type'] == 'user' && scData['contentId'] != null) {
          final resolvedUid = scData['contentId'].toString().trim();
          if (resolvedUid.isNotEmpty) {
            final profileRes = await fsGetDoc('profiles/$resolvedUid');
            final profileDoc = jsonDecode(profileRes);
            if (profileDoc['exists'] == true && profileDoc['data'] is Map) {
              final data = Map<String, dynamic>.from(profileDoc['data'] as Map);
              data['uid'] ??= resolvedUid;
              data['username'] ??= (scData['displayCode'] ?? handleKey).toString();
              return data;
            }
          }
        }
      }
    } catch (_) {}
  }

  // 3. Fallback query by `username` field on `profiles`
  for (final handleKey in candidates) {
    try {
      final queryRes = await fsQuery(
        'profiles',
        'username',
        '==',
        jsonEncode(handleKey),
        '',
      );
      final List decoded = jsonDecode(queryRes);
      if (decoded.isNotEmpty && decoded.first['data'] is Map) {
        final data = Map<String, dynamic>.from(decoded.first['data'] as Map);
        data['uid'] ??= decoded.first['id']?.toString() ?? '';
        return data;
      }
    } catch (_) {}
  }

  return null;
}

/// Resolves a profile from an entity's display label (for entities that don't yet carry
/// an explicit `user:<uid>` reference in `text_linked`, e.g. `[[Phil Seuling|address:...]]`).
Future<Map<String, dynamic>?> _resolveProfileByLabel(
    String label,
    IUserRepository userRepo,
    ) async {
  final clean = label.trim();
  if (clean.isEmpty || _looksLikeStreetOrCityOnly(clean)) return null;

  for (final cand in _handleCandidatesFromLabel(clean)) {
    final found = await _resolveProfileByUidOrHandle(cand, userRepo);
    if (found != null) return found;
  }

  try {
    final queryRes = await fsQuery(
      'profiles',
      'displayName',
      '==',
      jsonEncode(clean),
      '',
    );
    final List decoded = jsonDecode(queryRes);
    if (decoded.isNotEmpty && decoded.first['data'] is Map) {
      final data = Map<String, dynamic>.from(decoded.first['data'] as Map);
      data['uid'] ??= decoded.first['id']?.toString() ?? '';
      return data;
    }
  } catch (_) {}

  return null;
}

/// Resolves a profile map for [entity] from the loaded cache or live Firestore lookup.
Future<Map<String, dynamic>?> _resolveProfileForEntity(
    EntityLink entity,
    Map<String, Map<String, dynamic>> loadedProfiles,
    IUserRepository userRepo,
    ) async {
  final cached = loadedProfiles[entity.profileLookupKey];
  if (cached != null) return cached;

  if (entity.hasUser) {
    final byRef = await _resolveProfileByUidOrHandle(entity.userRef!, userRepo);
    if (byRef != null) return byRef;
  }

  return await _resolveProfileByLabel(entity.label, userRepo);
}

/// Navigates to the linked user profile (`/@username`) or opens the linked place in Google Maps.
/// For combined entities (`[[Phil Seuling|user:...|address:...]]`), clicking navigates to `/@username`.
Future<void> _navigateToEntity(
    BuildContext context,
    EntityLink entity,
    Map<String, Map<String, dynamic>> loadedProfiles,
    IUserRepository userRepo,
    ) async {
  final profile = await _resolveProfileForEntity(entity, loadedProfiles, userRepo);
  final String? username = profile?['username']?.toString().trim();
  if (username != null && username.isNotEmpty) {
    Router.of(context).push('/@$username');
    return;
  }

  // Fallback if `user:` was specified with a handle or profile doc lacks a `username` field
  if (entity.hasUser) {
    final rawRef = entity.userRef!.trim().replaceAll('@', '');
    if (rawRef.isNotEmpty && !rawRef.startsWith('managed_')) {
      Router.of(context).push('/@$rawRef');
      return;
    }
  }

  if (entity.hasAddress) {
    final addressVal = entity.addressRef!.trim();
    if (addressVal.isNotEmpty) {
      openWindow(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(addressVal)}',
        '_blank',
      );
    }
  }
}

/// Standalone header widget rendered at the very top of the bonusColumn
/// list of entities panels. Aggregates all place entities (including combined
/// person+address entities and linked profiles with public mailing addresses)
/// across every page in the fanzine, geocodes them into map pins, and renders
/// a single unified Google Map.
class EntitiesColumnPanelHeader extends StatefulComponent {
  final String fanzineId;
  final List<Map<String, dynamic>> pages;

  const EntitiesColumnPanelHeader({
    required this.fanzineId,
    required this.pages,
    super.key,
  });

  @override
  State<EntitiesColumnPanelHeader> createState() =>
      _EntitiesColumnPanelHeaderState();
}

class _EntitiesColumnPanelHeaderState extends State<EntitiesColumnPanelHeader> {
  bool _isLoading = true;
  bool _isGeocoding = false;
  List<Map<String, dynamic>> _markers = [];
  final String _mapContainerId = 'entities-issue-header-map';
  final IUserRepository _userRepo = createUserRepository();

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _aggregateAndGeocodeAllPlaces();
    }
  }

  @override
  void didUpdateComponent(EntitiesColumnPanelHeader oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.fanzineId != component.fanzineId ||
        oldComponent.pages.length != component.pages.length) {
      if (kIsWeb) {
        _aggregateAndGeocodeAllPlaces();
      }
    }
  }

  Future<void> _aggregateAndGeocodeAllPlaces() async {
    if (component.pages.isEmpty) {
      setState(() {
        _isLoading = false;
        _markers = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _isGeocoding = true;
    });

    final Map<String, Map<String, String>> uniquePlaces = {};
    final List<EntityLink> allLinks = [];

    try {
      final List<Future<void>> fetches = [];

      for (var page in component.pages) {
        final imageId = page['imageId']?.toString() ?? '';
        if (imageId.isEmpty) continue;

        fetches.add(
          fsGetDoc('images/$imageId').then((res) {
            try {
              final doc = jsonDecode(res);
              if (doc['exists'] == true) {
                final data = doc['data'] as Map<String, dynamic>;
                final textLinked = data['text_linked']?.toString() ?? '';
                final textCorrected = data['text_corrected']?.toString() ??
                    data['text']?.toString() ??
                    '';
                final textRaw = data['text_raw']?.toString() ?? '';
                final fullText = textLinked.isNotEmpty
                    ? textLinked
                    : (textCorrected.isNotEmpty ? textCorrected : textRaw);

                allLinks.addAll(_parseEntityLinks(fullText));
              }
            } catch (err) {
              print('Error reading image $imageId for place entities: $err');
            }
          }),
        );
      }

      await Future.wait(fetches);

      // Resolve any linked user profiles so combined entities and profiles with
      // mailing addresses also drop pins on the Entities header map.
      final Map<String, Map<String, dynamic>> resolvedProfiles = {};
      if (allLinks.isNotEmpty) {
        await Future.wait(
          allLinks.map((link) =>
              _resolveProfileForEntity(link, resolvedProfiles, _userRepo).then((p) {
                if (p != null) {
                  resolvedProfiles[link.profileLookupKey] = p;
                }
              })),
        );
      }

      for (final link in allLinks) {
        final profile = resolvedProfiles[link.profileLookupKey];
        final resolvedAddr = _resolveEntityAddress(profile, link.addressRef);
        if (resolvedAddr.fullAddress.isNotEmpty) {
          final String title = (profile != null &&
              (profile['displayName'] ?? '').toString().trim().isNotEmpty)
              ? profile['displayName'].toString().trim()
              : link.label;
          final key = '${title.toLowerCase()}::${resolvedAddr.fullAddress.toLowerCase()}';
          uniquePlaces[key] = {
            'label': title,
            'address': resolvedAddr.fullAddress,
          };
        }
      }

      final List<Map<String, dynamic>> resolvedMarkers = [];

      for (final place in uniquePlaces.values) {
        final address = place['address']!;
        final label = place['label']!;

        final String? geocodeJson = await geocodeAddress(address);
        if (geocodeJson != null && geocodeJson.isNotEmpty) {
          try {
            final dynamic decoded = jsonDecode(geocodeJson);
            if (decoded is Map && decoded['lat'] != null && decoded['lng'] != null) {
              final double lat = (decoded['lat'] as num).toDouble();
              final double lng = (decoded['lng'] as num).toDouble();
              final String subtitle = decoded['formatted']?.toString() ?? address;
              resolvedMarkers.add({
                'lat': lat,
                'lng': lng,
                'title': label,
                'subtitle': subtitle,
              });
            }
          } catch (e) {
            print('[EntitiesColumnPanelHeader] Failed parsing geocode coords for $address: $e');
          }
        }
      }

      if (mounted) {
        setState(() {
          _markers = resolvedMarkers;
          _isLoading = false;
          _isGeocoding = false;
        });

        Future.delayed(const Duration(milliseconds: 120), () {
          if (_markers.isNotEmpty) {
            renderEntityMap(_mapContainerId, jsonEncode(_markers));
          }
        });
      }
    } catch (e) {
      print('[EntitiesColumnPanelHeader] Aggregate places error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isGeocoding = false;
        });
      }
    }
  }

  @override
  Component build(BuildContext context) {
    if (!_isLoading && _markers.isEmpty) {
      return div([]);
    }

    return div(
      classes: 'bg-white rounded-lg border border-gray-300 shadow-md p-5 mb-5',
      attributes: const {
        'style':
        'background-color: #ffffff; border: 1px solid #cbd5e1; border-radius: 8px; padding: 20px; margin-bottom: 20px; box-shadow: 0 4px 12px rgba(0, 0, 0, 0.08);'
      },
      [
        div(
          classes:
          'flex-row items-center justify-between border-b border-gray-200 pb-2 mb-4',
          attributes: const {
            'style':
            'display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #e2e8f0; padding-bottom: 8px; margin-bottom: 16px;'
          },
          [
            span(
              classes:
              'text-xs font-bold text-gray-600 uppercase tracking-wider',
              attributes: const {
                'style':
                'font-size: 11px; font-weight: bold; color: #475569; letter-spacing: 0.8px; text-transform: uppercase; display: flex; align-items: center; gap: 6px;'
              },
              [
                span(
                  [Component.text('map')],
                  classes: 'material-symbols-outlined',
                  attributes: const {'style': 'font-size: 16px;'},
                ),
                Component.text(' IDENTIFIED PLACES (${_markers.length})'),
              ],
            ),
            if (_isGeocoding)
              span(
                attributes: const {
                  'style': 'font-size: 11px; color: #777; font-style: italic;'
                },
                [Component.text('Geocoding locations...')],
              ),
          ],
        ),
        div(
          classes: 'entities-map-header-wrapper',
          attributes: const {
            'style':
            'width: 100%; border-radius: 8px; overflow: hidden; border: 1px solid #e2e8f0; background-color: #f8fafc; position: relative;'
          },
          [
            div(
              id: _mapContainerId,
              attributes: const {
                'style': 'width: 100%; height: 260px; background-color: #e5e5e5;'
              },
              [
                if (_isGeocoding)
                  div(
                    classes: 'flex items-center justify-center h-full',
                    attributes: const {
                      'style':
                      'height: 100%; display: flex; align-items: center; justify-content: center; color: #888; font-size: 13px;'
                    },
                    [Component.text('Loading map & geocoding places...')],
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Builds a serializable `[[Label|...]]` wikilink tag combining optional person UID and address.
String _buildCombinedWikilinkTag({
  required String label,
  String? userUid,
  String? address,
}) {
  final parts = <String>[label.trim()];
  if (userUid != null && userUid.trim().isNotEmpty) {
    parts.add('user:${userUid.trim()}');
  }
  if (address != null && address.trim().isNotEmpty) {
    parts.add('address:${address.trim()}');
  }
  return '[[${parts.join('|')}]]';
}

/// Dedicated inline drawer (bonusRow) view for wiki-linked entities.
/// Navigates to linked profiles/locations in [ToolScope.reader], and opens the
/// entity-linking modal when in [ToolScope.editor] or [ToolScope.curator].
class EntitiesRowPanel extends StatefulComponent {
  final String imageId;
  final String? fanzineId;
  final bool isEditingMode;
  final ToolScope? activeScope;

  const EntitiesRowPanel({
    required this.imageId,
    this.fanzineId,
    this.isEditingMode = false,
    this.activeScope,
    super.key,
  });

  @override
  State<EntitiesRowPanel> createState() => _EntitiesRowPanelState();
}

class _EntitiesRowPanelState extends State<EntitiesRowPanel> {
  List<EntityLink> _entities = [];
  Map<String, Map<String, dynamic>> _loadedProfiles = {};
  String _rawFullText = '';
  bool _loading = true;

  // Modal Editing State (used when _canEdit is true)
  EntityLink? _editingEntity;
  String _entityType = 'person';
  String _handleInput = '';
  String _addressInput = '';
  bool _modalSaving = false;
  String? _modalError;
  String? _suggestedHandle;

  final IUserRepository _userRepo = createUserRepository();
  final IUploadRepository _uploadRepo = createUploadRepository();

  bool get _canEdit {
    if (component.activeScope != null) {
      return component.activeScope == ToolScope.editor ||
          component.activeScope == ToolScope.curator;
    }
    return component.isEditingMode;
  }

  String get _addressInputId => 'row-modal-address-input-${component.imageId}';

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loadEntities();
    }
  }

  @override
  void didUpdateComponent(EntitiesRowPanel oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.imageId != component.imageId && kIsWeb) {
      _loadEntities();
    }
  }

  Future<void> _loadEntities() async {
    if (component.imageId.isEmpty) {
      setState(() {
        _entities = [];
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);

    try {
      final res = await fsGetDoc('images/${component.imageId}');
      final doc = jsonDecode(res);
      if (doc['exists'] && mounted) {
        final data = doc['data'] as Map<String, dynamic>;
        final textLinked = data['text_linked'] ?? '';
        final textCorrected = data['text_corrected'] ?? data['text'] ?? '';
        final textRaw = data['text_raw'] ?? '';
        _rawFullText = textLinked.isNotEmpty
            ? textLinked
            : (textCorrected.isNotEmpty ? textCorrected : textRaw);

        final parsedList = _parseEntityLinks(_rawFullText);
        setState(() {
          _entities = parsedList;
          _loading = false;
        });
        _loadProfiles(parsedList);
      } else {
        setState(() {
          _entities = [];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProfiles(List<EntityLink> links) async {
    final Map<String, Map<String, dynamic>> tempProfiles = {};
    final List<Future<void>> fetches = [];

    for (final link in links) {
      final lookupKey = link.profileLookupKey;
      if (!tempProfiles.containsKey(lookupKey)) {
        fetches.add(
          _resolveProfileForEntity(link, tempProfiles, _userRepo).then((profileMap) {
            if (profileMap != null) {
              tempProfiles[lookupKey] = profileMap;
            }
          }),
        );
      }
    }

    if (fetches.isNotEmpty) {
      await Future.wait(fetches);
      if (mounted) {
        setState(() => _loadedProfiles = tempProfiles);
      }
    }
  }

  Future<void> _findSuggestedHandle(EntityLink entity) async {
    if (!mounted) return;
    setState(() {
      _suggestedHandle = null;
    });

    final resolved =
    await _resolveProfileForEntity(entity, _loadedProfiles, _userRepo);
    final foundUsername = resolved?['username']?.toString().trim() ?? '';
    if (foundUsername.isNotEmpty && mounted) {
      setState(() {
        _suggestedHandle = foundUsername;
      });
      return;
    }

    final String label = entity.label;
    if (component.fanzineId != null && component.fanzineId!.isNotEmpty) {
      try {
        final imagesRes = await fsQuery(
          'images',
          'usedInFanzines',
          'array-contains',
          jsonEncode(component.fanzineId),
          '',
        );
        final List decodedImages = jsonDecode(imagesRes);

        for (var imgDoc in decodedImages) {
          final Map<String, dynamic> imgData =
              imgDoc['data'] as Map<String, dynamic>? ?? {};
          final String textLinked = imgData['text_linked'] ?? '';
          if (textLinked.isNotEmpty) {
            final regex = RegExp(
              r'\[\[(' + RegExp.escape(label) + r')\|user:([^|\]]+)',
              caseSensitive: false,
            );
            final match = regex.firstMatch(textLinked);
            if (match != null) {
              final String targetUid = match.group(2)?.trim() ?? '';
              if (targetUid.isNotEmpty) {
                final profileRes = await fsGetDoc('profiles/$targetUid');
                final Map<String, dynamic> pDoc = jsonDecode(profileRes);
                if (pDoc['exists'] == true) {
                  final Map<String, dynamic> pData =
                      pDoc['data'] as Map<String, dynamic>? ?? {};
                  final String? username = pData['username'];
                  if (username != null && username.isNotEmpty && mounted) {
                    setState(() {
                      _suggestedHandle = username;
                    });
                    return;
                  }
                }
              }
            }
          }
        }
      } catch (_) {}
    }
  }

  void _onEditEntityTap(EntityLink entity) {
    final profile = _loadedProfiles[entity.profileLookupKey];
    String initialHandle = profile?['username']?.toString() ?? '';
    String initialAddress = entity.addressRef ?? '';
    String resolvedType =
    (entity.isAddressOnly && profile == null) ? 'place' : 'person';

    setState(() {
      _editingEntity = entity;
      _entityType = resolvedType;
      _handleInput = initialHandle;
      _addressInput = initialAddress;
      _modalError = null;
      _modalSaving = false;
      _suggestedHandle = null;
    });

    if (resolvedType == 'person') {
      _findSuggestedHandle(entity);
    } else {
      Timer(const Duration(milliseconds: 120), () {
        initAddressAutocomplete(_addressInputId, (String address) {
          setState(() {
            _addressInput = address;
          });
        });
      });
    }
  }

  Future<void> _saveEntityLink() async {
    final entity = _editingEntity;
    if (entity == null || _modalSaving) return;

    setState(() {
      _modalSaving = true;
      _modalError = null;
    });

    try {
      String replacement = '';
      if (_entityType == 'place') {
        final cleanAddress = _addressInput.trim();
        if (cleanAddress.isEmpty) {
          setState(() {
            _modalError = 'Please enter or select a valid address.';
            _modalSaving = false;
          });
          return;
        }
        replacement = _buildCombinedWikilinkTag(
          label: entity.label,
          userUid: entity.userRef,
          address: cleanAddress,
        );
      } else {
        final cleanHandle =
        _handleInput.trim().toLowerCase().replaceAll('@', '');
        if (cleanHandle.isEmpty) {
          setState(() {
            _modalError = 'Please enter a valid username.';
            _modalSaving = false;
          });
          return;
        }

        final result = await _uploadRepo.lookupUserByHandle(cleanHandle);
        if (result == null) {
          setState(() {
            _modalError = 'Profile @$cleanHandle not found in database.';
            _modalSaving = false;
          });
          return;
        }

        final targetUid = result['uid']?.toString() ?? '';
        final resolvedAddr = _resolveEntityAddress(result, entity.addressRef);
        replacement = _buildCombinedWikilinkTag(
          label: entity.label,
          userUid: targetUid,
          address: resolvedAddr.fullAddress.isNotEmpty
              ? resolvedAddr.fullAddress
              : entity.addressRef,
        );

        if (component.fanzineId != null) {
          await fsUpdateDoc(
            'fanzines/${component.fanzineId}',
            jsonEncode({
              'draftEntities': WebFieldValue.arrayUnion([entity.label])
            }),
          );
        }
      }

      final String updatedText =
      _rawFullText.replaceAll(entity.rawMatch, replacement);
      await fsUpdateDoc(
        'images/${component.imageId}',
        jsonEncode({
          'text_linked': updatedText,
          'needs_linking': false,
        }),
      );

      setState(() {
        _editingEntity = null;
        _handleInput = '';
        _addressInput = '';
        _modalSaving = false;
        _modalError = null;
      });
      _loadEntities();
    } catch (e) {
      setState(() {
        _modalError = 'Save failed: $e';
        _modalSaving = false;
      });
    }
  }

  Future<void> _unlinkEntity() async {
    final entity = _editingEntity;
    if (entity == null || _modalSaving) return;

    setState(() {
      _modalSaving = true;
      _modalError = null;
    });

    try {
      final String replacement = '[[${entity.label}]]';
      final String updatedText =
      _rawFullText.replaceAll(entity.rawMatch, replacement);
      await fsUpdateDoc(
        'images/${component.imageId}',
        jsonEncode({
          'text_linked': updatedText,
        }),
      );

      setState(() {
        _editingEntity = null;
        _handleInput = '';
        _addressInput = '';
        _modalSaving = false;
        _modalError = null;
      });
      _loadEntities();
    } catch (e) {
      setState(() {
        _modalError = 'Unlink failed: $e';
        _modalSaving = false;
      });
    }
  }

  void _onTap(BuildContext context, EntityLink entity) {
    if (_canEdit) {
      _onEditEntityTap(entity);
    } else {
      _navigateToEntity(context, entity, _loadedProfiles, _userRepo);
    }
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(
        [
          div(
            [],
            classes: 'skeleton-line shimmer-bg',
            attributes: const {
              'style': 'height: 12px; border-radius: 4px; width: 100%;'
            },
          ),
          div(
            [],
            classes: 'skeleton-line medium shimmer-bg',
            attributes: const {
              'style': 'height: 12px; border-radius: 4px; width: 85%;'
            },
          ),
        ],
        classes: 'flex-col gap-2 py-4',
        attributes: const {
          'style': 'display: flex; flex-direction: column; gap: 8px; width: 100%;'
        },
      );
    }

    if (_entities.isEmpty) {
      return div(
        [Component.text('No entity links found in page text.')],
        classes: 'p-6 text-center text-gray italic text-xs',
      );
    }

    return div(
      [
        for (var entity in _entities) _buildEntityCard(context, entity),
        if (_canEdit && _editingEntity != null) _buildEditModal(),
      ],
      classes: 'flex-col gap-3',
      attributes: const {
        'style': 'display: flex; flex-direction: column; gap: 12px; width: 100%;'
      },
    );
  }

  Component _buildEntityCard(BuildContext context, EntityLink entity) {
    final Map<String, dynamic>? profile = _loadedProfiles[entity.profileLookupKey];
    final bool isAddressOnly = entity.isAddressOnly && profile == null;
    final bool isLinked = profile != null || entity.hasUser || entity.hasAddress;
    final resolvedAddr = _resolveEntityAddress(profile, entity.addressRef);

    if (isAddressOnly) {
      final lines = resolvedAddr.lines.isNotEmpty
          ? resolvedAddr.lines
          : _formatAddressLinesFromString(entity.label);
      final String row1 = lines.isNotEmpty ? lines[0] : entity.label;
      final String? row2 = lines.length >= 2 ? lines[1] : null;
      return ProfileMiniCard(
        title: row1,
        subtitle: row2,
        isAddress: true,
        isLinked: isLinked,
        onTap: () => _onTap(context, entity),
      );
    }

    // Person-only or Combined Person + Mailing Address card:
    // Row 1: Display Name (e.g. "Phil Seuling")
    // Row 2: Street Address (e.g. "123 Main Street") or @username if no address
    // Row 3: City, State ZIP (e.g. "City, St 12345")
    final String displayName = (profile != null &&
        (profile['displayName'] ?? '').toString().trim().isNotEmpty)
        ? profile['displayName'].toString().trim()
        : entity.label;
    final String? photoUrl = profile?['photoUrl']?.toString();

    String? row2;
    String? row3;
    if (resolvedAddr.lines.isNotEmpty) {
      row2 = resolvedAddr.lines[0];
      if (resolvedAddr.lines.length >= 2) {
        row3 = resolvedAddr.lines[1];
      }
    } else if (profile != null &&
        (profile['username'] ?? '').toString().trim().isNotEmpty) {
      row2 = '@${profile['username'].toString().trim()}';
    }

    return ProfileMiniCard(
      title: displayName,
      subtitle: row2,
      subtitleLine2: row3,
      photoUrl: photoUrl,
      isAddress: false,
      isLinked: isLinked,
      onTap: () => _onTap(context, entity),
    );
  }

  Component _buildEditModal() {
    return div(
      [
        div(
          [
            div(
              [
                div(
                  [
                    div(
                      [
                        h2(
                          [Component.text('Link Entity')],
                          attributes: const {
                            'style':
                            'font-size: 16px; font-weight: bold; margin-bottom: 4px; margin-top: 0;'
                          },
                        ),
                        p(
                          [
                            Component.text('Link "'),
                            span(
                              [Component.text(_editingEntity!.label)],
                              attributes: const {
                                'style': 'font-weight: bold; color: #6750A4;'
                              },
                            ),
                            Component.text(
                                '" to a database profile or places location.')
                          ],
                          attributes: const {
                            'style':
                            'font-size: 12px; color: #555; line-height: 1.4; margin: 0;'
                          },
                        ),
                        div(
                          attributes: const {
                            'style':
                            'display: flex; border: 1px solid #ccc; border-radius: 100px; overflow: hidden; margin-top: 14px; background: white;'
                          },
                          [
                            button(
                              [
                                span(
                                  [Component.text('person')],
                                  classes: 'material-symbols-outlined',
                                  attributes: const {
                                    'style':
                                    'font-size: 14px; margin-right: 4px; vertical-align: middle;'
                                  },
                                ),
                                Component.text('Person')
                              ],
                              attributes: {
                                'type': 'button',
                                'style':
                                'flex: 1; border: none; padding: 6px; font-size: 11px; font-weight: bold; cursor: pointer; '
                                    'background-color: ${_entityType == 'person' ? '#E8DEF8' : 'transparent'}; '
                                    'color: ${_entityType == 'person' ? '#1D192B' : '#49454F'};'
                              },
                              events: {
                                'click': (e) => setState(() {
                                  _entityType = 'person';
                                  _modalError = null;
                                })
                              },
                            ),
                            div(
                              attributes: const {
                                'style': 'width: 1px; background: #ccc;'
                              },
                              [],
                            ),
                            button(
                              [
                                span(
                                  [Component.text('pin_drop')],
                                  classes: 'material-symbols-outlined',
                                  attributes: const {
                                    'style':
                                    'font-size: 14px; margin-right: 4px; vertical-align: middle;'
                                  },
                                ),
                                Component.text('Place')
                              ],
                              attributes: {
                                'type': 'button',
                                'style':
                                'flex: 1; border: none; padding: 6px; font-size: 11px; font-weight: bold; cursor: pointer; '
                                    'background-color: ${_entityType == 'place' ? '#E8DEF8' : 'transparent'}; '
                                    'color: ${_entityType == 'place' ? '#1D192B' : '#49454F'};'
                              },
                              events: {
                                'click': (e) {
                                  setState(() {
                                    _entityType = 'place';
                                    _modalError = null;
                                  });
                                  Timer(const Duration(milliseconds: 120), () {
                                    initAddressAutocomplete(
                                      _addressInputId,
                                          (String address) {
                                        setState(() {
                                          _addressInput = address;
                                        });
                                      },
                                    );
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                        if (_entityType == 'person')
                          div(
                            [
                              input(
                                attributes: {
                                  'type': 'text',
                                  'placeholder': '@username / handle',
                                  'value': _handleInput,
                                  'style':
                                  'width: 100%; padding: 10px; border: 1px solid #ccc; border-radius: 8px; box-sizing: border-box; outline: none; background: white;'
                                },
                                events: {
                                  'input': (e) =>
                                  _handleInput = getInputValue(e)
                                },
                              ),
                              if (_suggestedHandle != null)
                                div(
                                  [
                                    span(
                                      [Component.text('Suggested Link:')],
                                      attributes: const {
                                        'style':
                                        'font-size: 10px; color: #666; margin-bottom: 4px;'
                                      },
                                    ),
                                    button(
                                      [Component.text('@$_suggestedHandle')],
                                      classes: 'profile-btn',
                                      attributes: const {
                                        'type': 'button',
                                        'style':
                                        'padding: 8px 12px; font-size: 12px; border: 1px dashed #6750A4; color: #6750A4; border-radius: 6px; background: rgba(103, 80, 164, 0.05); cursor: pointer; font-weight: bold; width: 100%; text-align: left; display: flex; align-items: center; justify-content: flex-start;'
                                      },
                                      events: {
                                        'click': (e) {
                                          setState(() {
                                            _handleInput =
                                            '@$_suggestedHandle';
                                          });
                                        }
                                      },
                                    )
                                  ],
                                  classes: 'flex-col mt-2',
                                  attributes: const {
                                    'style':
                                    'display: flex; flex-direction: column; width: 100%; align-items: flex-start; margin-top: 8px;'
                                  },
                                ),
                            ],
                            classes: 'flex-col w-full mt-4',
                            attributes: const {
                              'style':
                              'display: flex; flex-direction: column; width: 100%; margin-top: 14px;'
                            },
                          )
                        else
                          div(
                            [
                              input(
                                attributes: {
                                  'type': 'text',
                                  'id': _addressInputId,
                                  'placeholder':
                                  'Start typing normalized address...',
                                  'value': _addressInput,
                                  'style':
                                  'width: 100%; padding: 10px; border: 1px solid #ccc; border-radius: 8px; box-sizing: border-box; outline: none; background: white;'
                                },
                                events: {
                                  'change': (e) {
                                    _addressInput = getInputValue(e);
                                  }
                                },
                              ),
                            ],
                            classes: 'flex-col w-full mt-4',
                            attributes: const {
                              'style':
                              'display: flex; flex-direction: column; width: 100%; margin-top: 14px;'
                            },
                          ),
                        if (_modalError != null)
                          p(
                            [Component.text(_modalError!)],
                            classes: 'error-msg mt-2',
                            attributes: const {
                              'style':
                              'font-size: 11px; margin-top: 4px; color: #ef4444;'
                            },
                          )
                      ],
                      classes: 'flex-col w-full text-left',
                      attributes: const {
                        'style':
                        'display: flex; flex-direction: column; text-align: left;'
                      },
                    ),
                    div(
                      [
                        if (_editingEntity!.ref != null)
                          button(
                            [Component.text('Unlink')],
                            classes: 'profile-btn text-red-500',
                            attributes: const {
                              'style':
                              'padding: 8px 16px; font-size: 12px; cursor: pointer; margin-right: auto; border: 1px solid #ff5252; color: #ff5252; border-radius: 4px; background: white;'
                            },
                            events: {'click': (e) => _unlinkEntity()},
                          ),
                        button(
                          [Component.text('Cancel')],
                          classes: 'profile-btn',
                          attributes: const {
                            'style':
                            'padding: 8px 16px; font-size: 12px; cursor: pointer; border: 1px solid #ccc; border-radius: 4px; background: white; color: #374151;'
                          },
                          events: {
                            'click': (e) {
                              setState(() {
                                _editingEntity = null;
                                _modalError = null;
                                _handleInput = '';
                                _addressInput = '';
                              });
                            }
                          },
                        ),
                        button(
                          [
                            Component.text(
                                _modalSaving ? 'Saving...' : 'Save Link')
                          ],
                          classes: 'btn-primary nav-pill mb-0',
                          attributes: {
                            'style':
                            'padding: 8px 16px; font-size: 12px; height: 32px; display: inline-flex; align-items: center; width: auto; background-color: #6750A4; border: none; border-radius: 50px; color: white; cursor: pointer;',
                            if (_modalSaving) 'disabled': 'true'
                          },
                          events: {'click': (e) => _saveEntityLink()},
                        )
                      ],
                      classes: 'flex-row gap-2 mt-4 justify-end w-full',
                      attributes: const {
                        'style':
                        'display: flex; flex-direction: row; gap: 8px; width: 100%; align-items: center; justify-content: flex-end; margin-top: 16px;'
                      },
                    )
                  ],
                  classes:
                  'white-sticker p-6 w-full h-full flex flex-col justify-between items-center',
                  attributes: const {
                    'style':
                    'display: flex; flex-direction: column; justify-content: space-between; align-items: center; width: 100%; height: 100%; box-sizing: border-box;'
                  },
                )
              ],
              classes: 'manila-envelope',
              attributes: const {
                'style':
                'max-width: 400px; max-height: 520px; border-radius: 12px; overflow: hidden; position: relative; width: 100%;'
              },
            )
          ],
          classes: 'global-modal-overlay',
          attributes: const {
            'style':
            'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.6); z-index: 10000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(4px);'
          },
        )
      ],
    );
  }
}

/// Dedicated desktop 3rd column (bonusColumn) view for page entity wikilinks.
/// Navigates to linked profiles/locations in [ToolScope.reader], and opens the
/// entity-linking modal when in [ToolScope.editor] or [ToolScope.curator].
class EntitiesColumnPanel extends StatefulComponent {
  final String imageId;
  final String? fanzineId;
  final bool isEditingMode;
  final ToolScope? activeScope;

  const EntitiesColumnPanel({
    required this.imageId,
    this.fanzineId,
    this.isEditingMode = false,
    this.activeScope,
    super.key,
  });

  @override
  State<EntitiesColumnPanel> createState() => _EntitiesColumnPanelState();
}

class _EntitiesColumnPanelState extends State<EntitiesColumnPanel> {
  List<EntityLink> _entities = [];
  Map<String, Map<String, dynamic>> _loadedProfiles = {};
  String _rawFullText = '';
  bool _loading = true;

  // Modal Editing State (used when _canEdit is true)
  EntityLink? _editingEntity;
  String _entityType = 'person';
  String _handleInput = '';
  String _addressInput = '';
  bool _modalSaving = false;
  String? _modalError;
  String? _suggestedHandle;

  final IUserRepository _userRepo = createUserRepository();
  final IUploadRepository _uploadRepo = createUploadRepository();

  bool get _canEdit {
    if (component.activeScope != null) {
      return component.activeScope == ToolScope.editor ||
          component.activeScope == ToolScope.curator;
    }
    return component.isEditingMode;
  }

  String get _addressInputId => 'col-modal-address-input-${component.imageId}';

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loadTextData();
    }
  }

  @override
  void didUpdateComponent(EntitiesColumnPanel oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.imageId != component.imageId && kIsWeb) {
      _loadTextData();
    }
  }

  Future<void> _loadTextData() async {
    if (component.imageId.isEmpty) {
      setState(() {
        _entities = [];
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);

    try {
      final res = await fsGetDoc('images/${component.imageId}');
      final doc = jsonDecode(res);
      if (doc['exists'] && mounted) {
        final data = doc['data'] as Map<String, dynamic>;
        final textLinked = data['text_linked'] ?? '';
        final textCorrected = data['text_corrected'] ?? data['text'] ?? '';
        final textRaw = data['text_raw'] ?? '';
        _rawFullText = textLinked.isNotEmpty
            ? textLinked
            : (textCorrected.isNotEmpty ? textCorrected : textRaw);

        final parsedList = _parseEntityLinks(_rawFullText);
        setState(() {
          _entities = parsedList;
          _loading = false;
        });
        _loadEntityProfiles(parsedList);
      } else {
        setState(() {
          _entities = [];
          _loading = false;
        });
      }
    } catch (e) {
      print('[ENTITIES COLUMN PANEL ERROR] Failed loading: $e');
      setState(() {
        _entities = [];
        _loading = false;
      });
    }
  }

  Future<void> _loadEntityProfiles(List<EntityLink> links) async {
    final Map<String, Map<String, dynamic>> tempProfiles = {};
    final List<Future<void>> fetches = [];

    for (final link in links) {
      final lookupKey = link.profileLookupKey;
      if (!tempProfiles.containsKey(lookupKey)) {
        fetches.add(
          _resolveProfileForEntity(link, tempProfiles, _userRepo).then((profileMap) {
            if (profileMap != null) {
              tempProfiles[lookupKey] = profileMap;
            }
          }),
        );
      }
    }

    if (fetches.isNotEmpty) {
      await Future.wait(fetches);
      if (mounted) {
        setState(() {
          _loadedProfiles = tempProfiles;
        });
      }
    }
  }

  Future<void> _findSuggestedHandle(EntityLink entity) async {
    if (!mounted) return;
    setState(() {
      _suggestedHandle = null;
    });

    final resolved =
    await _resolveProfileForEntity(entity, _loadedProfiles, _userRepo);
    final foundUsername = resolved?['username']?.toString().trim() ?? '';
    if (foundUsername.isNotEmpty && mounted) {
      setState(() {
        _suggestedHandle = foundUsername;
      });
      return;
    }

    final String label = entity.label;
    if (component.fanzineId != null && component.fanzineId!.isNotEmpty) {
      try {
        final imagesRes = await fsQuery(
          'images',
          'usedInFanzines',
          'array-contains',
          jsonEncode(component.fanzineId),
          '',
        );
        final List decodedImages = jsonDecode(imagesRes);

        for (var imgDoc in decodedImages) {
          final Map<String, dynamic> imgData =
              imgDoc['data'] as Map<String, dynamic>? ?? {};
          final String textLinked = imgData['text_linked'] ?? '';
          if (textLinked.isNotEmpty) {
            final regex = RegExp(
              r'\[\[(' + RegExp.escape(label) + r')\|user:([^|\]]+)',
              caseSensitive: false,
            );
            final match = regex.firstMatch(textLinked);
            if (match != null) {
              final String targetUid = match.group(2)?.trim() ?? '';
              if (targetUid.isNotEmpty) {
                final profileRes = await fsGetDoc('profiles/$targetUid');
                final Map<String, dynamic> pDoc = jsonDecode(profileRes);
                if (pDoc['exists'] == true) {
                  final Map<String, dynamic> pData =
                      pDoc['data'] as Map<String, dynamic>? ?? {};
                  final String? username = pData['username'];
                  if (username != null && username.isNotEmpty && mounted) {
                    setState(() {
                      _suggestedHandle = username;
                    });
                    return;
                  }
                }
              }
            }
          }
        }
      } catch (_) {}
    }
  }

  void _onEditEntityTap(EntityLink entity) {
    final profile = _loadedProfiles[entity.profileLookupKey];
    String initialHandle = profile?['username']?.toString() ?? '';
    String initialAddress = entity.addressRef ?? '';
    String resolvedType =
    (entity.isAddressOnly && profile == null) ? 'place' : 'person';

    setState(() {
      _editingEntity = entity;
      _entityType = resolvedType;
      _handleInput = initialHandle;
      _addressInput = initialAddress;
      _modalError = null;
      _modalSaving = false;
      _suggestedHandle = null;
    });

    if (resolvedType == 'person') {
      _findSuggestedHandle(entity);
    } else {
      Timer(const Duration(milliseconds: 120), () {
        initAddressAutocomplete(_addressInputId, (String address) {
          setState(() {
            _addressInput = address;
          });
        });
      });
    }
  }

  void _onEntityTap(BuildContext context, EntityLink entity) {
    if (_canEdit) {
      _onEditEntityTap(entity);
    } else {
      _navigateToEntity(context, entity, _loadedProfiles, _userRepo);
    }
  }

  Future<void> _saveEntityLink() async {
    final entity = _editingEntity;
    if (entity == null || _modalSaving) return;

    setState(() {
      _modalSaving = true;
      _modalError = null;
    });

    try {
      String replacement = '';
      if (_entityType == 'place') {
        final cleanAddress = _addressInput.trim();
        if (cleanAddress.isEmpty) {
          setState(() {
            _modalError = 'Please enter or select a valid address.';
            _modalSaving = false;
          });
          return;
        }
        replacement = _buildCombinedWikilinkTag(
          label: entity.label,
          userUid: entity.userRef,
          address: cleanAddress,
        );
      } else {
        final cleanHandle =
        _handleInput.trim().toLowerCase().replaceAll('@', '');
        if (cleanHandle.isEmpty) {
          setState(() {
            _modalError = 'Please enter a valid username.';
            _modalSaving = false;
          });
          return;
        }

        final result = await _uploadRepo.lookupUserByHandle(cleanHandle);
        if (result == null) {
          setState(() {
            _modalError = 'Profile @$cleanHandle not found in database.';
            _modalSaving = false;
          });
          return;
        }

        final targetUid = result['uid']?.toString() ?? '';
        final resolvedAddr = _resolveEntityAddress(result, entity.addressRef);
        replacement = _buildCombinedWikilinkTag(
          label: entity.label,
          userUid: targetUid,
          address: resolvedAddr.fullAddress.isNotEmpty
              ? resolvedAddr.fullAddress
              : entity.addressRef,
        );

        if (component.fanzineId != null) {
          await fsUpdateDoc(
            'fanzines/${component.fanzineId}',
            jsonEncode({
              'draftEntities': WebFieldValue.arrayUnion([entity.label])
            }),
          );
        }
      }

      final String updatedText =
      _rawFullText.replaceAll(entity.rawMatch, replacement);
      await fsUpdateDoc(
        'images/${component.imageId}',
        jsonEncode({
          'text_linked': updatedText,
          'needs_linking': false,
        }),
      );

      setState(() {
        _editingEntity = null;
        _handleInput = '';
        _addressInput = '';
        _modalSaving = false;
        _modalError = null;
      });
      _loadTextData();
    } catch (e) {
      setState(() {
        _modalError = 'Save failed: $e';
        _modalSaving = false;
      });
    }
  }

  Future<void> _unlinkEntity() async {
    final entity = _editingEntity;
    if (entity == null || _modalSaving) return;

    setState(() {
      _modalSaving = true;
      _modalError = null;
    });

    try {
      final String replacement = '[[${entity.label}]]';
      final String updatedText =
      _rawFullText.replaceAll(entity.rawMatch, replacement);
      await fsUpdateDoc(
        'images/${component.imageId}',
        jsonEncode({
          'text_linked': updatedText,
        }),
      );

      setState(() {
        _editingEntity = null;
        _handleInput = '';
        _addressInput = '';
        _modalSaving = false;
        _modalError = null;
      });
      _loadTextData();
    } catch (e) {
      setState(() {
        _modalError = 'Unlink failed: $e';
        _modalSaving = false;
      });
    }
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(
        [
          div(
            [],
            classes: 'skeleton-line shimmer-bg',
            attributes: const {
              'style': 'height: 12px; border-radius: 4px; width: 100%;'
            },
          ),
          div(
            [],
            classes: 'skeleton-line medium shimmer-bg',
            attributes: const {
              'style': 'height: 12px; border-radius: 4px; width: 85%;'
            },
          ),
        ],
        classes: 'flex-col gap-2 py-4',
        attributes: const {
          'style': 'display: flex; flex-direction: column; gap: 8px; width: 100%;'
        },
      );
    }

    if (_entities.isEmpty) {
      return div(
        [Component.text('No entity links found in page text.')],
        classes: 'p-6 text-center text-gray italic text-xs',
      );
    }

    return div(
      [
        for (var entity in _entities) _buildEntityCard(context, entity),
        if (_canEdit && _editingEntity != null) _buildEditModal()
      ],
      classes: 'flex-col gap-3',
      attributes: const {
        'style': 'display: flex; flex-direction: column; gap: 12px; width: 100%;'
      },
    );
  }

  Component _buildEntityCard(BuildContext context, EntityLink entity) {
    final Map<String, dynamic>? profile = _loadedProfiles[entity.profileLookupKey];
    final bool isAddressOnly = entity.isAddressOnly && profile == null;

    final bool isLinked = profile != null || entity.hasUser || entity.hasAddress;
    final bool isClickable = _canEdit || isLinked;
    final resolvedAddr = _resolveEntityAddress(profile, entity.addressRef);

    String row1;
    String? row2;
    String? row3;
    String? photoUrl;

    if (isAddressOnly) {
      final lines = resolvedAddr.lines.isNotEmpty
          ? resolvedAddr.lines
          : _formatAddressLinesFromString(entity.label);
      row1 = lines.isNotEmpty ? lines[0] : entity.label;
      row2 = lines.length >= 2 ? lines[1] : null;
    } else {
      row1 = (profile != null &&
          (profile['displayName'] ?? '').toString().trim().isNotEmpty)
          ? profile['displayName'].toString().trim()
          : entity.label;
      photoUrl = profile?['photoUrl']?.toString();
      if (resolvedAddr.lines.isNotEmpty) {
        row2 = resolvedAddr.lines[0];
        if (resolvedAddr.lines.length >= 2) {
          row3 = resolvedAddr.lines[1];
        }
      } else if (profile != null &&
          (profile['username'] ?? '').toString().trim().isNotEmpty) {
        row2 = '@${profile['username'].toString().trim()}';
      }
    }

    final String trailingIcon = _canEdit
        ? (isLinked ? 'edit_note' : 'link_off')
        : (isAddressOnly
        ? 'open_in_new'
        : (isLinked ? 'arrow_forward' : 'link_off'));

    return div(
      [
        div(
          [
            div(
              [
                if (isAddressOnly)
                  span(
                    [Component.text('pin_drop')],
                    classes: 'material-symbols-outlined text-indigo-600',
                    attributes: const {'style': 'font-size: 18px;'},
                  )
                else if (photoUrl != null && photoUrl.isNotEmpty)
                  img(classes: 'user-avatar', src: photoUrl)
                else
                  div(
                    classes: 'user-avatar-placeholder',
                    [
                      Component.text(
                        row1.isNotEmpty ? row1[0].toUpperCase() : '?',
                      )
                    ],
                  )
              ],
              classes: 'user-avatar-container',
              attributes: const {
                'style':
                'width: 32px; height: 32px; border-radius: 50%; overflow: hidden; background-color: #f1f1f1; flex-shrink: 0; display: flex; align-items: center; justify-content: center; border: 1px solid rgba(0,0,0,0.05);'
              },
            ),
            div(
              [
                div(
                  [Component.text(row1)],
                  classes: 'user-display-name',
                  attributes: const {
                    'style':
                    'font-size: 13px; font-weight: bold; color: black; line-height: 1.25; text-align: left;'
                  },
                ),
                if (row2 != null && row2.isNotEmpty)
                  div(
                    [Component.text(row2)],
                    classes: 'text-xs text-gray',
                    attributes: const {
                      'style':
                      'color: #555555; font-size: 11px; font-weight: 500; margin-top: 2px; line-height: 1.3; text-align: left;'
                    },
                  ),
                if (row3 != null && row3.isNotEmpty)
                  div(
                    [Component.text(row3)],
                    classes: 'text-xs text-gray',
                    attributes: const {
                      'style':
                      'color: #555555; font-size: 11px; font-weight: 500; margin-top: 1px; line-height: 1.3; text-align: left;'
                    },
                  ),
              ],
              classes: 'user-info',
              attributes: const {
                'style':
                'display: flex; flex-direction: column; justify-content: center; text-align: left;'
              },
            )
          ],
          classes: 'user-tile',
          attributes: const {
            'style':
            'display: flex; flex-direction: row; align-items: center; gap: 12px;'
          },
        ),
        span(
          classes: 'material-symbols-outlined text-gray',
          attributes: const {'style': 'font-size: 18px; color: #79747E; flex-shrink: 0;'},
          [
            Component.text(trailingIcon)
          ],
        )
      ],
      classes: isClickable ? 'hover:shadow-md transition-all' : 'transition-all',
      attributes: {
        'style':
        'display: flex; flex-direction: row; align-items: center; justify-content: space-between; padding: 16px; margin-bottom: 8px; '
            'cursor: ${isClickable ? "pointer" : "default"}; '
            'background-color: #ffffff; border: 1px solid #e2e8f0; border-radius: 12px; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.04); width: 100%; box-sizing: border-box;'
      },
      events: {
        if (isClickable) 'click': (e) => _onEntityTap(context, entity),
      },
    );
  }

  Component _buildEditModal() {
    return div(
      [
        div(
          [
            div(
              [
                div(
                  [
                    div(
                      [
                        h2(
                          [Component.text('Link Entity')],
                          attributes: const {
                            'style':
                            'font-size: 16px; font-weight: bold; margin-bottom: 4px; margin-top: 0;'
                          },
                        ),
                        p(
                          [
                            Component.text('Link "'),
                            span(
                              [Component.text(_editingEntity!.label)],
                              attributes: const {
                                'style': 'font-weight: bold; color: #6750A4;'
                              },
                            ),
                            Component.text(
                                '" to a database profile or places location.')
                          ],
                          attributes: const {
                            'style':
                            'font-size: 12px; color: #555; line-height: 1.4; margin: 0;'
                          },
                        ),
                        div(
                          attributes: const {
                            'style':
                            'display: flex; border: 1px solid #ccc; border-radius: 100px; overflow: hidden; margin-top: 14px; background: white;'
                          },
                          [
                            button(
                              [
                                span(
                                  [Component.text('person')],
                                  classes: 'material-symbols-outlined',
                                  attributes: const {
                                    'style':
                                    'font-size: 14px; margin-right: 4px; vertical-align: middle;'
                                  },
                                ),
                                Component.text('Person')
                              ],
                              attributes: {
                                'type': 'button',
                                'style':
                                'flex: 1; border: none; padding: 6px; font-size: 11px; font-weight: bold; cursor: pointer; '
                                    'background-color: ${_entityType == 'person' ? '#E8DEF8' : 'transparent'}; '
                                    'color: ${_entityType == 'person' ? '#1D192B' : '#49454F'};'
                              },
                              events: {
                                'click': (e) => setState(() {
                                  _entityType = 'person';
                                  _modalError = null;
                                })
                              },
                            ),
                            div(
                              attributes: const {
                                'style': 'width: 1px; background: #ccc;'
                              },
                              [],
                            ),
                            button(
                              [
                                span(
                                  [Component.text('pin_drop')],
                                  classes: 'material-symbols-outlined',
                                  attributes: const {
                                    'style':
                                    'font-size: 14px; margin-right: 4px; vertical-align: middle;'
                                  },
                                ),
                                Component.text('Place')
                              ],
                              attributes: {
                                'type': 'button',
                                'style':
                                'flex: 1; border: none; padding: 6px; font-size: 11px; font-weight: bold; cursor: pointer; '
                                    'background-color: ${_entityType == 'place' ? '#E8DEF8' : 'transparent'}; '
                                    'color: ${_entityType == 'place' ? '#1D192B' : '#49454F'};'
                              },
                              events: {
                                'click': (e) {
                                  setState(() {
                                    _entityType = 'place';
                                    _modalError = null;
                                  });
                                  Timer(const Duration(milliseconds: 120), () {
                                    initAddressAutocomplete(
                                      _addressInputId,
                                          (String address) {
                                        setState(() {
                                          _addressInput = address;
                                        });
                                      },
                                    );
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                        if (_entityType == 'person')
                          div(
                            [
                              input(
                                attributes: {
                                  'type': 'text',
                                  'placeholder': '@username / handle',
                                  'value': _handleInput,
                                  'style':
                                  'width: 100%; padding: 10px; border: 1px solid #ccc; border-radius: 8px; box-sizing: border-box; outline: none; background: white;'
                                },
                                events: {
                                  'input': (e) =>
                                  _handleInput = getInputValue(e)
                                },
                              ),
                              if (_suggestedHandle != null)
                                div(
                                  [
                                    span(
                                      [Component.text('Suggested Link:')],
                                      attributes: const {
                                        'style':
                                        'font-size: 10px; color: #666; margin-bottom: 4px;'
                                      },
                                    ),
                                    button(
                                      [Component.text('@$_suggestedHandle')],
                                      classes: 'profile-btn',
                                      attributes: const {
                                        'type': 'button',
                                        'style':
                                        'padding: 8px 12px; font-size: 12px; border: 1px dashed #6750A4; color: #6750A4; border-radius: 6px; background: rgba(103, 80, 164, 0.05); cursor: pointer; font-weight: bold; width: 100%; text-align: left; display: flex; align-items: center; justify-content: flex-start;'
                                      },
                                      events: {
                                        'click': (e) {
                                          setState(() {
                                            _handleInput =
                                            '@$_suggestedHandle';
                                          });
                                        }
                                      },
                                    )
                                  ],
                                  classes: 'flex-col mt-2',
                                  attributes: const {
                                    'style':
                                    'display: flex; flex-direction: column; width: 100%; align-items: flex-start; margin-top: 8px;'
                                  },
                                ),
                            ],
                            classes: 'flex-col w-full mt-4',
                            attributes: const {
                              'style':
                              'display: flex; flex-direction: column; width: 100%; margin-top: 14px;'
                            },
                          )
                        else
                          div(
                            [
                              input(
                                attributes: {
                                  'type': 'text',
                                  'id': _addressInputId,
                                  'placeholder':
                                  'Start typing normalized address...',
                                  'value': _addressInput,
                                  'style':
                                  'width: 100%; padding: 10px; border: 1px solid #ccc; border-radius: 8px; box-sizing: border-box; outline: none; background: white;'
                                },
                                events: {
                                  'change': (e) {
                                    _addressInput = getInputValue(e);
                                  }
                                },
                              ),
                            ],
                            classes: 'flex-col w-full mt-4',
                            attributes: const {
                              'style':
                              'display: flex; flex-direction: column; width: 100%; margin-top: 14px;'
                            },
                          ),
                        if (_modalError != null)
                          p(
                            [Component.text(_modalError!)],
                            classes: 'error-msg mt-2',
                            attributes: const {
                              'style':
                              'font-size: 11px; margin-top: 4px; color: #ef4444;'
                            },
                          )
                      ],
                      classes: 'flex-col w-full text-left',
                      attributes: const {
                        'style':
                        'display: flex; flex-direction: column; text-align: left;'
                      },
                    ),
                    div(
                      [
                        if (_editingEntity!.ref != null)
                          button(
                            [Component.text('Unlink')],
                            classes: 'profile-btn text-red-500',
                            attributes: const {
                              'style':
                              'padding: 8px 16px; font-size: 12px; cursor: pointer; margin-right: auto; border: 1px solid #ff5252; color: #ff5252; border-radius: 4px; background: white;'
                            },
                            events: {'click': (e) => _unlinkEntity()},
                          ),
                        button(
                          [Component.text('Cancel')],
                          classes: 'profile-btn',
                          attributes: const {
                            'style':
                            'padding: 8px 16px; font-size: 12px; cursor: pointer; border: 1px solid #ccc; border-radius: 4px; background: white; color: #374151;'
                          },
                          events: {
                            'click': (e) {
                              setState(() {
                                _editingEntity = null;
                                _modalError = null;
                                _handleInput = '';
                                _addressInput = '';
                              });
                            }
                          },
                        ),
                        button(
                          [
                            Component.text(
                                _modalSaving ? 'Saving...' : 'Save Link')
                          ],
                          classes: 'btn-primary nav-pill mb-0',
                          attributes: {
                            'style':
                            'padding: 8px 16px; font-size: 12px; height: 32px; display: inline-flex; align-items: center; width: auto; background-color: #6750A4; border: none; border-radius: 50px; color: white; cursor: pointer;',
                            if (_modalSaving) 'disabled': 'true'
                          },
                          events: {'click': (e) => _saveEntityLink()},
                        )
                      ],
                      classes: 'flex-row gap-2 mt-4 justify-end w-full',
                      attributes: const {
                        'style':
                        'display: flex; flex-direction: row; gap: 8px; width: 100%; align-items: center; justify-content: flex-end; margin-top: 16px;'
                      },
                    )
                  ],
                  classes:
                  'white-sticker p-6 w-full h-full flex flex-col justify-between items-center',
                  attributes: const {
                    'style':
                    'display: flex; flex-direction: column; justify-content: space-between; align-items: center; width: 100%; height: 100%; box-sizing: border-box;'
                  },
                )
              ],
              classes: 'manila-envelope',
              attributes: const {
                'style':
                'max-width: 400px; max-height: 520px; border-radius: 12px; overflow: hidden; position: relative; width: 100%;'
              },
            )
          ],
          classes: 'global-modal-overlay',
          attributes: const {
            'style':
            'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.6); z-index: 10000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(4px);'
          },
        )
      ],
    );
  }
}

/// Backwards-compatible alias for the default row panel
typedef EntitiesPanel = EntitiesRowPanel;