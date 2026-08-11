import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:jaspr/jaspr.dart';
import 'web_firebase_interop.dart';
import 'firebase_mocks.dart';
import 'unsaved_fanzine_registry.dart';

/// A hybrid client that uses the Google Cloud Firestore REST API with Web API Key authorization
/// during server-side pre-rendering, and falls back to the heavily optimized Firebase JS SDK
/// via interop for client-side routing.
class ServerFirestoreClient {
  static const String projectId = 'bqopd-9ce06';
  static const String apiKey = 'AIzaSyAKrrl8l8A-3RDzaI04qgp99-vpeMLMR_g';

  static const String baseUrl =
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  /// Generates the standard public API parameter list.
  static String _getQueryString() {
    return '?key=$apiKey';
  }

  // Robust safe Firestore parsing utilities to prevent TypeErrors in UI components
  static String? parseDateString(dynamic val) {
    if (val == null) return null;
    if (val is String) {
      if (val.contains('-') && val.length >= 10) {
        return val.substring(0, 10);
      }
      return val;
    }
    if (val is DateTime) {
      return "${val.year}-${val.month.toString().padLeft(2, '0')}-${val.day.toString().padLeft(2, '0')}";
    }

    // Handle JS Timestamp or objects with toDate()
    try {
      final date = val.toDate();
      if (date is DateTime) {
        return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      }
    } catch (_) {}

    // Handle JS/Dart objects with seconds property
    try {
      final secs = val.seconds;
      if (secs != null) {
        final dt = DateTime.fromMillisecondsSinceEpoch((secs as num).toInt() * 1000).toUtc();
        return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
      }
    } catch (_) {}

    if (val is Map) {
      final seconds = val['seconds'] ?? val['_seconds'];
      if (seconds != null) {
        try {
          final dt = DateTime.fromMillisecondsSinceEpoch((seconds as num).toInt() * 1000).toUtc();
          return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
        } catch (_) {}
      }
      final formatted = val['formatted'] ?? val['date'] ?? val['iso'];
      if (formatted != null) return formatted.toString();
    }

    final str = val.toString();
    if (str.startsWith('Timestamp(')) {
      try {
        final regExp = RegExp(r'seconds=(\d+)');
        final match = regExp.firstMatch(str);
        if (match != null) {
          final secs = int.parse(match.group(1)!);
          final dt = DateTime.fromMillisecondsSinceEpoch(secs * 1000).toUtc();
          return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
        }
      } catch (_) {}
    }
    if (str.contains('-') && str.length >= 10) {
      return str.substring(0, 10);
    }
    return null;
  }

  static String? parseSeriesString(dynamic val) {
    if (val == null) return null;
    if (val is String) return val;
    if (val is Map) {
      final name = val['name'] ?? val['title'] ?? val['id'];
      if (name != null) return name.toString();
    }
    try {
      final path = val.path;
      if (path != null) {
        return path.toString().split('/').last;
      }
    } catch (_) {}
    try {
      final id = val.id;
      if (id != null) {
        return id.toString();
      }
    } catch (_) {}
    return val.toString();
  }

  /// Sanitizes raw Firestore map payloads to format complex types into clean strings.
  static Map<String, dynamic> sanitizeFanzineData(Map<String, dynamic> data) {
    final copy = Map<String, dynamic>.from(data);
    if (copy.containsKey('publishedDate')) {
      copy['publishedDate'] = parseDateString(copy['publishedDate']);
    }
    if (copy.containsKey('series')) {
      copy['series'] = parseSeriesString(copy['series']);
    }
    return copy;
  }

  /// Decodes Firestore's strongly typed REST JSON format into clean Dart types.
  static dynamic _decodeValue(Map<String, dynamic> val) {
    if (val.containsKey('stringValue')) return val['stringValue'];
    if (val.containsKey('booleanValue')) return val['booleanValue'];
    if (val.containsKey('integerValue')) return int.tryParse(val['integerValue'].toString()) ?? 0;
    if (val.containsKey('doubleValue')) return (val['doubleValue'] as num).toDouble();
    if (val.containsKey('arrayValue')) {
      final values = val['arrayValue']['values'] as List? ?? [];
      return values.map((v) => _decodeValue(v as Map<String, dynamic>)).toList();
    }
    if (val.containsKey('mapValue')) {
      final fields = val['mapValue']['fields'] as Map<String, dynamic>? ?? {};
      return fields.map((key, value) => MapEntry(key, _decodeValue(value as Map<String, dynamic>)));
    }
    if (val.containsKey('timestampValue')) {
      return val['timestampValue'];
    }
    if (val.containsKey('nullValue')) {
      return null;
    }
    return null;
  }

  /// Iterates and parses the structured field map of a REST document.
  static Map<String, dynamic> decodeFields(Map<String, dynamic> fields) {
    return fields.map((key, value) => MapEntry(key, _decodeValue(value as Map<String, dynamic>)));
  }

  /// Fetches a document from the Firestore REST API using the Web API Key.
  static Future<Map<String, dynamic>?> getDocument(String path) async {
    final stopwatch = Stopwatch()..start();
    try {
      final url = Uri.parse('$baseUrl/$path${_getQueryString()}');
      final response = await http.get(url);
      stopwatch.stop();
      print('[REST CLIENT] GET /$path - Status: ${response.statusCode} (${stopwatch.elapsedMilliseconds}ms)');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final fields = data['fields'] as Map<String, dynamic>? ?? {};
        final decoded = decodeFields(fields);
        decoded['id'] = data['name'].toString().split('/').last;
        return sanitizeFanzineData(decoded);
      } else {
        print('[REST CLIENT ERROR] GET /$path failed: Status ${response.statusCode}\nBody: ${response.body}');
      }
    } catch (e, stack) {
      print('[REST CLIENT EXCEPTION] GET /$path - Error: $e\n$stack');
    }
    return null;
  }

  /// Fetches an entire subcollection path using the Web API Key.
  static Future<List<Map<String, dynamic>>> getCollection(String path) async {
    final stopwatch = Stopwatch()..start();
    try {
      final url = Uri.parse('$baseUrl/$path${_getQueryString()}');
      final response = await http.get(url);
      stopwatch.stop();
      print('[REST CLIENT] GET COLLECTION /$path - Status: ${response.statusCode} (${stopwatch.elapsedMilliseconds}ms)');

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final docs = body['documents'] as List? ?? [];
        return docs.map((doc) {
          final data = doc as Map<String, dynamic>;
          final fields = data['fields'] as Map<String, dynamic>? ?? {};
          final decoded = decodeFields(fields);
          decoded['id'] = data['name'].toString().split('/').last;
          return sanitizeFanzineData(decoded);
        }).toList();
      } else {
        print('[REST CLIENT ERROR] GET COLLECTION /$path failed: Status ${response.statusCode}\nBody: ${response.body}');
      }
    } catch (e, stack) {
      print('[REST CLIENT EXCEPTION] GET COLLECTION /$path - Error: $e\n$stack');
    }
    return [];
  }

  /// Runs a structured EQUAL query on the specified collection path using Web API Key parameterization.
  static Future<List<Map<String, dynamic>>> runQuery({
    required String collectionId,
    required String fieldPath,
    required String value,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final url = Uri.parse('$baseUrl:runQuery${_getQueryString()}');
      final body = {
        'structuredQuery': {
          'from': [
            {'collectionId': collectionId}
          ],
          'where': {
            'fieldFilter': {
              'field': {'fieldPath': fieldPath},
              'op': 'EQUAL',
              'value': {'stringValue': value}
            }
          },
          'limit': 1
        }
      };
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      stopwatch.stop();
      print('[REST CLIENT] runQuery on $collectionId ($fieldPath == $value) - Status: ${response.statusCode} (${stopwatch.elapsedMilliseconds}ms)');

      if (response.statusCode == 200) {
        final results = jsonDecode(response.body) as List? ?? [];
        final List<Map<String, dynamic>> decodedDocs = [];
        for (var res in results) {
          final doc = res['document'] as Map<String, dynamic>?;
          if (doc != null && doc.containsKey('fields')) {
            final fields = doc['fields'] as Map<String, dynamic>? ?? {};
            final decoded = decodeFields(fields);
            decoded['id'] = doc['name'].toString().split('/').last;
            decodedDocs.add(sanitizeFanzineData(decoded));
          }
        }
        return decodedDocs;
      } else {
        print('[REST CLIENT ERROR] runQuery on $collectionId failed: Status ${response.statusCode}\nBody: ${response.body}');
      }
    } catch (e, stack) {
      print('[REST CLIENT EXCEPTION] runQuery on $collectionId - Error: $e\n$stack');
    }
    return [];
  }

  /// Master routing logic to use the correct infrastructure
  static Future<Map<String, dynamic>> resolveFullPayload(String code) async {
    print('[PAYLOAD RESOLVER] Beginning payload resolution for path code: "$code"');
    if (kIsWeb) {
      print('[PAYLOAD RESOLVER] Context: Client-side browser. Routing to JS SDK channels.');
      return _resolveViaJsSdk(code);
    } else {
      print('[PAYLOAD RESOLVER] Context: Server-side container. Routing to REST public endpoints.');
      return _resolveViaRest(code);
    }
  }

  /// CLIENT-SIDE OPTIMIZATION:
  /// Uses the Firebase JS SDK via interop to fire targeted, fast-path queries.
  static Future<Map<String, dynamic>> _resolveViaJsSdk(String code) async {
    final payload = <String, dynamic>{};
    try {
      final String cleanCode = Uri.decodeComponent(code).trim();
      final bool isUserRoute = cleanCode.startsWith('@');
      final String handle = isUserRoute ? cleanCode.substring(1) : cleanCode;
      final String codeUpper = handle.toUpperCase();
      final String codeLower = handle.toLowerCase();

      // INTERCEPT FIRST: Check local temporary unsaved fanzines in client memory!
      if (!isUserRoute && UnsavedFanzineRegistry.hasCode(cleanCode)) {
        final fz = UnsavedFanzineRegistry.getByCode(cleanCode)!;
        payload['targetFanzineId'] = fz.id;
        payload['status'] = 'fanzine';
        payload['fanzineData'] = ServerFirestoreClient.sanitizeFanzineData({
          'id': fz.id,
          'title': fz.title,
          'volume': fz.volume,
          'issue': fz.issue,
          'wholeNumber': fz.wholeNumber,
          'type': fz.type.name,
          'isLive': fz.isLive,
          'processingStatus': fz.processingStatus,
          'ownerId': fz.ownerId,
          'editors': fz.editors,
          'twoPage': fz.twoPage,
          'hasCover': fz.hasCover,
          'shortCode': fz.shortCode,
          'sourceFile': fz.sourceFile,
          'draftEntities': fz.draftEntities,
          'masterCreators': fz.masterCreators,
          'masterIndicia': fz.masterIndicia,
          'indiciaPageId': fz.indiciaPageId,
          'startMonth': fz.startMonth,
          'startYear': fz.startYear,
          'isSoftPublished': fz.isSoftPublished,
          'series': fz.series,
          'publishedDate': fz.publishedDate,
        });

        final pgs = UnsavedFanzineRegistry.pages[fz.id] ?? [];
        payload['pages'] = pgs.map((p) => {
          'id': p.id,
          'pageNumber': p.pageNumber,
          'imageId': p.imageId,
          'imageUrl': p.imageUrl,
          'gridUrl': p.gridUrl,
          'listUrl': p.listUrl,
          'status': p.status,
          'spreadPosition': p.spreadPosition,
          'sidePreference': p.sidePreference,
          'width': p.width,
          'height': p.height,
        }).toList();

        payload['creatorProfiles'] = <String, Map<String, dynamic>>{};
        payload['imageStats'] = <String, Map<String, dynamic>>{};

        return payload;
      }

      if (isUserRoute) {
        // FAST-PATH USER LOOKUP: Direct lookup on usernames doc
        final unRes = await fsGetDoc('usernames/$codeLower');
        final Map<String, dynamic> unDoc = jsonDecode(unRes);
        if (unDoc['exists'] == true) {
          final data = unDoc['data'] as Map<String, dynamic>? ?? {};
          payload['targetUserId'] = data['uid'];
          payload['status'] = 'user';
        } else {
          // Fallback query for profiles collection
          final prRes = await fsQuery('profiles', 'username', '==', jsonEncode(codeLower), '');
          final List prDocs = jsonDecode(prRes);
          if (prDocs.isNotEmpty) {
            final firstDoc = prDocs.first;
            payload['targetUserId'] = firstDoc['id'];
            payload['status'] = 'user';
          } else {
            // Check shortcodes for legacy user shortcodes
            final scRes = await fsGetDoc('shortcodes/$codeUpper');
            final Map<String, dynamic> scDoc = jsonDecode(scRes);
            if (scDoc['exists'] == true) {
              final data = scDoc['data'] as Map<String, dynamic>? ?? {};
              if (data['type'] == 'user') {
                payload['targetUserId'] = data['contentId'];
                payload['status'] = 'user';
              }
            }
          }
        }
      } else {
        // FAST-PATH FANZINE LOOKUP: Direct lookup on shortcodes doc
        final scRes = await fsGetDoc('shortcodes/$codeUpper');
        final Map<String, dynamic> scDoc = jsonDecode(scRes);
        if (scDoc['exists'] == true) {
          final data = scDoc['data'] as Map<String, dynamic>? ?? {};
          if (data['type'] == 'fanzine') {
            payload['targetFanzineId'] = data['contentId'];
            payload['status'] = 'fanzine';
          } else if (data['type'] == 'user') {
            payload['targetUserId'] = data['contentId'];
            payload['status'] = 'user';
          }
        }

        if (payload.isEmpty) {
          final fzRes = await fsQuery('fanzines', 'shortCode', '==', jsonEncode(cleanCode), '');
          final List fzDocs = jsonDecode(fzRes);
          if (fzDocs.isNotEmpty) {
            final firstDoc = fzDocs.first;
            payload['targetFanzineId'] = firstDoc['id'];
            payload['status'] = 'fanzine';
          }
        }
      }

      if (payload['targetFanzineId'] != null) {
        final String fanzineId = payload['targetFanzineId'];

        final fzResults = await Future.wait([
          fsGetDoc('fanzines/$fanzineId'),
          fsQuery('fanzines/$fanzineId/pages', '', '', '', 'pageNumber')
        ]);

        final Map<String, dynamic> fzDoc = jsonDecode(fzResults[0]);
        final List pagesListRaw = jsonDecode(fzResults[1]);

        if (fzDoc['exists'] == true) {
          final Map<String, dynamic> fzData = fzDoc['data'] ?? {};
          payload['fanzineData'] = ServerFirestoreClient.sanitizeFanzineData(restoreTimestamps(fzData));

          final pagesList = pagesListRaw.map((p) {
            final Map<String, dynamic> mapItem = p;
            final d = restoreTimestamps(mapItem['data']);
            d['id'] = mapItem['id'];
            return d;
          }).toList();

          payload['pages'] = pagesList;

          final creators = fzData['masterCreators'] as List? ?? [];
          final uidsToFetch = creators
              .whereType<Map>()
              .map((c) => c['uid'] as String?)
              .whereType<String>()
              .where((uid) => uid.isNotEmpty)
              .toSet()
              .toList();

          final Map<String, dynamic> creatorProfiles = {};
          final Map<String, dynamic> imageStats = {};

          final List<Future<void>> parallelFetches = [];

          for (final uid in uidsToFetch) {
            parallelFetches.add(
              fsGetDoc('profiles/$uid').then((pRes) {
                final Map<String, dynamic> pDoc = jsonDecode(pRes);
                if (pDoc['exists'] == true) {
                  creatorProfiles[uid] = restoreTimestamps(pDoc['data']);
                }
              }),
            );
          }

          for (final page in pagesList) {
            final imageId = page['imageId'];
            if (imageId != null && imageId.isNotEmpty) {
              parallelFetches.add(
                fsGetDoc('images/$imageId').then((imgRes) {
                  final Map<String, dynamic> imgDoc = jsonDecode(imgRes);
                  if (imgDoc['exists'] == true) {
                    final Map<String, dynamic> imgData = imgDoc['data'] ?? {};
                    imageStats[imageId] = {
                      'likeCount': imgData['likeCount'] ?? 0,
                      'commentCount': imgData['commentCount'] ?? 0,
                      'regListCount': imgData['regListCount'] ?? 0,
                      'anonListCount': imgData['anonListCount'] ?? 0,
                      'regGridCount': imgData['regGridCount'] ?? 0,
                      'anonGridCount': imgData['anonGridCount'] ?? 0,
                    };
                  }
                }),
              );
            }
          }

          await Future.wait(parallelFetches);

          payload['creatorProfiles'] = creatorProfiles;
          payload['imageStats'] = imageStats;
        }
      }
    } catch (e) {
      print('Error resolving client-side payload: $e');
      payload['status'] = 'Error: $e';
    }

    if (payload.isEmpty && !payload.containsKey('status')) {
      payload['status'] = "Link '$code' not found.";
    }
    return payload;
  }

  /// SERVER-SIDE STATIC PRE-RENDERING:
  /// Uses targeted REST calls based on `@` route detection.
  static Future<Map<String, dynamic>> _resolveViaRest(String code) async {
    final payload = <String, dynamic>{};
    try {
      final String cleanCode = Uri.decodeComponent(code).trim();
      final bool isUserRoute = cleanCode.startsWith('@');
      final String handle = isUserRoute ? cleanCode.substring(1) : cleanCode;
      final String codeUpper = handle.toUpperCase();
      final String codeLower = handle.toLowerCase();

      if (isUserRoute) {
        // FAST-PATH USER LOOKUP (REST)
        final usernameDoc = await getDocument('usernames/$codeLower');
        if (usernameDoc != null) {
          payload['targetUserId'] = usernameDoc['uid'];
          payload['status'] = 'user';
          print('[RESOLVE REST] Successfully mapped "@$handle" to target User ID: "${usernameDoc['uid']}"');
        } else {
          final profileDocs = await runQuery(collectionId: 'profiles', fieldPath: 'username', value: codeLower);
          if (profileDocs.isNotEmpty) {
            payload['targetUserId'] = profileDocs.first['id'];
            payload['status'] = 'user';
            print('[RESOLVE REST] Query matched "@$handle". Target ID: "${profileDocs.first['id']}"');
          } else {
            final scDoc = await getDocument('shortcodes/$codeUpper');
            if (scDoc != null && scDoc['type'] == 'user') {
              payload['targetUserId'] = scDoc['contentId'];
              payload['status'] = 'user';
            }
          }
        }
      } else {
        // FAST-PATH FANZINE LOOKUP (REST)
        final scDoc = await getDocument('shortcodes/$codeUpper');
        if (scDoc != null) {
          final type = scDoc['type'] ?? 'fanzine';
          if (type == 'user') {
            payload['targetUserId'] = scDoc['contentId'];
            payload['status'] = 'user';
          } else {
            payload['targetFanzineId'] = scDoc['contentId'];
            payload['status'] = 'fanzine';
          }
          print('[RESOLVE REST] Successfully mapped code "$cleanCode" (type: $type) to contentId: "${scDoc['contentId']}"');
        } else {
          final fzDocs = await runQuery(collectionId: 'fanzines', fieldPath: 'shortCode', value: cleanCode);
          if (fzDocs.isNotEmpty) {
            payload['targetFanzineId'] = fzDocs.first['id'];
            payload['status'] = 'fanzine';
            print('[RESOLVE REST] Query matched fanzine shortcode. Target ID: "${fzDocs.first['id']}"');
          }
        }
      }

      // Pre-fetch fanzine pages if target was resolved
      if (payload['targetFanzineId'] != null) {
        final String fanzineId = payload['targetFanzineId'];
        print('[RESOLVE REST] Gathering fanzine data and page matrices for ID: "$fanzineId"');

        final fzDataResults = await Future.wait([
          getDocument('fanzines/$fanzineId'),
          getCollection('fanzines/$fanzineId/pages'),
        ]);

        final Map<String, dynamic>? fanzineData = fzDataResults[0] as Map<String, dynamic>?;
        final List<Map<String, dynamic>> pagesList = (fzDataResults[1] as List).cast<Map<String, dynamic>>();

        if (fanzineData != null) {
          payload['fanzineData'] = ServerFirestoreClient.sanitizeFanzineData(fanzineData);

          pagesList.sort((a, b) {
            final int pA = a['pageNumber'] ?? 0;
            final int pB = b['pageNumber'] ?? 0;
            return pA.compareTo(pB);
          });
          payload['pages'] = pagesList;

          final creators = fanzineData['masterCreators'] as List? ?? [];
          final Set<String> uidsToFetch = creators
              .whereType<Map>()
              .map((c) => c['uid'] as String?)
              .whereType<String>()
              .toSet();

          final Map<String, dynamic> creatorProfiles = {};
          final Map<String, dynamic> imageStats = {};

          final List<Future<void>> parallelFetches = [];

          for (final uid in uidsToFetch) {
            parallelFetches.add(
              getDocument('profiles/$uid').then((pDoc) {
                if (pDoc != null) {
                  creatorProfiles[uid] = pDoc;
                }
              }),
            );
          }

          // Preload Individual Image Stats
          for (final page in pagesList) {
            final imageId = page['imageId'];
            if (imageId != null && imageId.isNotEmpty) {
              parallelFetches.add(
                getDocument('images/$imageId').then((imgDoc) {
                  if (imgDoc != null) {
                    imageStats[imageId] = {
                      'likeCount': imgDoc['likeCount'] ?? 0,
                      'commentCount': imgDoc['commentCount'] ?? 0,
                      'regListCount': imgDoc['regListCount'] ?? 0,
                      'anonListCount': imgDoc['anonListCount'] ?? 0,
                      'regGridCount': imgDoc['regGridCount'] ?? 0,
                      'anonGridCount': imgDoc['anonGridCount'] ?? 0,
                    };
                  }
                }),
              );
            }
          }

          await Future.wait(parallelFetches);

          payload['creatorProfiles'] = creatorProfiles;
          payload['imageStats'] = imageStats;
          print('[RESOLVE REST] Preloaded Creator and Image Stats payload successfully built!');
        } else {
          print('[RESOLVE REST ERROR] Fanzine metadata was NULL for ID: "$fanzineId"');
        }
      }
    } catch (e, stack) {
      print('[RESOLVE REST EXCEPTION] Master Exception occurred: $e\n$stack');
      payload['status'] = 'Error: $e';
    }

    if (payload.isEmpty) {
      payload['status'] = "Link '$code' not found.";
      print('[RESOLVE REST WARNING] No target entity mapped. Resolving with empty lookup payload.');
    }
    return payload;
  }
}