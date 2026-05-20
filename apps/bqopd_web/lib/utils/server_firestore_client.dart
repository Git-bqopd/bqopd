import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:jaspr/jaspr.dart';
import 'web_firebase_interop.dart';
import 'firebase_mocks.dart';

/// A hybrid client that uses the Google Cloud Firestore REST API during server-side pre-rendering,
/// and falls back to the heavily optimized Firebase JS SDK via interop for client-side routing.
class ServerFirestoreClient {
  static const String baseUrl =
      'https://firestore.googleapis.com/v1/projects/bqopd-9ce06/databases/(default)/documents';

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

  /// Fetches a document from the Firestore REST API.
  static Future<Map<String, dynamic>?> getDocument(String path) async {
    try {
      final url = Uri.parse('$baseUrl/$path');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final fields = data['fields'] as Map<String, dynamic>? ?? {};
        final decoded = decodeFields(fields);
        decoded['id'] = data['name'].toString().split('/').last;
        return decoded;
      }
    } catch (e) {
      print('Error getting server-side document $path: $e');
    }
    return null;
  }

  /// Fetches an entire subcollection or collection path from Firestore REST API.
  static Future<List<Map<String, dynamic>>> getCollection(String path) async {
    try {
      final url = Uri.parse('$baseUrl/$path');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final docs = body['documents'] as List? ?? [];
        return docs.map((doc) {
          final data = doc as Map<String, dynamic>;
          final fields = data['fields'] as Map<String, dynamic>? ?? {};
          final decoded = decodeFields(fields);
          decoded['id'] = data['name'].toString().split('/').last;
          return decoded;
        }).toList();
      }
    } catch (e) {
      print('Error getting server-side collection $path: $e');
    }
    return [];
  }

  /// Runs a structured EQUAL query on the specified collection path via REST API.
  static Future<List<Map<String, dynamic>>> runQuery({
    required String collectionId,
    required String fieldPath,
    required String value,
  }) async {
    try {
      final url = Uri.parse('$baseUrl:runQuery');
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
      if (response.statusCode == 200) {
        final results = jsonDecode(response.body) as List? ?? [];
        final List<Map<String, dynamic>> decodedDocs = [];
        for (var res in results) {
          final doc = res['document'] as Map<String, dynamic>?;
          if (doc != null && doc.containsKey('fields')) {
            final fields = doc['fields'] as Map<String, dynamic>? ?? {};
            final decoded = decodeFields(fields);
            decoded['id'] = doc['name'].toString().split('/').last;
            decodedDocs.add(decoded);
          }
        }
        return decodedDocs;
      }
    } catch (e) {
      print('Error running server-side query on $collectionId ($fieldPath == $value): $e');
    }
    return [];
  }

  /// Master routing logic to use the correct infrastructure
  static Future<Map<String, dynamic>> resolveFullPayload(String code) async {
    if (kIsWeb) {
      return _resolveViaJsSdk(code);
    } else {
      return _resolveViaRest(code);
    }
  }

  /// CLIENT-SIDE OPTIMIZATION:
  /// Uses the Firebase JS SDK via interop to fire parallel Websocket queries.
  /// Eliminates the HTTP waterfall effect in the browser.
  static Future<Map<String, dynamic>> _resolveViaJsSdk(String code) async {
    final payload = <String, dynamic>{};
    try {
      final String codeUpper = code.toUpperCase();
      final String codeLower = code.toLowerCase();

      // 1. Check Shortcodes and Usernames in parallel
      final lookupResults = await Future.wait([
        fsGetDoc('shortcodes/$codeUpper'),
        fsGetDoc('usernames/$codeLower')
      ]);

      final scDoc = jsonDecode(lookupResults[0]);
      final unDoc = jsonDecode(lookupResults[1]);

      if (scDoc['exists'] == true) {
        if (scDoc['data']['type'] == 'fanzine') {
          payload['targetFanzineId'] = scDoc['data']['contentId'];
          payload['status'] = 'fanzine';
        } else if (scDoc['data']['type'] == 'user') {
          payload['targetUserId'] = scDoc['data']['contentId'];
          payload['status'] = 'user';
        }
      }

      if (payload.isEmpty && unDoc['exists'] == true) {
        payload['targetUserId'] = unDoc['data']['uid'];
        payload['status'] = 'user';
      }

      // 2. Query fanzines and profiles if direct lookups failed
      if (payload.isEmpty) {
        final fzRes = await fsQuery('fanzines', 'shortCode', '==', jsonEncode(code), '');
        final fzDocs = jsonDecode(fzRes) as List;
        if (fzDocs.isNotEmpty) {
          payload['targetFanzineId'] = fzDocs.first['id'];
          payload['status'] = 'fanzine';
        }
      }

      if (payload.isEmpty) {
        final prRes = await fsQuery('profiles', 'username', '==', jsonEncode(codeLower), '');
        final prDocs = jsonDecode(prRes) as List;
        if (prDocs.isNotEmpty) {
          payload['targetUserId'] = prDocs.first['id'];
          payload['status'] = 'user';
        }
      }

      // 3. Parallel fetch Fanzine data + Pages + Creators + Image Stats
      if (payload['targetFanzineId'] != null) {
        final String fanzineId = payload['targetFanzineId'] as String;

        final fzResults = await Future.wait([
          fsGetDoc('fanzines/$fanzineId'),
          fsQuery('fanzines/$fanzineId/pages', '', '', '', 'pageNumber')
        ]);

        final fzDoc = jsonDecode(fzResults[0]);
        final pagesListRaw = jsonDecode(fzResults[1]) as List;

        if (fzDoc['exists'] == true) {
          // Restore timestamps via our mock helper
          payload['fanzineData'] = restoreTimestamps(fzDoc['data']);

          final pagesList = pagesListRaw.map((p) {
            final d = restoreTimestamps(p['data'] as Map<String, dynamic>);
            d['id'] = p['id'];
            return d;
          }).toList();

          payload['pages'] = pagesList;

          // Extract IDs to fetch details for
          final creators = fzDoc['data']['masterCreators'] as List? ?? [];
          final uidsToFetch = creators.map((c) => (c as Map)['uid'] as String?)
              .where((uid) => uid != null && uid.isNotEmpty)
              .cast<String>().toSet().toList();

          final imageIdsToFetch = pagesList.map((p) => p['imageId'] as String?)
              .where((id) => id != null && id.isNotEmpty)
              .cast<String>().toSet().toList();

          final Map<String, dynamic> creatorProfiles = {};
          final Map<String, dynamic> imageStats = {};

          // Fire ALL profile and image requests simultaneously
          final profileFutures = uidsToFetch.map((uid) async {
            final pRes = await fsGetDoc('profiles/$uid');
            final pDoc = jsonDecode(pRes);
            if (pDoc['exists'] == true) creatorProfiles[uid] = restoreTimestamps(pDoc['data']);
          });

          final imageFutures = imageIdsToFetch.map((id) async {
            final iRes = await fsGetDoc('images/$id');
            final iDoc = jsonDecode(iRes);
            if (iDoc['exists'] == true) imageStats[id] = restoreTimestamps(iDoc['data']);
          });

          // Wait for the entire batch of metadata to return
          await Future.wait([...profileFutures, ...imageFutures]);

          payload['creatorProfiles'] = creatorProfiles;
          payload['imageStats'] = imageStats;
        }
      }
    } catch (e) {
      print('Error resolving client-side payload: $e');
      payload['status'] = 'Error: $e';
    }

    if (payload.isEmpty && !payload.containsKey('status')) {
      payload['status'] = "Link '\$code' not found.";
    }
    return payload;
  }

  /// SERVER-SIDE STATIC PRE-RENDERING:
  /// Uses sequential HTTP requests since dart:js_interop is not available in the VM.
  static Future<Map<String, dynamic>> _resolveViaRest(String code) async {
    final payload = <String, dynamic>{};
    try {
      final String codeUpper = code.toUpperCase();
      final String codeLower = code.toLowerCase();

      // 1. Check shortcodes collection
      final scDoc = await getDocument('shortcodes/$codeUpper');
      if (scDoc != null) {
        if (scDoc['type'] == 'fanzine') {
          payload['targetFanzineId'] = scDoc['contentId'];
          payload['status'] = 'fanzine';
        } else if (scDoc['type'] == 'user') {
          payload['targetUserId'] = scDoc['contentId'];
          payload['status'] = 'user';
        }
      }

      // 2. Check usernames collection
      if (payload.isEmpty) {
        final usernameDoc = await getDocument('usernames/$codeLower');
        if (usernameDoc != null) {
          payload['targetUserId'] = usernameDoc['uid'];
          payload['status'] = 'user';
        }
      }

      // 3. Query fanzines by shortCode
      if (payload.isEmpty) {
        final fzDocs = await runQuery(
          collectionId: 'fanzines',
          fieldPath: 'shortCode',
          value: code,
        );
        if (fzDocs.isNotEmpty) {
          payload['targetFanzineId'] = fzDocs.first['id'];
          payload['status'] = 'fanzine';
        }
      }

      // 4. Query profiles by username
      if (payload.isEmpty) {
        final profileDocs = await runQuery(
          collectionId: 'profiles',
          fieldPath: 'username',
          value: codeLower,
        );
        if (profileDocs.isNotEmpty) {
          payload['targetUserId'] = profileDocs.first['id'];
          payload['status'] = 'user';
        }
      }

      // 5. If we resolved a fanzine target, pre-fetch and pack all its dependent layouts
      if (payload['targetFanzineId'] != null) {
        final String fanzineId = payload['targetFanzineId'] as String;

        // Fetch fanzine document
        final fanzineData = await getDocument('fanzines/$fanzineId');
        if (fanzineData != null) {
          payload['fanzineData'] = fanzineData;

          // Fetch page subcollections
          final pagesList = await getCollection('fanzines/$fanzineId/pages');
          pagesList.sort((a, b) {
            final int pA = a['pageNumber'] ?? 0;
            final int pB = b['pageNumber'] ?? 0;
            return pA.compareTo(pB);
          });
          payload['pages'] = pagesList;

          // Preload Creator Profiles
          final creators = fanzineData['masterCreators'] as List? ?? [];
          final Map<String, dynamic> creatorProfiles = {};
          final List<String> uidsToFetch = creators
              .map((c) {
            if (c is Map) return c['uid'] as String?;
            return null;
          })
              .where((uid) => uid != null && uid.isNotEmpty)
              .cast<String>()
              .toList();

          for (final uid in uidsToFetch) {
            final pDoc = await getDocument('profiles/$uid');
            if (pDoc != null) {
              creatorProfiles[uid] = pDoc;
            }
          }
          payload['creatorProfiles'] = creatorProfiles;

          // Preload Image Stats
          final Map<String, dynamic> imageStats = {};
          final List<String> imageIdsToFetch = pagesList
              .map((p) => p['imageId'] as String?)
              .where((id) => id != null && id.isNotEmpty)
              .cast<String>()
              .toList();

          for (final id in imageIdsToFetch) {
            final iDoc = await getDocument('images/$id');
            if (iDoc != null) {
              imageStats[id] = iDoc;
            }
          }
          payload['imageStats'] = imageStats;
        }
      }
    } catch (e) {
      print('Error resolving full server payload: $e');
      payload['status'] = 'Error: $e';
    }

    if (payload.isEmpty) {
      payload['status'] = "Link '$code' not found.";
    }
    return payload;
  }
}