import 'package:equatable/equatable.dart';

/// Default fanzine series metadata options matching the curator & publisher workspaces.
const Map<String, String> defaultPublisherSeriesOptions = {
  '': 'no series / independent',
  'the-fantasy-fan': 'the fantasy fan',
  'the-comet-cosmology': 'the comet / cosmology',
  'phantagraph': 'phantagraph',
  'science-fiction-digest': 'science-fiction-digest / fantasy magazine',
  'the-planet': 'the planet',
  'the-time-traveller': 'the time traveller',
  'futuria-fantasia': 'futuria fantasia',
};

/// Color palette for the 24-page / 72-page bundle flatplan categories and slot rules.
const Map<String, String> publisherCategoryColors = {
  'cover': '#6750A4', // Primary Purple (Covers / Indicia)
  'ad': '#F59E0B', // Amber (Advertisements)
  'letters': '#10B981', // Emerald (Radius / Local Letters & UGC)
  'articles': '#3B82F6', // Blue (Global UGC / Articles / Essays)
  'terminal': '#EC4899', // Pink (Combat Terminal Turn Output)
  'filler': '#94A3B8', // Slate (Fillers / Spot Art)
};

/// Source types for a page range inside a 24-page Fanzine Blueprint template.
enum BlueprintSlotSource {
  coverIndicia,
  globalUgc,
  localUgc,
  terminalTurn,
  sponsorAd,
  fillerArt,
}

extension BlueprintSlotSourceX on BlueprintSlotSource {
  String get id => name;

  String get label {
    switch (this) {
      case BlueprintSlotSource.coverIndicia:
        return 'Cover & Indicia';
      case BlueprintSlotSource.globalUgc:
        return 'Global UGC Feed';
      case BlueprintSlotSource.localUgc:
        return 'Local / Carrier-Route UGC';
      case BlueprintSlotSource.terminalTurn:
        return 'Combat Terminal Turn (3f/wk)';
      case BlueprintSlotSource.sponsorAd:
        return 'Sponsor Ad / Backfill';
      case BlueprintSlotSource.fillerArt:
        return 'Filler & Spot Art';
    }
  }

  String get categoryKey {
    switch (this) {
      case BlueprintSlotSource.coverIndicia:
        return 'cover';
      case BlueprintSlotSource.globalUgc:
        return 'articles';
      case BlueprintSlotSource.localUgc:
        return 'letters';
      case BlueprintSlotSource.terminalTurn:
        return 'terminal';
      case BlueprintSlotSource.sponsorAd:
        return 'ad';
      case BlueprintSlotSource.fillerArt:
        return 'filler';
    }
  }

  static BlueprintSlotSource fromString(String? raw) {
    for (final val in BlueprintSlotSource.values) {
      if (val.name == raw) return val;
    }
    return BlueprintSlotSource.globalUgc;
  }
}

/// Defines how a range of pages (`startPage..endPage`, 1-indexed within `1..24`)
/// is populated in a Publisher Blueprint, along with an optional condition and fallback.
class BlueprintSlotRule extends Equatable {
  final int startPage;
  final int endPage;
  final BlueprintSlotSource primarySource;
  final String? condition; // e.g. 'plays_terminal', 'has_local_pool'
  final BlueprintSlotSource fallbackSource;

  const BlueprintSlotRule({
    required this.startPage,
    required this.endPage,
    required this.primarySource,
    this.condition,
    this.fallbackSource = BlueprintSlotSource.globalUgc,
  });

  bool containsPage(int pageNumber) =>
      pageNumber >= startPage && pageNumber <= endPage;

  String get rangeLabel =>
      startPage == endPage ? 'Page $startPage' : 'Pages $startPage–$endPage';

  Map<String, dynamic> toMap() => {
    'startPage': startPage,
    'endPage': endPage,
    'primarySource': primarySource.name,
    if (condition != null) 'condition': condition,
    'fallbackSource': fallbackSource.name,
  };

  factory BlueprintSlotRule.fromMap(Map<String, dynamic> map) {
    return BlueprintSlotRule(
      startPage: (map['startPage'] as num?)?.toInt() ?? 1,
      endPage: (map['endPage'] as num?)?.toInt() ?? 1,
      primarySource: BlueprintSlotSourceX.fromString(
        map['primarySource']?.toString(),
      ),
      condition: map['condition']?.toString(),
      fallbackSource: BlueprintSlotSourceX.fromString(
        map['fallbackSource']?.toString(),
      ),
    );
  }

  BlueprintSlotRule copyWith({
    int? startPage,
    int? endPage,
    BlueprintSlotSource? primarySource,
    String? condition,
    BlueprintSlotSource? fallbackSource,
  }) {
    return BlueprintSlotRule(
      startPage: startPage ?? this.startPage,
      endPage: endPage ?? this.endPage,
      primarySource: primarySource ?? this.primarySource,
      condition: condition ?? this.condition,
      fallbackSource: fallbackSource ?? this.fallbackSource,
    );
  }

  @override
  List<Object?> get props => [
    startPage,
    endPage,
    primarySource,
    condition,
    fallbackSource,
  ];
}

/// Default 24-page slot rules for each of the 3 weekly zine slots.
List<BlueprintSlotRule> defaultBlueprintRulesForSlot(int zineSlot) {
  if (zineSlot == 1) {
    return const [
      BlueprintSlotRule(
        startPage: 1,
        endPage: 2,
        primarySource: BlueprintSlotSource.coverIndicia,
      ),
      BlueprintSlotRule(
        startPage: 3,
        endPage: 6,
        primarySource: BlueprintSlotSource.globalUgc,
      ),
      BlueprintSlotRule(
        startPage: 7,
        endPage: 10,
        primarySource: BlueprintSlotSource.terminalTurn,
        condition: 'plays_terminal',
        fallbackSource: BlueprintSlotSource.globalUgc,
      ),
      BlueprintSlotRule(
        startPage: 11,
        endPage: 15,
        primarySource: BlueprintSlotSource.globalUgc,
      ),
      BlueprintSlotRule(
        startPage: 16,
        endPage: 23,
        primarySource: BlueprintSlotSource.localUgc,
        condition: 'has_local_pool',
        fallbackSource: BlueprintSlotSource.globalUgc,
      ),
      BlueprintSlotRule(
        startPage: 24,
        endPage: 24,
        primarySource: BlueprintSlotSource.sponsorAd,
      ),
    ];
  } else if (zineSlot == 2) {
    return const [
      BlueprintSlotRule(
        startPage: 1,
        endPage: 2,
        primarySource: BlueprintSlotSource.coverIndicia,
      ),
      BlueprintSlotRule(
        startPage: 3,
        endPage: 15,
        primarySource: BlueprintSlotSource.globalUgc,
      ),
      BlueprintSlotRule(
        startPage: 16,
        endPage: 19,
        primarySource: BlueprintSlotSource.localUgc,
        condition: 'has_local_pool',
        fallbackSource: BlueprintSlotSource.globalUgc,
      ),
      BlueprintSlotRule(
        startPage: 20,
        endPage: 23,
        primarySource: BlueprintSlotSource.fillerArt,
        fallbackSource: BlueprintSlotSource.globalUgc,
      ),
      BlueprintSlotRule(
        startPage: 24,
        endPage: 24,
        primarySource: BlueprintSlotSource.sponsorAd,
      ),
    ];
  } else {
    return const [
      BlueprintSlotRule(
        startPage: 1,
        endPage: 2,
        primarySource: BlueprintSlotSource.coverIndicia,
      ),
      BlueprintSlotRule(
        startPage: 3,
        endPage: 14,
        primarySource: BlueprintSlotSource.localUgc,
        condition: 'has_local_pool',
        fallbackSource: BlueprintSlotSource.globalUgc,
      ),
      BlueprintSlotRule(
        startPage: 15,
        endPage: 18,
        primarySource: BlueprintSlotSource.terminalTurn,
        condition: 'plays_terminal',
        fallbackSource: BlueprintSlotSource.globalUgc,
      ),
      BlueprintSlotRule(
        startPage: 19,
        endPage: 23,
        primarySource: BlueprintSlotSource.globalUgc,
      ),
      BlueprintSlotRule(
        startPage: 24,
        endPage: 24,
        primarySource: BlueprintSlotSource.sponsorAd,
      ),
    ];
  }
}

/// Model representing a single miniature page definition inside the 72-page recipient bundle.
class BundlePageDef extends Equatable {
  final int zineNum; // 1, 2, or 3
  final int pageNum; // 1..24
  final int spreadNum; // 1..13 (Spread 1 has blank left, Spread 13 has blank right)
  final String side; // 'left' or 'right'
  final String category; // 'cover', 'ad', 'letters', 'articles', 'terminal', 'filler'
  final String label;

  const BundlePageDef({
    required this.zineNum,
    required this.pageNum,
    required this.spreadNum,
    required this.side,
    required this.category,
    required this.label,
  });

  @override
  List<Object?> get props => [zineNum, pageNum, spreadNum, side, category, label];
}

/// Model representing a 24-page fanzine blueprint scheduled for publication during a weekly print run.
/// Every fanzine is strictly 24 pages and automatically carries over week-to-week.
class ScheduledFanzine extends Equatable {
  final String id;
  final String title;
  final String series;
  final String volume; // 'vol.'
  final String issue; // 'num.'
  final String wholeNumber; // 'whole num.'
  final int pageCount; // Always 24 pages
  final String shortCode;
  final String weekId;
  final bool isCanceled;
  final String? parentFanzineId;
  final DateTime createdAt;
  final List<BlueprintSlotRule> slotRules;

  const ScheduledFanzine({
    required this.id,
    required this.title,
    this.series = '',
    this.volume = '',
    this.issue = '',
    this.wholeNumber = '',
    this.pageCount = 24,
    required this.shortCode,
    required this.weekId,
    this.isCanceled = false,
    this.parentFanzineId,
    required this.createdAt,
    this.slotRules = const [],
  });

  List<BlueprintSlotRule> effectiveRules({int slotIndex = 1}) =>
      slotRules.isNotEmpty ? slotRules : defaultBlueprintRulesForSlot(slotIndex);

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'series': series,
    'volume': volume,
    'issue': issue,
    'wholeNumber': wholeNumber,
    'pageCount': pageCount,
    'shortCode': shortCode,
    'weekId': weekId,
    'isCanceled': isCanceled,
    if (parentFanzineId != null) 'parentFanzineId': parentFanzineId,
    'createdAt': createdAt.millisecondsSinceEpoch,
    if (slotRules.isNotEmpty)
      'slotRules': slotRules.map((r) => r.toMap()).toList(),
  };

  factory ScheduledFanzine.fromMap(Map<String, dynamic> map) {
    DateTime parsedCreatedAt;
    if (map['createdAt'] is int) {
      parsedCreatedAt = DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int);
    } else if (map['createdAt'] is String) {
      parsedCreatedAt = DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now();
    } else {
      parsedCreatedAt = DateTime.now();
    }
    final rawRules = map['slotRules'] as List?;
    final parsedRules = rawRules != null
        ? rawRules
            .whereType<Map>()
            .map((m) => BlueprintSlotRule.fromMap(Map<String, dynamic>.from(m)))
            .toList()
        : const <BlueprintSlotRule>[];

    return ScheduledFanzine(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? 'Untitled Fanzine').toString(),
      series: (map['series'] ?? '').toString(),
      volume: (map['volume'] ?? '').toString(),
      issue: (map['issue'] ?? '').toString(),
      wholeNumber: (map['wholeNumber'] ?? '').toString(),
      pageCount: (map['pageCount'] as num?)?.toInt() ?? 24,
      shortCode: (map['shortCode'] ?? '').toString(),
      weekId: (map['weekId'] ?? '').toString(),
      isCanceled: map['isCanceled'] == true,
      parentFanzineId: map['parentFanzineId']?.toString(),
      createdAt: parsedCreatedAt,
      slotRules: parsedRules,
    );
  }

  ScheduledFanzine copyWith({
    String? id,
    String? title,
    String? series,
    String? volume,
    String? issue,
    String? wholeNumber,
    int? pageCount,
    String? shortCode,
    String? weekId,
    bool? isCanceled,
    String? parentFanzineId,
    DateTime? createdAt,
    List<BlueprintSlotRule>? slotRules,
  }) {
    return ScheduledFanzine(
      id: id ?? this.id,
      title: title ?? this.title,
      series: series ?? this.series,
      volume: volume ?? this.volume,
      issue: issue ?? this.issue,
      wholeNumber: wholeNumber ?? this.wholeNumber,
      pageCount: pageCount ?? this.pageCount,
      shortCode: shortCode ?? this.shortCode,
      weekId: weekId ?? this.weekId,
      isCanceled: isCanceled ?? this.isCanceled,
      parentFanzineId: parentFanzineId ?? this.parentFanzineId,
      createdAt: createdAt ?? this.createdAt,
      slotRules: slotRules ?? this.slotRules,
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    series,
    volume,
    issue,
    wholeNumber,
    pageCount,
    shortCode,
    weekId,
    isCanceled,
    parentFanzineId,
    createdAt,
    slotRules,
  ];
}

/// Helper that increments issue numbering in publication titles when carrying over week-to-week
/// (e.g. 'The Fanzine Zine issue 1' -> 'The Fanzine Zine issue 2').
String incrementIssueTitle(String title, int nextIssueNum) {
  final clean = title.trim();
  final issueRegex = RegExp(r'(issue\s*)(\d+)', caseSensitive: false);
  if (issueRegex.hasMatch(clean)) {
    return clean.replaceAllMapped(issueRegex, (m) => '${m.group(1)}$nextIssueNum');
  }
  final hashRegex = RegExp(r'(#\s*)(\d+)');
  if (hashRegex.hasMatch(clean)) {
    return clean.replaceAllMapped(hashRegex, (m) => '${m.group(1)}$nextIssueNum');
  }
  final noRegex = RegExp(r'(no\.?\s*)(\d+)', caseSensitive: false);
  if (noRegex.hasMatch(clean)) {
    return clean.replaceAllMapped(noRegex, (m) => '${m.group(1)}$nextIssueNum');
  }
  return clean;
}

/// Model representing an individual recipient receiving a printed fanzine issue.
/// Supports both registered app users (with a profile) and external contacts (without a profile).
class CirculationRecipient extends Equatable {
  final String id;
  final String displayName;
  final String? username;
  final String? photoUrl;
  final bool hasProfile;
  final String street1;
  final String street2;
  final String city;
  final String state;
  final String zipCode;
  final String country;
  final String? notes;
  final DateTime addedAt;

  const CirculationRecipient({
    required this.id,
    required this.displayName,
    this.username,
    this.photoUrl,
    this.hasProfile = false,
    this.street1 = '',
    this.street2 = '',
    this.city = '',
    this.state = '',
    this.zipCode = '',
    this.country = '',
    this.notes,
    required this.addedAt,
  });

  /// Returns a clean, multi-line mailing address in standard envelope format.
  String get formattedAddress {
    final lines = <String>[];
    final streetParts = [
      if (street1.trim().isNotEmpty) street1.trim(),
      if (street2.trim().isNotEmpty) street2.trim(),
    ];
    if (streetParts.isNotEmpty) lines.add(streetParts.join(', '));

    final cityStateZip = [
      if (city.trim().isNotEmpty) city.trim(),
      if (state.trim().isNotEmpty) state.trim(),
    ].join(', ') +
        (zipCode.trim().isNotEmpty ? ' ${zipCode.trim()}' : '');
    if (cityStateZip.trim().isNotEmpty) lines.add(cityStateZip.trim());

    if (country.trim().isNotEmpty &&
        country.toLowerCase() != 'us' &&
        country.toLowerCase() != 'usa' &&
        country.toLowerCase() != 'united states') {
      lines.add(country.trim());
    }
    return lines.join('\n');
  }

  bool get hasAddress =>
      street1.trim().isNotEmpty || city.trim().isNotEmpty || zipCode.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
    'id': id,
    'displayName': displayName,
    'username': username,
    'photoUrl': photoUrl,
    'hasProfile': hasProfile,
    'street1': street1,
    'street2': street2,
    'city': city,
    'state': state,
    'zipCode': zipCode,
    'country': country,
    if (notes != null) 'notes': notes,
    'addedAt': addedAt.millisecondsSinceEpoch,
  };

  factory CirculationRecipient.fromMap(Map<String, dynamic> map) {
    DateTime parsedAddedAt;
    if (map['addedAt'] is int) {
      parsedAddedAt = DateTime.fromMillisecondsSinceEpoch(map['addedAt'] as int);
    } else if (map['addedAt'] is String) {
      parsedAddedAt = DateTime.tryParse(map['addedAt'] as String) ?? DateTime.now();
    } else {
      parsedAddedAt = DateTime.now();
    }
    return CirculationRecipient(
      id: (map['id'] ?? '').toString(),
      displayName: (map['displayName'] ?? map['name'] ?? 'Unnamed Recipient').toString(),
      username: map['username']?.toString(),
      photoUrl: map['photoUrl']?.toString(),
      hasProfile: map['hasProfile'] == true,
      street1: (map['street1'] ?? '').toString(),
      street2: (map['street2'] ?? '').toString(),
      city: (map['city'] ?? '').toString(),
      state: (map['state'] ?? '').toString(),
      zipCode: (map['zipCode'] ?? '').toString(),
      country: (map['country'] ?? '').toString(),
      notes: map['notes']?.toString(),
      addedAt: parsedAddedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    displayName,
    username,
    photoUrl,
    hasProfile,
    street1,
    street2,
    city,
    state,
    zipCode,
    country,
    notes,
    addedAt,
  ];
}

/// Model representing a single publication week in the production schedule.
class PublishingWeek extends Equatable {
  final int weekNumber;
  final int year;
  final DateTime startDate;
  final DateTime endDate;
  final String startDateString;
  final bool isCurrent;
  final bool isPast;
  final int publishedCount;

  bool get hasPublishedContent => publishedCount > 0;
  String get weekId => '${year}_w${weekNumber.toString().padLeft(2, '0')}';

  const PublishingWeek({
    required this.weekNumber,
    required this.year,
    required this.startDate,
    required this.endDate,
    required this.startDateString,
    this.isCurrent = false,
    this.isPast = false,
    this.publishedCount = 0,
  });

  @override
  List<Object?> get props => [
    weekNumber,
    year,
    startDate,
    endDate,
    startDateString,
    isCurrent,
    isPast,
    publishedCount,
  ];
}

/// Generates standard 7-day Monday–Sunday publication blocks for the specified [year].
List<PublishingWeek> generatePublishingWeeks(
  int year, {
  Map<int, int> publishedCounts = const {},
}) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  final now = DateTime.now();
  final List<PublishingWeek> weeks = [];

  final jan1 = DateTime(year, 1, 1);
  DateTime currentMonday =
      jan1.subtract(Duration(days: jan1.weekday - DateTime.monday));

  for (int i = 1; i <= 52; i++) {
    final currentSunday = currentMonday.add(
      const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
    );

    final bool isCurrent =
        now.isAfter(currentMonday.subtract(const Duration(seconds: 1))) &&
        now.isBefore(currentSunday.add(const Duration(seconds: 1)));
    final bool isPast = currentSunday.isBefore(now);
    final int count = publishedCounts[i] ?? 0;
    final bool hasPublished = count > 0;

    if (isPast && !hasPublished && !isCurrent) {
      currentMonday = currentMonday.add(const Duration(days: 7));
      continue;
    }

    final String startMonthStr = months[currentMonday.month - 1];
    final String startDateFormatted =
        '$startMonthStr ${currentMonday.day}, $year';

    weeks.add(
      PublishingWeek(
        weekNumber: i,
        year: year,
        startDate: currentMonday,
        endDate: currentSunday,
        startDateString: startDateFormatted,
        isCurrent: isCurrent,
        isPast: isPast,
        publishedCount: count,
      ),
    );

    currentMonday = currentMonday.add(const Duration(days: 7));
  }

  return weeks;
}

/// Generates the 24 miniature page definitions for a single zine column in the 72-page bundle.
/// If [blueprint] has custom [BlueprintSlotRule]s, the flatplan reflects those slot rules.
List<BundlePageDef> generateZineBundlePages(
  int zineNum, {
  String? customTitle,
  List<BlueprintSlotRule>? rules,
}) {
  final List<BundlePageDef> pages = [];
  final String titlePrefix = customTitle != null && customTitle.isNotEmpty
      ? customTitle
      : (zineNum == 1
            ? 'Radius Letters'
            : (zineNum == 2 ? 'Fiction & Articles' : 'Community Directory'));

  if (rules != null && rules.isNotEmpty) {
    for (int p = 1; p <= 24; p++) {
      final int spreadIndex = p == 1 ? 1 : (p == 24 ? 13 : (p ~/ 2) + 1);
      final String side = (p % 2 == 0) ? 'left' : 'right';
      BlueprintSlotRule? matchingRule;
      for (final r in rules) {
        if (r.containsPage(p)) {
          matchingRule = r;
          break;
        }
      }
      final source =
          matchingRule?.primarySource ?? BlueprintSlotSource.globalUgc;
      pages.add(
        BundlePageDef(
          zineNum: zineNum,
          pageNum: p,
          spreadNum: spreadIndex,
          side: side,
          category: source.categoryKey,
          label: '$titlePrefix · ${source.label}',
        ),
      );
    }
    return pages;
  }

  // Page 1: Front Cover on the RIGHT of Spread 1 (Left is Blank space)
  pages.add(
    BundlePageDef(
      zineNum: zineNum,
      pageNum: 1,
      spreadNum: 1,
      side: 'right',
      category: 'cover',
      label: '$titlePrefix Cover Plate',
    ),
  );

  // Page 2: Inside Indicia on the LEFT of Spread 2
  pages.add(
    BundlePageDef(
      zineNum: zineNum,
      pageNum: 2,
      spreadNum: 2,
      side: 'left',
      category: 'cover',
      label: 'Publication Indicia & Colophon',
    ),
  );

  // Pages 3..22: Spreads 2 through 12
  for (int p = 3; p <= 22; p++) {
    final int spreadIndex = (p ~/ 2) + 1;
    final String side = (p % 2 == 0) ? 'left' : 'right';

    if (zineNum == 1) {
      if (p == 6 || p == 11 || p == 14 || p == 18 || p == 22) {
        pages.add(
          BundlePageDef(
            zineNum: zineNum,
            pageNum: p,
            spreadNum: spreadIndex,
            side: side,
            category: 'ad',
            label: 'Vintage Sponsor Ad',
          ),
        );
      } else {
        pages.add(
          BundlePageDef(
            zineNum: zineNum,
            pageNum: p,
            spreadNum: spreadIndex,
            side: side,
            category: 'letters',
            label: 'Archival Radius Letter',
          ),
        );
      }
    } else if (zineNum == 2) {
      if (p == 4 ||
          p == 8 ||
          p == 12 ||
          p == 15 ||
          p == 17 ||
          p == 20 ||
          p == 22) {
        pages.add(
          BundlePageDef(
            zineNum: zineNum,
            pageNum: p,
            spreadNum: spreadIndex,
            side: side,
            category: 'ad',
            label: 'Sponsor Advertisement',
          ),
        );
      } else if (p == 10 || p == 19) {
        pages.add(
          BundlePageDef(
            zineNum: zineNum,
            pageNum: p,
            spreadNum: spreadIndex,
            side: side,
            category: 'filler',
            label: 'Spot Illustration / Art',
          ),
        );
      } else {
        pages.add(
          BundlePageDef(
            zineNum: zineNum,
            pageNum: p,
            spreadNum: spreadIndex,
            side: side,
            category: 'articles',
            label: 'Feature Article / Archival Essay',
          ),
        );
      }
    } else {
      if (p == 5 || p == 9 || p == 13 || p == 16 || p == 18 || p == 21) {
        pages.add(
          BundlePageDef(
            zineNum: zineNum,
            pageNum: p,
            spreadNum: spreadIndex,
            side: side,
            category: 'ad',
            label: 'Community Sponsor Ad',
          ),
        );
      } else if (p == 7 || p == 14) {
        pages.add(
          BundlePageDef(
            zineNum: zineNum,
            pageNum: p,
            spreadNum: spreadIndex,
            side: side,
            category: 'filler',
            label: 'Spot Art / Fan Graphic',
          ),
        );
      } else if (p == 3 ||
          p == 4 ||
          p == 10 ||
          p == 11 ||
          p == 12 ||
          p == 17 ||
          p == 19 ||
          p == 20) {
        pages.add(
          BundlePageDef(
            zineNum: zineNum,
            pageNum: p,
            spreadNum: spreadIndex,
            side: side,
            category: 'letters',
            label: 'Regional Correspondent Letter',
          ),
        );
      } else {
        pages.add(
          BundlePageDef(
            zineNum: zineNum,
            pageNum: p,
            spreadNum: spreadIndex,
            side: side,
            category: 'articles',
            label: 'Convention Directory & Calendar',
          ),
        );
      }
    }
  }

  // Page 23: Closing Feature or Letter on the RIGHT of Spread 12
  pages.add(
    BundlePageDef(
      zineNum: zineNum,
      pageNum: 23,
      spreadNum: 12,
      side: 'right',
      category: zineNum == 1 ? 'letters' : 'articles',
      label: zineNum == 1 ? 'Concluding Editorial Letter' : 'Department Notes',
    ),
  );

  // Page 24: Back Cover Ad on the LEFT of Spread 13 (Right is Blank space)
  pages.add(
    BundlePageDef(
      zineNum: zineNum,
      pageNum: 24,
      spreadNum: 13,
      side: 'left',
      category: 'ad',
      label: 'Back Cover Sponsor Ad',
    ),
  );

  return pages;
}
