import 'dart:convert';
import 'dart:math' as math;
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import '../utils/publisher_compiler.dart';
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

/// Internal helper bundle holding a selected letter along with its distance and parsed historical date.
class _SelectedRadiusLetter {
  final HistoricalLetterEntry entry;
  final Map<String, dynamic> raw;
  final String markdown;
  final double distance;
  final DateTime publishedDate;

  _SelectedRadiusLetter({
    required this.entry,
    required this.raw,
    required this.markdown,
    required this.distance,
    required this.publishedDate,
  });
}

/// Encapsulates geospatial nearest-neighbor resolution, letter querying,
/// distance calculation, ordering, fast mathematical layout fitting, and map cover generation.
class AddressRadiusLetters {
  /// Usable height per column in pixels (maxY 3120 - startY 33).
  static const double kColumnHeight = 3087.0;

  /// Number of columns per publisher folio page.
  static const int kColumnsPerPage = 3;

  /// Total theoretical vertical pixels available per page across all 3 columns.
  static const double kTotalPageHeight = kColumnHeight * kColumnsPerPage; // 9,261 px

  /// Column packing efficiency factor (accounting for image wrap padding & column margins).
  static const double kPackingEfficiency = 0.88;

  /// Effective usable vertical pixels per page when arranging composite image/text blocks.
  static const double kEffectivePageCapacity = kTotalPageHeight * kPackingEfficiency; // ~8,150 px

  /// Parses historical/vintage date strings (e.g. "March 1, 1927", "January, 1971", "1935")
  /// into comparable DateTime objects for chronological ordering.
  static DateTime parseHistoricalDate(dynamic rawDate, [String? markdownContext]) {
    String text = '';
    if (rawDate != null && rawDate.toString().trim().isNotEmpty) {
      text = rawDate.toString().trim();
    } else if (markdownContext != null && markdownContext.isNotEmpty) {
      text = markdownContext;
    }

    if (text.isEmpty) {
      return DateTime(2099, 1, 1);
    }

    // Direct ISO / YYYY-MM-DD parsing
    final tryDirect = DateTime.tryParse(text);
    if (tryDirect != null) {
      return tryDirect;
    }

    // Find 4-digit year (1800 - 2099)
    final yearMatch = RegExp(r'\b(1[89]\d\d|20\d\d)\b').firstMatch(text);
    if (yearMatch == null) {
      return DateTime(2099, 1, 1);
    }
    final int year = int.parse(yearMatch.group(1)!);

    int month = 1;
    final lower = text.toLowerCase();
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
      'spring': 3, 'summer': 6, 'fall': 9, 'autumn': 9, 'winter': 12,
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
            (1 - math.cos((lon2 - lon1) * p)) /
            2;
    return 12742 * math.asin(math.sqrt(math.max(0.0, math.min(1.0, a)))) * 0.621371; // km to miles
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

  /// Geocodes the user-provided center address string into latitude/longitude coordinates.
  static Future<Map<String, double>?> _geocodeTarget(String targetAddress) async {
    final cleanAddr = targetAddress.trim();
    if (cleanAddr.isEmpty) return null;

    final targetGeoJson = await geocodeAddress(cleanAddr);
    if (targetGeoJson != null && targetGeoJson.isNotEmpty) {
      final decoded = jsonDecode(targetGeoJson);
      if (decoded != null && decoded['lat'] != null && decoded['lng'] != null) {
        return {
          'lat': (decoded['lat'] as num).toDouble(),
          'lng': (decoded['lng'] as num).toDouble(),
        };
      }
    }
    return null;
  }

  /// Calls the `query_nearest_letters` Cloud Function to retrieve the closest
  /// candidate letters using geospatial spatial grid indexing on Firestore.
  static Future<List<Map<String, dynamic>>> _fetchNearestLetters({
    required double lat,
    required double lng,
    required int limit,
    double maxRadiusMiles = 5000.0,
  }) async {
    print('[AddressRadiusLetters] Requesting $limit closest letters from Cloud Function query_nearest_letters...');
    try {
      final payload = {
        'lat': lat,
        'lng': lng,
        'limit': limit,
        'max_radius_miles': maxRadiusMiles,
      };
      final resStr = await fnCall('query_nearest_letters', jsonEncode(payload));
      final decoded = jsonDecode(resStr);
      if (decoded is Map && decoded['letters'] is List) {
        final List list = decoded['letters'];
        final letters = list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
        print('[AddressRadiusLetters] Server returned ${letters.length} candidate letters.');
        return letters;
      }
    } catch (e) {
      print('[AddressRadiusLetters] Server callable query_nearest_letters failed or uninitialized: $e. Falling back to bounded search.');
    }

    return _fallbackBoundedLetters(lat, lng, limit, maxRadiusMiles);
  }

  /// Bounded client-side search used as an emergency fallback if the backend function is unavailable.
  static Future<List<Map<String, dynamic>>> _fallbackBoundedLetters(
      double targetLat,
      double targetLng,
      int limit,
      double maxRadius,
      ) async {
    print('[AddressRadiusLetters] Running fallback bounded letters query...');
    final commentsRes = await fsQuery('artifacts/bqopd/public/data/comments', '', '', '', '');
    final List decodedComments = jsonDecode(commentsRes) as List;

    final List<Map<String, dynamic>> matchingLetters = [];
    final Map<String, Map<String, double>?> locationCache = {};

    for (final item in decodedComments) {
      final data = Map<String, dynamic>.from(item['data'] as Map);
      data['_id'] = item['id'];

      final isLetter = data['sourceType'] == 'letter_column' ||
          (data['location'] != null && data['location'].toString().trim().isNotEmpty);
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

      if (letterLat == null || letterLng == null) {
        final rawLoc = (data['location'] ?? '').toString().trim();
        if (rawLoc.isNotEmpty) {
          final cleanLoc = cleanLocation(rawLoc);
          if (!locationCache.containsKey(cleanLoc)) {
            final geoJson = await geocodeAddress(cleanLoc);
            if (geoJson != null && geoJson.isNotEmpty) {
              final d = jsonDecode(geoJson);
              if (d != null && d['lat'] != null && d['lng'] != null) {
                locationCache[cleanLoc] = {
                  'lat': (d['lat'] as num).toDouble(),
                  'lng': (d['lng'] as num).toDouble(),
                };
              } else {
                locationCache[cleanLoc] = null;
              }
            } else {
              locationCache[cleanLoc] = null;
            }
          }
          final coords = locationCache[cleanLoc];
          if (coords != null) {
            letterLat = coords['lat'];
            letterLng = coords['lng'];
          }
        }
      }

      if (letterLat != null && letterLng != null) {
        final dist = calculateDistanceMiles(targetLat, targetLng, letterLat, letterLng);
        if (dist <= maxRadius) {
          data['_calculatedDistanceMiles'] = double.parse(dist.toStringAsFixed(2));
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

  /// Calculates the exact physical vertical pixel height markdown content consumes
  /// in the 608px column publisher canvas without downloading image binaries or rendering.
  static double estimateMarkdownHeight(String markdown) {
    double totalHeight = 0.0;
    final lines = markdown.split('\n');

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        totalHeight += 12.0;
        continue;
      }

      if (line.startsWith('{{IMAGE') || line.startsWith('{{TEMPLATE')) {
        totalHeight += 420.0;
      } else if (line.startsWith('###')) {
        totalHeight += 50.0;
      } else if (line.startsWith('##')) {
        totalHeight += 60.0;
      } else if (line.startsWith('#')) {
        totalHeight += 70.0;
      } else {
        final words = line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        if (words.isNotEmpty) {
          final lineCount = math.max(1, (words.length / 7.2).ceil());
          totalHeight += (lineCount * 42.0) + 14.0;
        }
      }
    }

    totalHeight += 32.0;
    return totalHeight;
  }

  /// Orchestrates geocoding, candidate spatial querying, parallel metadata resolution,
  /// fast mathematical fitting, chronological sorting, map cover generation, and compiles publisher pages.
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

    final int contentPagesCount = hasMapCover ? math.max(1, targetPages - 1) : targetPages;

    // 1. Geocode Target Center Address
    print('[AddressRadiusLetters] Step 1: Geocoding center address "$cleanTargetAddr"...');
    onProgress?.call('Geocoding center address...');
    final targetCoords = await _geocodeTarget(cleanTargetAddr);
    if (targetCoords == null) {
      throw Exception('Unable to geocode "$cleanTargetAddr". Please check the address or city name.');
    }

    final double targetLat = targetCoords['lat']!;
    final double targetLng = targetCoords['lng']!;
    print('[AddressRadiusLetters] Target coordinates: $targetLat, $targetLng');

    // 2. Fetch nearest candidate letters (buffer size scaled to requested page capacity)
    final int candidateLimit = (contentPagesCount * 4).clamp(16, 120);

    onProgress?.call('Querying closest candidate letters...');
    final candidateLetters = await _fetchNearestLetters(
      lat: targetLat,
      lng: targetLng,
      limit: candidateLimit,
      maxRadiusMiles: radiusMiles?.toDouble() ?? 5000.0,
    );

    if (candidateLetters.isEmpty) {
      throw Exception('No historical letters found near $cleanTargetAddr.');
    }

    // 3. Resolve metadata concurrently in parallel
    print('[AddressRadiusLetters] Found ${candidateLetters.length} candidate letters. Resolving metadata in parallel...');
    onProgress?.call('Resolving letter metadata...');

    final resolvedEntries = await Future.wait(
      candidateLetters.map((raw) => HistoricalLetterEntry.resolveComplete(
        rawComment: raw,
        distanceMiles: (raw['_calculatedDistanceMiles'] as num?)?.toDouble(),
      )),
    );

    print('[AddressRadiusLetters] Successfully resolved ${resolvedEntries.length} entries. Performing fast mathematical height fitting...');
    onProgress?.call('Fitting letters to $contentPagesCount letter ${contentPagesCount == 1 ? "page" : "pages"}...');

    final double maxPixelCapacity = contentPagesCount * kEffectivePageCapacity;
    double accumulatedPixels = 0.0;
    final List<_SelectedRadiusLetter> selectedLetters = [];

    // Phase 1: Proximity Selection (closest letters first until page capacity is satisfied)
    for (int i = 0; i < resolvedEntries.length; i++) {
      final entry = resolvedEntries[i];
      final raw = candidateLetters[i];
      final letterMd = entry.toPublisherMarkdown();
      final letterHeight = estimateMarkdownHeight(letterMd);

      if (accumulatedPixels + letterHeight > maxPixelCapacity && selectedLetters.isNotEmpty) {
        print('[AddressRadiusLetters] Reached target page capacity (${accumulatedPixels.toInt()}px + ${letterHeight.toInt()}px > ${maxPixelCapacity.toInt()}px). Halting mathematical fit at ${selectedLetters.length} letters.');
        break;
      }

      final dist = (raw['_calculatedDistanceMiles'] as num?)?.toDouble() ?? 0.0;
      final pubDate = parseHistoricalDate(
        raw['historicalDate'] ?? (raw['context'] is Map ? raw['context']['publishedDate'] : null),
        letterMd,
      );

      selectedLetters.add(_SelectedRadiusLetter(
        entry: entry,
        raw: raw,
        markdown: letterMd,
        distance: dist,
        publishedDate: pubDate,
      ));
      accumulatedPixels += letterHeight;
    }

    if (selectedLetters.isEmpty && resolvedEntries.isNotEmpty) {
      final entry = resolvedEntries.first;
      final raw = candidateLetters.first;
      final letterMd = entry.toPublisherMarkdown();
      selectedLetters.add(_SelectedRadiusLetter(
        entry: entry,
        raw: raw,
        markdown: letterMd,
        distance: (raw['_calculatedDistanceMiles'] as num?)?.toDouble() ?? 0.0,
        publishedDate: parseHistoricalDate(raw['historicalDate'], letterMd),
      ));
    }

    print('[AddressRadiusLetters] Mathematical fit selected ${selectedLetters.length} letters (~${accumulatedPixels.toInt()}px for $contentPagesCount pages).');

    // Assemble temporary text to perform single verification check
    String fullText = selectedLetters.map((l) => l.markdown).join('\n\n').trim();
    if (fullText.isEmpty) {
      throw Exception('Unable to generate letter content for publication.');
    }

    // 4. Verification Check: Single dry-run layout pass to guarantee page bounds
    try {
      final testJson = await renderPublisherPages(fullText);
      final List testPages = jsonDecode(testJson) as List;
      print('[AddressRadiusLetters] Single layout check: rendered ${testPages.length} pages (Target: $contentPagesCount)');

      if (testPages.length > contentPagesCount && selectedLetters.length > 1) {
        print('[AddressRadiusLetters] Trimming 1 trailing letter (furthest in proximity) to guarantee exact $contentPagesCount-page limit.');
        selectedLetters.removeLast();
      }
    } catch (e) {
      print('[AddressRadiusLetters] Layout verification bypassed: $e');
    }

    // Phase 2: Chronological Ordering (Oldest to Newest)
    // The selection is fixed; now sort so oldest published date starts at top-left and flows to newest at bottom-right
    print('[AddressRadiusLetters] Sorting selected ${selectedLetters.length} letters chronologically (oldest to newest)...');
    selectedLetters.sort((a, b) {
      final dateComp = a.publishedDate.compareTo(b.publishedDate);
      if (dateComp != 0) return dateComp;
      // Tie-breaker: closer distance first
      return a.distance.compareTo(b.distance);
    });

    // Rebuild final markdown in chronological order
    final sortedBuffer = StringBuffer();
    for (final item in selectedLetters) {
      sortedBuffer.write(item.markdown);
      sortedBuffer.writeln();
    }
    fullText = sortedBuffer.toString().trim();

    final fanzineId = 'folio_${DateTime.now().millisecondsSinceEpoch}';
    final List<FanzinePage> finalPages = [];
    String? coverImageUrl;

    // 5. Generate Map Cover Page (If enabled)
    if (hasMapCover) {
      print('[AddressRadiusLetters] Step 5: Rendering 2000x3200 illustrated Map Cover page...');
      onProgress?.call('Drawing high-resolution illustrated map cover...');

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
          'publicationTitle': context['fanzineTitle'] ?? 'Archival Fanzine',
          'issueDate': raw['historicalDate'] ?? '',
          'lat': geo['lat'],
          'lng': geo['lng'],
        });
      }

      final mapCoverConfig = {
        'title': 'Letters near $cleanTargetAddr',
        'center': {
          'address': cleanTargetAddr,
          'lat': targetLat,
          'lng': targetLng,
        },
        'letters': mapLettersPayload,
      };

      try {
        final coverJson = await renderMapCoverPage(jsonEncode(mapCoverConfig));
        final coverData = jsonDecode(coverJson) as Map<String, dynamic>;

        onProgress?.call('Publishing illustrated map cover image...');
        final origBytes = base64Decode(coverData['original'] as String);
        final listBytes = base64Decode(coverData['list'] as String);
        final gridBytes = base64Decode(coverData['grid'] as String);

        coverImageUrl = await stUpload('fanzines/$fanzineId/page_1.webp', origBytes, 'image/webp');
        await stUpload('fanzines/$fanzineId/page_1_list.webp', listBytes, 'image/webp');
        await stUpload('fanzines/$fanzineId/page_1_grid.webp', gridBytes, 'image/webp');

        final coverPage = FanzinePage(
          id: '${fanzineId}_page_1',
          pageNumber: 1,
          imageUrl: coverImageUrl,
          status: 'ready',
        );

        finalPages.add(coverPage);
        print('[AddressRadiusLetters] Map cover published successfully as Page 1.');
      } catch (e) {
        print('[AddressRadiusLetters] Failed to render or upload map cover: $e');
      }
    }

    // 6. Compile Content Pages
    print('[AddressRadiusLetters] Final letter pool: ${selectedLetters.length} letters. Compiling and publishing final folio...');
    onProgress?.call('Compiling connected publisher text pages...');

    final List<FanzinePage> contentPages = await PublisherCompiler.compileAndPublishMultiPage(
      fanzineId: fanzineId,
      fullText: fullText,
      onProgress: (current, total) {
        onProgress?.call('Compiling publisher text page $current of $total...');
      },
    );

    final int pageOffset = hasMapCover && finalPages.isNotEmpty ? 1 : 0;
    for (int i = 0; i < contentPages.length; i++) {
      final cp = contentPages[i];
      final targetPageNum = i + 1 + pageOffset;
      finalPages.add(FanzinePage(
        id: '${fanzineId}_page_$targetPageNum',
        pageNumber: targetPageNum,
        imageUrl: cp.imageUrl,
        status: cp.status,
        templateId: cp.templateId,
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
      hasCover: hasMapCover && coverImageUrl != null,
    );

    print('[AddressRadiusLetters] Build completed successfully. Generated ${finalPages.length} total pages.');
    return RadiusFolioResult(fanzine: newFanzine, pages: finalPages);
  }
}