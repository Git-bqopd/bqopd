import 'dart:convert';
import 'dart:math' as math;
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import '../utils/publisher_compiler.dart';
import '../utils/unsaved_fanzine_registry.dart';
import '../components/historical_letter_card.dart';

/// Result container holding the compiled [Fanzine] folio document and generated [FanzinePage] list.
class RadiusFolioResult {
  final Fanzine fanzine;
  final List<FanzinePage> pages;

  RadiusFolioResult({
    required this.fanzine,
    required this.pages,
  });
}

/// Internal helper bundle holding a selected letter along with its distance, parsed date, and precalculated height.
class _SelectedRadiusLetter {
  final HistoricalLetterEntry entry;
  final Map<String, dynamic> raw;
  final String markdown;
  final double distance;
  final DateTime publishedDate;
  final double estimatedHeight;

  _SelectedRadiusLetter({
    required this.entry,
    required this.raw,
    required this.markdown,
    required this.distance,
    required this.publishedDate,
    required this.estimatedHeight,
  });
}

/// Encapsulates geospatial nearest-neighbor resolution, letter querying,
/// distance calculation, ordering, fast mathematical layout fitting, and server-side compilation.
class AddressRadiusLetters {
  /// Usable height per column in pixels derived from the registered basic_text publisher template.
  static double get kColumnHeight {
    final template = PageTemplateRegistry.getTemplate('basic_text');
    final height = template?.metadata['usableColumnHeight'];
    if (height is num) return height.toDouble();
    return 3087.0;
  }

  /// Number of columns per publisher folio page derived from the registered basic_text template.
  static int get kColumnsPerPage {
    final template = PageTemplateRegistry.getTemplate('basic_text');
    final cols = template?.metadata['columnCount'];
    if (cols is int) return cols;
    return 3;
  }

  /// Total theoretical vertical pixels available per page across all columns (3 * 3087 = 9,261 px).
  static double get kTotalPageHeight => kColumnHeight * kColumnsPerPage;

  /// Parses historical/vintage date strings (e.g. "March 1, 1927", "January, 1971", "1935")
  /// into comparable DateTime objects for chronological ordering.
  static DateTime parseHistoricalDate(dynamic rawDate,
      [String? markdownContext]) {
    String text = '';
    if (rawDate != null && rawDate.toString().trim().isNotEmpty) {
      text = rawDate.toString().trim();
    } else if (markdownContext != null && markdownContext.isNotEmpty) {
      text = markdownContext;
    }
    if (text.isEmpty) {
      return DateTime(2099, 1, 1);
    }
    final tryDirect = DateTime.tryParse(text);
    if (tryDirect != null) {
      return tryDirect;
    }
    final yearMatch = RegExp(r'\b(1[89]\d\d|20\d\d)\b').firstMatch(text);
    if (yearMatch == null) {
      return DateTime(2099, 1, 1);
    }
    final int year = int.parse(yearMatch.group(1)!);
    int month = 1;
    final lower = text.toLowerCase();
    const months = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
      'spring': 3,
      'summer': 6,
      'fall': 9,
      'autumn': 9,
      'winter': 12,
    };
    for (final entry in months.entries) {
      if (RegExp('\\b${entry.key}', caseSensitive: false).hasMatch(lower)) {
        month = entry.value;
        break;
      }
    }
    int day = 1;
    final dayMatches = RegExp(r'\b([12]\d|3[01]|0?[1-9])\b').allMatches(text);
    for (final m in dayMatches) {
      final val = int.tryParse(m.group(1)!);
      if (val != null && val != year && val >= 1 && val <= 31) {
        day = val;
        break;
      }
    }
    return DateTime(year, month, day);
  }

  /// Calculates geodesic distance between two latitude/longitude points in miles (Haversine formula).
  static double calculateDistanceMiles(
      double lat1,
      double lon1,
      double lat2,
      double lon2,
      ) {
    const double p = 0.017453292519943295; // Math.PI / 180
    final a = 0.5 -
        math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) *
            math.cos(lat2 * p) *
            (1.0 - math.cos((lon2 - lon1) * p)) /
            2;
    return 12742.0 *
        math.asin(math.sqrt(math.max(0.0, math.min(1.0, a)))) *
        0.621371;
  }

  /// Cleans up vintage abbreviation spellings (e.g. Wis. -> WI) and formats city, state pairs.
  static String cleanLocation(String raw) {
    var loc = raw.trim();
    loc = loc.replaceAll(RegExp(r'\bWis\b\.?', caseSensitive: false), 'WI');
    loc = loc.replaceAll(RegExp(r'\bIll\b\.?', caseSensitive: false), 'IL');
    loc = loc.replaceAll(RegExp(r'\bMich\b\.?', caseSensitive: false), 'MI');
    loc = loc.replaceAll(RegExp(r'\bMinn\b\.?', caseSensitive: false), 'MN');
    loc = loc.replaceAll(RegExp(r'\bPenn\b\.?', caseSensitive: false), 'PA');
    loc = loc.replaceAll(RegExp(r'\bN\.\s*D\b\.?', caseSensitive: false), 'ND');
    loc = loc.replaceAll(RegExp(r'\bS\.\s*D\b\.?', caseSensitive: false), 'SD');
    loc = loc.replaceAll(RegExp(r'\bCal\b\.?', caseSensitive: false), 'CA');
    loc = loc.replaceAll(RegExp(r'\bCalif\b\.?', caseSensitive: false), 'CA');
    loc = loc.replaceAll(RegExp(r'\bInd\b\.?', caseSensitive: false), 'IN');
    loc = loc.replaceAll(RegExp(r'\bMo\b\.?', caseSensitive: false), 'MO');
    loc = loc.replaceAll(RegExp(r'\bMass\b\.?', caseSensitive: false), 'MA');
    loc = loc.replaceAll(RegExp(r'\bConn\b\.?', caseSensitive: false), 'CT');
    loc = loc.replaceAll(RegExp(r'\bWash\b\.?', caseSensitive: false), 'WA');
    if (loc.contains(',')) {
      final parts = loc.split(',');
      if (parts.length >= 2) {
        final last = parts[parts.length - 1].trim();
        final secondLast = parts[parts.length - 2].trim();
        loc = '$secondLast, $last';
      }
    }
    return loc;
  }

  /// Resolves the center target address into geographic coordinates using
  /// the server-verified Cloud Function endpoint with Firestore geocache caching.
  static Future<Map<String, dynamic>?> _geocodeTarget(
      String targetAddress) async {
    final cleanAddr = targetAddress.trim();
    if (cleanAddr.isEmpty) return null;
    final targetGeoJson = await geocodeAddress(cleanAddr);
    if (targetGeoJson != null && targetGeoJson.isNotEmpty) {
      final decoded = jsonDecode(targetGeoJson);
      if (decoded is Map && decoded['lat'] != null && decoded['lng'] != null) {
        return {
          'lat': (decoded['lat'] as num).toDouble(),
          'lng': (decoded['lng'] as num).toDouble(),
          'formatted': decoded['formatted']?.toString() ?? cleanAddr,
          'city': decoded['city']?.toString() ?? '',
          'state': decoded['state']?.toString() ?? '',
          'country': decoded['country']?.toString() ?? '',
          'geohash': decoded['geohash']?.toString() ?? '',
        };
      }
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> _fetchNearestLetters({
    required double lat,
    required double lng,
    required int limit,
    double maxRadiusMiles = 5000.0,
  }) async {
    print(
        '[AddressRadiusLetters] Requesting $limit closest letters from Cloud Function query_nearest_letters...');
    try {
      final payload = {
        'lat': lat,
        'lng': lng,
        'limit': limit,
        'max_radius_miles': maxRadiusMiles,
      };
      final resStr =
      await fnCall('query_nearest_letters', jsonEncode(payload));
      final decoded = jsonDecode(resStr);
      if (decoded is Map && decoded['letters'] is List) {
        final List list = decoded['letters'];
        final letters =
        list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
        print(
            '[AddressRadiusLetters] Server returned ${letters.length} candidate letters.');
        return letters;
      }
    } catch (e) {
      print(
          '[AddressRadiusLetters] Server callable query_nearest_letters fallback: $e');
    }
    return _fallbackBoundedLetters(lat, lng, limit, maxRadiusMiles);
  }

  static Future<List<Map<String, dynamic>>> _fallbackBoundedLetters(
      double targetLat,
      double targetLng,
      int limit,
      double maxRadius,
      ) async {
    print(
        '[AddressRadiusLetters] Running fallback bounded letters query over pre-indexed geo data...');
    final commentsRes = await fsQuery(
      'artifacts/bqopd/public/data/comments',
      'sourceType',
      '==',
      jsonEncode('letter_column'),
      '',
    );
    List decodedComments = jsonDecode(commentsRes) as List;
    if (decodedComments.isEmpty) {
      final fallbackRes = await fsQuery(
          'artifacts/bqopd/public/data/comments', '', '', '', '');
      decodedComments = jsonDecode(fallbackRes) as List;
    }
    final List<Map<String, dynamic>> matchingLetters = [];

    for (final item in decodedComments) {
      final data = Map<String, dynamic>.from(item['data'] as Map);
      data['_id'] = item['id'];
      final isLetter = data['sourceType'] == 'letter_column' ||
          (data['location'] != null &&
              data['location'].toString().trim().isNotEmpty);
      if (!isLetter) continue;

      double? letterLat;
      double? letterLng;
      if (data['geo'] is Map) {
        final geo = data['geo'] as Map;
        if (geo['lat'] != null && geo['lng'] != null) {
          letterLat = (geo['lat'] as num).toDouble();
          letterLng = (geo['lng'] as num).toDouble();
        }
      }

      if (letterLat != null && letterLng != null) {
        final dist = calculateDistanceMiles(
            targetLat, targetLng, letterLat, letterLng);
        if (dist <= maxRadius) {
          data['_calculatedDistanceMiles'] =
              double.parse(dist.toStringAsFixed(2));
          matchingLetters.add(data);
        }
      }
    }

    matchingLetters.sort((a, b) {
      final double distA = (a['_calculatedDistanceMiles'] as double?) ?? 0.0;
      final double distB = (b['_calculatedDistanceMiles'] as double?) ?? 0.0;
      return distA.compareTo(distB);
    });
    return matchingLetters.take(limit).toList();
  }

  /// Calculates estimated height structured around the strict 42px baseline grid
  /// using natural aspect ratios for images rather than a fixed height.
  static double estimateMarkdownHeight(String markdown) {
    const double rowHeight = 42.0;
    const double colWidth = PublisherLayoutEngine.kColumnWidth;
    double totalHeight = 0.0;
    final lines = markdown.split('\n');

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        totalHeight += rowHeight;
        continue;
      }
      if (line.startsWith('{{TEMPLATE')) {
        totalHeight += 29.0 * rowHeight; // ~1218px
      } else if (line.startsWith('{{IMAGE')) {
        // Extract optional dimensions or calculate based on natural 5:8 aspect ratio
        double drawHeight = colWidth / 0.625; // Default ~972.8px
        final dimMatch = RegExp(r'(\d+)\s*[xX]\s*(\d+)').firstMatch(line);
        final ratioMatch = RegExp(r'(?:ratio|aspectRatio)=(\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(line);
        if (dimMatch != null) {
          final w = double.tryParse(dimMatch.group(1) ?? '') ?? 0.0;
          final h = double.tryParse(dimMatch.group(2) ?? '') ?? 0.0;
          if (w > 0 && h > 0) {
            drawHeight = colWidth * (h / w);
          }
        } else if (ratioMatch != null) {
          final r = double.tryParse(ratioMatch.group(1) ?? '') ?? 0.0;
          if (r > 0) {
            drawHeight = colWidth / r;
          }
        }
        const double minMarginBottom = 14.0;
        final int rowsNeeded = ((drawHeight + minMarginBottom) / rowHeight).ceil();
        totalHeight += rowsNeeded * rowHeight;
      } else if (line.startsWith('### ')) {
        totalHeight += 2.0 * rowHeight; // 84px
      } else if (line.startsWith('## ')) {
        totalHeight += 2.0 * rowHeight; // 84px
      } else if (line.startsWith('# ')) {
        totalHeight += 2.0 * rowHeight; // 84px
      } else {
        final words =
        line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        if (words.isNotEmpty) {
          final lineCount = math.max(1, (words.length / 7.2).ceil());
          totalHeight += (lineCount * rowHeight) + rowHeight;
        }
      }
    }
    totalHeight += rowHeight;
    return totalHeight;
  }

  /// Builds a Markdown representation of a historical letter, embedding the
  /// natural dimensions or aspect ratio for both the fanzine cover and the page scan.
  static String buildLetterMarkdown(
      HistoricalLetterEntry entry, {
        Map<String, dynamic>? coverMetadata,
        Map<String, dynamic>? pageMetadata,
      }) {
    final buffer = StringBuffer();

    // 1. Cover Image with dimensions or aspect ratio
    if (entry.coverImageUrl != null && entry.coverImageUrl!.isNotEmpty) {
      final int? w = coverMetadata?['width'] as int?;
      final int? h = coverMetadata?['height'] as int?;
      final num? ratio = coverMetadata?['aspectRatio'] as num?;

      if (w != null && h != null && w > 0 && h > 0) {
        buffer.writeln('{{IMAGE: ${entry.coverImageUrl!} | ${w}x${h}}}');
      } else if (ratio != null && ratio > 0) {
        buffer.writeln('{{IMAGE: ${entry.coverImageUrl!} | ratio=${ratio.toDouble().toStringAsFixed(4)}}}');
      } else {
        buffer.writeln('{{IMAGE: ${entry.coverImageUrl!} | ratio=0.625}}');
      }
      buffer.writeln();
    }

    // 2. Publication Title & Volume/Issue
    buffer.writeln(entry.fanzineTitle);
    final volIssueParts = <String>[];
    if (entry.volume != null && entry.volume!.isNotEmpty) {
      volIssueParts.add('Volume ${entry.volume!}');
    }
    if (entry.issue != null && entry.issue!.isNotEmpty) {
      volIssueParts.add('Issue ${entry.issue!}');
    }
    if (volIssueParts.isNotEmpty) {
      buffer.writeln(volIssueParts.join(', '));
    }

    // 3. Published Date
    if (entry.publishedDate != null && entry.publishedDate!.isNotEmpty) {
      buffer.writeln(entry.publishedDate!);
    }
    buffer.writeln();

    // 4. Letter Page Scan Image with dimensions or aspect ratio
    if (entry.pageImageUrl != null && entry.pageImageUrl!.isNotEmpty) {
      final int? w = pageMetadata?['width'] as int?;
      final int? h = pageMetadata?['height'] as int?;
      final num? ratio = pageMetadata?['aspectRatio'] as num?;

      if (w != null && h != null && w > 0 && h > 0) {
        buffer.writeln('{{IMAGE: ${entry.pageImageUrl!} | ${w}x${h}}}');
      } else if (ratio != null && ratio > 0) {
        buffer.writeln('{{IMAGE: ${entry.pageImageUrl!} | ratio=${ratio.toDouble().toStringAsFixed(4)}}}');
      } else {
        buffer.writeln('{{IMAGE: ${entry.pageImageUrl!} | ratio=0.625}}');
      }
      buffer.writeln();
    }

    // 5. Letter Content
    buffer.writeln(entry.letterText);
    buffer.writeln();

    // 6. Author and Location sign-off
    final cleanTextLower = entry.letterText.toLowerCase();
    final bool hasAuthor = entry.authorName != null &&
        entry.authorName!.isNotEmpty &&
        cleanTextLower.contains(entry.authorName!.toLowerCase());
    final bool hasLocation = entry.location != null &&
        entry.location!.isNotEmpty &&
        cleanTextLower.contains(entry.location!.toLowerCase());

    if (!hasAuthor && entry.authorName != null && entry.authorName!.isNotEmpty) {
      buffer.writeln(entry.authorName!);
    }
    if (!hasLocation && entry.location != null && entry.location!.isNotEmpty) {
      buffer.writeln(entry.location!);
    }
    buffer.writeln();

    return buffer.toString();
  }

  /// Evaluates exact canvas page count for a set of letters by testing the layout
  /// in its final chronological publication sequence using pure-Dart PublisherLayoutEngine.
  static Future<int> _testRenderPageCount(
      List<_SelectedRadiusLetter> letters) async {
    if (letters.isEmpty) return 0;
    final copy = List<_SelectedRadiusLetter>.from(letters);
    copy.sort((a, b) {
      final dComp = a.publishedDate.compareTo(b.publishedDate);
      if (dComp != 0) return dComp;
      return a.distance.compareTo(b.distance);
    });
    final testMarkdown = copy.map((l) => l.markdown).join('\n\n').trim();
    try {
      return PublisherLayoutEngine.measurePageCount(testMarkdown);
    } catch (e) {
      print('[_testRenderPageCount PublisherLayoutEngine Error] $e');
      try {
        return await measurePublisherPages(testMarkdown);
      } catch (_) {
        return 0;
      }
    }
  }

  /// Resolves all candidate letter metadata and dimension metadata with internal caching for fanzines and image assets.
  static Future<List<HistoricalLetterEntry>> _resolveLetterEntriesBatch(
      List<Map<String, dynamic>> rawComments, {
        Map<String, Map<String, dynamic>>? imageMetadataCache,
      }) async {
    final Map<String, Map<String, dynamic>> fanzineCache = {};
    final Map<String, String> imageCache = {};
    final Set<String> fzIdsToFetch = {};
    final Set<String> imgIdsToFetch = {};

    for (var raw in rawComments) {
      final contextMap = raw['context'] is Map
          ? (raw['context'] as Map<String, dynamic>)
          : {};
      final fzId = (contextMap['fanzineId'] ?? '').toString();
      final imgId = (raw['contentId'] ?? '').toString();
      if (fzId.isNotEmpty &&
          !UnsavedFanzineRegistry.fanzines.containsKey(fzId)) {
        fzIdsToFetch.add(fzId);
      }
      if (imgId.isNotEmpty) {
        imgIdsToFetch.add(imgId);
      }
    }

    final List<Future<void>> parallelFetches = [];
    for (var fzId in fzIdsToFetch) {
      parallelFetches.add(
        fsGetDoc('fanzines/$fzId').then((fzRes) {
          try {
            final doc = jsonDecode(fzRes);
            if (doc['exists'] == true) {
              fanzineCache[fzId] =
                  doc['data'] as Map<String, dynamic>? ?? {};
            }
          } catch (_) {}
        }),
      );
    }
    for (var imgId in imgIdsToFetch) {
      parallelFetches.add(
        fsGetDoc('images/$imgId').then((imgRes) {
          try {
            final doc = jsonDecode(imgRes);
            if (doc['exists'] == true) {
              final d = doc['data'] as Map<String, dynamic>? ?? {};
              if (imageMetadataCache != null) {
                imageMetadataCache[imgId] = d;
              }
              final url = d['fileUrl'] ??
                  d['listUrl'] ??
                  d['gridUrl'] ??
                  d['imageUrl'];
              if (url != null && url.toString().isNotEmpty) {
                imageCache[imgId] = url.toString();
              }
            }
          } catch (_) {}
        }),
      );
    }
    if (parallelFetches.isNotEmpty) {
      await Future.wait(parallelFetches);
    }

    final List<HistoricalLetterEntry> entries = [];
    for (var raw in rawComments) {
      final dist = (raw['_calculatedDistanceMiles'] as num?)?.toDouble();
      final entry =
      HistoricalLetterEntry.fromCommentMap(raw, distanceMiles: dist);
      String resolvedTitle = entry.fanzineTitle;
      String? resolvedVolume = entry.volume;
      String? resolvedIssue = entry.issue;
      String? resolvedCover = entry.coverImageUrl;
      String? resolvedPubDate = entry.publishedDate;
      String? resolvedShortCode = entry.fanzineShortCode;
      String? resolvedPageUrl = entry.pageImageUrl;

      if ((resolvedPageUrl == null || resolvedPageUrl.isEmpty) &&
          entry.imageId != null &&
          imageCache.containsKey(entry.imageId)) {
        resolvedPageUrl = imageCache[entry.imageId];
      }

      if (entry.fanzineId.isNotEmpty) {
        if (UnsavedFanzineRegistry.fanzines.containsKey(entry.fanzineId)) {
          final fz = UnsavedFanzineRegistry.fanzines[entry.fanzineId]!;
          resolvedTitle = fz.title;
          resolvedVolume ??= fz.volume;
          resolvedIssue ??= fz.issue;
          resolvedShortCode ??= fz.shortCode;
          resolvedPubDate ??= fz.publishedDate;
          final pgs =
              UnsavedFanzineRegistry.pages[entry.fanzineId] ?? [];
          if (pgs.isNotEmpty) {
            resolvedCover ??= pgs.first.gridUrl ?? pgs.first.imageUrl;
          }
        } else if (fanzineCache.containsKey(entry.fanzineId)) {
          final fzData = fanzineCache[entry.fanzineId]!;
          resolvedTitle = fzData['title'] ?? resolvedTitle;
          resolvedVolume ??= fzData['volume']?.toString();
          resolvedIssue ??= fzData['issue']?.toString();
          resolvedShortCode ??= fzData['shortCode'];
          resolvedPubDate ??= fzData['publishedDate'];
          resolvedCover ??= fzData['gridCoverImage'];
        }
      }

      entries.add(HistoricalLetterEntry(
        commentId: entry.commentId,
        fanzineId: entry.fanzineId,
        fanzineTitle: resolvedTitle,
        volume: resolvedVolume,
        issue: resolvedIssue,
        fanzineShortCode: resolvedShortCode,
        coverImageUrl: resolvedCover,
        publishedDate: resolvedPubDate,
        imageId: entry.imageId,
        pageImageUrl: resolvedPageUrl,
        pageNumber: entry.pageNumber,
        letterText: entry.letterText,
        authorName: entry.authorName,
        authorHandle: entry.authorHandle,
        location: entry.location,
        distanceMiles: dist,
      ));
    }
    return entries;
  }

  /// Orchestrates geocoding, candidate spatial querying, parallel metadata resolution,
  /// two-way convergence layout fitting, chronological sorting, map cover generation, and compiles publisher pages.
  static Future<RadiusFolioResult> buildFolio({
    required String targetAddress,
    int targetPages = 4,
    bool hasMapCover = false,
    int? radiusMiles,
    required String ownerUserId,
    String? shortCode,
    void Function(String statusMessage)? onProgress,
  }) async {
    final cleanTargetAddr = targetAddress.trim();
    if (cleanTargetAddr.isEmpty) {
      throw Exception('Please enter an address or city.');
    }

    // When hasMapCover is true, exactly 1 page is the map cover; the rest must be letter content.
    final int contentPagesCount =
    hasMapCover ? math.max(1, targetPages - 1) : targetPages;

    // 1. Geocode Target Center Address
    print(
        '[AddressRadiusLetters] Step 1: Geocoding center address "$cleanTargetAddr"...');
    onProgress?.call('Geocoding center address...');
    final targetCoords = await _geocodeTarget(cleanTargetAddr);
    if (targetCoords == null) {
      throw Exception(
          'Unable to geocode "$cleanTargetAddr". Please check the address or city name.');
    }
    final double targetLat = targetCoords['lat'] as double;
    final double targetLng = targetCoords['lng'] as double;
    final String formattedCenter =
        targetCoords['formatted'] as String? ?? cleanTargetAddr;
    print(
        '[AddressRadiusLetters] Target coordinates: $targetLat, $targetLng ($formattedCenter)');

    // 2. Fetch nearest candidate letters (broad pool to guarantee full page coverage)
    final int candidateLimit = (contentPagesCount * 6).clamp(32, 160);
    onProgress?.call('Querying closest candidate letters...');
    final candidateLetters = await _fetchNearestLetters(
      lat: targetLat,
      lng: targetLng,
      limit: candidateLimit,
      maxRadiusMiles: radiusMiles?.toDouble() ?? 5000.0,
    );
    if (candidateLetters.isEmpty) {
      throw Exception(
          'No historical letters found near $cleanTargetAddr.');
    }
    print(
        '[AddressRadiusLetters] Found ${candidateLetters.length} candidate letters. Resolving metadata in parallel...');
    onProgress?.call('Resolving letter metadata...');
    final Map<String, Map<String, dynamic>> imageMetadataCache = {};
    final resolvedEntries =
    await _resolveLetterEntriesBatch(candidateLetters, imageMetadataCache: imageMetadataCache);

    // Build complete pool of candidate radius letters ordered by proximity (closest first)
    final List<_SelectedRadiusLetter> allCandidates = [];
    for (int i = 0; i < resolvedEntries.length; i++) {
      final entry = resolvedEntries[i];
      final raw = candidateLetters[i];
      final pageMeta = entry.imageId != null ? imageMetadataCache[entry.imageId] : null;

      // Construct markdown preserving natural dimensions and aspect ratios
      final letterMd = buildLetterMarkdown(
        entry,
        pageMetadata: pageMeta,
      );
      final dist =
          (raw['_calculatedDistanceMiles'] as num?)?.toDouble() ?? 0.0;
      final pubDate = parseHistoricalDate(
        raw['historicalDate'] ??
            (raw['context'] is Map
                ? raw['context']['publishedDate']
                : null),
        letterMd,
      );
      final estHeight = estimateMarkdownHeight(letterMd);
      allCandidates.add(_SelectedRadiusLetter(
        entry: entry,
        raw: raw,
        markdown: letterMd,
        distance: dist,
        publishedDate: pubDate,
        estimatedHeight: estHeight,
      ));
    }

    print(
        '[AddressRadiusLetters] Successfully resolved ${allCandidates.length} entries. Performing two-way convergence fitting for $contentPagesCount letter ${contentPagesCount == 1 ? "page" : "pages"}...');
    onProgress?.call(
        'Fitting letters to $contentPagesCount letter ${contentPagesCount == 1 ? "page" : "pages"}...');

    // Phase 1: Generous initial estimate to reach full page capacity
    final double targetCapacityPixels =
        contentPagesCount * kTotalPageHeight;
    double accumulatedEstPixels = 0.0;
    final List<_SelectedRadiusLetter> selectedLetters = [];
    int candidateIndex = 0;

    for (int i = 0; i < allCandidates.length; i++) {
      final letter = allCandidates[i];
      selectedLetters.add(letter);
      accumulatedEstPixels += letter.estimatedHeight;
      candidateIndex = i + 1;
      if (accumulatedEstPixels >= targetCapacityPixels) {
        break;
      }
    }
    if (selectedLetters.isEmpty && allCandidates.isNotEmpty) {
      selectedLetters.add(allCandidates.first);
      candidateIndex = 1;
    }

    // Phase 2: Exact Two-Way Canvas Convergence
    int renderedPages = await _testRenderPageCount(selectedLetters);
    print(
        '[AddressRadiusLetters] Initial measurement test: $renderedPages pages (Target: $contentPagesCount)');

    // Part A: Grow upwards if under-packed
    while (renderedPages < contentPagesCount &&
        candidateIndex < allCandidates.length) {
      selectedLetters.add(allCandidates[candidateIndex]);
      candidateIndex++;
      renderedPages = await _testRenderPageCount(selectedLetters);
      print(
          '[AddressRadiusLetters] Grew pool to ${selectedLetters.length} letters -> $renderedPages pages');
    }

    // Part B: Trim downwards if over-packed
    while (renderedPages > contentPagesCount && selectedLetters.length > 1) {
      selectedLetters.removeLast();
      renderedPages = await _testRenderPageCount(selectedLetters);
      print(
          '[AddressRadiusLetters] Trimmed pool to ${selectedLetters.length} letters -> $renderedPages pages');
    }

    // Part C: Fine-tuning - If trimming dropped below target, try subsequent smaller candidates
    if (renderedPages < contentPagesCount &&
        candidateIndex < allCandidates.length) {
      for (int i = candidateIndex; i < allCandidates.length; i++) {
        selectedLetters.add(allCandidates[i]);
        final testCount = await _testRenderPageCount(selectedLetters);
        if (testCount == contentPagesCount) {
          renderedPages = testCount;
          print(
              '[AddressRadiusLetters] Fine-tuned exact match: ${selectedLetters.length} letters -> $renderedPages pages');
          break;
        } else if (testCount > contentPagesCount) {
          selectedLetters.removeLast();
        } else {
          renderedPages = testCount;
        }
      }
    }

    print(
        '[AddressRadiusLetters] Final letter pool selected: ${selectedLetters.length} letters rendering to $renderedPages pages.');

    // Phase 3: Final Chronological Ordering (Oldest to Newest)
    selectedLetters.sort((a, b) {
      final dateComp = a.publishedDate.compareTo(b.publishedDate);
      if (dateComp != 0) return dateComp;
      return a.distance.compareTo(b.distance);
    });

    final sortedBuffer = StringBuffer();
    for (final item in selectedLetters) {
      sortedBuffer.write(item.markdown);
      sortedBuffer.writeln();
    }
    final fullText = sortedBuffer.toString().trim();
    final fanzineId = 'folio_${DateTime.now().millisecondsSinceEpoch}';
    final List<FanzinePage> finalPages = [];
    String? coverImageUrl;

    // 5. Generate Map Cover Page (If enabled)
    if (hasMapCover) {
      print(
          '[AddressRadiusLetters] Step 5: Rendering 2000x3200 Google Maps Cover page...');
      onProgress?.call('Drawing high-resolution map cover...');
      final List<Map<String, dynamic>> mapLettersPayload = [];
      for (int i = 0; i < selectedLetters.length; i++) {
        final item = selectedLetters[i];
        final raw = item.raw;
        final geo = raw['geo'] is Map ? (raw['geo'] as Map) : {};
        final context = raw['context'] is Map ? (raw['context'] as Map) : {};
        mapLettersPayload.add({
          'index': i + 1,
          'displayName': raw['displayName'] ?? 'Reader',
          'location': raw['location'] ?? '',
          'distanceMiles': item.distance,
          'publicationTitle':
          context['fanzineTitle'] ?? 'Archival Fanzine',
          'issueDate': raw['historicalDate'] ?? '',
          'lat': geo['lat'],
          'lng': geo['lng'],
        });
      }

      final mapCoverConfig = {
        'fanzineId': fanzineId,
        'ownerUserId': ownerUserId,
        'title': 'Letters near $cleanTargetAddr',
        'center': {
          'address': formattedCenter,
          'lat': targetLat,
          'lng': targetLng,
        },
        'letters': mapLettersPayload,
        'shortCode': shortCode ?? ShortcodeGenerator.generateStandardCode(),
      };

      // 5.A: Primary Server-Side Cloud Function Map Cover Compilation
      try {
        final resStr =
        await fnCall('compile_map_cover', jsonEncode(mapCoverConfig));
        final decoded = jsonDecode(resStr);
        if (decoded is Map &&
            decoded['status'] == 'success' &&
            decoded['coverPage'] is Map) {
          final cpMap = Map<String, dynamic>.from(decoded['coverPage'] as Map);
          final coverPage = FanzinePage.fromMap(
              cpMap['id']?.toString() ?? '${fanzineId}_page_1', cpMap);
          coverImageUrl = coverPage.imageUrl;
          finalPages.add(coverPage);
          print(
              '[AddressRadiusLetters] Map cover published server-side as Page 1.');
        }
      } catch (e) {
        print(
            '[AddressRadiusLetters] Server compile_map_cover error, falling back to client: $e');
      }

      // 5.B: Client Fallback if Server Function is offline
      if (finalPages.isEmpty) {
        try {
          final coverJson =
          await renderMapCoverPage(jsonEncode(mapCoverConfig));
          final coverData = jsonDecode(coverJson) as Map<String, dynamic>;
          onProgress?.call('Publishing map cover image...');
          final origBytes = base64Decode(coverData['original'] as String);
          final listBytes = base64Decode(coverData['list'] as String);
          final gridBytes = base64Decode(coverData['grid'] as String);

          final coverUrls = await Future.wait([
            stUpload(
                'fanzines/$fanzineId/page_1.webp', origBytes, 'image/webp'),
            stUpload('fanzines/$fanzineId/page_1_list.webp', listBytes,
                'image/webp'),
            stUpload('fanzines/$fanzineId/page_1_grid.webp', gridBytes,
                'image/webp'),
          ]);
          coverImageUrl = coverUrls[0];
          final coverImageId = 'map_cover_${fanzineId}_1';

          final coverMetadata = {
            'uid': ownerUserId,
            'uploaderId': ownerUserId,
            'type': 'template',
            'templateId': 'map_cover',
            'title': 'Map Cover',
            'isGenerated': true,
            'width': 2000,
            'height': 3200,
            'aspectRatio': 0.625,
            'is5x8': true,
            'shortCode':
            shortCode ?? ShortcodeGenerator.generateStandardCode(),
            'folioContext': fanzineId,
            'usedInFanzines': [fanzineId],
            'fileUrl': coverUrls[0],
            'listUrl': coverUrls[1],
            'gridUrl': coverUrls[2],
          };
          await fsSetDoc(
              'images/$coverImageId', jsonEncode(coverMetadata), true);

          final coverPage = FanzinePage(
            id: '${fanzineId}_page_1',
            pageNumber: 1,
            imageId: coverImageId,
            imageUrl: coverUrls[0],
            gridUrl: coverUrls[2],
            listUrl: coverUrls[1],
            templateId: 'map_cover',
            width: 2000,
            height: 3200,
            is5x8: true,
            status: 'ready',
          );
          finalPages.add(coverPage);
          print(
              '[AddressRadiusLetters] Map cover published via client fallback as Page 1.');
        } catch (e, stack) {
          print(
              '[AddressRadiusLetters] Failed client map cover fallback: $e\n$stack');
        }
      }
    }

    // 6. Compile Content Pages via Server-Side Cloud Function
    print(
        '[AddressRadiusLetters] Compiling and publishing final folio text pages...');
    onProgress?.call('Compiling publisher text pages...');
    final int startPageNum = hasMapCover && finalPages.isNotEmpty ? 2 : 1;
    final List<FanzinePage> contentPages =
    await PublisherCompiler.compileAndPublishMultiPage(
      fanzineId: fanzineId,
      fullText: fullText,
      startPageNumber: startPageNum,
      onProgress: (current, total) {
        onProgress?.call(
            'Compiling publisher text page $current of $total...');
      },
    );

    // Hard clamp: Ensure the number of content pages never exceeds contentPagesCount
    final int pageOffset = hasMapCover && finalPages.isNotEmpty ? 1 : 0;
    final int pagesToTake =
    math.min(contentPages.length, contentPagesCount);
    for (int i = 0; i < pagesToTake; i++) {
      final cp = contentPages[i];
      final targetPageNum = i + 1 + pageOffset;
      finalPages.add(FanzinePage(
        id: '${fanzineId}_page_$targetPageNum',
        pageNumber: targetPageNum,
        imageId: cp.imageId,
        imageUrl: cp.imageUrl,
        gridUrl: cp.gridUrl,
        listUrl: cp.listUrl,
        status: cp.status,
        templateId: cp.templateId ?? 'basic_text',
        width: cp.width,
        height: cp.height,
        is5x8: true,
      ));
    }

    final String folioTitle = targetPages == 24
        ? 'Letters near $cleanTargetAddr (Full Fanzine)'
        : 'Letters near $cleanTargetAddr';

    final newFanzine = Fanzine(
      id: fanzineId,
      title: folioTitle,
      ownerId: ownerUserId,
      curators: [ownerUserId],
      collections: [ownerUserId],
      type: FanzineType.folio,
      isLive: false,
      processingStatus: 'complete',
      shortCode: shortCode,
      twoPage: true,
      hasCover: hasMapCover && coverImageUrl != null && finalPages.isNotEmpty,
    );

    print(
        '[AddressRadiusLetters] Build completed successfully. Generated exactly ${finalPages.length} total pages (Requested: $targetPages).');
    return RadiusFolioResult(fanzine: newFanzine, pages: finalPages);
  }
}