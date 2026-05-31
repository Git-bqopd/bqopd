import 'dart:convert';
import 'web_firebase_interop.dart';
import 'unsaved_fanzine_registry.dart';
import 'package:bqopd_core/bqopd_core.dart';

/// Maps the serialized ISO string back into a pure Dart DateTime object.
/// This completely eliminates the need for cloud_firestore's Timestamp class in the Jaspr Web app.
Map<String, dynamic> restoreTimestamps(Map<String, dynamic>? data) {
  if (data == null) return {};
  final res = <String, dynamic>{};
  data.forEach((k, v) {
    res[k] = _processValue(v);
  });
  return res;
}

dynamic _processValue(dynamic v) {
  if (v is Map) {
    // Intercept our custom JS interop timestamp format
    if (v['__type'] == 'timestamp') {
      return DateTime.parse(v['iso']);
    }
    // Recursively process nested maps
    return restoreTimestamps(Map<String, dynamic>.from(v));
  } else if (v is List) {
    // Recursively process arrays
    return v.map((e) => _processValue(e)).toList();
  }
  return v;
}

/// Resolves the mapping of "img01", "img02" etc. to their actual URLs for a given fanzine
/// and replaces any occurrences of [[imgXX]] or { {imgXX} } in the text with { {IMAGE: url} }.
Future<String> resolveAndReplaceShortcodes(String fanzineId, String text) async {
  if (fanzineId.isEmpty || text.isEmpty) return text;
  try {
    // 1. Fetch fanzine page document models (check unsaved memory registry first)
    List<Map<String, dynamic>> pagesList = [];
    if (UnsavedFanzineRegistry.fanzines.containsKey(fanzineId)) {
      final pgs = UnsavedFanzineRegistry.pages[fanzineId] ?? [];
      pagesList = pgs.map((p) => {
        'id': p.id,
        'imageId': p.imageId,
        'imageUrl': p.imageUrl,
        'gridUrl': p.gridUrl,
        'listUrl': p.listUrl,
        'pageNumber': p.pageNumber,
      }).toList();
    } else {
      final pagesRes = await fsQuery('fanzines/$fanzineId/pages', '', '', '', 'pageNumber');
      final List decoded = jsonDecode(pagesRes) as List;
      pagesList = decoded.map((d) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(d['data'] as Map);
        data['id'] = d['id'];
        return data;
      }).toList();
    }

    // 2. Extract distinct image IDs utilized in this fanzine
    final Set<String> imageIds = pagesList
        .map((p) => p['imageId'] as String?)
        .where((id) => id != null && id.isNotEmpty)
        .cast<String>()
        .toSet();

    if (imageIds.isEmpty) return text;

    // 3. Fetch details of all associated images in parallel
    final List<Map<String, dynamic>> images = [];
    final List<Future<void>> fetches = [];

    for (final imageId in imageIds) {
      if (UnsavedFanzineRegistry.fanzines.containsKey(fanzineId)) {
        fetches.add(
          fsGetDoc('images/$imageId').then((imgRes) {
            final imgDoc = jsonDecode(imgRes);
            if (imgDoc['exists'] == true) {
              final data = Map<String, dynamic>.from(imgDoc['data'] as Map);
              data['id'] = imgDoc['id'];
              images.add(data);
            } else {
              // Create local fallback representation
              images.add({
                'id': imageId,
                'fileUrl': pagesList.firstWhere((p) => p['imageId'] == imageId, orElse: () => {})['imageUrl'] ?? '',
                'timestamp': DateTime.now().millisecondsSinceEpoch,
              });
            }
          }),
        );
      } else {
        fetches.add(
          fsGetDoc('images/$imageId').then((imgRes) {
            final imgDoc = jsonDecode(imgRes);
            if (imgDoc['exists'] == true) {
              final data = Map<String, dynamic>.from(imgDoc['data'] as Map);
              data['id'] = imgDoc['id'];
              images.add(data);
            }
          }),
        );
      }
    }
    await Future.wait(fetches);

    // 4. Sort images in ascending order of upload timestamp to match exact same shortname indexing logic
    images.sort((a, b) {
      final aT = a['timestamp'] ?? a['createdAt'] ?? '';
      final bT = b['timestamp'] ?? b['createdAt'] ?? '';
      return aT.toString().compareTo(bT.toString());
    });

    // 5. Replace each shortname with the correct IMAGE tag format
    String processedText = text;
    for (int i = 0; i < images.length; i++) {
      final img = images[i];
      final String? fileUrl = img['fileUrl'] ?? img['gridUrl'] ?? img['imageUrl'];
      if (fileUrl != null && fileUrl.isNotEmpty) {
        final String shortName = "img${(i + 1).toString().padLeft(2, '0')}";

        // Support both [[img01]] and {{img01}}
        processedText = processedText
            .replaceAll("[[$shortName]]", "{{IMAGE: $fileUrl}}")
            .replaceAll("{{$shortName}}", "{{IMAGE: $fileUrl}}");
      }
    }
    return processedText;
  } catch (e) {
    print('[resolveAndReplaceShortcodes Error] $e');
    return text;
  }
}