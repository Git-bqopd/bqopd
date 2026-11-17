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

/// Resolved Firestore profile identity + mailing address for a historical letter writer.
class _ResolvedAuthorIdentity {
  final String? uid;
  final String? username;
  final String displayName;
  final String fullMailingAddress;

  const _ResolvedAuthorIdentity({
    this.uid,
    this.username,
    required this.displayName,
    this.fullMailingAddress = '',
  });

  bool get isLinked => uid != null && uid!.isNotEmpty;
}

/// Internal helper bundle holding a selected letter along with its distance, parsed date, and precalculated height.
class _SelectedRadiusLetter {
  final HistoricalLetterEntry entry;
  final Map<String, dynamic> raw;
  final _ResolvedAuthorIdentity author;
  final String markdown;
  final double distance;
  final DateTime publishedDate;
  final double estimatedHeight;

  _SelectedRadiusLetter({
    required this.entry,
    required this.raw,
    required this.author,
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

  /// Normalizes a display name or handle into a lowercase underscore-delimited handle
  /// (e.g. `"Phil Seuling"` -> `"phil_seuling"`).
  static String _normalizeUnderscoreHandle(String input) {
    return input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  /// Normalizes a display name or handle into a hyphenated handle candidate
  /// (e.g. `"Phil Seuling"` -> `"phil-seuling"`).
  static String _normalizeHyphenHandle(String input) {
    return input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  /// Normalizes a display name or handle into a compact alphanumeric handle
  /// (e.g. `"Phil Seuling"` -> `"philseuling"`).
  static String _normalizeCompactHandle(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Generates all plausible handle candidates for a writer's name or handle,
  /// covering underscore (`phil_seuling`), hyphen (`phil-seuling`), compact (`philseuling`),
  /// and first+last variants when middle names/initials are present.
  static Set<String> _handleCandidatesForName(String input) {
    final clean = input.trim().replaceAll('@', '');
    if (clean.isEmpty) return const {};

    final candidates = <String>{};
    final u = _normalizeUnderscoreHandle(clean);
    final h = _normalizeHyphenHandle(clean);
    final c = _normalizeCompactHandle(clean);
    if (u.isNotEmpty) candidates.add(u);
    if (h.isNotEmpty) candidates.add(h);
    if (c.isNotEmpty) candidates.add(c);

    final words = clean
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase())
        .where((w) => w.isNotEmpty)
        .toList();

    if (words.length >= 3) {
      final firstLast = '${words.first} ${words.last}';
      candidates.add(_normalizeUnderscoreHandle(firstLast));
      candidates.add(_normalizeHyphenHandle(firstLast));
      candidates.add(_normalizeCompactHandle(firstLast));
    }

    candidates.removeWhere((s) => s.isEmpty);
    return candidates;
  }

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

  /// Extracts whatever mailing address parts are stored on a `/profiles/{uid}` document
  /// (`street1`, `street2`, `city`, `state`, `zipCode`, `geo.formatted`, `location`),
  /// falling back to the letter's cleaned location metadata if the profile has no address.
  static String _extractMailingAddressFromProfile(
      Map<String, dynamic>? profileData,
      HistoricalLetterEntry entry,
      Map<String, dynamic> rawComment,
      ) {
    if (profileData != null) {
      final street1 = (profileData['street1'] ?? '').toString().trim();
      final street2 = (profileData['street2'] ?? '').toString().trim();
      final city = (profileData['city'] ?? '').toString().trim();
      final state = (profileData['state'] ?? '').toString().trim();
      final zipCode = (profileData['zipCode'] ?? '').toString().trim();
      final location = (profileData['location'] ?? '').toString().trim();
      final geo = profileData['geo'] is Map ? (profileData['geo'] as Map) : null;
      final geoFormatted = geo?['formatted']?.toString().trim() ?? '';

      final streetPart = [
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

      final fullParts = [
        if (streetPart.isNotEmpty) streetPart,
        if (cityStateZip.isNotEmpty) cityStateZip,
      ];

      if (fullParts.isNotEmpty) {
        return fullParts.join(', ');
      }
      if (geoFormatted.isNotEmpty) {
        return geoFormatted;
      }
      if (location.isNotEmpty) {
        return cleanLocation(location);
      }
    }

    // Fallback to letter comment metadata if profile has no address fields yet
    final commentGeo = rawComment['geo'] is Map ? (rawComment['geo'] as Map) : null;
    final commentGeoFormatted = commentGeo?['formatted']?.toString().trim() ?? '';
    if (commentGeoFormatted.isNotEmpty) {
      return commentGeoFormatted;
    }
    final rawLoc = entry.location?.trim() ?? '';
    if (rawLoc.isNotEmpty) {
      return cleanLocation(rawLoc);
    }
    return '';
  }

  /// Resolves the center target address into geographic coordinates using
  /// the server-verified Cloud Function endpoint with Firestore geocache caching.
  static Future<Map<String, dynamic>?> _geocodeTarget(String targetAddress) async {
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
      print('[AddressRadiusLetters] Server callable query_nearest_letters fallback: $e');
    }
    return _fallbackBoundedLetters(lat, lng, limit, maxRadiusMiles);
  }

  static Future<List<Map<String, dynamic>>> _fallbackBoundedLetters(
      double targetLat,
      double targetLng,
      int limit,
      double maxRadius,
      ) async {
    print('[AddressRadiusLetters] Running fallback bounded letters query over pre-indexed geo data...');
    final commentsRes = await fsQuery(
      'artifacts/bqopd/public/data/comments',
      'sourceType',
      '==',
      jsonEncode('letter_column'),
      '',
    );
    List decodedComments = jsonDecode(commentsRes) as List;
    if (decodedComments.isEmpty) {
      final fallbackRes = await fsQuery('artifacts/bqopd/public/data/comments', '', '', '', '');
      decodedComments = jsonDecode(fallbackRes) as List;
    }
    final List<Map<String, dynamic>> matchingLetters = [];

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
        final words = line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        if (words.isNotEmpty) {
          final lineCount = math.max(1, (words.length / 7.2).ceil());
          totalHeight += (lineCount * rowHeight) + rowHeight;
        }
      }
    }
    totalHeight += rowHeight;
    return totalHeight;
  }

  /// Replaces the first plain-text occurrence of [targetPhrase] outside existing
  /// `[[...]]` blocks with [replacement], returning the updated string and whether
  /// a replacement occurred.
  static ({String text, bool replaced}) _replacePlainTextOutsideWikilinks(
      String source,
      String targetPhrase,
      String replacement,
      ) {
    final cleanPhrase = targetPhrase.trim();
    if (cleanPhrase.isEmpty) {
      return (text: source, replaced: false);
    }

    final pattern = RegExp(
      '(?<![\\w])${RegExp.escape(cleanPhrase)}(?![\\w])',
      caseSensitive: false,
    );

    final parts = source.split(RegExp(r'(\[\[.*?\]\])'));
    final matches = RegExp(r'\[\[.*?\]\]').allMatches(source).toList();
    final buffer = StringBuffer();
    bool replaced = false;

    for (int i = 0; i < parts.length; i++) {
      String segment = parts[i];
      if (!replaced) {
        final m = pattern.firstMatch(segment);
        if (m != null) {
          segment = segment.replaceRange(m.start, m.end, replacement);
          replaced = true;
        }
      }
      buffer.write(segment);
      if (i < matches.length) {
        buffer.write(matches[i].group(0));
      }
    }

    return (text: buffer.toString(), replaced: replaced);
  }

  /// Builds a Markdown representation of a historical letter, embedding the
  /// natural dimensions or aspect ratio for both the fanzine cover and the page scan,
  /// and encoding ONE combined `[[Display Name|user:<uid>|address:<profileAddress>]]`
  /// wikilink per letter writer so each letter produces a single 3-row entity card
  /// (`Name` / `Street` / `City, State ZIP`) that links to the writer's profile
  /// and plots a pin on the Entities column header map.
  static String buildLetterMarkdown(
      HistoricalLetterEntry entry, {
        Map<String, dynamic>? coverMetadata,
        Map<String, dynamic>? pageMetadata,
        String? resolvedAuthorUid,
        String? resolvedAuthorDisplayName,
        String? profileMailingAddress,
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

    // 5. Consolidate writer + profile mailing address into ONE single combined wikilink
    // so there is only 1 entity card per letter writer (displaying Full Name + Address).
    String bodyText = entry.letterText;
    final String rawAuthorName = entry.authorName?.trim() ?? '';
    final String effectiveAuthorName = (resolvedAuthorDisplayName != null &&
        resolvedAuthorDisplayName.trim().isNotEmpty)
        ? resolvedAuthorDisplayName.trim()
        : rawAuthorName;
    final String? uid =
    (resolvedAuthorUid != null && resolvedAuthorUid.trim().isNotEmpty)
        ? resolvedAuthorUid.trim()
        : null;
    final String mailingAddress = (profileMailingAddress ?? '').trim();

    final String rawLoc = entry.location?.trim() ?? '';
    final String cleanedLoc = rawLoc.isNotEmpty ? cleanLocation(rawLoc) : '';
    final Set<String> locationLabelsToUnwrap = {
      if (rawLoc.isNotEmpty) rawLoc.toLowerCase(),
      if (cleanedLoc.isNotEmpty) cleanedLoc.toLowerCase(),
    };

    // Unwrap any standalone location-only wikilinks inside the letter text so we don't
    // emit duplicate address-only cards alongside the writer's combined entity card.
    bodyText = bodyText.replaceAllMapped(RegExp(r'\[\[(.*?)\]\]'), (m) {
      final content = m.group(1) ?? '';
      final parts = content.split('|');
      final firstLabel = parts.isNotEmpty ? parts[0].trim() : '';
      final hasUser = parts.any((p) => p.trim().startsWith('user:'));
      final hasAddr = parts.any((p) => p.trim().startsWith('address:'));
      if (!hasUser &&
          (hasAddr || locationLabelsToUnwrap.contains(firstLabel.toLowerCase()))) {
        return firstLabel;
      }
      return m.group(0)!;
    });

    final String entityLabel = effectiveAuthorName.isNotEmpty
        ? effectiveAuthorName
        : (mailingAddress.isNotEmpty ? mailingAddress : '');

    if (entityLabel.isNotEmpty) {
      final tagParts = <String>[entityLabel];
      if (uid != null) {
        tagParts.add('user:$uid');
      }
      if (mailingAddress.isNotEmpty) {
        tagParts.add('address:$mailingAddress');
      }
      final String combinedWikilink = '[[${tagParts.join('|')}]]';

      final candidateAuthorLabels = <String>{
        if (effectiveAuthorName.isNotEmpty) effectiveAuthorName.toLowerCase(),
        if (rawAuthorName.isNotEmpty) rawAuthorName.toLowerCase(),
      };

      // Upgrade any existing author wikilink in the body to the combined tag
      bool upgradedExisting = false;
      bodyText = bodyText.replaceAllMapped(RegExp(r'\[\[(.*?)\]\]'), (m) {
        final content = m.group(1) ?? '';
        final parts = content.split('|');
        final firstLabel = parts.isNotEmpty ? parts[0].trim().toLowerCase() : '';
        final hasMatchingUid = uid != null &&
            parts.any((p) => p.trim().toLowerCase() == 'user:${uid.toLowerCase()}');
        if (!upgradedExisting &&
            (hasMatchingUid || candidateAuthorLabels.contains(firstLabel))) {
          upgradedExisting = true;
          return combinedWikilink;
        }
        return m.group(0)!;
      });

      bool insertedInBody = upgradedExisting;
      if (!insertedInBody) {
        for (final labelCand in [
          if (rawAuthorName.isNotEmpty) rawAuthorName,
          if (effectiveAuthorName.isNotEmpty) effectiveAuthorName,
        ]) {
          final res = _replacePlainTextOutsideWikilinks(
            bodyText,
            labelCand,
            combinedWikilink,
          );
          if (res.replaced) {
            bodyText = res.text;
            insertedInBody = true;
            break;
          }
        }
      }

      buffer.writeln(bodyText);
      buffer.writeln();

      if (!insertedInBody) {
        buffer.writeln('**$combinedWikilink**');
        buffer.writeln();
      }
    } else {
      buffer.writeln(bodyText);
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Evaluates exact canvas page count for a set of letters by testing the layout
  /// in its final chronological publication sequence using pure-Dart PublisherLayoutEngine.
  static Future<int> _testRenderPageCount(List<_SelectedRadiusLetter> letters) async {
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

  /// Resolves real Firestore profiles and their full mailing addresses in batch
  /// for candidate letters by checking embedded wikilink UIDs, explicit handles,
  /// `usernames/{handle}`, `shortcodes/{HANDLE}`, verified `userId`/`authorUid`
  /// records, and case-insensitive `profiles` lookups.
  static Future<List<_ResolvedAuthorIdentity>> _resolveAuthorIdentitiesBatch(
      List<HistoricalLetterEntry> entries,
      List<Map<String, dynamic>> rawComments,
      ) async {
    final Set<String> uidsToFetch = {};
    final Set<String> handlesToFetch = {};
    final List<String?> embeddedUids = List<String?>.filled(entries.length, null);

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final raw = rawComments[i];

      // Check if comment text already contains an embedded `[[...|user:<uid>]]` link
      final embeddedMatch =
      RegExp(r'\[\[[^|\]]+\|user:([^|\]]+)').firstMatch(entry.letterText);
      if (embeddedMatch != null) {
        final embUid = embeddedMatch.group(1)?.trim() ?? '';
        if (embUid.isNotEmpty) {
          embeddedUids[i] = embUid;
          uidsToFetch.add(embUid);
        }
      }

      for (final uidKey in ['authorUid', 'profileId', 'userId']) {
        final candidateUid = raw[uidKey]?.toString().trim() ?? '';
        if (candidateUid.isNotEmpty && candidateUid != 'system') {
          uidsToFetch.add(candidateUid);
        }
      }

      final rawHandle = (entry.authorHandle ??
          raw['authorHandle'] ??
          raw['handle'] ??
          '')
          .toString()
          .trim()
          .replaceAll('@', '');
      if (rawHandle.isNotEmpty) {
        handlesToFetch.addAll(_handleCandidatesForName(rawHandle));
      }

      final authorName = (entry.authorName ??
          raw['authorName'] ??
          raw['author'] ??
          '')
          .toString()
          .trim();
      if (authorName.isNotEmpty) {
        handlesToFetch.addAll(_handleCandidatesForName(authorName));
      }
    }

    final Map<String, Map<String, dynamic>> profilesByUid = {};
    final Map<String, Map<String, dynamic>> usernameDocs = {};
    final Map<String, String> uidByShortcode = {};

    final List<Future<void>> initialFetches = [];
    for (final uid in uidsToFetch) {
      initialFetches.add(
        fsGetDoc('profiles/$uid').then((res) {
          try {
            final doc = jsonDecode(res);
            if (doc['exists'] == true && doc['data'] is Map) {
              profilesByUid[uid] = Map<String, dynamic>.from(doc['data'] as Map);
            }
          } catch (_) {}
        }).catchError((_) {}),
      );
    }
    for (final handle in handlesToFetch) {
      initialFetches.add(
        fsGetDoc('usernames/$handle').then((res) {
          try {
            final doc = jsonDecode(res);
            if (doc['exists'] == true && doc['data'] is Map) {
              usernameDocs[handle] = Map<String, dynamic>.from(doc['data'] as Map);
            }
          } catch (_) {}
        }).catchError((_) {}),
      );
      initialFetches.add(
        fsGetDoc('shortcodes/${handle.toUpperCase()}').then((res) {
          try {
            final doc = jsonDecode(res);
            if (doc['exists'] == true && doc['data'] is Map) {
              final data = doc['data'] as Map;
              if (data['type'] == 'user' && data['contentId'] != null) {
                final cid = data['contentId'].toString().trim();
                if (cid.isNotEmpty) {
                  uidByShortcode[handle] = cid;
                }
              }
            }
          } catch (_) {}
        }).catchError((_) {}),
      );
    }
    if (initialFetches.isNotEmpty) {
      await Future.wait(initialFetches);
    }

    // Follow any alias redirects in `usernames`
    final Set<String> redirectHandles = {};
    for (final uDoc in usernameDocs.values) {
      if (uDoc['isAlias'] == true && uDoc['redirect'] != null) {
        final target = uDoc['redirect'].toString().trim().toLowerCase();
        if (target.isNotEmpty && !usernameDocs.containsKey(target)) {
          redirectHandles.add(target);
        }
      }
    }
    if (redirectHandles.isNotEmpty) {
      await Future.wait(
        redirectHandles.map((handle) => fsGetDoc('usernames/$handle').then((res) {
          try {
            final doc = jsonDecode(res);
            if (doc['exists'] == true && doc['data'] is Map) {
              usernameDocs[handle] =
              Map<String, dynamic>.from(doc['data'] as Map);
            }
          } catch (_) {}
        }).catchError((_) {})),
      );
    }

    // Fetch missing profiles discovered via `usernames` or `shortcodes` lookups
    final Set<String> additionalUids = {};
    for (final uDoc in usernameDocs.values) {
      final uid = uDoc['uid']?.toString().trim() ?? '';
      if (uid.isNotEmpty && !profilesByUid.containsKey(uid)) {
        additionalUids.add(uid);
      }
    }
    for (final uid in uidByShortcode.values) {
      if (uid.isNotEmpty && !profilesByUid.containsKey(uid)) {
        additionalUids.add(uid);
      }
    }
    if (additionalUids.isNotEmpty) {
      await Future.wait(
        additionalUids.map((uid) => fsGetDoc('profiles/$uid').then((res) {
          try {
            final doc = jsonDecode(res);
            if (doc['exists'] == true && doc['data'] is Map) {
              profilesByUid[uid] =
              Map<String, dynamic>.from(doc['data'] as Map);
            }
          } catch (_) {}
        }).catchError((_) {})),
      );
    }

    String? lookupUidByHandle(String rawHandle) {
      for (final h in _handleCandidatesForName(rawHandle)) {
        Map<String, dynamic>? doc = usernameDocs[h];
        if (doc != null && doc['isAlias'] == true && doc['redirect'] != null) {
          final redir = doc['redirect'].toString().trim().toLowerCase();
          doc = usernameDocs[redir] ?? doc;
        }
        final uid = doc?['uid']?.toString().trim() ?? '';
        if (uid.isNotEmpty) return uid;

        final scUid = uidByShortcode[h];
        if (scUid != null && scUid.isNotEmpty) return scUid;
      }
      return null;
    }

    // Check if any candidate authors remain unresolved; if so, load managed profiles
    // once so we can match case-insensitively by displayName, username, or first+last name.
    bool hasUnresolvedAuthors = false;
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final raw = rawComments[i];
      final authorName = (entry.authorName ?? raw['authorName'] ?? '').toString().trim();
      final rawHandle = (entry.authorHandle ?? raw['authorHandle'] ?? '').toString().trim();
      final embUid = embeddedUids[i];
      if (embUid == null &&
          (rawHandle.isEmpty || lookupUidByHandle(rawHandle) == null) &&
          (authorName.isEmpty || lookupUidByHandle(authorName) == null)) {
        hasUnresolvedAuthors = true;
        break;
      }
    }

    final Map<String, String> uidByNormalizedDisplayName = {};
    if (hasUnresolvedAuthors) {
      try {
        final managedRes = await fsQuery(
          'profiles',
          'isManaged',
          '==',
          'true',
          '',
        );
        final List decodedManaged = jsonDecode(managedRes);
        for (final item in decodedManaged) {
          final id = item['id']?.toString().trim() ?? '';
          if (id.isEmpty || item['data'] is! Map) continue;
          final data = Map<String, dynamic>.from(item['data'] as Map);
          profilesByUid[id] ??= data;

          final dName = (data['displayName'] ?? '').toString().trim().toLowerCase();
          if (dName.isNotEmpty) {
            uidByNormalizedDisplayName[dName] = id;
          }
          final first = (data['firstName'] ?? '').toString().trim().toLowerCase();
          final last = (data['lastName'] ?? '').toString().trim().toLowerCase();
          if (first.isNotEmpty && last.isNotEmpty) {
            uidByNormalizedDisplayName['$first $last'] = id;
          }
          final uName = (data['username'] ?? '').toString().trim();
          if (uName.isNotEmpty) {
            for (final c in _handleCandidatesForName(uName)) {
              uidByShortcode.putIfAbsent(c, () => id);
            }
          }
        }
      } catch (_) {}
    }

    final List<_ResolvedAuthorIdentity> results = [];
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final raw = rawComments[i];
      final String authorName = (entry.authorName ??
          raw['authorName'] ??
          raw['author'] ??
          '')
          .toString()
          .trim();
      final String rawHandle = (entry.authorHandle ??
          raw['authorHandle'] ??
          raw['handle'] ??
          '')
          .toString()
          .trim()
          .replaceAll('@', '');
      final String explicitAuthorUid =
      (raw['authorUid'] ?? raw['profileId'] ?? '').toString().trim();
      final String rawUid = raw['userId']?.toString().trim() ?? '';
      final String? embUid = embeddedUids[i];

      String? matchedUid;

      // 1. Embedded `[[...|user:<uid>]]` inside comment text
      if (embUid != null && embUid.isNotEmpty) {
        matchedUid = embUid;
      }

      // 2. Explicit authorUid / profileId field on comment
      if (matchedUid == null &&
          explicitAuthorUid.isNotEmpty &&
          profilesByUid.containsKey(explicitAuthorUid)) {
        matchedUid = explicitAuthorUid;
      }

      // 3. Explicit handle on the letter entry
      if (matchedUid == null && rawHandle.isNotEmpty) {
        matchedUid = lookupUidByHandle(rawHandle);
      }

      // 4. Verified `userId` on the comment (matching author name or managed profile)
      if (matchedUid == null &&
          rawUid.isNotEmpty &&
          rawUid != 'system' &&
          profilesByUid.containsKey(rawUid)) {
        final p = profilesByUid[rawUid]!;
        final pDisplay = (p['displayName'] ?? '').toString().trim().toLowerCase();
        final pUser = (p['username'] ?? '').toString().trim().toLowerCase();
        final bool isManaged = p['isManaged'] == true;
        final String authorLower = authorName.toLowerCase();
        final authorCands = _handleCandidatesForName(authorName);

        if (authorName.isEmpty ||
            isManaged ||
            pDisplay == authorLower ||
            authorCands.contains(pUser)) {
          matchedUid = rawUid;
        }
      }

      // 5. Name-based handle, shortcode, or displayName lookup against `usernames` / `profiles`
      if (matchedUid == null && authorName.isNotEmpty) {
        matchedUid = lookupUidByHandle(authorName) ??
            uidByNormalizedDisplayName[authorName.toLowerCase()];
      }

      final Map<String, dynamic>? profileData =
      matchedUid != null ? profilesByUid[matchedUid] : null;
      final String fullAddress =
      _extractMailingAddressFromProfile(profileData, entry, raw);

      if (matchedUid != null) {
        final String resolvedUsername =
        (profileData?['username'] ?? rawHandle).toString().trim();
        final String resolvedDisplay =
        (profileData?['displayName']?.toString().trim().isNotEmpty == true)
            ? profileData!['displayName'].toString().trim()
            : (authorName.isNotEmpty ? authorName : resolvedUsername);
        results.add(_ResolvedAuthorIdentity(
          uid: matchedUid,
          username: resolvedUsername,
          displayName: resolvedDisplay,
          fullMailingAddress: fullAddress,
        ));
      } else {
        results.add(_ResolvedAuthorIdentity(
          uid: null,
          username: null,
          displayName: authorName,
          fullMailingAddress: fullAddress,
        ));
      }
    }

    return results;
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
      final contextMap = raw['context'] is Map ? (raw['context'] as Map<String, dynamic>) : {};
      final fzId = (contextMap['fanzineId'] ?? '').toString();
      final imgId = (raw['contentId'] ?? '').toString();
      if (fzId.isNotEmpty && !UnsavedFanzineRegistry.fanzines.containsKey(fzId)) {
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
              fanzineCache[fzId] = doc['data'] as Map<String, dynamic>? ?? {};
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
              final url = d['fileUrl'] ?? d['listUrl'] ?? d['gridUrl'] ?? d['imageUrl'];
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
      final entry = HistoricalLetterEntry.fromCommentMap(raw, distanceMiles: dist);
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
          final pgs = UnsavedFanzineRegistry.pages[entry.fanzineId] ?? [];
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
  /// two-way convergence layout fitting, chronological sorting, map cover generation,
  /// and compiles publisher pages with frozen, pre-baked static HTML ready for zero-latency reading.
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

    final String resolvedShortCode =
    (shortCode != null && shortCode.trim().isNotEmpty)
        ? shortCode.trim()
        : ShortcodeGenerator.generateStandardCode();

    final int contentPagesCount = hasMapCover ? math.max(1, targetPages - 1) : targetPages;

    // 1. Geocode Target Center Address
    print('[AddressRadiusLetters] Step 1: Geocoding center address "$cleanTargetAddr"...');
    onProgress?.call('Geocoding center address...');
    final targetCoords = await _geocodeTarget(cleanTargetAddr);
    if (targetCoords == null) {
      throw Exception('Unable to geocode "$cleanTargetAddr". Please check the address or city name.');
    }
    final double targetLat = targetCoords['lat'] as double;
    final double targetLng = targetCoords['lng'] as double;
    final String formattedCenter = targetCoords['formatted'] as String? ?? cleanTargetAddr;
    print('[AddressRadiusLetters] Target coordinates: $targetLat, $targetLng ($formattedCenter)');

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
      throw Exception('No historical letters found near $cleanTargetAddr.');
    }
    print('[AddressRadiusLetters] Found ${candidateLetters.length} candidate letters. Resolving metadata & profiles in parallel...');
    onProgress?.call('Resolving letter metadata & profiles...');
    final Map<String, Map<String, dynamic>> imageMetadataCache = {};
    final resolvedEntries =
    await _resolveLetterEntriesBatch(candidateLetters, imageMetadataCache: imageMetadataCache);
    final resolvedAuthors =
    await _resolveAuthorIdentitiesBatch(resolvedEntries, candidateLetters);

    // Pre-resolve global identity mappings: userHandles, userNames, and profile mailing addresses
    final Map<String, String> userHandlesMap = {};
    final Map<String, String> userNamesMap = {};
    final Map<String, String> addressMap = {};

    for (int i = 0; i < resolvedEntries.length; i++) {
      final entry = resolvedEntries[i];
      final author = resolvedAuthors[i];

      if (author.isLinked && author.uid != null) {
        final uid = author.uid!;
        final handle = (author.username != null && author.username!.isNotEmpty)
            ? author.username!
            : uid;
        userHandlesMap[uid] = handle;
        userNamesMap[uid] = author.displayName.isNotEmpty ? author.displayName : handle;
        if (author.username != null && author.username!.isNotEmpty) {
          userHandlesMap[author.username!] = author.username!;
          userNamesMap[author.username!] =
          author.displayName.isNotEmpty ? author.displayName : author.username!;
        }
        if (author.displayName.isNotEmpty) {
          userHandlesMap[author.displayName] = handle;
        }
      }

      if (author.fullMailingAddress.isNotEmpty) {
        addressMap[author.fullMailingAddress] = author.fullMailingAddress;
        final rawLoc = entry.location?.trim() ?? '';
        if (rawLoc.isNotEmpty) {
          addressMap[rawLoc] = author.fullMailingAddress;
        }
      }
    }

    // Build complete pool of candidate radius letters ordered by proximity (closest first)
    final List<_SelectedRadiusLetter> allCandidates = [];
    for (int i = 0; i < resolvedEntries.length; i++) {
      final entry = resolvedEntries[i];
      final raw = candidateLetters[i];
      final author = resolvedAuthors[i];
      final pageMeta = entry.imageId != null ? imageMetadataCache[entry.imageId] : null;

      final letterMd = buildLetterMarkdown(
        entry,
        pageMetadata: pageMeta,
        resolvedAuthorUid: author.uid,
        resolvedAuthorDisplayName: author.displayName,
        profileMailingAddress: author.fullMailingAddress,
      );
      final dist = (raw['_calculatedDistanceMiles'] as num?)?.toDouble() ?? 0.0;
      final pubDate = parseHistoricalDate(
        raw['historicalDate'] ?? (raw['context'] is Map ? raw['context']['publishedDate'] : null),
        letterMd,
      );
      final estHeight = estimateMarkdownHeight(letterMd);
      allCandidates.add(_SelectedRadiusLetter(
        entry: entry,
        raw: raw,
        author: author,
        markdown: letterMd,
        distance: dist,
        publishedDate: pubDate,
        estimatedHeight: estHeight,
      ));
    }

    print('[AddressRadiusLetters] Successfully resolved ${allCandidates.length} entries. Performing two-way convergence fitting for $contentPagesCount letter ${contentPagesCount == 1 ? "page" : "pages"}...');
    onProgress?.call('Fitting letters to $contentPagesCount letter ${contentPagesCount == 1 ? "page" : "pages"}...');

    // Phase 1: Generous initial estimate to reach full page capacity
    final double targetCapacityPixels = contentPagesCount * kTotalPageHeight;
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
    print('[AddressRadiusLetters] Initial measurement test: $renderedPages pages (Target: $contentPagesCount)');

    while (renderedPages < contentPagesCount && candidateIndex < allCandidates.length) {
      selectedLetters.add(allCandidates[candidateIndex]);
      candidateIndex++;
      renderedPages = await _testRenderPageCount(selectedLetters);
      print('[AddressRadiusLetters] Grew pool to ${selectedLetters.length} letters -> $renderedPages pages');
    }

    while (renderedPages > contentPagesCount && selectedLetters.length > 1) {
      selectedLetters.removeLast();
      renderedPages = await _testRenderPageCount(selectedLetters);
      print('[AddressRadiusLetters] Trimmed pool to ${selectedLetters.length} letters -> $renderedPages pages');
    }

    if (renderedPages < contentPagesCount && candidateIndex < allCandidates.length) {
      for (int i = candidateIndex; i < allCandidates.length; i++) {
        selectedLetters.add(allCandidates[i]);
        final testCount = await _testRenderPageCount(selectedLetters);
        if (testCount == contentPagesCount) {
          renderedPages = testCount;
          print('[AddressRadiusLetters] Fine-tuned exact match: ${selectedLetters.length} letters -> $renderedPages pages');
          break;
        } else if (testCount > contentPagesCount) {
          selectedLetters.removeLast();
        } else {
          renderedPages = testCount;
        }
      }
    }

    print('[AddressRadiusLetters] Final letter pool selected: ${selectedLetters.length} letters rendering to $renderedPages pages.');

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

    final String folioTitle = targetPages == 24
        ? 'Letters near $cleanTargetAddr (Full Fanzine)'
        : 'Letters near $cleanTargetAddr';

    if (hasMapCover) {
      print('[AddressRadiusLetters] Step 5: Rendering 2000x3200 Google Maps Cover page...');
      onProgress?.call('Drawing high-resolution map cover...');
      final List<Map<String, dynamic>> mapLettersPayload = [];
      for (int i = 0; i < selectedLetters.length; i++) {
        final item = selectedLetters[i];
        final raw = item.raw;
        final geo = raw['geo'] is Map ? (raw['geo'] as Map) : {};
        final context = raw['context'] is Map ? (raw['context'] as Map) : {};
        mapLettersPayload.add({
          'index': i + 1,
          'displayName': item.author.displayName.isNotEmpty
              ? item.author.displayName
              : (raw['displayName'] ?? 'Reader'),
          'location': item.author.fullMailingAddress.isNotEmpty
              ? item.author.fullMailingAddress
              : (raw['location'] ?? ''),
          'distanceMiles': item.distance,
          'publicationTitle': context['fanzineTitle'] ?? 'Archival Fanzine',
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
        'shortCode': resolvedShortCode,
      };

      final String coverText = 'Map Cover: $folioTitle\nCenter: $formattedCenter\nLetters: ${mapLettersPayload.length}';
      final String coverHtml = '<div class="map-cover-text"><h1 style="font-family: \'Anton\', sans-serif; font-size: 26px; text-transform: uppercase; margin-bottom: 8px;">$folioTitle</h1><p style="font-family: \'Arimo\', sans-serif; font-size: 14px; color: #475569; margin: 0 0 16px 0;"><strong>Center:</strong> $formattedCenter</p><p style="font-family: \'Arimo\', sans-serif; font-size: 13px; color: #64748b; margin: 0;"><strong>Archival Radius:</strong> ${mapLettersPayload.length} historical letters found radiating from this location.</p></div>';

      // 5.A: Primary Server-Side Cloud Function Map Cover Compilation
      try {
        final resStr = await fnCall('compile_map_cover', jsonEncode(mapCoverConfig));
        final decoded = jsonDecode(resStr);
        if (decoded is Map && decoded['status'] == 'success' && decoded['coverPage'] is Map) {
          final cpMap = Map<String, dynamic>.from(decoded['coverPage'] as Map);
          final coverPage = FanzinePage.fromMap(
            cpMap['id']?.toString() ?? '${fanzineId}_page_1',
            cpMap,
          ).copyWith(
            text: coverText,
            textHtml: coverHtml,
          );
          coverImageUrl = coverPage.imageUrl;
          finalPages.add(coverPage);
          if (coverPage.imageId != null && coverPage.imageId!.isNotEmpty) {
            fsUpdateDoc('images/${coverPage.imageId}', jsonEncode({
              'text': coverText,
              'text_html': coverHtml,
            })).catchError((_) => null);
          }
          print('[AddressRadiusLetters] Map cover published server-side as Page 1.');
        }
      } catch (e) {
        print('[AddressRadiusLetters] Server compile_map_cover error, falling back to client: $e');
      }

      // 5.B: Client Fallback if Server Function is offline
      if (finalPages.isEmpty) {
        try {
          final coverJson = await renderMapCoverPage(jsonEncode(mapCoverConfig));
          final coverData = jsonDecode(coverJson) as Map<String, dynamic>;
          onProgress?.call('Publishing map cover image...');
          final origBytes = base64Decode(coverData['original'] as String);
          final listBytes = base64Decode(coverData['list'] as String);
          final gridBytes = base64Decode(coverData['grid'] as String);

          final coverUrls = await Future.wait([
            stUpload('fanzines/$fanzineId/page_1.webp', origBytes, 'image/webp'),
            stUpload('fanzines/$fanzineId/page_1_list.webp', listBytes, 'image/webp'),
            stUpload('fanzines/$fanzineId/page_1_grid.webp', gridBytes, 'image/webp'),
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
            'shortCode': resolvedShortCode,
            'folioContext': fanzineId,
            'usedInFanzines': [fanzineId],
            'fileUrl': coverUrls[0],
            'listUrl': coverUrls[1],
            'gridUrl': coverUrls[2],
            'text': coverText,
            'text_html': coverHtml,
          };
          await fsSetDoc('images/$coverImageId', jsonEncode(coverMetadata), true);

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
            text: coverText,
            textHtml: coverHtml,
          );
          finalPages.add(coverPage);
          print('[AddressRadiusLetters] Map cover published via client fallback as Page 1.');
        } catch (e, stack) {
          print('[AddressRadiusLetters] Failed client map cover fallback: $e\n$stack');
        }
      }
    }

    print('[AddressRadiusLetters] Compiling and publishing final folio text pages...');
    onProgress?.call('Compiling publisher text pages...');
    final int startPageNum = hasMapCover && finalPages.isNotEmpty ? 2 : 1;

    // Compile content pages with pre-resolved identity tables passed into the layout engine
    final List<FanzinePage> contentPages = await PublisherCompiler.compileAndPublishMultiPage(
      fanzineId: fanzineId,
      fullText: fullText,
      startPageNumber: startPageNum,
      userHandles: userHandlesMap,
      userNames: userNamesMap,
      addressMap: addressMap,
      onProgress: (current, total) {
        onProgress?.call('Compiling publisher text page $current of $total...');
      },
    );

    // Hard clamp: Ensure the number of content pages never exceeds contentPagesCount
    final int pageOffset = hasMapCover && finalPages.isNotEmpty ? 1 : 0;
    final int pagesToTake = math.min(contentPages.length, contentPagesCount);

    for (int i = 0; i < pagesToTake; i++) {
      final cp = contentPages[i];
      final targetPageNum = i + 1 + pageOffset;

      // Ensure pre-baked HTML is populated even if backend service was offline
      String pageHtml = cp.textHtml ?? '';
      if (pageHtml.isEmpty && (cp.text != null && cp.text!.isNotEmpty)) {
        pageHtml = TextHtmlRenderer.renderToHtml(
          cp.text!,
          userHandles: userHandlesMap,
          userNames: userNamesMap,
          addressMap: addressMap,
        );
      }

      // Persist baked text_html in Firestore images collection
      if (cp.imageId != null && cp.imageId!.isNotEmpty && pageHtml.isNotEmpty) {
        fsUpdateDoc('images/${cp.imageId}', jsonEncode({
          'text_html': pageHtml,
        })).catchError((_) => null);
      }

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
        text: cp.text,
        textHtml: pageHtml,
      ));
    }

    final newFanzine = Fanzine(
      id: fanzineId,
      title: folioTitle,
      ownerId: ownerUserId,
      curators: [ownerUserId],
      collections: [ownerUserId],
      type: FanzineType.folio,
      isLive: false,
      processingStatus: 'complete',
      shortCode: resolvedShortCode,
      twoPage: true,
      hasCover: hasMapCover && coverImageUrl != null && finalPages.isNotEmpty,
    );

    print('[AddressRadiusLetters] Build completed successfully. Generated exactly ${finalPages.length} total pages (Requested: $targetPages).');
    return RadiusFolioResult(fanzine: newFanzine, pages: finalPages);
  }
}