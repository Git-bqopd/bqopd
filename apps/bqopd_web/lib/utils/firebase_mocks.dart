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
/// and replaces any occurrences of [[imgXX]] or {{imgXX}} in the text with {{IMAGE: url}}.
///
/// EXTENDED: Also scans for potential fanzine shortcodes (e.g. {{NCbqopdQ}} or [[NCbqopdQ]]),
/// resolves their cover images from Firestore or the local temporary memory registry,
/// and swaps them with the appropriate {{IMAGE: coverUrl}} layout tag in-place.
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

    final List<Map<String, dynamic>> images = [];
    if (imageIds.isNotEmpty) {
      // Fetch details of all associated images in parallel
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

      // Sort images in ascending order of upload timestamp to match exact same shortname indexing logic
      images.sort((a, b) {
        final aT = a['timestamp'] ?? a['createdAt'] ?? '';
        final bT = b['timestamp'] ?? b['createdAt'] ?? '';
        return aT.toString().compareTo(bT.toString());
      });
    }

    // 3. Replace each local imgXX shortname with the correct IMAGE tag format
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

    // --- 4. NEW: DYNAMIC FANZINE SHORTCODE RESOLUTION ---
    // Extract candidates of potentially custom Base36 shortcodes in double brackets or braces
    final regexBraces = RegExp(r'\{\{([a-zA-Z0-9]{5,12})\}\}');
    final regexBrackets = RegExp(r'\[\[([a-zA-Z0-9]{5,12})\]\]');

    final Set<String> candidates = {};
    for (final match in regexBraces.allMatches(processedText)) {
      final code = match.group(1);
      if (code != null && !code.toLowerCase().startsWith('img')) {
        candidates.add(code);
      }
    }
    for (final match in regexBrackets.allMatches(processedText)) {
      final code = match.group(1);
      if (code != null && !code.toLowerCase().startsWith('img')) {
        candidates.add(code);
      }
    }

    if (candidates.isNotEmpty) {
      final Map<String, String> resolvedCovers = {};
      final List<Future<void>> fzFetches = [];

      for (final code in candidates) {
        final codeUpper = code.toUpperCase();

        fzFetches.add(
          fsGetDoc('shortcodes/$codeUpper').then((scRes) async {
            final scDoc = jsonDecode(scRes);
            if (scDoc['exists'] == true) {
              final scData = scDoc['data'] as Map<String, dynamic>? ?? {};
              if (scData['type'] == 'fanzine') {
                final targetFanzineId = scData['contentId'] as String?;
                if (targetFanzineId != null && targetFanzineId.isNotEmpty) {
                  // Attempt to load the fanzine's cover image
                  if (UnsavedFanzineRegistry.fanzines.containsKey(targetFanzineId)) {
                    final pgs = UnsavedFanzineRegistry.pages[targetFanzineId] ?? [];
                    if (pgs.isNotEmpty) {
                      final sortedPgs = List<FanzinePage>.from(pgs)
                        ..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
                      final firstPage = sortedPgs.firstWhere(
                            (p) => (p.gridUrl != null && p.gridUrl!.isNotEmpty) || (p.imageUrl != null && p.imageUrl!.isNotEmpty),
                        orElse: () => sortedPgs.first,
                      );
                      final coverUrl = firstPage.gridUrl ?? firstPage.imageUrl;
                      if (coverUrl != null && coverUrl.isNotEmpty) {
                        resolvedCovers[code] = coverUrl;
                      }
                    }
                  } else {
                    final fzRes = await fsGetDoc('fanzines/$targetFanzineId');
                    final fzDoc = jsonDecode(fzRes);
                    if (fzDoc['exists'] == true) {
                      final fzData = fzDoc['data'] as Map<String, dynamic>? ?? {};
                      final gridCoverImage = fzData['gridCoverImage'] as String?;
                      if (gridCoverImage != null && gridCoverImage.isNotEmpty) {
                        resolvedCovers[code] = gridCoverImage;
                      } else {
                        // Grab cover from the first page in the subcollection
                        final pagesRes = await fsQuery('fanzines/$targetFanzineId/pages', '', '', '', 'pageNumber');
                        final List pagesList = jsonDecode(pagesRes) as List;
                        if (pagesList.isNotEmpty) {
                          final firstPage = pagesList.first;
                          final data = firstPage['data'] as Map<String, dynamic>;
                          final url = data['gridUrl'] ?? data['thumbnailUrl'] ?? data['imageUrl'];
                          if (url != null && url.toString().isNotEmpty) {
                            resolvedCovers[code] = url.toString();
                          }
                        }
                      }
                    }
                  }
                }
              }
            } else {
              // Direct fallback query for older fanzines unindexed in shortcodes lookup collection
              final fzQueryRes = await fsQuery('fanzines', 'shortCode', '==', jsonEncode(code), '');
              final fzDocs = jsonDecode(fzQueryRes) as List;
              if (fzDocs.isNotEmpty) {
                final firstFz = fzDocs.first;
                final fzId = firstFz['id'] as String;
                final fzData = firstFz['data'] as Map<String, dynamic>? ?? {};
                final gridCoverImage = fzData['gridCoverImage'] as String?;
                if (gridCoverImage != null && gridCoverImage.isNotEmpty) {
                  resolvedCovers[code] = gridCoverImage;
                } else {
                  final pagesRes = await fsQuery('fanzines/$fzId/pages', '', '', '', 'pageNumber');
                  final List pagesList = jsonDecode(pagesRes) as List;
                  if (pagesList.isNotEmpty) {
                    final firstPage = pagesList.first;
                    final data = firstPage['data'] as Map<String, dynamic>;
                    final url = data['gridUrl'] ?? data['thumbnailUrl'] ?? data['imageUrl'];
                    if (url != null && url.toString().isNotEmpty) {
                      resolvedCovers[code] = url.toString();
                    }
                  }
                }
              }
            }
          }),
        );
      }

      await Future.wait(fzFetches);

      // Perform clean inline replacements for all successfully resolved fanzine cover images
      resolvedCovers.forEach((code, coverUrl) {
        processedText = processedText
            .replaceAll("[[$code]]", "{{IMAGE: $coverUrl}}")
            .replaceAll("{{$code}}", "{{IMAGE: $coverUrl}}");
      });
    }

    return processedText;
  } catch (e) {
    print('[resolveAndReplaceShortcodes Error] $e');
    return text;
  }
}