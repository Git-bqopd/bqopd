import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';
import '../../utils/unsaved_fanzine_registry.dart';
import '../../repositories/repositories.dart';
import '../segmented_button.dart';
import '../fanzine_thumbnail_card.dart';

const String _base32 = "0123456789bcdefghjkmnpqrstuvwxyz";

/// Encodes (lat, lng) coordinates into a standard Base32 geohash string.
String encodeGeohash(double lat, double lng, [int precision = 6]) {
  List<double> latInterval = [-90.0, 90.0];
  List<double> lngInterval = [-180.0, 180.0];
  final buffer = StringBuffer();
  const bits = [16, 8, 4, 2, 1];
  int bit = 0;
  int ch = 0;
  bool even = true;

  while (buffer.length < precision) {
    if (even) {
      final mid = (lngInterval[0] + lngInterval[1]) / 2.0;
      if (lng > mid) {
        ch |= bits[bit];
        lngInterval[0] = mid;
      } else {
        lngInterval[1] = mid;
      }
    } else {
      final mid = (latInterval[0] + latInterval[1]) / 2.0;
      if (lat > mid) {
        ch |= bits[bit];
        latInterval[0] = mid;
      } else {
        latInterval[1] = mid;
      }
    }
    even = !even;
    if (bit < 4) {
      bit++;
    } else {
      buffer.write(_base32[ch]);
      bit = 0;
      ch = 0;
    }
  }
  return buffer.toString();
}

/// Geocodes a location string using server-side verified endpoints and cached Firestore records.
Future<Map<String, dynamic>?> resolveGeoForLocation(String locationStr) async {
  final cleanLoc = locationStr.trim();
  if (cleanLoc.isEmpty) return null;
  try {
    final geoJson = await geocodeAddress(cleanLoc);
    if (geoJson != null && geoJson.isNotEmpty) {
      final decoded = jsonDecode(geoJson);
      if (decoded is Map && decoded['lat'] != null && decoded['lng'] != null) {
        final double lat = (decoded['lat'] as num).toDouble();
        final double lng = (decoded['lng'] as num).toDouble();
        final String gh = decoded['geohash']?.toString() ?? encodeGeohash(lat, lng, 6);
        return {
          'lat': lat,
          'lng': lng,
          'geohash': gh,
          'geohash_3': decoded['geohash_3']?.toString() ?? (gh.length >= 3 ? gh.substring(0, 3) : gh),
          'geohash_2': decoded['geohash_2']?.toString() ?? (gh.length >= 2 ? gh.substring(0, 2) : gh),
          if (decoded['formatted'] != null) 'formatted': decoded['formatted'],
          if (decoded['city'] != null) 'city': decoded['city'],
          if (decoded['state'] != null) 'state': decoded['state'],
          if (decoded['country'] != null) 'country': decoded['country'],
        };
      }
    }
  } catch (_) {}
  return null;
}

Map<String, dynamic> _sanitizeGeoMap(Map g) {
  final double lat = (g['lat'] as num).toDouble();
  final double lng = (g['lng'] as num).toDouble();
  final String gh = g['geohash']?.toString() ?? encodeGeohash(lat, lng, 6);
  return {
    'lat': lat,
    'lng': lng,
    'geohash': gh,
    'geohash_3': g['geohash_3']?.toString() ?? (gh.length >= 3 ? gh.substring(0, 3) : gh),
    'geohash_2': g['geohash_2']?.toString() ?? (gh.length >= 2 ? gh.substring(0, 2) : gh),
    if (g['formatted'] != null) 'formatted': g['formatted'],
    if (g['city'] != null) 'city': g['city'],
    if (g['state'] != null) 'state': g['state'],
    if (g['country'] != null) 'country': g['country'],
  };
}

String normalizeHandle(String input) {
  return input
      .trim()
      .toLowerCase()
      .replaceAll('@', '')
      .replaceAll(' ', '-')
      .replaceAll(RegExp(r'[^a-z0-9_-]'), '');
}

/// Extracts a clean geographic location string (e.g. "City, State") from profile or user data.
String extractLocationFromData(Map<String, dynamic> data) {
  if (data['location'] != null && data['location'].toString().trim().isNotEmpty) {
    return data['location'].toString().trim();
  }
  final city = (data['city'] ?? '').toString().trim();
  final state = (data['state'] ?? '').toString().trim();
  final country = (data['country'] ?? '').toString().trim();
  final parts = <String>[];
  if (city.isNotEmpty) parts.add(city);
  if (state.isNotEmpty) parts.add(state);
  if (parts.isEmpty && country.isNotEmpty) {
    parts.add(country);
  } else if (parts.isNotEmpty &&
      country.isNotEmpty &&
      country.toLowerCase() != 'us' &&
      country.toLowerCase() != 'usa' &&
      country.toLowerCase() != 'united states') {
    parts.add(country);
  }
  return parts.join(', ');
}

/// Encapsulates pulled location text along with verified geographic coordinates from an author profile.
class AuthorProfileLocationData {
  final String location;
  final Map<String, dynamic>? geo;
  final String? displayName;
  final String? uid;

  const AuthorProfileLocationData({
    required this.location,
    this.geo,
    this.displayName,
    this.uid,
  });
}

/// Looks up author profile metadata, pulling coordinates and physical locations.
Future<AuthorProfileLocationData> lookupAuthorProfileData({String? uid, String? username}) async {
  String? resolvedUid = uid;
  if (resolvedUid == null || resolvedUid.isEmpty || resolvedUid.startsWith('archival_')) {
    if (username != null && username.isNotEmpty) {
      final handle = normalizeHandle(username);
      try {
        final res = await fsGetDoc('usernames/$handle');
        final doc = jsonDecode(res);
        if (doc['exists'] == true) {
          final data = doc['data'] as Map<String, dynamic>? ?? {};
          if (data['isAlias'] == true && data['redirect'] != null) {
            final redirectHandle = normalizeHandle(data['redirect'].toString());
            final rRes = await fsGetDoc('usernames/$redirectHandle');
            final rDoc = jsonDecode(rRes);
            if (rDoc['exists'] == true) {
              resolvedUid = (rDoc['data'] as Map<String, dynamic>?)?['uid'];
            }
          } else {
            resolvedUid = data['uid'];
          }
        }
      } catch (_) {}
    }
  }

  Map<String, dynamic>? resolvedGeo;
  String resolvedLocation = '';
  String? resolvedDisplayName;

  if (resolvedUid != null && resolvedUid.isNotEmpty && !resolvedUid.startsWith('archival_')) {
    // 1. Check public profile document first (where verified geo is stored)
    try {
      final pRes = await fsGetDoc('profiles/$resolvedUid');
      final pDoc = jsonDecode(pRes);
      if (pDoc['exists'] == true) {
        final pData = pDoc['data'] as Map<String, dynamic>? ?? {};
        resolvedDisplayName = pData['displayName'] ?? pData['username'];
        resolvedLocation = extractLocationFromData(pData);
        if (pData['geo'] is Map) {
          final g = pData['geo'] as Map;
          if (g['lat'] != null && g['lng'] != null) {
            resolvedGeo = _sanitizeGeoMap(g);
          }
        }
      }
    } catch (_) {}

    // 2. Check private Users doc fallback
    if (resolvedGeo == null) {
      try {
        final uRes = await fsGetDoc('Users/$resolvedUid');
        final uDoc = jsonDecode(uRes);
        if (uDoc['exists'] == true) {
          final uData = uDoc['data'] as Map<String, dynamic>? ?? {};
          if (resolvedLocation.isEmpty) {
            resolvedLocation = extractLocationFromData(uData);
          }
          if (uData['geo'] is Map) {
            final g = uData['geo'] as Map;
            if (g['lat'] != null && g['lng'] != null) {
              resolvedGeo = _sanitizeGeoMap(g);
            }
          }
        }
      } catch (_) {}
    }
  } else if (username != null && username.isNotEmpty) {
    try {
      final pQuery = await fsQuery('profiles', 'username', '==', jsonEncode(normalizeHandle(username)), '');
      final List pDocs = jsonDecode(pQuery);
      if (pDocs.isNotEmpty) {
        final firstDoc = pDocs.first;
        resolvedUid = firstDoc['id'] ?? (firstDoc['data'] as Map?)?['uid'];
        final pData = firstDoc['data'] as Map<String, dynamic>? ?? {};
        resolvedDisplayName = pData['displayName'] ?? pData['username'];
        resolvedLocation = extractLocationFromData(pData);
        if (pData['geo'] is Map) {
          final g = pData['geo'] as Map;
          if (g['lat'] != null && g['lng'] != null) {
            resolvedGeo = _sanitizeGeoMap(g);
          }
        }
      }
    } catch (_) {}
  }

  // 3. Fallback: if location text exists but geo coordinates are not yet saved on profile, geocode and backfill
  if (resolvedGeo == null && resolvedLocation.trim().isNotEmpty) {
    resolvedGeo = await resolveGeoForLocation(resolvedLocation.trim());
    if (resolvedGeo != null && resolvedUid != null && resolvedUid.isNotEmpty && !resolvedUid.startsWith('archival_')) {
      fsUpdateDoc('profiles/$resolvedUid', jsonEncode({'geo': resolvedGeo})).catchError((_) => null);
    }
  }

  return AuthorProfileLocationData(
    location: resolvedLocation,
    geo: resolvedGeo,
    displayName: resolvedDisplayName,
    uid: resolvedUid,
  );
}

/// Backwards-compatible string helper for looking up location string only.
Future<String> lookupLocationForAuthor({String? uid, String? username}) async {
  final data = await lookupAuthorProfileData(uid: uid, username: username);
  return data.location;
}

/// Dedicated inline accordion drawer (bonusRow) comments panel.
/// Renders standard conversation in reader mode and the letters transcriber in curator mode.
class CommentsRowPanel extends StatefulComponent {
  final String imageId;
  final String? fanzineId;
  final String? fanzineTitle;
  final String? fanzinePublishedDate;

  const CommentsRowPanel({
    required this.imageId,
    this.fanzineId,
    this.fanzineTitle,
    this.fanzinePublishedDate,
    super.key,
  });

  @override
  State<CommentsRowPanel> createState() => _CommentsRowPanelState();
}

class _CommentsRowPanelState extends State<CommentsRowPanel> {
  late final InteractionBloc _bloc;
  StreamSubscription? _blocSub;
  InteractionState _blocState = const InteractionState();

  String _viewMode = 'reader'; // 'reader' or 'curator'
  bool _isCurator = false;

  // Fanzine metadata cache
  String _fanzineTitle = '';
  String _fanzinePublishedDate = '';

  // Standard reader comment input
  String _newCommentText = "";

  // Curator letters transcriber fields
  String _authorName = "";
  String _authorHandle = "";
  String _authorLocation = "";
  Map<String, dynamic>? _authorGeo; // Stores pulled coordinates
  String _letterText = "";
  String _letterDate = "";

  // Profile lookup & creation state for the letter writer
  bool _profileFound = false;
  String? _resolvedAuthorUid;
  bool _isCreatingProfile = false;
  bool _isLookingUpAuthor = false;
  String? _curatorFeedback;
  bool _isCuratorError = false;

  @override
  void initState() {
    super.initState();
    _fanzineTitle = component.fanzineTitle ?? '';
    _fanzinePublishedDate = component.fanzinePublishedDate ?? '';
    if (_letterDate.isEmpty && _fanzinePublishedDate.isNotEmpty) {
      _letterDate = _fanzinePublishedDate;
    }
    _bloc = InteractionBloc(repository: createEngagementRepository());
    _bloc.add(LoadCommentsRequested(component.imageId));
    _blocSub = _bloc.stream.listen((state) {
      if (mounted) {
        setState(() {
          _blocState = state;
        });
      }
    });
    if (kIsWeb) {
      _fetchFanzineDataAndPermissions();
    }
  }

  @override
  void didUpdateComponent(CommentsRowPanel oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.imageId != component.imageId) {
      _bloc.add(LoadCommentsRequested(component.imageId));
      if (kIsWeb) {
        _fetchFanzineDataAndPermissions();
      }
    }
    if (oldComponent.fanzinePublishedDate != component.fanzinePublishedDate &&
        component.fanzinePublishedDate != null) {
      _fanzinePublishedDate = component.fanzinePublishedDate!;
      if (_letterDate.isEmpty) {
        _letterDate = _fanzinePublishedDate;
      }
    }
  }

  @override
  void dispose() {
    _blocSub?.cancel();
    _bloc.close();
    super.dispose();
  }

  Future<void> _fetchFanzineDataAndPermissions() async {
    final uid = getCurrentUserId();
    bool hasAccess = false;
    final fzId = component.fanzineId;

    String? pubDate;
    String? pubMode;
    bool pubGuess = false;
    String? fzTitle;

    if (fzId != null && fzId.isNotEmpty) {
      if (UnsavedFanzineRegistry.fanzines.containsKey(fzId)) {
        final fz = UnsavedFanzineRegistry.fanzines[fzId]!;
        pubDate = fz.publishedDate;
        pubMode = fz.publishedDateMode;
        pubGuess = fz.publishedDateGuess;
        fzTitle = fz.title;
        if (uid != null && (fz.curators.contains(uid) || fz.ownerId == uid || fz.editors.contains(uid))) {
          hasAccess = true;
        }
      } else {
        try {
          final res = await fsGetDoc('fanzines/$fzId');
          final decoded = jsonDecode(res);
          if (decoded['exists'] == true) {
            final data = decoded['data'] as Map<String, dynamic>? ?? {};
            final List curators = data['curators'] ?? [];
            final List editors = data['editors'] ?? [];
            final String ownerId = data['ownerId'] ?? data['editorId'] ?? '';
            pubDate = data['publishedDate']?.toString();
            pubMode = data['publishedDateMode']?.toString();
            pubGuess = data['publishedDateGuess'] == true;
            fzTitle = data['title']?.toString();
            if (uid != null && (curators.contains(uid) || ownerId == uid || editors.contains(uid))) {
              hasAccess = true;
            }
          }
        } catch (_) {}
      }
    }

    if (!hasAccess && uid != null) {
      try {
        final profRes = await fsGetDoc('profiles/$uid');
        final profDoc = jsonDecode(profRes);
        if (profDoc['exists'] == true) {
          final pData = profDoc['data'] as Map<String, dynamic>? ?? {};
          if (pData['isCurator'] == true || pData['isAdmin'] == true) {
            hasAccess = true;
          }
        }
      } catch (_) {}
    }

    String formatted = '';
    if (pubDate != null && pubDate.isNotEmpty) {
      formatted = formatThumbnailDate(pubDate, pubMode, pubGuess);
      if (formatted.isEmpty) formatted = pubDate;
    }

    if (mounted) {
      setState(() {
        _isCurator = hasAccess;
        if (formatted.isNotEmpty) {
          _fanzinePublishedDate = formatted;
          if (_letterDate.isEmpty) {
            _letterDate = formatted;
          }
        }
        if (fzTitle != null && fzTitle.isNotEmpty && _fanzineTitle.isEmpty) {
          _fanzineTitle = fzTitle;
        }
      });
    }
  }

  void _onAuthorNameChanged(String val) {
    _authorName = val;
    final suggested = normalizeHandle(val);
    _authorHandle = suggested;
    _resolvedAuthorUid = null;
    _profileFound = false;
    _authorGeo = null;
    if (suggested.isNotEmpty) {
      _checkAuthorHandle(suggested);
    }
  }

  Future<void> _checkAuthorHandle(String handle) async {
    final cleanHandle = normalizeHandle(handle);
    if (cleanHandle.isEmpty) return;
    setState(() => _isLookingUpAuthor = true);
    try {
      final data = await lookupAuthorProfileData(username: cleanHandle);
      if (data.uid != null && data.uid!.isNotEmpty && mounted) {
        setState(() {
          _profileFound = true;
          _resolvedAuthorUid = data.uid;
          _isLookingUpAuthor = false;
          if (data.geo != null) {
            _authorGeo = data.geo;
          }
          if (_authorLocation.trim().isEmpty && data.location.isNotEmpty) {
            _authorLocation = data.location;
          }
          if (_authorName.trim().isEmpty && data.displayName != null && data.displayName!.isNotEmpty) {
            _authorName = data.displayName!;
          }
          final locDisplay = data.location.isNotEmpty ? data.location : (data.geo?['formatted'] ?? '');
          final coordDisplay = data.geo != null ? " [${data.geo!['lat']?.toStringAsFixed(2)}, ${data.geo!['lng']?.toStringAsFixed(2)}]" : "";
          _curatorFeedback = locDisplay.isNotEmpty
              ? "Profile linked: @$cleanHandle ($locDisplay)$coordDisplay"
              : "Profile linked: @$cleanHandle$coordDisplay";
          _isCuratorError = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _profileFound = false;
            _resolvedAuthorUid = null;
            _authorGeo = null;
            _isLookingUpAuthor = false;
            _curatorFeedback = null;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLookingUpAuthor = false);
    }
  }

  Future<void> _manualRefreshLocation() async {
    final handle = _authorHandle.isNotEmpty ? _authorHandle : _authorName;
    if (handle.trim().isEmpty) {
      setState(() {
        _curatorFeedback = "Enter a writer name or @handle first.";
        _isCuratorError = true;
      });
      return;
    }
    setState(() => _isLookingUpAuthor = true);
    final data = await lookupAuthorProfileData(uid: _resolvedAuthorUid, username: handle);
    if (mounted) {
      setState(() {
        _isLookingUpAuthor = false;
        if (data.geo != null) {
          _authorGeo = data.geo;
          if (data.location.isNotEmpty) {
            _authorLocation = data.location;
          }
          if (data.displayName != null && data.displayName!.isNotEmpty && _authorName.isEmpty) {
            _authorName = data.displayName!;
          }
          if (data.uid != null && data.uid!.isNotEmpty) {
            _resolvedAuthorUid = data.uid;
            _profileFound = true;
          }
          _curatorFeedback = "Coordinates pulled: ${_authorGeo!['lat']?.toStringAsFixed(4)}, ${_authorGeo!['lng']?.toStringAsFixed(4)} (${_authorLocation.isNotEmpty ? _authorLocation : _authorGeo!['formatted'] ?? ''})";
          _isCuratorError = false;
        } else if (data.location.isNotEmpty) {
          _authorLocation = data.location;
          if (data.displayName != null && data.displayName!.isNotEmpty && _authorName.isEmpty) {
            _authorName = data.displayName!;
          }
          if (data.uid != null && data.uid!.isNotEmpty) {
            _resolvedAuthorUid = data.uid;
            _profileFound = true;
          }
          _curatorFeedback = "Location pulled: ${data.location} (no coordinates saved on profile, will geocode on save)";
          _isCuratorError = false;
        } else {
          _curatorFeedback = "No location or coordinates found on profile for @${normalizeHandle(handle)}.";
          _isCuratorError = true;
        }
      });
    }
  }

  Future<void> _createManagedProfileForAuthor() async {
    final name = _authorName.trim();
    final handle = normalizeHandle(_authorHandle.isNotEmpty ? _authorHandle : name);
    if (name.isEmpty || handle.isEmpty) return;
    setState(() {
      _isCreatingProfile = true;
      _curatorFeedback = "Generating managed profile @$handle...";
      _isCuratorError = false;
    });
    try {
      final uid = getCurrentUserId() ?? 'system';
      final profileId = 'profile_managed_${handle}_${DateTime.now().millisecondsSinceEpoch}';
      String firstName = name;
      String lastName = "";
      if (name.contains(' ')) {
        final parts = name.split(' ');
        firstName = parts.first;
        lastName = parts.sublist(1).join(' ');
      }
      String city = '';
      String state = '';
      if (_authorLocation.contains(',')) {
        final lParts = _authorLocation.split(',');
        city = lParts[0].trim();
        state = lParts.sublist(1).join(',').trim();
      } else {
        city = _authorLocation.trim();
      }
      Map<String, dynamic>? initialGeo = _authorGeo;
      if (initialGeo == null && _authorLocation.trim().isNotEmpty) {
        initialGeo = await resolveGeoForLocation(_authorLocation.trim());
      }

      final profileData = {
        'uid': profileId,
        'username': handle,
        'displayName': name,
        'firstName': firstName,
        'lastName': lastName,
        'city': city,
        'state': state,
        'location': _authorLocation.trim(),
        if (initialGeo != null) 'geo': initialGeo,
        'photoUrl': '',
        'bio': _authorLocation.isNotEmpty
            ? 'Historical letter writer from $_authorLocation.'
            : 'Historical letter writer.',
        'isManaged': true,
        'isCurator': false,
        'isAdmin': false,
        'managers': [uid],
        'followerCount': 0,
        'followingCount': 0,
        'createdAt': WebFieldValue.serverTimestamp(),
        'updatedAt': WebFieldValue.serverTimestamp(),
      };
      await fsSetDoc('profiles/$profileId', jsonEncode(profileData), true);
      await fsSetDoc('usernames/$handle', jsonEncode({
        'uid': profileId,
        'isManaged': true,
        'createdAt': WebFieldValue.serverTimestamp(),
      }), true);
      await fsSetDoc('shortcodes/${handle.toUpperCase()}', jsonEncode({
        'type': 'user',
        'contentId': profileId,
        'displayCode': handle,
        'createdAt': WebFieldValue.serverTimestamp(),
      }), true);
      if (mounted) {
        setState(() {
          _isCreatingProfile = false;
          _profileFound = true;
          _resolvedAuthorUid = profileId;
          _authorGeo = initialGeo;
          _curatorFeedback = initialGeo != null
              ? "Managed profile @$handle created with coordinates!"
              : "Managed profile @$handle created and linked!";
          _isCuratorError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCreatingProfile = false;
          _curatorFeedback = "Failed to create profile: $e";
          _isCuratorError = true;
        });
      }
    }
  }

  Future<void> _transcribeLetter() async {
    final text = _letterText.trim();
    if (text.isEmpty) {
      setState(() {
        _curatorFeedback = "Please enter the letter text.";
        _isCuratorError = true;
      });
      return;
    }
    final authorName = _authorName.trim().isNotEmpty ? _authorName.trim() : 'Anonymous Reader';
    final handle = _authorHandle.trim().isNotEmpty ? normalizeHandle(_authorHandle) : 'reader';
    final authorUid = _resolvedAuthorUid ?? 'archival_${DateTime.now().millisecondsSinceEpoch}';

    setState(() {
      _curatorFeedback = "Committing archival letter...";
      _isCuratorError = false;
    });

    try {
      Map<String, dynamic>? geoData = _authorGeo;
      if (geoData == null && _authorLocation.trim().isNotEmpty) {
        geoData = await resolveGeoForLocation(_authorLocation.trim());
      }

      final commentDoc = {
        'contentId': component.imageId,
        'userId': authorUid,
        'displayName': authorName,
        'username': handle,
        'location': _authorLocation.trim(),
        if (geoData != null) 'geo': geoData,
        'historicalDate': _letterDate.trim(),
        'text': text,
        'sourceType': 'letter_column',
        'createdAt': WebFieldValue.serverTimestamp(),
        'likeCount': 0,
        'context': {
          'fanzineId': component.fanzineId,
          'fanzineTitle': _fanzineTitle.isNotEmpty ? _fanzineTitle : component.fanzineTitle,
        }
      };

      await fsAddDoc('artifacts/bqopd/public/data/comments', jsonEncode(commentDoc));
      if (component.imageId.isNotEmpty) {
        await fsUpdateDoc('images/${component.imageId}', jsonEncode({
          'commentCount': WebFieldValue.increment(1),
        })).catchError((_) => null);
      }

      if (component.fanzineId != null && component.fanzineId!.isNotEmpty && authorName.isNotEmpty) {
        await fsUpdateDoc('fanzines/${component.fanzineId}', jsonEncode({
          'draftEntities': WebFieldValue.arrayUnion([authorName]),
        })).catchError((_) => null);
      }

      if (mounted) {
        setState(() {
          _letterText = "";
          _authorName = "";
          _authorHandle = "";
          _authorLocation = "";
          _authorGeo = null;
          _letterDate = _fanzinePublishedDate;
          _curatorFeedback = "Letter transcribed and linked to @$handle!";
          _isCuratorError = false;
          _profileFound = false;
          _resolvedAuthorUid = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _curatorFeedback = "Error submitting letter: $e";
          _isCuratorError = true;
        });
      }
    }
  }

  void _submitReaderComment() {
    final textVal = _newCommentText.trim();
    if (textVal.isEmpty) return;
    final uid = getCurrentUserId();
    if (uid == null) {
      GlobalModalBus.show();
      return;
    }
    createUserRepository().watchUser(uid).first.then((profile) {
      _bloc.add(AddCommentRequested(
        imageId: component.imageId,
        text: textVal,
        fanzineId: component.fanzineId,
        fanzineTitle: _fanzineTitle.isNotEmpty ? _fanzineTitle : component.fanzineTitle,
        displayName: profile?.displayName,
        username: profile?.username,
      ));
      if (mounted) {
        setState(() {
          _newCommentText = "";
        });
      }
    });
  }

  Component _buildHeaderBar() {
    return div(
      attributes: const {
        'style':
        'display: flex; justify-content: space-between; align-items: center; width: 100%; margin-bottom: 12px; border-bottom: 1px solid #f0f0f0; padding-bottom: 8px;'
      },
      [
        span(
          [Component.text('COMMENTS')],
          attributes: const {
            'style':
            'font-size: 11px; font-weight: bold; color: #475569; letter-spacing: 0.8px; text-transform: uppercase;'
          },
        ),
        if (_isCurator)
          SegmentedButton<String>(
            segments: const ['reader', 'curator'],
            selected: _viewMode,
            labelBuilder: (m) => m,
            showSelectedCheckmark: true,
            onSelectionChanged: (m) {
              setState(() {
                _viewMode = m;
                if (m == 'curator') {
                  if (_letterDate.isEmpty && _fanzinePublishedDate.isNotEmpty) {
                    _letterDate = _fanzinePublishedDate;
                  }
                  if (_authorLocation.isEmpty && _authorHandle.isNotEmpty) {
                    _checkAuthorHandle(_authorHandle);
                  }
                }
              });
            },
          ),
      ],
    );
  }

  Component _buildCuratorView(List<Map<String, dynamic>> comments) {
    final letters = comments.where((c) => c['sourceType'] == 'letter_column').toList();
    return div(
      classes: 'flex-col gap-3',
      attributes: const {'style': 'display: flex; flex-direction: column; gap: 12px; width: 100%;'},
      [
        div(
          attributes: const {
            'style':
            'background-color: #fcfcfc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 14px; display: flex; flex-direction: column; gap: 10px; width: 100%; box-sizing: border-box;'
          },
          [
            div(
              attributes: const {
                'style': 'display: flex; justify-content: space-between; align-items: center;'
              },
              [
                span(
                  [Component.text('TRANSCRIBE LETTER COLUMN ENTRY')],
                  attributes: const {
                    'style':
                    'font-size: 11px; font-weight: bold; color: #6750A4; text-transform: uppercase; letter-spacing: 0.5px;'
                  },
                ),
                span(
                  [Component.text('links letter to commenter index')],
                  attributes: const {'style': 'font-size: 10px; color: #888; font-style: italic;'},
                ),
              ],
            ),
            div(
              attributes: const {
                'style': 'display: flex; gap: 8px; width: 100%; flex-wrap: wrap;'
              },
              [
                div(
                  attributes: const {'style': 'flex: 2; min-width: 140px;'},
                  [
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'Letter writer name (e.g. Wesley A. Kauder)',
                        'value': _authorName,
                        'style':
                        'width: 100%; padding: 8px 10px; border: 1px solid #ccc; border-radius: 6px; font-size: 12px; background: white; outline: none; box-sizing: border-box; margin: 0;'
                      },
                      events: {
                        'input': (e) {
                          setState(() {
                            _onAuthorNameChanged(getInputValue(e));
                          });
                        }
                      },
                    )
                  ],
                ),
                div(
                  attributes: const {'style': 'flex: 1.5; min-width: 120px;'},
                  [
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': '@handle',
                        'value': _authorHandle,
                        'style':
                        'width: 100%; padding: 8px 10px; border: 1px solid #ccc; border-radius: 6px; font-size: 12px; background: white; outline: none; box-sizing: border-box; margin: 0; font-family: monospace;'
                      },
                      events: {
                        'input': (e) {
                          final h = getInputValue(e);
                          setState(() {
                            _authorHandle = h;
                            _checkAuthorHandle(normalizeHandle(h));
                          });
                        }
                      },
                    )
                  ],
                ),
              ],
            ),
            div(
              attributes: const {
                'style': 'display: flex; gap: 8px; width: 100%; flex-wrap: wrap;'
              },
              [
                div(
                  attributes: const {'style': 'flex: 2; min-width: 140px; position: relative;'},
                  [
                    div(
                      attributes: const {
                        'style': 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 2px;'
                      },
                      [
                        div(
                          attributes: const {'style': 'display: flex; align-items: center; gap: 4px;'},
                          [
                            span([Component.text('location:')], attributes: const {'style': 'font-size: 9px; color: #666; font-weight: bold;'}),
                            if (_authorGeo != null)
                              span(
                                [
                                  span([Component.text('pin_drop')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 10px; vertical-align: middle; margin-right: 1px;'}),
                                  Component.text('${_authorGeo!['lat']?.toStringAsFixed(4)}, ${_authorGeo!['lng']?.toStringAsFixed(4)}'),
                                ],
                                attributes: const {
                                  'style': 'font-size: 9px; font-weight: bold; color: #16a34a; font-family: monospace; background: #ecfdf5; padding: 1px 4px; border-radius: 4px; border: 1px solid #bbf7d0; display: inline-flex; align-items: center;'
                                },
                              ),
                          ],
                        ),
                        button(
                          [
                            span([Component.text('refresh')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 11px; margin-right: 2px; vertical-align: middle;'}),
                            Component.text(_isLookingUpAuthor ? 'pulling...' : 'refresh from profile'),
                          ],
                          attributes: const {
                            'type': 'button',
                            'title': 'Re-pull location and coordinates from author profile',
                            'style': 'border: none; background: transparent; color: #6750A4; font-size: 9px; font-weight: bold; cursor: pointer; padding: 0; text-decoration: underline;'
                          },
                          events: {'click': (e) => _manualRefreshLocation()},
                        ),
                      ],
                    ),
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'Location (e.g. Jamestown, N. D.)',
                        'value': _authorLocation,
                        'style':
                        'width: 100%; padding: 8px 10px; border: 1px solid #ccc; border-radius: 6px; font-size: 12px; background: white; outline: none; box-sizing: border-box; margin: 0;'
                      },
                      events: {
                        'input': (e) {
                          final newLoc = getInputValue(e);
                          setState(() {
                            _authorLocation = newLoc;
                            if (_authorGeo != null) {
                              final geoLoc = _authorGeo!['formatted'] ?? _authorGeo!['city'] ?? '';
                              if (newLoc.trim().toLowerCase() != geoLoc.toString().trim().toLowerCase()) {
                                _authorGeo = null;
                              }
                            }
                          });
                        }
                      },
                    )
                  ],
                ),
                div(
                  attributes: const {'style': 'flex: 1.5; min-width: 120px;'},
                  [
                    div(
                      attributes: const {'style': 'margin-bottom: 2px;'},
                      [
                        span([Component.text('historical date:')], attributes: const {'style': 'font-size: 9px; color: #666; font-weight: bold;'}),
                      ],
                    ),
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'Historical date (e.g. March 1927)',
                        'value': _letterDate,
                        'style':
                        'width: 100%; padding: 8px 10px; border: 1px solid #ccc; border-radius: 6px; font-size: 12px; background: white; outline: none; box-sizing: border-box; margin: 0;'
                      },
                      events: {
                        'input': (e) => setState(() => _letterDate = getInputValue(e))
                      },
                    )
                  ],
                ),
              ],
            ),
            if (_authorName.trim().isNotEmpty && !_profileFound)
              div(
                attributes: const {
                  'style':
                  'background: #fff8e1; border: 1px solid #ffe082; border-radius: 6px; padding: 8px 12px; display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 8px;'
                },
                [
                  span(
                    [Component.text('No profile exists yet for @$_authorHandle')],
                    attributes: const {'style': 'font-size: 11px; color: #856404; font-weight: 500;'},
                  ),
                  button(
                    [
                      span([Component.text('person_add')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px; margin-right: 4px;'}),
                      Component.text(_isCreatingProfile ? 'creating...' : 'create managed profile')
                    ],
                    classes: 'profile-btn',
                    attributes: {
                      'type': 'button',
                      'style':
                      'padding: 4px 10px; font-size: 10px; font-weight: bold; background: #6750A4; color: white; border: none; border-radius: 4px; cursor: pointer; display: inline-flex; align-items: center;',
                      if (_isCreatingProfile) 'disabled': 'true',
                    },
                    events: {'click': (e) => _createManagedProfileForAuthor()},
                  ),
                ],
              ),
            textarea(
              classes: 'border border-gray-300 rounded-md',
              attributes: {
                'placeholder': 'Type or paste letter content from the scan...',
                'style':
                'width: 100%; min-height: 90px; padding: 8px 10px; font-size: 13px; font-family: inherit; line-height: 1.5; border: 1px solid #ccc; border-radius: 6px; box-sizing: border-box; outline: none; background: white; margin: 0;',
              },
              events: {
                'input': (e) => setState(() => _letterText = getInputValue(e))
              },
              [Component.text(_letterText)],
            ),
            div(
              attributes: const {
                'style': 'display: flex; justify-content: space-between; align-items: center; width: 100%;'
              },
              [
                if (_curatorFeedback != null)
                  span(
                    [Component.text(_curatorFeedback!)],
                    attributes: {
                      'style':
                      'font-size: 11px; font-weight: bold; color: ${_isCuratorError ? "#ef4444" : "#16a34a"};'
                    },
                  )
                else
                  span([], attributes: const {'style': 'display: inline-block;'}),
                button(
                  [
                    span([Component.text('post_add')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px; margin-right: 4px;'}),
                    Component.text('save letter as comment')
                  ],
                  classes: 'btn-primary nav-pill mb-0',
                  attributes: const {
                    'type': 'button',
                    'style':
                    'padding: 8px 16px; font-size: 11px; font-weight: bold; background-color: #6750A4; color: white; border: none; border-radius: 50px; cursor: pointer; display: inline-flex; align-items: center;'
                  },
                  events: {'click': (e) => _transcribeLetter()},
                ),
              ],
            ),
          ],
        ),
        if (letters.isNotEmpty) ...[
          div(
            attributes: const {
              'style':
              'font-size: 11px; font-weight: bold; color: #666; text-transform: uppercase; letter-spacing: 0.5px; margin-top: 8px;'
            },
            [Component.text('Transcribed Letters on This Page (${letters.length})')],
          ),
          for (var comment in letters)
            CommentItem(
              data: comment,
              isCuratorMode: true,
              fanzinePublishedDate: _fanzinePublishedDate,
              key: ValueKey('curator_letter_${comment['_id']}'),
            ),
        ] else
          div(
            [Component.text('No archival letters transcribed on this page yet.')],
            classes: 'p-4 text-center text-gray text-xs italic',
          ),
      ],
    );
  }

  Component _buildReaderView(List<Map<String, dynamic>> comments, bool isLoading) {
    return div(
      classes: 'flex-col',
      attributes: const {'style': 'display: flex; flex-direction: column; width: 100%;'},
      [
        if (isLoading)
          div(
            [
              div([], classes: 'w-8 h-8 rounded-full shimmer-bg flex-shrink-0', attributes: const {'style': 'width: 32px; height: 32px; border-radius: 50%;'}),
              div([], classes: 'skeleton-line medium shimmer-bg', attributes: const {'style': 'height: 12px; border-radius: 4px; width: 85%;'}),
            ],
            classes: 'flex-row gap-3 py-4 border-b border-gray-100 items-start',
            attributes: const {'style': 'display: flex; gap: 12px; align-items: flex-start;'},
          )
        else if (comments.isEmpty)
          div(
            [Component.text('No thoughts shared yet.')],
            classes: 'p-8 text-center text-gray text-sm italic',
          )
        else
          for (var comment in comments)
            CommentItem(data: comment, key: ValueKey(comment['_id'] ?? '')),
        div(
          [
            div(
              [
                input(
                  attributes: {
                    'placeholder': 'Add a thought...',
                    'value': _newCommentText,
                    'style': 'width: 100%; box-sizing: border-box; margin: 0; padding: 8px; border: 1px solid #ccc; border-radius: 4px; font-size: 14px;'
                  },
                  classes: 'w-full p-2 border border-gray-200 rounded-md text-sm',
                  events: {
                    'input': (e) => _newCommentText = getInputValue(e),
                    'click': (e) {
                      if (getCurrentUserId() == null) {
                        GlobalModalBus.show();
                      }
                    }
                  },
                ),
              ],
              classes: 'flex-1',
              attributes: const {'style': 'flex: 1;'},
            ),
            button(
              [span([Component.text('send')], classes: 'material-symbols-outlined text-sm')],
              classes: 'nav-pill mb-0',
              attributes: const {
                'style':
                'margin-bottom: 0; height: 32px; display: inline-flex; align-items: center; justify-content: center; border-radius: 16px; padding: 0 16px; border: 1px solid #ccc; cursor: pointer; background: white;'
              },
              events: {'click': (e) => _submitReaderComment()},
            )
          ],
          classes: 'flex-row gap-2 mt-4 p-2 bg-gray-50 rounded-lg items-center',
          attributes: const {
            'style': 'display: flex; flex-direction: row; gap: 8px; align-items: center; margin-top: 16px; padding: 8px; background-color: #f9f9f9; border-radius: 8px;'
          },
        )
      ],
    );
  }

  @override
  Component build(BuildContext context) {
    final comments = _blocState.comments;
    final isLoading = _blocState.isLoadingComments;
    return div(
      classes: 'flex-col',
      attributes: const {'style': 'display: flex; flex-direction: column; width: 100%;'},
      [
        _buildHeaderBar(),
        if (_viewMode == 'curator')
          _buildCuratorView(comments)
        else
          _buildReaderView(comments, isLoading),
      ],
    );
  }
}

/// Dedicated desktop 3rd column (bonusColumn) comments panel.
/// Embeds the M3 single-select mode switcher and full letters workstation for curators.
class CommentsColumnPanel extends StatefulComponent {
  final String imageId;
  final String? fanzineId;
  final String? fanzineTitle;
  final String? fanzinePublishedDate;

  const CommentsColumnPanel({
    required this.imageId,
    this.fanzineId,
    this.fanzineTitle,
    this.fanzinePublishedDate,
    super.key,
  });

  @override
  State<CommentsColumnPanel> createState() => _CommentsColumnPanelState();
}

class _CommentsColumnPanelState extends State<CommentsColumnPanel> {
  late final InteractionBloc _bloc;
  StreamSubscription? _blocSub;
  InteractionState _blocState = const InteractionState();

  String _viewMode = 'reader';
  bool _isCurator = false;

  String _fanzineTitle = '';
  String _fanzinePublishedDate = '';

  String _newCommentText = "";

  // Curator letters transcriber fields
  String _authorName = "";
  String _authorHandle = "";
  String _authorLocation = "";
  Map<String, dynamic>? _authorGeo; // Stores pulled coordinates
  String _letterText = "";
  String _letterDate = "";

  bool _profileFound = false;
  String? _resolvedAuthorUid;
  bool _isCreatingProfile = false;
  bool _isLookingUpAuthor = false;
  String? _curatorFeedback;
  bool _isCuratorError = false;

  @override
  void initState() {
    super.initState();
    _fanzineTitle = component.fanzineTitle ?? '';
    _fanzinePublishedDate = component.fanzinePublishedDate ?? '';
    if (_letterDate.isEmpty && _fanzinePublishedDate.isNotEmpty) {
      _letterDate = _fanzinePublishedDate;
    }
    _bloc = InteractionBloc(repository: createEngagementRepository());
    _bloc.add(LoadCommentsRequested(component.imageId));
    _blocSub = _bloc.stream.listen((state) {
      if (mounted) {
        setState(() {
          _blocState = state;
        });
      }
    });
    if (kIsWeb) {
      _fetchFanzineDataAndPermissions();
    }
  }

  @override
  void didUpdateComponent(CommentsColumnPanel oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.imageId != component.imageId) {
      _bloc.add(LoadCommentsRequested(component.imageId));
      if (kIsWeb) {
        _fetchFanzineDataAndPermissions();
      }
    }
    if (oldComponent.fanzinePublishedDate != component.fanzinePublishedDate &&
        component.fanzinePublishedDate != null) {
      _fanzinePublishedDate = component.fanzinePublishedDate!;
      if (_letterDate.isEmpty) {
        _letterDate = _fanzinePublishedDate;
      }
    }
  }

  @override
  void dispose() {
    _blocSub?.cancel();
    _bloc.close();
    super.dispose();
  }

  Future<void> _fetchFanzineDataAndPermissions() async {
    final uid = getCurrentUserId();
    bool hasAccess = false;
    final fzId = component.fanzineId;

    String? pubDate;
    String? pubMode;
    bool pubGuess = false;
    String? fzTitle;

    if (fzId != null && fzId.isNotEmpty) {
      if (UnsavedFanzineRegistry.fanzines.containsKey(fzId)) {
        final fz = UnsavedFanzineRegistry.fanzines[fzId]!;
        pubDate = fz.publishedDate;
        pubMode = fz.publishedDateMode;
        pubGuess = fz.publishedDateGuess;
        fzTitle = fz.title;
        if (uid != null && (fz.curators.contains(uid) || fz.ownerId == uid || fz.editors.contains(uid))) {
          hasAccess = true;
        }
      } else {
        try {
          final res = await fsGetDoc('fanzines/$fzId');
          final decoded = jsonDecode(res);
          if (decoded['exists'] == true) {
            final data = decoded['data'] as Map<String, dynamic>? ?? {};
            final List curators = data['curators'] ?? [];
            final List editors = data['editors'] ?? [];
            final String ownerId = data['ownerId'] ?? data['editorId'] ?? '';
            pubDate = data['publishedDate']?.toString();
            pubMode = data['publishedDateMode']?.toString();
            pubGuess = data['publishedDateGuess'] == true;
            fzTitle = data['title']?.toString();
            if (uid != null && (curators.contains(uid) || ownerId == uid || editors.contains(uid))) {
              hasAccess = true;
            }
          }
        } catch (_) {}
      }
    }

    if (!hasAccess && uid != null) {
      try {
        final profRes = await fsGetDoc('profiles/$uid');
        final profDoc = jsonDecode(profRes);
        if (profDoc['exists'] == true) {
          final pData = profDoc['data'] as Map<String, dynamic>? ?? {};
          if (pData['isCurator'] == true || pData['isAdmin'] == true) {
            hasAccess = true;
          }
        }
      } catch (_) {}
    }

    String formatted = '';
    if (pubDate != null && pubDate.isNotEmpty) {
      formatted = formatThumbnailDate(pubDate, pubMode, pubGuess);
      if (formatted.isEmpty) formatted = pubDate;
    }

    if (mounted) {
      setState(() {
        _isCurator = hasAccess;
        if (formatted.isNotEmpty) {
          _fanzinePublishedDate = formatted;
          if (_letterDate.isEmpty) {
            _letterDate = formatted;
          }
        }
        if (fzTitle != null && fzTitle.isNotEmpty && _fanzineTitle.isEmpty) {
          _fanzineTitle = fzTitle;
        }
      });
    }
  }

  void _onAuthorNameChanged(String val) {
    _authorName = val;
    final suggested = normalizeHandle(val);
    _authorHandle = suggested;
    _resolvedAuthorUid = null;
    _profileFound = false;
    _authorGeo = null;
    if (suggested.isNotEmpty) {
      _checkAuthorHandle(suggested);
    }
  }

  Future<void> _checkAuthorHandle(String handle) async {
    final cleanHandle = normalizeHandle(handle);
    if (cleanHandle.isEmpty) return;
    setState(() => _isLookingUpAuthor = true);
    try {
      final data = await lookupAuthorProfileData(username: cleanHandle);
      if (data.uid != null && data.uid!.isNotEmpty && mounted) {
        setState(() {
          _profileFound = true;
          _resolvedAuthorUid = data.uid;
          _isLookingUpAuthor = false;
          if (data.geo != null) {
            _authorGeo = data.geo;
          }
          if (_authorLocation.trim().isEmpty && data.location.isNotEmpty) {
            _authorLocation = data.location;
          }
          if (_authorName.trim().isEmpty && data.displayName != null && data.displayName!.isNotEmpty) {
            _authorName = data.displayName!;
          }
          final locDisplay = data.location.isNotEmpty ? data.location : (data.geo?['formatted'] ?? '');
          final coordDisplay = data.geo != null ? " [${data.geo!['lat']?.toStringAsFixed(2)}, ${data.geo!['lng']?.toStringAsFixed(2)}]" : "";
          _curatorFeedback = locDisplay.isNotEmpty
              ? "Profile linked: @$cleanHandle ($locDisplay)$coordDisplay"
              : "Profile linked: @$cleanHandle$coordDisplay";
          _isCuratorError = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _profileFound = false;
            _resolvedAuthorUid = null;
            _authorGeo = null;
            _isLookingUpAuthor = false;
            _curatorFeedback = null;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLookingUpAuthor = false);
    }
  }

  Future<void> _manualRefreshLocation() async {
    final handle = _authorHandle.isNotEmpty ? _authorHandle : _authorName;
    if (handle.trim().isEmpty) {
      setState(() {
        _curatorFeedback = "Enter a writer name or @handle first.";
        _isCuratorError = true;
      });
      return;
    }
    setState(() => _isLookingUpAuthor = true);
    final data = await lookupAuthorProfileData(uid: _resolvedAuthorUid, username: handle);
    if (mounted) {
      setState(() {
        _isLookingUpAuthor = false;
        if (data.geo != null) {
          _authorGeo = data.geo;
          if (data.location.isNotEmpty) {
            _authorLocation = data.location;
          }
          if (data.displayName != null && data.displayName!.isNotEmpty && _authorName.isEmpty) {
            _authorName = data.displayName!;
          }
          if (data.uid != null && data.uid!.isNotEmpty) {
            _resolvedAuthorUid = data.uid;
            _profileFound = true;
          }
          _curatorFeedback = "Coordinates pulled: ${_authorGeo!['lat']?.toStringAsFixed(4)}, ${_authorGeo!['lng']?.toStringAsFixed(4)} (${_authorLocation.isNotEmpty ? _authorLocation : _authorGeo!['formatted'] ?? ''})";
          _isCuratorError = false;
        } else if (data.location.isNotEmpty) {
          _authorLocation = data.location;
          if (data.displayName != null && data.displayName!.isNotEmpty && _authorName.isEmpty) {
            _authorName = data.displayName!;
          }
          if (data.uid != null && data.uid!.isNotEmpty) {
            _resolvedAuthorUid = data.uid;
            _profileFound = true;
          }
          _curatorFeedback = "Location pulled: ${data.location} (no coordinates saved on profile, will geocode on save)";
          _isCuratorError = false;
        } else {
          _curatorFeedback = "No location or coordinates found on profile for @${normalizeHandle(handle)}.";
          _isCuratorError = true;
        }
      });
    }
  }

  Future<void> _createManagedProfileForAuthor() async {
    final name = _authorName.trim();
    final handle = normalizeHandle(_authorHandle.isNotEmpty ? _authorHandle : name);
    if (name.isEmpty || handle.isEmpty) return;
    setState(() {
      _isCreatingProfile = true;
      _curatorFeedback = "Generating managed profile @$handle...";
      _isCuratorError = false;
    });
    try {
      final uid = getCurrentUserId() ?? 'system';
      final profileId = 'profile_managed_${handle}_${DateTime.now().millisecondsSinceEpoch}';
      String firstName = name;
      String lastName = "";
      if (name.contains(' ')) {
        final parts = name.split(' ');
        firstName = parts.first;
        lastName = parts.sublist(1).join(' ');
      }
      String city = '';
      String state = '';
      if (_authorLocation.contains(',')) {
        final lParts = _authorLocation.split(',');
        city = lParts[0].trim();
        state = lParts.sublist(1).join(',').trim();
      } else {
        city = _authorLocation.trim();
      }
      Map<String, dynamic>? initialGeo = _authorGeo;
      if (initialGeo == null && _authorLocation.trim().isNotEmpty) {
        initialGeo = await resolveGeoForLocation(_authorLocation.trim());
      }

      final profileData = {
        'uid': profileId,
        'username': handle,
        'displayName': name,
        'firstName': firstName,
        'lastName': lastName,
        'city': city,
        'state': state,
        'location': _authorLocation.trim(),
        if (initialGeo != null) 'geo': initialGeo,
        'photoUrl': '',
        'bio': _authorLocation.isNotEmpty
            ? 'Historical letter writer from $_authorLocation.'
            : 'Historical letter writer.',
        'isManaged': true,
        'isCurator': false,
        'isAdmin': false,
        'managers': [uid],
        'followerCount': 0,
        'followingCount': 0,
        'createdAt': WebFieldValue.serverTimestamp(),
        'updatedAt': WebFieldValue.serverTimestamp(),
      };
      await fsSetDoc('profiles/$profileId', jsonEncode(profileData), true);
      await fsSetDoc('usernames/$handle', jsonEncode({
        'uid': profileId,
        'isManaged': true,
        'createdAt': WebFieldValue.serverTimestamp(),
      }), true);
      await fsSetDoc('shortcodes/${handle.toUpperCase()}', jsonEncode({
        'type': 'user',
        'contentId': profileId,
        'displayCode': handle,
        'createdAt': WebFieldValue.serverTimestamp(),
      }), true);
      if (mounted) {
        setState(() {
          _isCreatingProfile = false;
          _profileFound = true;
          _resolvedAuthorUid = profileId;
          _authorGeo = initialGeo;
          _curatorFeedback = initialGeo != null
              ? "Managed profile @$handle created with coordinates!"
              : "Managed profile @$handle created and linked!";
          _isCuratorError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCreatingProfile = false;
          _curatorFeedback = "Failed to create profile: $e";
          _isCuratorError = true;
        });
      }
    }
  }

  Future<void> _transcribeLetter() async {
    final text = _letterText.trim();
    if (text.isEmpty) {
      setState(() {
        _curatorFeedback = "Please enter the letter text.";
        _isCuratorError = true;
      });
      return;
    }
    final authorName = _authorName.trim().isNotEmpty ? _authorName.trim() : 'Anonymous Reader';
    final handle = _authorHandle.trim().isNotEmpty ? normalizeHandle(_authorHandle) : 'reader';
    final authorUid = _resolvedAuthorUid ?? 'archival_${DateTime.now().millisecondsSinceEpoch}';

    setState(() {
      _curatorFeedback = "Committing archival letter...";
      _isCuratorError = false;
    });

    try {
      Map<String, dynamic>? geoData = _authorGeo;
      if (geoData == null && _authorLocation.trim().isNotEmpty) {
        geoData = await resolveGeoForLocation(_authorLocation.trim());
      }

      final commentDoc = {
        'contentId': component.imageId,
        'userId': authorUid,
        'displayName': authorName,
        'username': handle,
        'location': _authorLocation.trim(),
        if (geoData != null) 'geo': geoData,
        'historicalDate': _letterDate.trim(),
        'text': text,
        'sourceType': 'letter_column',
        'createdAt': WebFieldValue.serverTimestamp(),
        'likeCount': 0,
        'context': {
          'fanzineId': component.fanzineId,
          'fanzineTitle': _fanzineTitle.isNotEmpty ? _fanzineTitle : component.fanzineTitle,
        }
      };

      await fsAddDoc('artifacts/bqopd/public/data/comments', jsonEncode(commentDoc));
      if (component.imageId.isNotEmpty) {
        await fsUpdateDoc('images/${component.imageId}', jsonEncode({
          'commentCount': WebFieldValue.increment(1),
        })).catchError((_) => null);
      }

      if (component.fanzineId != null && component.fanzineId!.isNotEmpty && authorName.isNotEmpty) {
        await fsUpdateDoc('fanzines/${component.fanzineId}', jsonEncode({
          'draftEntities': WebFieldValue.arrayUnion([authorName]),
        })).catchError((_) => null);
      }

      if (mounted) {
        setState(() {
          _letterText = "";
          _authorName = "";
          _authorHandle = "";
          _authorLocation = "";
          _authorGeo = null;
          _letterDate = _fanzinePublishedDate;
          _curatorFeedback = "Letter transcribed and linked to @$handle!";
          _isCuratorError = false;
          _profileFound = false;
          _resolvedAuthorUid = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _curatorFeedback = "Error submitting letter: $e";
          _isCuratorError = true;
        });
      }
    }
  }

  void _submitReaderComment() {
    final textVal = _newCommentText.trim();
    if (textVal.isEmpty) return;
    final uid = getCurrentUserId();
    if (uid == null) {
      GlobalModalBus.show();
      return;
    }
    createUserRepository().watchUser(uid).first.then((profile) {
      _bloc.add(AddCommentRequested(
        imageId: component.imageId,
        text: textVal,
        fanzineId: component.fanzineId,
        fanzineTitle: _fanzineTitle.isNotEmpty ? _fanzineTitle : component.fanzineTitle,
        displayName: profile?.displayName,
        username: profile?.username,
      ));
      if (mounted) {
        setState(() {
          _newCommentText = "";
        });
      }
    });
  }

  Component _buildHeaderBar() {
    return div(
      attributes: const {
        'style':
        'display: flex; justify-content: space-between; align-items: center; width: 100%; margin-bottom: 12px; border-bottom: 1px solid #e2e8f0; padding-bottom: 8px;'
      },
      [
        span(
          [Component.text('COMMENTS')],
          attributes: const {
            'style':
            'font-size: 11px; font-weight: bold; color: #475569; letter-spacing: 0.8px; text-transform: uppercase;'
          },
        ),
        if (_isCurator)
          SegmentedButton<String>(
            segments: const ['reader', 'curator'],
            selected: _viewMode,
            labelBuilder: (m) => m,
            showSelectedCheckmark: true,
            onSelectionChanged: (m) {
              setState(() {
                _viewMode = m;
                if (m == 'curator') {
                  if (_letterDate.isEmpty && _fanzinePublishedDate.isNotEmpty) {
                    _letterDate = _fanzinePublishedDate;
                  }
                  if (_authorLocation.isEmpty && _authorHandle.isNotEmpty) {
                    _checkAuthorHandle(_authorHandle);
                  }
                }
              });
            },
          ),
      ],
    );
  }

  Component _buildCuratorView(List<Map<String, dynamic>> comments) {
    final letters = comments.where((c) => c['sourceType'] == 'letter_column').toList();
    return div(
      classes: 'flex-col gap-3',
      attributes: const {'style': 'display: flex; flex-direction: column; gap: 14px; width: 100%;'},
      [
        div(
          attributes: const {
            'style':
            'background-color: #f8fafc; border: 1px solid #cbd5e1; border-radius: 8px; padding: 16px; display: flex; flex-direction: column; gap: 12px; width: 100%; box-sizing: border-box;'
          },
          [
            div(
              attributes: const {
                'style': 'display: flex; justify-content: space-between; align-items: center;'
              },
              [
                span(
                  [Component.text('TRANSCRIBE LETTER COLUMN ENTRY')],
                  attributes: const {
                    'style':
                    'font-size: 11px; font-weight: bold; color: #6750A4; text-transform: uppercase; letter-spacing: 0.5px;'
                  },
                ),
                span(
                  [Component.text('curator archival workbench')],
                  attributes: const {'style': 'font-size: 10px; color: #64748b; font-style: italic;'},
                ),
              ],
            ),
            div(
              attributes: const {
                'style': 'display: flex; gap: 10px; width: 100%;'
              },
              [
                div(
                  attributes: const {'style': 'flex: 2;'},
                  [
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'Letter writer name (e.g. Wesley A. Kauder)',
                        'value': _authorName,
                        'style':
                        'width: 100%; padding: 8px 12px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; outline: none; box-sizing: border-box;'
                      },
                      events: {
                        'input': (e) {
                          setState(() {
                            _onAuthorNameChanged(getInputValue(e));
                          });
                        }
                      },
                    )
                  ],
                ),
                div(
                  attributes: const {'style': 'flex: 1.5;'},
                  [
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': '@handle',
                        'value': _authorHandle,
                        'style':
                        'width: 100%; padding: 8px 12px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; outline: none; box-sizing: border-box; font-family: monospace;'
                      },
                      events: {
                        'input': (e) {
                          final h = getInputValue(e);
                          setState(() {
                            _authorHandle = h;
                            _checkAuthorHandle(normalizeHandle(h));
                          });
                        }
                      },
                    )
                  ],
                ),
              ],
            ),
            div(
              attributes: const {
                'style': 'display: flex; gap: 10px; width: 100%; flex-wrap: wrap;'
              },
              [
                div(
                  attributes: const {'style': 'flex: 2; min-width: 140px; position: relative;'},
                  [
                    div(
                      attributes: const {
                        'style': 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 2px;'
                      },
                      [
                        div(
                          attributes: const {'style': 'display: flex; align-items: center; gap: 4px;'},
                          [
                            span([Component.text('location:')], attributes: const {'style': 'font-size: 9px; color: #666; font-weight: bold;'}),
                            if (_authorGeo != null)
                              span(
                                [
                                  span([Component.text('pin_drop')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 10px; vertical-align: middle; margin-right: 1px;'}),
                                  Component.text('${_authorGeo!['lat']?.toStringAsFixed(4)}, ${_authorGeo!['lng']?.toStringAsFixed(4)}'),
                                ],
                                attributes: const {
                                  'style': 'font-size: 9px; font-weight: bold; color: #16a34a; font-family: monospace; background: #ecfdf5; padding: 1px 4px; border-radius: 4px; border: 1px solid #bbf7d0; display: inline-flex; align-items: center;'
                                },
                              ),
                          ],
                        ),
                        button(
                          [
                            span([Component.text('refresh')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 11px; margin-right: 2px; vertical-align: middle;'}),
                            Component.text(_isLookingUpAuthor ? 'pulling...' : 'refresh from profile'),
                          ],
                          attributes: const {
                            'type': 'button',
                            'title': 'Re-pull location and coordinates from author profile',
                            'style': 'border: none; background: transparent; color: #6750A4; font-size: 9px; font-weight: bold; cursor: pointer; padding: 0; text-decoration: underline;'
                          },
                          events: {'click': (e) => _manualRefreshLocation()},
                        ),
                      ],
                    ),
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'Location (e.g. Jamestown, N. D.)',
                        'value': _authorLocation,
                        'style':
                        'width: 100%; padding: 8px 12px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; outline: none; box-sizing: border-box;'
                      },
                      events: {
                        'input': (e) {
                          final newLoc = getInputValue(e);
                          setState(() {
                            _authorLocation = newLoc;
                            if (_authorGeo != null) {
                              final geoLoc = _authorGeo!['formatted'] ?? _authorGeo!['city'] ?? '';
                              if (newLoc.trim().toLowerCase() != geoLoc.toString().trim().toLowerCase()) {
                                _authorGeo = null;
                              }
                            }
                          });
                        }
                      },
                    )
                  ],
                ),
                div(
                  attributes: const {'style': 'flex: 1.5; min-width: 120px;'},
                  [
                    div(
                      attributes: const {'style': 'margin-bottom: 2px;'},
                      [
                        span([Component.text('historical date:')], attributes: const {'style': 'font-size: 9px; color: #666; font-weight: bold;'}),
                      ],
                    ),
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'Historical date (e.g. March 1927)',
                        'value': _letterDate,
                        'style':
                        'width: 100%; padding: 8px 12px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; outline: none; box-sizing: border-box;'
                      },
                      events: {
                        'input': (e) => setState(() => _letterDate = getInputValue(e))
                      },
                    )
                  ],
                ),
              ],
            ),
            if (_authorName.trim().isNotEmpty && !_profileFound)
              div(
                attributes: const {
                  'style':
                  'background: #fff8e1; border: 1px solid #ffe082; border-radius: 6px; padding: 8px 12px; display: flex; justify-content: space-between; align-items: center;'
                },
                [
                  span(
                    [Component.text('No managed profile for @$_authorHandle')],
                    attributes: const {'style': 'font-size: 11px; color: #856404; font-weight: 500;'},
                  ),
                  button(
                    [
                      span([Component.text('person_add')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px; margin-right: 4px;'}),
                      Component.text(_isCreatingProfile ? 'creating...' : 'create managed profile')
                    ],
                    classes: 'profile-btn',
                    attributes: {
                      'type': 'button',
                      'style':
                      'padding: 4px 12px; font-size: 10px; font-weight: bold; background: #6750A4; color: white; border: none; border-radius: 4px; cursor: pointer; display: inline-flex; align-items: center;',
                      if (_isCreatingProfile) 'disabled': 'true',
                    },
                    events: {'click': (e) => _createManagedProfileForAuthor()},
                  ),
                ],
              ),
            textarea(
              classes: 'border border-gray-300 rounded-md',
              attributes: {
                'placeholder': 'Type or paste letter content from the scan...',
                'style':
                'width: 100%; min-height: 100px; padding: 10px; font-size: 13px; font-family: inherit; line-height: 1.5; border: 1px solid #cbd5e1; border-radius: 6px; box-sizing: border-box; outline: none; background: white;',
              },
              events: {
                'input': (e) => setState(() => _letterText = getInputValue(e))
              },
              [Component.text(_letterText)],
            ),
            div(
              attributes: const {
                'style': 'display: flex; justify-content: space-between; align-items: center; width: 100%;'
              },
              [
                if (_curatorFeedback != null)
                  span(
                    [Component.text(_curatorFeedback!)],
                    attributes: {
                      'style':
                      'font-size: 11px; font-weight: bold; color: ${_isCuratorError ? "#ef4444" : "#16a34a"};'
                    },
                  )
                else
                  span([], attributes: const {'style': 'display: inline-block;'}),
                button(
                  [
                    span([Component.text('post_add')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px; margin-right: 4px;'}),
                    Component.text('save letter as comment')
                  ],
                  classes: 'btn-primary nav-pill mb-0',
                  attributes: const {
                    'type': 'button',
                    'style':
                    'padding: 8px 18px; font-size: 11px; font-weight: bold; background-color: #6750A4; color: white; border: none; border-radius: 50px; cursor: pointer; display: inline-flex; align-items: center;'
                  },
                  events: {'click': (e) => _transcribeLetter()},
                ),
              ],
            ),
          ],
        ),
        if (letters.isNotEmpty) ...[
          div(
            attributes: const {
              'style':
              'font-size: 11px; font-weight: bold; color: #64748b; text-transform: uppercase; letter-spacing: 0.5px; margin-top: 8px;'
            },
            [Component.text('Transcribed Letters on This Page (${letters.length})')],
          ),
          for (var comment in letters)
            CommentItem(
              data: comment,
              isCuratorMode: true,
              fanzinePublishedDate: _fanzinePublishedDate,
              key: ValueKey('curator_col_letter_${comment['_id']}'),
            ),
        ] else
          div(
            [Component.text('No archival letters transcribed on this page yet.')],
            classes: 'p-4 text-center text-gray text-xs italic',
          ),
      ],
    );
  }

  Component _buildReaderView(List<Map<String, dynamic>> comments, bool isLoading) {
    return div(
      classes: 'flex-col',
      attributes: const {'style': 'display: flex; flex-direction: column; width: 100%;'},
      [
        if (isLoading)
          div(
            [
              div([], classes: 'w-8 h-8 rounded-full shimmer-bg flex-shrink-0', attributes: const {'style': 'width: 32px; height: 32px; border-radius: 50%;'}),
              div([], classes: 'skeleton-line medium shimmer-bg', attributes: const {'style': 'height: 12px; border-radius: 4px; width: 85%;'}),
            ],
            classes: 'flex-row gap-3 py-4 border-b border-gray-100 items-start',
            attributes: const {'style': 'display: flex; gap: 12px; align-items: flex-start;'},
          )
        else if (comments.isEmpty)
          div(
            [Component.text('No comments posted for this page.')],
            classes: 'p-6 text-center text-gray text-xs italic',
          )
        else
          for (var comment in comments)
            CommentItem(data: comment, key: ValueKey(comment['_id'] ?? '')),
        div(
          [
            div(
              [
                input(
                  attributes: {
                    'placeholder': 'Add a thought...',
                    'value': _newCommentText,
                    'style': 'width: 100%; box-sizing: border-box; margin: 0; padding: 8px 12px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 13px;'
                  },
                  classes: 'w-full p-2 border border-gray-200 rounded-md text-sm',
                  events: {
                    'input': (e) => _newCommentText = getInputValue(e),
                    'click': (e) {
                      if (getCurrentUserId() == null) {
                        GlobalModalBus.show();
                      }
                    }
                  },
                ),
              ],
              classes: 'flex-1',
              attributes: const {'style': 'flex: 1;'},
            ),
            button(
              [span([Component.text('send')], classes: 'material-symbols-outlined text-sm')],
              classes: 'nav-pill mb-0',
              attributes: const {
                'style':
                'margin-bottom: 0; height: 34px; display: inline-flex; align-items: center; justify-content: center; border-radius: 6px; padding: 0 14px; border: 1px solid #cbd5e1; cursor: pointer; background: white;'
              },
              events: {'click': (e) => _submitReaderComment()},
            )
          ],
          classes: 'flex-row gap-2 mt-4 p-2 bg-gray-50 rounded-lg items-center',
          attributes: const {
            'style': 'display: flex; flex-direction: row; gap: 8px; align-items: center; margin-top: 14px; padding: 8px; background-color: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0;'
          },
        )
      ],
    );
  }

  @override
  Component build(BuildContext context) {
    final comments = _blocState.comments;
    final isLoading = _blocState.isLoadingComments;
    return div(
      classes: 'flex-col',
      attributes: const {'style': 'display: flex; flex-direction: column; width: 100%;'},
      [
        _buildHeaderBar(),
        if (_viewMode == 'curator')
          _buildCuratorView(comments)
        else
          _buildReaderView(comments, isLoading),
      ],
    );
  }
}

typedef CommentsPanel = CommentsRowPanel;

class CommentItem extends StatefulComponent {
  final Map<String, dynamic> data;
  final bool isCuratorMode;
  final String? fanzinePublishedDate;
  final VoidCallback? onCommentUpdated;

  const CommentItem({
    required this.data,
    this.isCuratorMode = false,
    this.fanzinePublishedDate,
    this.onCommentUpdated,
    super.key,
  });

  @override
  State<CommentItem> createState() => _CommentItemState();
}

class _CommentItemState extends State<CommentItem> {
  UserProfile? _profile;
  bool _isLiked = false;
  StreamSubscription? _likeSub;

  // Inline Curator Editing State
  bool _isEditing = false;
  bool _isSaving = false;
  bool _refreshingLocation = false;
  String _editText = '';
  String _editLocation = '';
  Map<String, dynamic>? _editGeo; // Stores pulled coordinates for edited comment
  String _editHistoricalDate = '';
  String _editAuthorName = '';
  String _editAuthorHandle = '';
  String? _locationRefreshedMessage;

  final IUserRepository _userRepo = createUserRepository();
  final IEngagementRepository _engagementRepo = createEngagementRepository();

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _listenToLikes();
  }

  @override
  void dispose() {
    _likeSub?.cancel();
    super.dispose();
  }

  void _loadProfile() {
    final uid = component.data['userId'];
    if (uid == null) return;
    _userRepo.watchUser(uid).first.then((profile) {
      if (profile != null && mounted) {
        setState(() => _profile = profile);
      }
    });
  }

  void _listenToLikes() {
    final commentId = component.data['_id'];
    if (commentId == null) return;
    _likeSub?.cancel();
    _likeSub = _engagementRepo.isCommentLiked(commentId).listen((isLiked) {
      if (mounted) {
        setState(() => _isLiked = isLiked);
      }
    });
  }

  void _handleLike() {
    final commentId = component.data['_id'];
    if (getCurrentUserId() == null || commentId == null) {
      GlobalModalBus.show();
      return;
    }
    _engagementRepo.toggleCommentLike(commentId, _isLiked);
  }

  Future<void> _handleDelete() async {
    final commentId = component.data['_id'];
    final imageId = component.data['contentId'] ?? '';
    if (commentId == null) return;
    try {
      await fsDeleteDoc('artifacts/bqopd/public/data/comments/$commentId');
      if (imageId.isNotEmpty) {
        await fsUpdateDoc('images/$imageId', jsonEncode({
          'commentCount': WebFieldValue.increment(-1),
        })).catchError((_) => null);
      }
    } catch (e) {
      print("Error deleting comment: $e");
    }
  }

  /// Opens the comment for curator inspection/editing and automatically refreshes
  /// the location and coordinates from the writer's profile if it was previously empty.
  Future<void> _openAndRefreshLocation() async {
    _editText = component.data['text'] ?? '';
    _editAuthorName = component.data['displayName'] ?? '';
    _editAuthorHandle = component.data['username'] ?? '';
    _editHistoricalDate = component.data['historicalDate'] ?? '';
    _editLocation = component.data['location'] ?? '';
    _editGeo = component.data['geo'] is Map ? Map<String, dynamic>.from(component.data['geo']) : null;
    _locationRefreshedMessage = null;

    if (_editGeo == null || _editLocation.trim().isEmpty) {
      _refreshingLocation = true;
      setState(() => _isEditing = true);

      final uid = component.data['userId'];
      final username = component.data['username'];
      final pulled = await lookupAuthorProfileData(uid: uid, username: username);
      if (mounted) {
        setState(() {
          if (pulled.geo != null) {
            _editGeo = pulled.geo;
          }
          if (pulled.location.isNotEmpty) {
            _editLocation = pulled.location;
          }
          if (_editGeo != null) {
            _locationRefreshedMessage = 'Coordinates pulled: ${_editGeo!['lat']?.toStringAsFixed(4)}, ${_editGeo!['lng']?.toStringAsFixed(4)} (${_editLocation})';
          } else if (pulled.location.isNotEmpty) {
            _locationRefreshedMessage = 'Location pulled: ${pulled.location}';
          }
          _refreshingLocation = false;
        });
      }
    } else {
      setState(() => _isEditing = true);
    }

    if (_editHistoricalDate.trim().isEmpty &&
        component.fanzinePublishedDate != null &&
        component.fanzinePublishedDate!.isNotEmpty) {
      _editHistoricalDate = component.fanzinePublishedDate!;
    }

    if (mounted) setState(() {});
  }

  Future<void> _manualRefreshLocation() async {
    setState(() => _refreshingLocation = true);
    final uid = component.data['userId'];
    final username = _editAuthorHandle.isNotEmpty ? _editAuthorHandle : component.data['username'];
    final pulled = await lookupAuthorProfileData(uid: uid, username: handleOrUser(username));
    if (mounted) {
      setState(() {
        _refreshingLocation = false;
        if (pulled.geo != null) {
          _editGeo = pulled.geo;
          if (pulled.location.isNotEmpty) {
            _editLocation = pulled.location;
          }
          _locationRefreshedMessage = 'Coordinates pulled: ${_editGeo!['lat']?.toStringAsFixed(4)}, ${_editGeo!['lng']?.toStringAsFixed(4)} (${_editLocation})';
        } else if (pulled.location.isNotEmpty) {
          _editLocation = pulled.location;
          _locationRefreshedMessage = 'Location pulled: ${pulled.location} (no coordinates on profile)';
        } else {
          _locationRefreshedMessage = 'No location or coordinates on profile yet.';
        }
      });
    }
  }

  String handleOrUser(dynamic val) {
    return val?.toString() ?? '';
  }

  Future<void> _saveEditedComment() async {
    final commentId = component.data['_id'];
    if (commentId == null || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      Map<String, dynamic>? geoData = _editGeo;
      if (geoData == null && _editLocation.trim().isNotEmpty) {
        geoData = await resolveGeoForLocation(_editLocation.trim());
      }

      final updates = <String, dynamic>{
        'text': _editText.trim(),
        'location': _editLocation.trim(),
        if (geoData != null) 'geo': geoData,
        'historicalDate': _editHistoricalDate.trim(),
        'displayName': _editAuthorName.trim(),
        'username': normalizeHandle(_editAuthorHandle),
        'updatedAt': WebFieldValue.serverTimestamp(),
      };
      await fsUpdateDoc('artifacts/bqopd/public/data/comments/$commentId', jsonEncode(updates));

      // Synchronize in-memory record so UI reflects changes instantly
      component.data['text'] = _editText.trim();
      component.data['location'] = _editLocation.trim();
      if (geoData != null) component.data['geo'] = geoData;
      component.data['historicalDate'] = _editHistoricalDate.trim();
      component.data['displayName'] = _editAuthorName.trim();
      component.data['username'] = normalizeHandle(_editAuthorHandle);

      if (mounted) {
        setState(() {
          _isEditing = false;
          _isSaving = false;
          _locationRefreshedMessage = null;
        });
      }
      if (component.onCommentUpdated != null) {
        component.onCommentUpdated!();
      }
    } catch (e) {
      print("Error saving edited comment: $e");
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Component build(BuildContext context) {
    if (_isEditing) {
      return div(
        classes: 'flex-col gap-2 py-3 border-b border-gray-200',
        attributes: const {
          'style':
          'display: flex; flex-direction: column; gap: 10px; padding: 12px; background: #fafafa; border: 1px solid #e2e8f0; border-radius: 8px; margin-bottom: 8px; box-sizing: border-box; width: 100%;'
        },
        [
          div(
            attributes: const {'style': 'display: flex; justify-content: space-between; align-items: center;'},
            [
              span(
                [Component.text('EDIT TRANSCRIBED LETTER')],
                attributes: const {
                  'style':
                  'font-size: 10px; font-weight: bold; color: #6750A4; text-transform: uppercase; letter-spacing: 0.5px;'
                },
              ),
              button(
                [span([Component.text('close')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px;'})],
                attributes: const {
                  'type': 'button',
                  'style': 'border: none; background: transparent; cursor: pointer; color: #888; padding: 2px;'
                },
                events: {'click': (e) => setState(() => _isEditing = false)},
              ),
            ],
          ),
          div(
            attributes: const {'style': 'display: flex; gap: 8px; width: 100%; flex-wrap: wrap;'},
            [
              div(
                attributes: const {'style': 'flex: 2; min-width: 140px;'},
                [
                  span([Component.text('writer name:')], attributes: const {'style': 'font-size: 10px; color: #666; font-weight: bold; display: block; margin-bottom: 2px;'}),
                  input(
                    attributes: {
                      'type': 'text',
                      'value': _editAuthorName,
                      'style':
                      'width: 100%; padding: 6px 8px; border: 1px solid #ccc; border-radius: 4px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;'
                    },
                    events: {'input': (e) => _editAuthorName = getInputValue(e)},
                  ),
                ],
              ),
              div(
                attributes: const {'style': 'flex: 1.5; min-width: 120px;'},
                [
                  span([Component.text('@handle:')], attributes: const {'style': 'font-size: 10px; color: #666; font-weight: bold; display: block; margin-bottom: 2px;'}),
                  input(
                    attributes: {
                      'type': 'text',
                      'value': _editAuthorHandle,
                      'style':
                      'width: 100%; padding: 6px 8px; border: 1px solid #ccc; border-radius: 4px; font-size: 12px; background: white; font-family: monospace; box-sizing: border-box; margin: 0;'
                    },
                    events: {'input': (e) => _editAuthorHandle = getInputValue(e)},
                  ),
                ],
              ),
            ],
          ),
          div(
            attributes: const {'style': 'display: flex; gap: 8px; width: 100%; flex-wrap: wrap;'},
            [
              div(
                attributes: const {'style': 'flex: 2; min-width: 140px;'},
                [
                  div(
                    attributes: const {
                      'style': 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 2px;'
                    },
                    [
                      div(
                        attributes: const {'style': 'display: flex; align-items: center; gap: 4px;'},
                        [
                          span([Component.text('location:')], attributes: const {'style': 'font-size: 10px; color: #666; font-weight: bold;'}),
                          if (_editGeo != null)
                            span(
                              [
                                span([Component.text('pin_drop')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 10px; vertical-align: middle; margin-right: 1px;'}),
                                Component.text('${_editGeo!['lat']?.toStringAsFixed(4)}, ${_editGeo!['lng']?.toStringAsFixed(4)}'),
                              ],
                              attributes: const {
                                'style': 'font-size: 9px; font-weight: bold; color: #16a34a; font-family: monospace; background: #ecfdf5; padding: 1px 4px; border-radius: 4px; border: 1px solid #bbf7d0; display: inline-flex; align-items: center;'
                              },
                            ),
                        ],
                      ),
                      button(
                        [
                          span([Component.text('refresh')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 11px; margin-right: 2px; vertical-align: middle;'}),
                          Component.text(_refreshingLocation ? 'pulling...' : 'refresh from profile'),
                        ],
                        attributes: const {
                          'type': 'button',
                          'title': 'Re-pull location and coordinates from author profile',
                          'style': 'border: none; background: transparent; color: #6750A4; font-size: 9px; font-weight: bold; cursor: pointer; padding: 0; text-decoration: underline;'
                        },
                        events: {'click': (e) => _manualRefreshLocation()},
                      ),
                    ],
                  ),
                  input(
                    attributes: {
                      'type': 'text',
                      'placeholder': 'Location (e.g. Jamestown, N. D.)',
                      'value': _editLocation,
                      'style':
                      'width: 100%; padding: 6px 8px; border: 1px solid #ccc; border-radius: 4px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;'
                    },
                    events: {
                      'input': (e) {
                        final newLoc = getInputValue(e);
                        setState(() {
                          _editLocation = newLoc;
                          if (_editGeo != null) {
                            final geoLoc = _editGeo!['formatted'] ?? _editGeo!['city'] ?? '';
                            if (newLoc.trim().toLowerCase() != geoLoc.toString().trim().toLowerCase()) {
                              _editGeo = null;
                            }
                          }
                        });
                      }
                    },
                  ),
                ],
              ),
              div(
                attributes: const {'style': 'flex: 1.5; min-width: 120px;'},
                [
                  span([Component.text('historical date:')], attributes: const {'style': 'font-size: 10px; color: #666; font-weight: bold; display: block; margin-bottom: 2px;'}),
                  input(
                    attributes: {
                      'type': 'text',
                      'placeholder': 'Historical date (e.g. March 1927)',
                      'value': _editHistoricalDate,
                      'style':
                      'width: 100%; padding: 6px 8px; border: 1px solid #ccc; border-radius: 4px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;'
                    },
                    events: {'input': (e) => _editHistoricalDate = getInputValue(e)},
                  ),
                ],
              ),
            ],
          ),
          if (_locationRefreshedMessage != null)
            span(
              [Component.text(_locationRefreshedMessage!)],
              attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #16a34a; font-style: italic;'},
            ),
          div(
            attributes: const {'style': 'display: flex; flex-direction: column; width: 100%;'},
            [
              span([Component.text('letter text:')], attributes: const {'style': 'font-size: 10px; color: #666; font-weight: bold; margin-bottom: 2px;'}),
              textarea(
                classes: 'border border-gray-300 rounded-md',
                attributes: {
                  'style':
                  'width: 100%; min-height: 80px; padding: 6px 8px; font-size: 12px; font-family: inherit; line-height: 1.4; border: 1px solid #ccc; border-radius: 4px; box-sizing: border-box; background: white; margin: 0;'
                },
                events: {'input': (e) => _editText = getInputValue(e)},
                [Component.text(_editText)],
              ),
            ],
          ),
          div(
            attributes: const {'style': 'display: flex; justify-content: flex-end; gap: 8px; align-items: center; margin-top: 4px;'},
            [
              button(
                [Component.text('cancel')],
                classes: 'profile-btn',
                attributes: const {
                  'type': 'button',
                  'style': 'padding: 4px 10px; font-size: 11px; background: white; border: 1px solid #ccc; cursor: pointer;'
                },
                events: {'click': (e) => setState(() => _isEditing = false)},
              ),
              button(
                [Component.text(_isSaving ? 'saving...' : 'save changes')],
                classes: 'btn-primary nav-pill mb-0',
                attributes: {
                  'type': 'button',
                  'style':
                  'padding: 4px 14px; font-size: 11px; font-weight: bold; background: #6750A4; color: white; border: none; border-radius: 20px; cursor: pointer;',
                  if (_isSaving) 'disabled': 'true',
                },
                events: {'click': (e) => _saveEditedComment()},
              ),
            ],
          ),
        ],
      );
    }

    final String displayName = _profile?.displayName ?? component.data['displayName'] ?? 'user';
    final String username = _profile?.username ?? component.data['username'] ?? 'anonymous';
    final String? photoUrl = _profile?.photoUrl;
    final String textContent = component.data['text'] ?? '';
    final int likeCount = component.data['likeCount'] ?? 0;
    final bool isLetter = component.data['sourceType'] == 'letter_column';
    final String? location = component.data['location'];
    final String? historicalDate = component.data['historicalDate'];
    final dynamic geoData = component.data['geo'];
    final Map<String, dynamic>? geo = geoData is Map ? Map<String, dynamic>.from(geoData) : null;
    String dateStr = '';
    final createdAt = component.data['createdAt'];
    if (createdAt is DateTime) {
      dateStr = '${createdAt.month.toString().padLeft(2, '0')}.${createdAt.day.toString().padLeft(2, '0')}.${createdAt.year.toString().substring(2)}';
    }
    final targetProfileHref = '/@$username';
    return div(
      [
        // Left Column: Avatar
        a(
          [
            if (photoUrl != null && photoUrl.isNotEmpty)
              img(
                src: photoUrl,
                attributes: const {
                  'style': 'width: 100%; height: 100%; object-fit: cover; display: block; border-radius: 50%;'
                },
              )
            else
              div(
                [Component.text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?')],
                attributes: const {
                  'style': 'font-weight: bold; color: #9ca3af; font-size: 12px; line-height: 1; text-align: center;'
                },
              )
          ],
          href: targetProfileHref,
          classes: 'w-8 h-8 rounded-full bg-gray-100 overflow-hidden flex-shrink-0 border border-gray-200',
          attributes: const {
            'style':
            'width: 32px; height: 32px; min-width: 32px; min-height: 32px; max-width: 32px; max-height: 32px; flex: 0 0 32px; aspect-ratio: 1 / 1; border-radius: 50%; overflow: hidden; display: flex; align-items: center; justify-content: center; background-color: #f3f4f6; border: 1px solid #ddd; box-sizing: border-box; text-decoration: none;'
          },
        ),
        // Right Column: Details
        div(
          [
            div(
              [
                div(
                  [
                    div(
                      [
                        a(
                          [Component.text(displayName)],
                          href: targetProfileHref,
                          classes: 'font-bold text-sm text-black hover:underline',
                          attributes: const {
                            'style': 'font-weight: bold; font-size: 13px; color: black; text-decoration: none;'
                          },
                        ),
                        a(
                          [Component.text('@$username')],
                          href: targetProfileHref,
                          classes: 'text-gray-500 text-xs hover:underline',
                          attributes: const {
                            'style': 'color: #6b7280; font-size: 11px; text-decoration: none;'
                          },
                        ),
                        if (isLetter)
                          span(
                            [Component.text('letter')],
                            attributes: const {
                              'style':
                              'font-size: 8px; font-weight: bold; background: #e0e7ff; color: #3730a3; padding: 1px 4px; border-radius: 4px; text-transform: uppercase;'
                            },
                          ),
                      ],
                      classes: 'flex-row items-center gap-1',
                      attributes: const {
                        'style': 'display: flex; flex-direction: row; align-items: center; gap: 6px; flex-wrap: wrap;'
                      },
                    ),
                    div(
                      [
                        if (location != null && location.isNotEmpty)
                          span(
                            [
                              span([Component.text('pin_drop')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 12px; margin-right: 2px; vertical-align: middle;'}),
                              Component.text(location)
                            ],
                            attributes: const {
                              'style': 'color: #64748b; font-size: 10px; font-weight: 500; margin-right: 6px;'
                            },
                          ),
                        if (component.isCuratorMode && geo != null && geo['lat'] != null)
                          span(
                            [
                              Component.text('[${(geo['lat'] as num).toDouble().toStringAsFixed(2)}, ${(geo['lng'] as num).toDouble().toStringAsFixed(2)}]')
                            ],
                            attributes: const {
                              'style': 'color: #16a34a; font-size: 10px; font-family: monospace; font-weight: bold; margin-right: 6px;'
                            },
                          ),
                        if (historicalDate != null && historicalDate.isNotEmpty)
                          span([Component.text(historicalDate)], attributes: const {'style': 'color: #94a3b8; font-size: 10px; margin-right: 6px;'})
                        else if (dateStr.isNotEmpty)
                          span([Component.text(dateStr)], attributes: const {'style': 'color: #94a3b8; font-size: 10px;'}),
                      ],
                      attributes: const {
                        'style': 'display: flex; align-items: center; flex-wrap: wrap; margin-top: 2px;'
                      },
                    ),
                  ],
                  classes: 'flex-col',
                  attributes: const {'style': 'display: flex; flex-direction: column;'},
                ),
                div(
                  attributes: const {'style': 'display: flex; align-items: center; gap: 4px;'},
                  [
                    if (component.isCuratorMode) ...[
                      button(
                        [span([Component.text('edit_note')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px; color: #6750A4;'})],
                        attributes: const {
                          'type': 'button',
                          'title': 'Open & edit letter (refreshes location from profile)',
                          'style': 'background: transparent; border: none; cursor: pointer; padding: 2px;'
                        },
                        events: {'click': (e) => _openAndRefreshLocation()},
                      ),
                      button(
                        [span([Component.text('delete')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px; color: #ef4444;'})],
                        attributes: const {
                          'type': 'button',
                          'title': 'Delete letter',
                          'style': 'background: transparent; border: none; cursor: pointer; padding: 2px;'
                        },
                        events: {'click': (e) => _handleDelete()},
                      ),
                    ],
                    button(
                      [
                        span(
                          [Component.text(likeCount > 0 ? '$likeCount' : '')],
                          classes: 'text-xs font-bold ${_isLiked ? 'text-red-500' : 'text-gray-400'}',
                          attributes: {
                            'style': 'font-size: 11px; font-weight: bold; color: ${_isLiked ? "#ef4444" : "#9ca3af"};'
                          },
                        ),
                        span(
                          [Component.text('favorite')],
                          classes: 'material-symbols-outlined text-sm ${_isLiked ? 'text-red-500' : 'text-gray-300'}',
                          attributes: {
                            'style': 'font-size: 16px; color: ${_isLiked ? "#ef4444" : "#d1d5db"};'
                          },
                        ),
                      ],
                      classes: 'flex-row items-center gap-1 bg-transparent border-none cursor-pointer group p-1 rounded hover:bg-gray-50',
                      attributes: const {
                        'type': 'button',
                        'style': 'display: inline-flex; align-items: center; gap: 4px; border: none; background: transparent; cursor: pointer; padding: 4px;'
                      },
                      events: {'click': (e) => _handleLike()},
                    ),
                  ],
                ),
              ],
              classes: 'flex-row justify-between items-start',
              attributes: const {
                'style': 'display: flex; flex-direction: row; justify-content: space-between; align-items: flex-start;'
              },
            ),
            p(
              [Component.text(textContent)],
              classes: 'text-sm text-gray-800 mt-2 leading-relaxed',
              attributes: const {
                'style': 'margin: 6px 0 0 0; font-size: 13px; color: #1f2937; line-height: 1.5; text-align: left; white-space: pre-wrap; word-break: break-word;'
              },
            ),
          ],
          classes: 'flex-1 flex-col',
          attributes: const {
            'style': 'flex: 1; display: flex; flex-direction: column; overflow: hidden;'
          },
        ),
      ],
      classes: 'flex-row gap-3 py-3 border-b border-gray-100 items-start',
      attributes: const {
        'style': 'display: flex; flex-direction: row; gap: 12px; align-items: flex-start; padding: 12px 0; border-bottom: 1px solid #f0f0f0; width: 100%; box-sizing: border-box;'
      },
    );
  }
}