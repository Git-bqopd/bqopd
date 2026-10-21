import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';
import '../../utils/unsaved_fanzine_registry.dart';

/// Default fanzine series metadata options matching the curator workspace choices.
const Map<String, String> _defaultSeriesOptions = {
  '': 'no series / independent',
  'the-fantasy-fan': 'the fantasy fan',
  'the-comet-cosmology': 'the comet / cosmology',
  'phantagraph': 'phantagraph',
  'science-fiction-digest': 'science-fiction-digest / fantasy magazine',
  'the-planet': 'the planet',
  'the-time-traveller': 'the time traveller',
  'futuria-fantasia': 'futuria fantasia',
};

/// Model representing a single miniature page definition inside the 72-page recipient bundle.
class BundlePageDef {
  final int zineNum; // 1, 2, or 3
  final int pageNum; // 1..24
  final int spreadNum; // 1..13 (Spread 1 has blank left, Spread 13 has blank right)
  final String side; // 'left' or 'right'
  final String category; // 'cover', 'ad', 'letters', 'articles', 'filler'
  final String label;

  const BundlePageDef({
    required this.zineNum,
    required this.pageNum,
    required this.spreadNum,
    required this.side,
    required this.category,
    required this.label,
  });
}

/// Model representing a fanzine scheduled for publication during a specific weekly print run.
/// Every fanzine is exactly 24 pages and can automatically carry over week-to-week.
class ScheduledFanzine {
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
  });

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
    );
  }
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
class CirculationRecipient {
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
    ].join(', ') + (zipCode.trim().isNotEmpty ? ' ${zipCode.trim()}' : '');
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
}

/// Model representing a single publication week in the production schedule.
class PublishingWeek {
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
  DateTime currentMonday = jan1.subtract(Duration(days: jan1.weekday - DateTime.monday));

  for (int i = 1; i <= 52; i++) {
    final currentSunday = currentMonday.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

    final bool isCurrent = now.isAfter(currentMonday.subtract(const Duration(seconds: 1))) &&
        now.isBefore(currentSunday.add(const Duration(seconds: 1)));
    final bool isPast = currentSunday.isBefore(now);
    final int count = publishedCounts[i] ?? 0;
    final bool hasPublished = count > 0;

    if (isPast && !hasPublished && !isCurrent) {
      currentMonday = currentMonday.add(const Duration(days: 7));
      continue;
    }

    final String startMonthStr = months[currentMonday.month - 1];
    final String startDateFormatted = '$startMonthStr ${currentMonday.day}, $year';

    weeks.add(PublishingWeek(
      weekNumber: i,
      year: year,
      startDate: currentMonday,
      endDate: currentSunday,
      startDateString: startDateFormatted,
      isCurrent: isCurrent,
      isPast: isPast,
      publishedCount: count,
    ));

    currentMonday = currentMonday.add(const Duration(days: 7));
  }

  return weeks;
}

const Map<String, String> _categoryColors = {
  'cover': '#6750A4',     // Primary Purple (Covers / Indicia)
  'ad': '#F59E0B',        // Amber (Advertisements)
  'letters': '#10B981',   // Emerald (Radius Letters)
  'articles': '#3B82F6',  // Blue (Articles / Essays)
  'filler': '#94A3B8',    // Slate (Fillers / Spot Art)
};

List<BundlePageDef> _generateZineBundlePages(int zineNum, {String? customTitle}) {
  final List<BundlePageDef> pages = [];
  final String titlePrefix = customTitle != null && customTitle.isNotEmpty
      ? customTitle
      : (zineNum == 1 ? 'Radius Letters' : (zineNum == 2 ? 'Fiction & Articles' : 'Community Directory'));

  // Page 1: Front Cover on the RIGHT of Spread 1 (Left is Blank space)
  pages.add(BundlePageDef(
    zineNum: zineNum,
    pageNum: 1,
    spreadNum: 1,
    side: 'right',
    category: 'cover',
    label: '$titlePrefix Cover Plate',
  ));

  // Page 2: Inside Indicia on the LEFT of Spread 2
  pages.add(BundlePageDef(
    zineNum: zineNum,
    pageNum: 2,
    spreadNum: 2,
    side: 'left',
    category: 'cover',
    label: 'Publication Indicia & Colophon',
  ));

  // Pages 3..22: Spreads 2 through 12
  for (int p = 3; p <= 22; p++) {
    final int spreadIndex = (p ~/ 2) + 1;
    final String side = (p % 2 == 0) ? 'left' : 'right';

    if (zineNum == 1) {
      if (p == 6 || p == 11 || p == 14 || p == 18 || p == 22) {
        pages.add(BundlePageDef(
          zineNum: zineNum,
          pageNum: p,
          spreadNum: spreadIndex,
          side: side,
          category: 'ad',
          label: 'Vintage Sponsor Ad',
        ));
      } else {
        pages.add(BundlePageDef(
          zineNum: zineNum,
          pageNum: p,
          spreadNum: spreadIndex,
          side: side,
          category: 'letters',
          label: 'Archival Radius Letter',
        ));
      }
    } else if (zineNum == 2) {
      if (p == 4 || p == 8 || p == 12 || p == 15 || p == 17 || p == 20 || p == 22) {
        pages.add(BundlePageDef(
          zineNum: zineNum,
          pageNum: p,
          spreadNum: spreadIndex,
          side: side,
          category: 'ad',
          label: 'Sponsor Advertisement',
        ));
      } else if (p == 10 || p == 19) {
        pages.add(BundlePageDef(
          zineNum: zineNum,
          pageNum: p,
          spreadNum: spreadIndex,
          side: side,
          category: 'filler',
          label: 'Spot Illustration / Art',
        ));
      } else {
        pages.add(BundlePageDef(
          zineNum: zineNum,
          pageNum: p,
          spreadNum: spreadIndex,
          side: side,
          category: 'articles',
          label: 'Feature Article / Archival Essay',
        ));
      }
    } else {
      if (p == 5 || p == 9 || p == 13 || p == 16 || p == 18 || p == 21) {
        pages.add(BundlePageDef(
          zineNum: zineNum,
          pageNum: p,
          spreadNum: spreadIndex,
          side: side,
          category: 'ad',
          label: 'Community Sponsor Ad',
        ));
      } else if (p == 7 || p == 14) {
        pages.add(BundlePageDef(
          zineNum: zineNum,
          pageNum: p,
          spreadNum: spreadIndex,
          side: side,
          category: 'filler',
          label: 'Spot Art / Fan Graphic',
        ));
      } else if (p == 3 || p == 4 || p == 10 || p == 11 || p == 12 || p == 17 || p == 19 || p == 20) {
        pages.add(BundlePageDef(
          zineNum: zineNum,
          pageNum: p,
          spreadNum: spreadIndex,
          side: side,
          category: 'letters',
          label: 'Regional Correspondent Letter',
        ));
      } else {
        pages.add(BundlePageDef(
          zineNum: zineNum,
          pageNum: p,
          spreadNum: spreadIndex,
          side: side,
          category: 'articles',
          label: 'Convention Directory & Calendar',
        ));
      }
    }
  }

  // Page 23: Closing Feature or Letter on the RIGHT of Spread 12
  pages.add(BundlePageDef(
    zineNum: zineNum,
    pageNum: 23,
    spreadNum: 12,
    side: 'right',
    category: zineNum == 1 ? 'letters' : 'articles',
    label: zineNum == 1 ? 'Concluding Editorial Letter' : 'Department Notes',
  ));

  // Page 24: Back Cover Ad on the LEFT of Spread 13 (Right is Blank space)
  pages.add(BundlePageDef(
    zineNum: zineNum,
    pageNum: 24,
    spreadNum: 13,
    side: 'left',
    category: 'ad',
    label: 'Back Cover Sponsor Ad',
  ));

  return pages;
}

/// The central studio dashboard for the dedicated `/publisher` production desk.
class PublisherColumnPanel extends StatefulComponent {
  const PublisherColumnPanel({super.key});

  @override
  State<PublisherColumnPanel> createState() => _PublisherColumnPanelState();
}

class _PublisherColumnPanelState extends State<PublisherColumnPanel> {
  int _selectedYear = DateTime.now().year;
  int? _selectedWeekNumber;
  List<PublishingWeek> _weeks = [];
  Map<int, int> _publishedCounts = {};
  FirebaseSubscription? _fanzinesSub;

  // Active takeover screens
  PublishingWeek? _activeWeekDashboard;
  PublishingWeek? _activeCirculationWeek;

  // Interactive 72-page visualizer filter state
  String? _activeCategoryFilter;

  // Scheduled Fanzines per week (cache & firestore subscription)
  final Map<String, List<ScheduledFanzine>> _weeklyFanzinesCache = {};
  FirebaseSubscription? _scheduledFanzinesSub;

  // Series selection map (loaded dynamically from database, falls back to default choices)
  Map<String, String> _seriesOptionsMap = Map.from(_defaultSeriesOptions);
  FirebaseSubscription? _seriesSub;

  // Create Fanzine Modal form state
  bool _showCreateFanzineModal = false;
  String _formTitle = '';
  String _formSeries = '';
  String _formVolume = '1';
  String _formIssue = '1';
  String _formWholeNumber = '1';
  bool _isCreatingFanzine = false;
  String? _formError;

  // Circulation recipient state per week ID
  final Map<String, List<CirculationRecipient>> _circulationCache = {};
  FirebaseSubscription? _circulationSub;

  // User search & profiles state
  List<Map<String, dynamic>> _allProfiles = [];
  FirebaseSubscription? _profilesSub;
  String _userSearchQuery = '';
  bool _searchDropdownOpen = false;

  // Manual contact creation form state
  bool _showAddManualForm = false;
  String _manualDisplayName = '';
  String _manualStreet1 = '';
  String _manualStreet2 = '';
  String _manualCity = '';
  String _manualState = '';
  String _manualZip = '';
  String _manualCountry = '';
  String _manualNotes = '';
  String? _manualFormError;

  // Recipient address editor modal state
  CirculationRecipient? _editingRecipient;
  String _editStreet1 = '';
  String _editStreet2 = '';
  String _editCity = '';
  String _editState = '';
  String _editZip = '';
  String _editCountry = '';
  String _editNotes = '';

  @override
  void initState() {
    super.initState();
    _rebuildWeeks();

    if (kIsWeb) {
      _listenToPublishedIssues();
      _listenToProfiles();
      _listenToSeries();
    }
  }

  @override
  void dispose() {
    _fanzinesSub?.callAsFunction();
    _profilesSub?.callAsFunction();
    _seriesSub?.callAsFunction();
    _circulationSub?.callAsFunction();
    _scheduledFanzinesSub?.callAsFunction();
    super.dispose();
  }

  void _listenToSeries() {
    _seriesSub?.callAsFunction();
    _seriesSub = fsListenQuery('artifacts/bqopd/public/data/series', '', '', '', '', false, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        final Map<String, String> loaded = {
          '': 'no series / independent',
        };
        for (var item in decoded) {
          final id = item['id'] as String? ?? '';
          final data = item['data'] as Map<String, dynamic>? ?? {};
          if (id.isNotEmpty) {
            loaded[id] = (data['name'] ?? id).toString();
          }
        }
        for (var e in _defaultSeriesOptions.entries) {
          if (!loaded.containsKey(e.key)) {
            loaded[e.key] = e.value;
          }
        }
        if (mounted) {
          setState(() {
            _seriesOptionsMap = loaded;
          });
        }
      } catch (e) {
        print('[PublisherColumnPanel] Error streaming series: $e');
      }
    });
  }

  void _listenToProfiles() {
    _profilesSub?.callAsFunction();
    _profilesSub = fsListenQuery('profiles', '', '', '', '', false, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        final List<Map<String, dynamic>> list = [];
        for (var d in decoded) {
          final rawData = d['data'];
          final Map<String, dynamic> data =
          rawData is Map ? Map<String, dynamic>.from(rawData) : {};
          final String docId = d['id'] ?? data['uid'] ?? '';
          data['id'] = docId;
          data['uid'] = docId;
          list.add(data);
        }
        list.sort((a, b) {
          final String nameA =
          (a['displayName'] ?? a['username'] ?? '').toString().toLowerCase();
          final String nameB =
          (b['displayName'] ?? b['username'] ?? '').toString().toLowerCase();
          return nameA.compareTo(nameB);
        });
        if (mounted) {
          setState(() {
            _allProfiles = list;
          });
        }
      } catch (e) {
        print('[PublisherColumnPanel] Error streaming profiles: $e');
      }
    });
  }

  void _listenToPublishedIssues() {
    _fanzinesSub?.callAsFunction();
    _fanzinesSub = fsListenQuery('fanzines', 'isLive', '==', 'true', '', false, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        final Map<int, int> counts = {};

        for (var item in decoded) {
          final data = item['data'] as Map<String, dynamic>? ?? {};
          DateTime? pubDate;

          if (data['publishedAt'] != null && data['publishedAt'] is int) {
            pubDate = DateTime.fromMillisecondsSinceEpoch(data['publishedAt'] as int);
          } else if (data['publishedDate'] != null) {
            pubDate = DateTime.tryParse(data['publishedDate'].toString());
          } else if (data['creationDate'] != null) {
            final c = data['creationDate'];
            if (c is int) {
              pubDate = DateTime.fromMillisecondsSinceEpoch(c);
            } else if (c is Map && c['iso'] != null) {
              pubDate = DateTime.tryParse(c['iso'].toString());
            }
          }

          if (pubDate != null && pubDate.year == _selectedYear) {
            final jan1 = DateTime(_selectedYear, 1, 1);
            final firstMonday = jan1.subtract(Duration(days: jan1.weekday - DateTime.monday));
            final diffDays = pubDate.difference(firstMonday).inDays;
            if (diffDays >= 0) {
              final weekNum = (diffDays ~/ 7) + 1;
              if (weekNum >= 1 && weekNum <= 52) {
                counts[weekNum] = (counts[weekNum] ?? 0) + 1;
              }
            }
          }
        }

        if (mounted) {
          setState(() {
            _publishedCounts = counts;
            _rebuildWeeks();
          });
        }
      } catch (e) {
        print('[PublisherColumnPanel] Error parsing published issues: $e');
      }
    });
  }

  void _rebuildWeeks() {
    _weeks = generatePublishingWeeks(
      _selectedYear,
      publishedCounts: _publishedCounts,
    );

    if (_weeks.isNotEmpty) {
      final hasCurrentSelection = _weeks.any((w) => w.weekNumber == _selectedWeekNumber);
      if (!hasCurrentSelection) {
        final currentWeek = _weeks.firstWhere(
              (w) => w.isCurrent,
          orElse: () => _weeks.first,
        );
        _selectedWeekNumber = currentWeek.weekNumber;
      }
    }
  }

  void _openWeekDashboard(PublishingWeek week) {
    setState(() {
      _selectedWeekNumber = week.weekNumber;
      _activeWeekDashboard = week;
      _activeCirculationWeek = null;
      _activeCategoryFilter = null;
    });
    _loadCirculationForWeek(week);
    _loadFanzinesForWeek(week);
  }

  void _closeWeekDashboard() {
    _scheduledFanzinesSub?.callAsFunction();
    _scheduledFanzinesSub = null;
    setState(() {
      _activeWeekDashboard = null;
      _activeCirculationWeek = null;
      _activeCategoryFilter = null;
    });
  }

  void _loadFanzinesForWeek(PublishingWeek week) {
    final weekId = week.weekId;

    // 1. Check local cache first
    final cachedJson = getLocalPreference('publisher_schedule_$weekId');
    if (cachedJson != null && cachedJson.isNotEmpty) {
      try {
        final List decoded = jsonDecode(cachedJson);
        final list = decoded.map((m) => ScheduledFanzine.fromMap(m as Map<String, dynamic>)).toList();
        setState(() {
          _weeklyFanzinesCache[weekId] = list;
        });
      } catch (_) {}
    }

    // 2. Listen to Firestore schedule doc for real-time collaboration
    final currentUid = getCurrentUserId() ?? 'system';
    final path = 'Users/$currentUid/publisher_schedule/$weekId';
    _scheduledFanzinesSub?.callAsFunction();
    _scheduledFanzinesSub = fsListenDoc(path, (String jsonStr) {
      try {
        final doc = jsonDecode(jsonStr);
        if (doc['exists'] == true && doc['data'] is Map) {
          final data = doc['data'] as Map<String, dynamic>;
          final rawList = data['fanzines'] as List? ?? [];
          final list = rawList
              .whereType<Map>()
              .map((m) => ScheduledFanzine.fromMap(Map<String, dynamic>.from(m)))
              .toList();
          if (mounted) {
            setState(() {
              _weeklyFanzinesCache[weekId] = list;
            });
            saveLocalPreference('publisher_schedule_$weekId', jsonEncode(list.map((f) => f.toMap()).toList()));
          }
        } else {
          // If no fanzines exist for this week yet, execute automated week-to-week carryover
          _executeAutomaticCarryover(week);
        }
      } catch (e) {
        print('[PublisherColumnPanel] Error listening to weekly fanzines: $e');
      }
    });
  }

  /// Finds the prior week's active publications and automatically carries them forward into [week].
  Future<void> _executeAutomaticCarryover(PublishingWeek week) async {
    final currentUid = getCurrentUserId() ?? 'system';
    final currentWeekIndex = _weeks.indexWhere((w) => w.weekNumber == week.weekNumber);
    if (currentWeekIndex <= 0) return;

    // Search backward for the most recent week with active fanzines
    List<ScheduledFanzine> previousFanzines = [];
    int deltaWeeks = 0;

    for (int i = currentWeekIndex - 1; i >= 0; i--) {
      final prevWeek = _weeks[i];
      final prevWeekId = prevWeek.weekId;
      var candidateList = _weeklyFanzinesCache[prevWeekId];

      if (candidateList == null || candidateList.isEmpty) {
        final cached = getLocalPreference('publisher_schedule_$prevWeekId');
        if (cached != null && cached.isNotEmpty) {
          try {
            final List dec = jsonDecode(cached);
            candidateList = dec.map((m) => ScheduledFanzine.fromMap(m as Map<String, dynamic>)).toList();
            _weeklyFanzinesCache[prevWeekId] = candidateList;
          } catch (_) {}
        }
      }

      if (candidateList != null && candidateList.isNotEmpty) {
        previousFanzines = candidateList.where((f) => !f.isCanceled).toList();
        deltaWeeks = week.weekNumber - prevWeek.weekNumber;
        break;
      }
    }

    if (previousFanzines.isEmpty) return;

    final List<ScheduledFanzine> carriedOverList = [];
    final currentWeekId = week.weekId;

    for (final prev in previousFanzines) {
      final int prevNum = int.tryParse(prev.issue) ?? 1;
      final int nextNum = prevNum + math.max(1, deltaWeeks);
      final int prevWhole = int.tryParse(prev.wholeNumber) ?? prevNum;
      final int nextWhole = prevWhole + math.max(1, deltaWeeks);

      final String nextTitle = incrementIssueTitle(prev.title, nextNum);
      final String fanzineId = 'folio_${DateTime.now().millisecondsSinceEpoch}_${carriedOverList.length}';
      final String shortCode = ShortcodeGenerator.generateStandardCode();

      final carriedFanzine = ScheduledFanzine(
        id: fanzineId,
        title: nextTitle,
        series: prev.series,
        volume: prev.volume,
        issue: '$nextNum',
        wholeNumber: '$nextWhole',
        pageCount: 24,
        shortCode: shortCode,
        weekId: currentWeekId,
        isCanceled: false,
        parentFanzineId: prev.id,
        createdAt: DateTime.now(),
      );

      carriedOverList.add(carriedFanzine);

      // Register the carried-over fanzine model in database as a 24-page template folio
      _createFanzineDocumentInBackend(
        fanzine: carriedFanzine,
        startDateString: week.startDateString,
        ownerId: currentUid,
      );
    }

    await _persistWeeklyFanzines(currentWeekId, carriedOverList);
  }

  Future<void> _persistWeeklyFanzines(String weekId, List<ScheduledFanzine> list) async {
    setState(() {
      _weeklyFanzinesCache[weekId] = list;
    });

    final serialized = list.map((f) => f.toMap()).toList();
    saveLocalPreference('publisher_schedule_$weekId', jsonEncode(serialized));

    final currentUid = getCurrentUserId() ?? 'system';
    final path = 'Users/$currentUid/publisher_schedule/$weekId';
    try {
      await fsSetDoc(
        path,
        jsonEncode({
          'weekId': weekId,
          'fanzines': serialized,
          'updatedAt': WebFieldValue.serverTimestamp(),
        }),
        true,
      );
    } catch (e) {
      print('[PublisherColumnPanel] Error persisting weekly fanzines: $e');
    }
  }

  Future<void> _createFanzineDocumentInBackend({
    required ScheduledFanzine fanzine,
    required String startDateString,
    required String ownerId,
  }) async {
    try {
      final fzData = {
        'id': fanzine.id,
        'title': fanzine.title,
        'series': fanzine.series,
        'volume': fanzine.volume,
        'issue': fanzine.issue,
        'wholeNumber': fanzine.wholeNumber,
        'type': 'folio',
        'isLive': false,
        'twoPage': true,
        'hasCover': true,
        'processingStatus': 'ready',
        'shortCode': fanzine.shortCode,
        'shortCodeKey': fanzine.shortCode.toUpperCase(),
        'ownerId': ownerId,
        'editorId': ownerId,
        'curators': [ownerId],
        'collections': [ownerId],
        'publishedDate': startDateString,
        'creationDate': WebFieldValue.serverTimestamp(),
        'draftEntities': [],
        'masterCreators': [],
      };

      await fsSetDoc('fanzines/${fanzine.id}', jsonEncode(fzData), true);

      // Create 24 template pages in the subcollection
      final List<FanzinePage> pages = [];
      for (int p = 1; p <= 24; p++) {
        final pageId = 'page_${DateTime.now().millisecondsSinceEpoch}_$p';
        pages.add(FanzinePage(
          id: pageId,
          pageNumber: p,
          templateId: 'basic_text',
          width: 2000,
          height: 3200,
          is5x8: true,
          status: 'ready',
        ));

        await fsSetDoc('fanzines/${fanzine.id}/pages/$pageId', jsonEncode({
          'pageNumber': p,
          'status': 'ready',
          'templateId': 'basic_text',
          'width': 2000,
          'height': 3200,
          'is5x8': true,
          'createdAt': WebFieldValue.serverTimestamp(),
        }), true);
      }

      await fsSetDoc('shortcodes/${fanzine.shortCode.toUpperCase()}', jsonEncode({
        'type': 'fanzine',
        'contentId': fanzine.id,
        'displayCode': fanzine.shortCode,
        'createdAt': WebFieldValue.serverTimestamp(),
      }), true);

      // Register into memory registry for instant zero-latency loading
      UnsavedFanzineRegistry.add(
        Fanzine(
          id: fanzine.id,
          title: fanzine.title,
          series: fanzine.series,
          volume: fanzine.volume,
          issue: fanzine.issue,
          wholeNumber: fanzine.wholeNumber,
          type: FanzineType.folio,
          isLive: false,
          processingStatus: 'ready',
          ownerId: ownerId,
          twoPage: true,
          hasCover: true,
          shortCode: fanzine.shortCode,
          publishedDate: startDateString,
        ),
        pages,
      );
    } catch (e) {
      print('[PublisherColumnPanel] Error creating fanzine document: $e');
    }
  }

  Future<void> _submitNewFanzineForm() async {
    final week = _activeWeekDashboard;
    if (week == null) return;

    final cleanTitle = _formTitle.trim();
    if (cleanTitle.isEmpty) {
      setState(() => _formError = 'Please enter a fanzine title.');
      return;
    }

    setState(() {
      _isCreatingFanzine = true;
      _formError = null;
    });

    final currentUid = getCurrentUserId() ?? 'system';
    final weekId = week.weekId;
    final currentList = List<ScheduledFanzine>.from(_weeklyFanzinesCache[weekId] ?? []);

    final String fanzineId = 'folio_${DateTime.now().millisecondsSinceEpoch}';
    final String shortCode = ShortcodeGenerator.generateStandardCode();

    final newFanzine = ScheduledFanzine(
      id: fanzineId,
      title: cleanTitle,
      series: _formSeries,
      volume: _formVolume.trim(),
      issue: _formIssue.trim(),
      wholeNumber: _formWholeNumber.trim(),
      pageCount: 24,
      shortCode: shortCode,
      weekId: weekId,
      isCanceled: false,
      createdAt: DateTime.now(),
    );

    await _createFanzineDocumentInBackend(
      fanzine: newFanzine,
      startDateString: week.startDateString,
      ownerId: currentUid,
    );

    currentList.add(newFanzine);
    await _persistWeeklyFanzines(weekId, currentList);

    setState(() {
      _showCreateFanzineModal = false;
      _formTitle = '';
      _formSeries = '';
      _formVolume = '1';
      _formIssue = '1';
      _formWholeNumber = '1';
      _isCreatingFanzine = false;
      _formError = null;
    });
  }

  Future<void> _toggleFanzineCancellation(ScheduledFanzine fanzine) async {
    final week = _activeWeekDashboard;
    if (week == null) return;

    final weekId = week.weekId;
    final currentList = List<ScheduledFanzine>.from(_weeklyFanzinesCache[weekId] ?? []);
    final idx = currentList.indexWhere((f) => f.id == fanzine.id);

    if (idx != -1) {
      currentList[idx] = fanzine.copyWith(isCanceled: !fanzine.isCanceled);
      await _persistWeeklyFanzines(weekId, currentList);
    }
  }

  Future<void> _deleteScheduledFanzine(String fanzineId) async {
    final week = _activeWeekDashboard;
    if (week == null) return;

    final weekId = week.weekId;
    final currentList = List<ScheduledFanzine>.from(_weeklyFanzinesCache[weekId] ?? [])
      ..removeWhere((f) => f.id == fanzineId);

    await _persistWeeklyFanzines(weekId, currentList);
  }

  void _openCirculation(PublishingWeek week) {
    setState(() {
      _selectedWeekNumber = week.weekNumber;
      _activeCirculationWeek = week;
      _userSearchQuery = '';
      _searchDropdownOpen = false;
      _showAddManualForm = false;
      _editingRecipient = null;
    });
    _loadCirculationForWeek(week);
  }

  void _closeCirculation() {
    _circulationSub?.callAsFunction();
    _circulationSub = null;
    setState(() {
      _activeCirculationWeek = null;
      _editingRecipient = null;
      _showAddManualForm = false;
    });
  }

  void _loadCirculationForWeek(PublishingWeek week) {
    final weekId = week.weekId;

    final cachedJson = getLocalPreference('circulation_$weekId');
    if (cachedJson != null && cachedJson.isNotEmpty) {
      try {
        final List decoded = jsonDecode(cachedJson);
        final list = decoded.map((m) => CirculationRecipient.fromMap(m as Map<String, dynamic>)).toList();
        setState(() {
          _circulationCache[weekId] = list;
        });
      } catch (_) {}
    }

    final currentUid = getCurrentUserId() ?? 'system';
    final path = 'Users/$currentUid/circulation/$weekId';
    _circulationSub?.callAsFunction();
    _circulationSub = fsListenDoc(path, (String jsonStr) {
      try {
        final doc = jsonDecode(jsonStr);
        if (doc['exists'] == true && doc['data'] is Map) {
          final data = doc['data'] as Map<String, dynamic>;
          final rawList = data['recipients'] as List? ?? [];
          final list = rawList
              .whereType<Map>()
              .map((m) => CirculationRecipient.fromMap(Map<String, dynamic>.from(m)))
              .toList();
          if (mounted) {
            setState(() {
              _circulationCache[weekId] = list;
            });
            saveLocalPreference('circulation_$weekId', jsonEncode(list.map((r) => r.toMap()).toList()));
          }
        }
      } catch (e) {
        print('[PublisherColumnPanel] Error listening to circulation doc: $e');
      }
    });
  }

  Future<void> _persistCirculation(String weekId, List<CirculationRecipient> list) async {
    setState(() {
      _circulationCache[weekId] = list;
    });

    final serialized = list.map((r) => r.toMap()).toList();
    saveLocalPreference('circulation_$weekId', jsonEncode(serialized));

    final currentUid = getCurrentUserId() ?? 'system';
    final path = 'Users/$currentUid/circulation/$weekId';
    try {
      await fsSetDoc(
        path,
        jsonEncode({
          'weekId': weekId,
          'recipients': serialized,
          'updatedAt': WebFieldValue.serverTimestamp(),
        }),
        true,
      );
    } catch (e) {
      print('[PublisherColumnPanel] Error persisting circulation to Firestore: $e');
    }
  }

  Future<void> _addUserProfileToCirculation(Map<String, dynamic> profile) async {
    final week = _activeCirculationWeek ?? _activeWeekDashboard;
    if (week == null) return;

    final weekId = week.weekId;
    final currentList = List<CirculationRecipient>.from(_circulationCache[weekId] ?? []);
    final String uid = profile['uid'] ?? profile['id'] ?? '';

    if (currentList.any((r) => r.id == uid)) {
      setState(() {
        _searchDropdownOpen = false;
        _userSearchQuery = '';
      });
      return;
    }

    final String displayName = (profile['displayName'] ?? profile['username'] ?? 'User').toString();
    final String? username = profile['username']?.toString();
    final String? photoUrl = profile['photoUrl']?.toString();

    String s1 = (profile['street1'] ?? '').toString().trim();
    String s2 = (profile['street2'] ?? '').toString().trim();
    String city = (profile['city'] ?? '').toString().trim();
    String state = (profile['state'] ?? '').toString().trim();
    String zip = (profile['zipCode'] ?? '').toString().trim();
    String country = (profile['country'] ?? '').toString().trim();

    if (s1.isEmpty && uid.isNotEmpty) {
      try {
        final uRes = await fsGetDoc('Users/$uid');
        final uDoc = jsonDecode(uRes);
        if (uDoc['exists'] == true && uDoc['data'] is Map) {
          final uData = uDoc['data'] as Map<String, dynamic>;
          if (s1.isEmpty && uData['street1'] != null) s1 = uData['street1'].toString();
          if (s2.isEmpty && uData['street2'] != null) s2 = uData['street2'].toString();
          if (city.isEmpty && uData['city'] != null) city = uData['city'].toString();
          if (state.isEmpty && uData['state'] != null) state = uData['state'].toString();
          if (zip.isEmpty && uData['zipCode'] != null) zip = uData['zipCode'].toString();
          if (country.isEmpty && uData['country'] != null) country = uData['country'].toString();
        }
      } catch (_) {}
    }

    final recipient = CirculationRecipient(
      id: uid,
      displayName: displayName,
      username: username,
      photoUrl: photoUrl,
      hasProfile: true,
      street1: s1,
      street2: s2,
      city: city,
      state: state,
      zipCode: zip,
      country: country,
      addedAt: DateTime.now(),
    );

    currentList.add(recipient);
    setState(() {
      _searchDropdownOpen = false;
      _userSearchQuery = '';
    });
    await _persistCirculation(weekId, currentList);
  }

  Future<void> _submitManualRecipient() async {
    final week = _activeCirculationWeek ?? _activeWeekDashboard;
    if (week == null) return;

    final cleanName = _manualDisplayName.trim();
    if (cleanName.isEmpty) {
      setState(() {
        _manualFormError = 'Please enter a real name.';
      });
      return;
    }

    final weekId = week.weekId;
    final currentList = List<CirculationRecipient>.from(_circulationCache[weekId] ?? []);
    final manualId = 'manual_${DateTime.now().millisecondsSinceEpoch}';

    final recipient = CirculationRecipient(
      id: manualId,
      displayName: cleanName,
      username: null,
      photoUrl: null,
      hasProfile: false,
      street1: _manualStreet1.trim(),
      street2: _manualStreet2.trim(),
      city: _manualCity.trim(),
      state: _manualState.trim(),
      zipCode: _manualZip.trim(),
      country: _manualCountry.trim(),
      notes: _manualNotes.trim().isNotEmpty ? _manualNotes.trim() : null,
      addedAt: DateTime.now(),
    );

    currentList.add(recipient);
    setState(() {
      _showAddManualForm = false;
      _manualDisplayName = '';
      _manualStreet1 = '';
      _manualStreet2 = '';
      _manualCity = '';
      _manualState = '';
      _manualZip = '';
      _manualCountry = '';
      _manualNotes = '';
      _manualFormError = null;
    });
    await _persistCirculation(weekId, currentList);
  }

  Future<void> _removeRecipient(String recipientId) async {
    final week = _activeCirculationWeek ?? _activeWeekDashboard;
    if (week == null) return;

    final weekId = week.weekId;
    final currentList = List<CirculationRecipient>.from(_circulationCache[weekId] ?? [])
      ..removeWhere((r) => r.id == recipientId);
    await _persistCirculation(weekId, currentList);
  }

  void _openEditAddress(CirculationRecipient recipient) {
    setState(() {
      _editingRecipient = recipient;
      _editStreet1 = recipient.street1;
      _editStreet2 = recipient.street2;
      _editCity = recipient.city;
      _editState = recipient.state;
      _editZip = recipient.zipCode;
      _editCountry = recipient.country;
      _editNotes = recipient.notes ?? '';
    });
  }

  Future<void> _saveEditedAddress() async {
    final week = _activeCirculationWeek ?? _activeWeekDashboard;
    final target = _editingRecipient;
    if (week == null || target == null) return;

    final weekId = week.weekId;
    final currentList = List<CirculationRecipient>.from(_circulationCache[weekId] ?? []);
    final idx = currentList.indexWhere((r) => r.id == target.id);
    if (idx != -1) {
      currentList[idx] = CirculationRecipient(
        id: target.id,
        displayName: target.displayName,
        username: target.username,
        photoUrl: target.photoUrl,
        hasProfile: target.hasProfile,
        street1: _editStreet1.trim(),
        street2: _editStreet2.trim(),
        city: _editCity.trim(),
        state: _editState.trim(),
        zipCode: _editZip.trim(),
        country: _editCountry.trim(),
        notes: _editNotes.trim().isNotEmpty ? _editNotes.trim() : null,
        addedAt: target.addedAt,
      );
      setState(() {
        _editingRecipient = null;
      });
      await _persistCirculation(weekId, currentList);
    }
  }

  void _toggleCategoryFilter(String cat) {
    setState(() {
      if (_activeCategoryFilter == cat) {
        _activeCategoryFilter = null;
      } else {
        _activeCategoryFilter = cat;
      }
    });
  }

  @override
  Component build(BuildContext context) {
    if (_activeCirculationWeek != null) {
      return _buildCirculationPage(_activeCirculationWeek!);
    }

    if (_activeWeekDashboard != null) {
      return _buildWeekDashboardPage(_activeWeekDashboard!);
    }

    return div(
      classes: 'flex-col gap-3 w-full',
      attributes: const {
        'style':
        'display: flex; flex-direction: column; gap: 12px; width: 100%; box-sizing: border-box;',
      },
      [
        // Header Section
        div(
          classes: 'flex-row justify-between items-center pb-2 mb-2',
          attributes: const {
            'style':
            'display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #d1d5db; padding-bottom: 8px;',
          },
          [
            div([
              span(
                [Component.text('PRODUCTION SCHEDULE')],
                attributes: const {
                  'style':
                  'font-size: 11px; font-weight: bold; color: #475569; letter-spacing: 0.8px; text-transform: uppercase;',
                },
              ),
              span(
                [Component.text('weekly release desk')],
                attributes: const {
                  'style':
                  'font-size: 10px; color: #94a3b8; display: block; margin-top: 1px;',
                },
              ),
            ]),
            span(
              [Component.text('$_selectedYear')],
              attributes: const {
                'style':
                'font-size: 11px; font-weight: bold; color: #1e293b; background: #ffffff; border: 1px solid #cbd5e1; border-radius: 4px; padding: 2px 8px;',
              },
            ),
          ],
        ),

        // List of Weekly Cards
        for (final week in _weeks)
          _buildWeekCard(week),
      ],
    );
  }

  Component _buildWeekCard(PublishingWeek week) {
    final bool isSelected = week.weekNumber == _selectedWeekNumber;
    final cachedList = _circulationCache[week.weekId];
    final int recipientCount = cachedList?.length ?? 0;

    return div(
      classes: 'publisher-week-card transition-all',
      attributes: {
        'style':
        'width: 100%; background-color: #ffffff; border: ${isSelected ? "2px solid #6750A4" : "1px solid #cbd5e1"}; '
            'border-radius: 8px; padding: 14px 16px; box-sizing: border-box; cursor: pointer; '
            'box-shadow: ${isSelected ? "0 4px 12px rgba(103, 80, 164, 0.15)" : "0 1px 3px rgba(0, 0, 0, 0.05)"}; '
            'transition: all 0.15s ease;',
      },
      events: {
        'click': (e) => _openWeekDashboard(week),
      },
      [
        // Top Row: Week Number and Status Badge
        div(
          classes: 'flex-row justify-between items-center mb-1',
          attributes: const {
            'style':
            'display: flex; justify-content: space-between; align-items: center; width: 100%; margin-bottom: 6px;',
          },
          [
            span(
              [Component.text('WEEK ${week.weekNumber.toString().padLeft(2, '0')}')],
              attributes: {
                'style':
                'font-size: 13px; font-weight: 900; letter-spacing: 0.5px; color: ${isSelected ? "#6750A4" : "#1e293b"};',
              },
            ),
            _buildStatusBadge(week, isSelected),
          ],
        ),

        div(
          classes: 'flex-row justify-between items-center mt-2 pt-2',
          attributes: const {
            'style':
            'display: flex; justify-content: space-between; align-items: center; margin-top: 8px; padding-top: 8px; border-top: 1px solid #f1f5f9;',
          },
          [
            // Starting Monday Date
            div(
              classes: 'flex-row items-center gap-1',
              attributes: const {
                'style': 'display: flex; align-items: center; gap: 4px;',
              },
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {
                    'style': 'font-size: 13px; color: #64748b; line-height: 1;',
                  },
                  [Component.text('calendar_today')],
                ),
                span(
                  [Component.text(week.startDateString)],
                  attributes: const {
                    'style': 'font-size: 11px; color: #64748b; font-weight: 500;',
                  },
                ),
              ],
            ),

            // Circulation Management Button
            button(
              classes: 'circulation-btn',
              attributes: {
                'type': 'button',
                'style':
                'padding: 4px 10px; font-size: 10px; font-weight: bold; '
                    'background: ${isSelected ? "#6750A4" : "#f1f5f9"}; '
                    'color: ${isSelected ? "white" : "#475569"}; '
                    'border: 1px solid ${isSelected ? "#6750A4" : "#cbd5e1"}; '
                    'border-radius: 12px; cursor: pointer; display: inline-flex; '
                    'align-items: center; gap: 4px; transition: all 0.15s ease;',
              },
              events: {
                'click': (dynamic e) {
                  try {
                    e.stopPropagation();
                  } catch (_) {}
                  _openCirculation(week);
                },
              },
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {
                    'style': 'font-size: 13px; line-height: 1;',
                  },
                  [Component.text('group')],
                ),
                Component.text(recipientCount > 0 ? 'circulation ($recipientCount)' : 'circulation'),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Component _buildStatusBadge(PublishingWeek week, bool isSelected) {
    if (week.isCurrent) {
      return span(
        [Component.text('current')],
        attributes: const {
          'style':
          'font-size: 9px; font-weight: bold; background-color: #ecfdf5; color: #16a34a; '
              'border: 1px solid #bbf7d0; border-radius: 4px; padding: 1px 6px; text-transform: uppercase;',
        },
      );
    }

    if (week.isPast) {
      final label = week.publishedCount > 0
          ? 'archived (${week.publishedCount})'
          : 'archived';
      return span(
        [Component.text(label)],
        attributes: const {
          'style':
          'font-size: 9px; font-weight: 500; background-color: #f1f5f9; color: #475569; '
              'border: 1px solid #cbd5e1; border-radius: 4px; padding: 1px 6px; text-transform: uppercase;',
        },
      );
    }

    return span(
      [Component.text('upcoming')],
      attributes: const {
        'style':
        'font-size: 9px; font-weight: 500; background-color: #f8fafc; color: #64748b; '
            'border: 1px solid #e2e8f0; border-radius: 4px; padding: 1px 6px; text-transform: uppercase;',
      },
    );
  }

  Component _buildWeekDashboardPage(PublishingWeek week) {
    final scheduledFanzines = _weeklyFanzinesCache[week.weekId] ?? [];
    final activeFanzines = scheduledFanzines.where((f) => !f.isCanceled).toList();

    final zine1Title = activeFanzines.isNotEmpty ? activeFanzines[0].title : null;
    final zine2Title = activeFanzines.length > 1 ? activeFanzines[1].title : null;
    final zine3Title = activeFanzines.length > 2 ? activeFanzines[2].title : null;

    final zine1Pages = _generateZineBundlePages(1, customTitle: zine1Title);
    final zine2Pages = _generateZineBundlePages(2, customTitle: zine2Title);
    final zine3Pages = _generateZineBundlePages(3, customTitle: zine3Title);

    return div(
      classes: 'flex-col gap-4 w-full',
      attributes: const {
        'style':
        'display: flex; flex-direction: column; gap: 14px; width: 100%; box-sizing: border-box;',
      },
      [
        // Top Navigation & Return Header
        div(
          classes: 'flex-row items-center justify-between pb-2 border-b border-gray-300',
          attributes: const {
            'style':
            'display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #cbd5e1; padding-bottom: 8px;',
          },
          [
            button(
              classes: 'profile-btn',
              attributes: const {
                'type': 'button',
                'style':
                'display: inline-flex; align-items: center; gap: 4px; padding: 4px 10px; font-size: 11px; '
                    'font-weight: bold; border: 1px solid #cbd5e1; background: white; border-radius: 14px; cursor: pointer;',
              },
              events: {
                'click': (e) => _closeWeekDashboard(),
              },
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {'style': 'font-size: 15px; line-height: 1;'},
                  [Component.text('arrow_back')],
                ),
                Component.text('schedule'),
              ],
            ),
            div(
              attributes: const {'style': 'display: flex; align-items: center; gap: 8px;'},
              [
                span(
                  [Component.text('WEEK ${week.weekNumber.toString().padLeft(2, '0')}')],
                  attributes: const {
                    'style': 'font-size: 12px; font-weight: 900; letter-spacing: 0.5px; color: #6750A4;',
                  },
                ),
                span(
                  [Component.text('· ${week.startDateString}')],
                  attributes: const {'style': 'font-size: 11px; color: #475569; font-weight: bold;'},
                ),
                _buildStatusBadge(week, true),
              ],
            ),
          ],
        ),

        // 2-Column Responsive Dashboard Board
        div(
          classes: 'flex flex-row flex-wrap gap-4 items-start w-full',
          attributes: const {
            'style':
            'display: flex; flex-direction: row; flex-wrap: wrap; gap: 14px; align-items: flex-start; width: 100%; box-sizing: border-box;',
          },
          [
            // COLUMN 1: The 80px Micro-Spread 3-Zine Flatplan Board (Width ~284px)
            _buildMicroSpreadBoard(zine1Pages, zine2Pages, zine3Pages, activeFanzines),

            // COLUMN 2: Circulation Section, Weekly Fanzines Manager, and Category Budget
            _buildDashboardRightColumn(week, scheduledFanzines),
          ],
        ),

        // Create Fanzine Modal Dialog
        if (_showCreateFanzineModal)
          _buildCreateFanzineModal(week),
      ],
    );
  }

  Component _buildMicroSpreadBoard(
      List<BundlePageDef> zine1,
      List<BundlePageDef> zine2,
      List<BundlePageDef> zine3,
      List<ScheduledFanzine> activeFanzines,
      ) {
    final sub1 = activeFanzines.isNotEmpty ? activeFanzines[0].title : 'Radius';
    final sub2 = activeFanzines.length > 1 ? activeFanzines[1].title : 'Articles';
    final sub3 = activeFanzines.length > 2 ? activeFanzines[2].title : 'Community';

    return div(
      attributes: const {
        'style':
        'background: white; border: 1px solid #cbd5e1; border-radius: 8px; padding: 12px; '
            'display: flex; flex-direction: column; align-items: center; width: 284px; flex-shrink: 0; box-sizing: border-box; '
            'box-shadow: 0 1px 3px rgba(0,0,0,0.03);',
      },
      [
        div(
          attributes: const {
            'style':
            'display: flex; justify-content: space-between; align-items: center; width: 100%; '
                'border-bottom: 1px solid #e2e8f0; padding-bottom: 6px; margin-bottom: 8px;',
          },
          [
            span(
              [Component.text('72-PAGE BUNDLE')],
              attributes: const {
                'style':
                'font-size: 10px; font-weight: 900; color: #475569; letter-spacing: 0.5px; text-transform: uppercase;',
              },
            ),
            span(
              [Component.text('${activeFanzines.length} / 3 Zines')],
              attributes: {
                'style':
                'font-size: 9px; font-weight: bold; '
                    'color: ${activeFanzines.length == 3 ? "#16a34a" : "#ca8a04"}; '
                    'background: ${activeFanzines.length == 3 ? "#ecfdf5" : "#fefce8"}; '
                    'border: 1px solid ${activeFanzines.length == 3 ? "#bbf7d0" : "#fef08a"}; '
                    'border-radius: 4px; padding: 1px 5px;',
              },
            ),
          ],
        ),
        div(
          attributes: const {
            'style': 'display: flex; gap: 10px; justify-content: center; width: 100%;',
          },
          [
            _buildZineColumn(1, sub1, '#10B981', zine1),
            _buildZineColumn(2, sub2, '#3B82F6', zine2),
            _buildZineColumn(3, sub3, '#F59E0B', zine3),
          ],
        ),
      ],
    );
  }

  Component _buildZineColumn(
      int zineNum,
      String subtitle,
      String subtitleColor,
      List<BundlePageDef> pages,
      ) {
    return div(
      attributes: const {
        'style':
        'width: 80px; min-width: 80px; max-width: 80px; display: flex; flex-direction: column; '
            'gap: 3px; align-items: center; box-sizing: border-box;',
      },
      [
        // Column Header
        div(
          attributes: const {
            'style':
            'width: 100%; text-align: center; border-bottom: 1px solid #e2e8f0; '
                'padding-bottom: 3px; margin-bottom: 2px; overflow: hidden;',
          },
          [
            span(
              [Component.text('ZINE #$zineNum')],
              attributes: const {
                'style':
                'font-family: Anton, sans-serif; font-size: 11px; letter-spacing: 0.5px; '
                    'color: #0f172a; display: block; line-height: 1;',
              },
            ),
            span(
              [Component.text(subtitle)],
              attributes: {
                'title': subtitle,
                'style':
                'font-size: 9px; font-weight: bold; color: $subtitleColor; display: block; margin-top: 2px; '
                    'white-space: nowrap; overflow: hidden; text-overflow: ellipsis;',
              },
            ),
          ],
        ),

        // SPREAD 1 (Front Cover Spread): Blank space on Left, Page 1 on Right
        div(
          attributes: const {
            'style':
            'width: 100%; display: flex; gap: 2px; background: rgba(226, 232, 240, 0.6); '
                'padding: 2px; border-radius: 2px; box-sizing: border-box;',
          },
          [
            _buildBlankPageBox(),
            _buildMicroPageBox(pages[0]),
          ],
        ),

        // SPREADS 2..12 (Interior Facing Spreads): Pages 2 through 23
        for (int s = 1; s <= 11; s++)
          div(
            attributes: const {
              'style':
              'width: 100%; display: flex; gap: 2px; background: rgba(226, 232, 240, 0.6); '
                  'padding: 2px; border-radius: 2px; box-sizing: border-box;',
            },
            [
              _buildMicroPageBox(pages[(s - 1) * 2 + 1]),
              _buildMicroPageBox(pages[(s - 1) * 2 + 2]),
            ],
          ),

        // SPREAD 13 (Back Cover Spread): Page 24 on Left, Blank space on Right
        div(
          attributes: const {
            'style':
            'width: 100%; display: flex; gap: 2px; background: rgba(226, 232, 240, 0.6); '
                'padding: 2px; border-radius: 2px; box-sizing: border-box;',
          },
          [
            _buildMicroPageBox(pages[23]),
            _buildBlankPageBox(),
          ],
        ),
      ],
    );
  }

  Component _buildBlankPageBox() {
    return div(
      attributes: const {
        'style':
        'flex: 1; aspect-ratio: 5 / 8; background-color: #ffffff; border: 1px dashed #cbd5e1; '
            'border-radius: 1px; box-sizing: border-box; display: flex; align-items: center; justify-content: center; '
            'user-select: none; pointer-events: none;',
      },
      [],
    );
  }

  Component _buildMicroPageBox(BundlePageDef page) {
    final bool isFiltered = _activeCategoryFilter != null;
    final bool matchesFilter = page.category == _activeCategoryFilter;

    final color = _categoryColors[page.category] ?? '#6750A4';
    final double opacity = (isFiltered && !matchesFilter) ? 0.2 : 1.0;
    final String outline = matchesFilter ? '2px solid #000000' : 'none';

    return div(
      attributes: {
        'title': 'Zine #${page.zineNum} · Page ${page.pageNum} (${page.category.toUpperCase()})',
        'style':
        'flex: 1; aspect-ratio: 5 / 8; background-color: $color; border-radius: 1px; '
            'display: flex; align-items: center; justify-content: center; user-select: none; '
            'font-size: 8px; font-weight: bold; font-family: monospace; color: rgba(255, 255, 255, 0.95); '
            'opacity: $opacity; outline: $outline; outline-offset: 1px; cursor: pointer; '
            'transition: transform 0.1s ease, opacity 0.15s ease;',
      },
      events: {
        'click': (e) => _toggleCategoryFilter(page.category),
      },
      [Component.text('${page.pageNum}')],
    );
  }

  Component _buildDashboardRightColumn(PublishingWeek week, List<ScheduledFanzine> scheduledFanzines) {
    final cachedList = _circulationCache[week.weekId];
    final int recipientCount = cachedList?.length ?? 0;

    return div(
      attributes: const {
        'style':
        'display: flex; flex-direction: column; gap: 12px; flex: 1; min-width: 280px; box-sizing: border-box;',
      },
      [
        // 1. CIRCULATION CARD
        div(
          attributes: const {
            'style':
            'background: white; border: 1px solid #cbd5e1; border-radius: 8px; padding: 14px 16px; '
                'display: flex; flex-direction: column; justify-content: space-between; gap: 10px; '
                'box-sizing: border-box; box-shadow: 0 1px 3px rgba(0,0,0,0.03);',
          },
          [
            div([
              div(
                attributes: const {
                  'style': 'display: flex; align-items: center; justify-content: space-between; margin-bottom: 4px;'
                },
                [
                  div(
                    attributes: const {'style': 'display: flex; align-items: center; gap: 6px;'},
                    [
                      span(
                        classes: 'material-symbols-outlined',
                        attributes: const {'style': 'font-size: 16px; color: #6750A4;'},
                        [Component.text('mark_email_read')],
                      ),
                      span(
                        [Component.text('CIRCULATION')],
                        attributes: const {
                          'style':
                          'font-size: 10px; font-weight: 900; color: #475569; letter-spacing: 0.5px; text-transform: uppercase;',
                        },
                      ),
                    ],
                  ),
                  span(
                    [Component.text('$recipientCount recipients queued')],
                    attributes: const {'style': 'font-size: 11px; font-weight: bold; color: #1e293b;'},
                  ),
                ],
              ),
              p(
                [
                  Component.text(
                    'Manage physical recipients for this issue. Each active recipient receives a complete 72-page print bundle (3 fanzines × 24 pages).',
                  ),
                ],
                attributes: const {
                  'style': 'margin: 0; font-size: 11px; color: #64748b; line-height: 1.35;',
                },
              ),
            ]),
            button(
              classes: 'circulation-btn',
              attributes: const {
                'type': 'button',
                'style':
                'padding: 7px 14px; font-size: 11px; font-weight: bold; '
                    'background: #f3f0fb; color: #6750A4; border: 1px solid #6750A4; '
                    'border-radius: 12px; cursor: pointer; display: inline-flex; '
                    'align-items: center; justify-content: center; gap: 6px; transition: all 0.15s ease;',
              },
              events: {
                'click': (e) => _openCirculation(week),
              },
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {'style': 'font-size: 14px; line-height: 1;'},
                  [Component.text('group')],
                ),
                Component.text(recipientCount > 0 ? 'manage circulation ($recipientCount)' : 'manage circulation'),
              ],
            ),
          ],
        ),

        // 2. THIS WEEK'S FANZINES CARD (24p TEMPLATE CREATION & CANCELLATION)
        _buildWeeklyFanzinesCard(week, scheduledFanzines),

        // 3. CATEGORY ALLOCATION BUDGET CARD (PAGE INSPECTOR HAS BEEN REMOVED)
        _buildCategoryAllocationCard(),
      ],
    );
  }

  Component _buildWeeklyFanzinesCard(PublishingWeek week, List<ScheduledFanzine> scheduledFanzines) {
    final activeCount = scheduledFanzines.where((f) => !f.isCanceled).length;

    return div(
      attributes: const {
        'style':
        'background: white; border: 1px solid #cbd5e1; border-radius: 8px; padding: 14px 16px; '
            'display: flex; flex-direction: column; gap: 10px; box-sizing: border-box; box-shadow: 0 1px 3px rgba(0,0,0,0.03);',
      },
      [
        div(
          attributes: const {
            'style': 'display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #f1f5f9; padding-bottom: 6px;'
          },
          [
            div(
              attributes: const {'style': 'display: flex; align-items: center; gap: 6px;'},
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {'style': 'font-size: 16px; color: #6750A4;'},
                  [Component.text('auto_stories')],
                ),
                span(
                  [Component.text("THIS WEEK'S FANZINES ($activeCount of 3)")],
                  attributes: const {
                    'style':
                    'font-size: 10px; font-weight: 900; color: #475569; letter-spacing: 0.5px; text-transform: uppercase;',
                  },
                ),
              ],
            ),
            button(
              classes: 'profile-btn',
              attributes: const {
                'type': 'button',
                'style':
                'border: 1px solid #6750A4; background: #f3f0fb; color: #6750A4; '
                    'padding: 3px 10px; font-size: 10px; font-weight: bold; border-radius: 12px; cursor: pointer; '
                    'display: inline-flex; align-items: center; gap: 4px;',
              },
              events: {
                'click': (e) {
                  setState(() {
                    _showCreateFanzineModal = true;
                    _formTitle = '';
                    _formSeries = '';
                    _formVolume = '1';
                    _formIssue = '${scheduledFanzines.length + 1}';
                    _formWholeNumber = '${scheduledFanzines.length + 1}';
                    _formError = null;
                  });
                }
              },
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {'style': 'font-size: 13px;'},
                  [Component.text('add')],
                ),
                Component.text('create fanzine'),
              ],
            ),
          ],
        ),

        p(
          [
            Component.text('3 fanzines × 24 pages = 72-page print bundle. Fanzines automatically carry over week-to-week and can be canceled for any week.'),
          ],
          attributes: const {'style': 'margin: 0; font-size: 11px; color: #64748b; line-height: 1.35;'},
        ),

        // List of Scheduled Fanzines for this Week
        if (scheduledFanzines.isEmpty)
          div(
            attributes: const {
              'style':
              'background: #f8fafc; border: 1px dashed #cbd5e1; border-radius: 6px; padding: 18px 12px; '
                  'display: flex; flex-direction: column; align-items: center; justify-content: center; text-align: center; gap: 4px;',
            },
            [
              span(
                classes: 'material-symbols-outlined',
                attributes: const {'style': 'font-size: 24px; color: #94a3b8;'},
                [Component.text('menu_book')],
              ),
              span(
                [Component.text('No fanzines scheduled yet for this week.')],
                attributes: const {'style': 'font-size: 11px; color: #64748b; font-weight: bold;'},
              ),
              span(
                [Component.text('Click "create fanzine" to add a 24-page publication.')],
                attributes: const {'style': 'font-size: 10px; color: #94a3b8;'},
              ),
            ],
          )
        else
          div(
            attributes: const {
              'style': 'display: flex; flex-direction: column; gap: 8px; width: 100%; box-sizing: border-box;'
            },
            [
              for (int i = 0; i < scheduledFanzines.length; i++)
                _buildScheduledFanzineRow(scheduledFanzines[i], i + 1),
            ],
          ),
      ],
    );
  }

  Component _buildScheduledFanzineRow(ScheduledFanzine fanzine, int slotIndex) {
    final bool isCanceled = fanzine.isCanceled;
    final String seriesLabel = _seriesOptionsMap[fanzine.series] ?? fanzine.series;

    return div(
      attributes: {
        'style':
        'background: ${isCanceled ? "#f8fafc" : "#ffffff"}; '
            'border: 1px solid ${isCanceled ? "#e2e8f0" : "#cbd5e1"}; '
            'border-radius: 6px; padding: 10px 12px; display: flex; flex-direction: column; gap: 6px; '
            'opacity: ${isCanceled ? "0.65" : "1.0"}; box-sizing: border-box; width: 100%; transition: all 0.15s ease;',
      },
      [
        // Top Row: Title, Slot, and Actions
        div(
          attributes: const {'style': 'display: flex; justify-content: space-between; align-items: flex-start; gap: 8px;'},
          [
            div(
              attributes: const {'style': 'display: flex; align-items: baseline; gap: 6px; overflow: hidden;'},
              [
                span(
                  [Component.text('ZINE #$slotIndex')],
                  attributes: const {
                    'style': 'font-family: Anton, sans-serif; font-size: 11px; color: #6750A4; letter-spacing: 0.5px;'
                  },
                ),
                span(
                  [Component.text(fanzine.title)],
                  attributes: {
                    'style':
                    'font-size: 12px; font-weight: bold; color: ${isCanceled ? "#64748b" : "#1e293b"}; '
                        '${isCanceled ? "text-decoration: line-through;" : ""} '
                        'white-space: nowrap; overflow: hidden; text-overflow: ellipsis;',
                  },
                ),
              ],
            ),

            // Top action buttons: Open in Maker & Delete
            div(
              attributes: const {'style': 'display: flex; align-items: center; gap: 4px; flex-shrink: 0;'},
              [
                if (!isCanceled)
                  a(
                    [
                      span(classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 12px;'}, [Component.text('edit')]),
                      Component.text('maker'),
                    ],
                    href: '/${fanzine.shortCode}/maker',
                    classes: 'profile-btn',
                    attributes: const {
                      'style':
                      'padding: 2px 7px; font-size: 9px; font-weight: bold; color: #6750A4; '
                          'border: 1px solid #cbd5e1; background: white; border-radius: 4px; text-decoration: none; '
                          'display: inline-flex; align-items: center; gap: 2px;',
                    },
                  ),
                button(
                  attributes: {
                    'type': 'button',
                    'title': isCanceled ? 'Restore to this week' : 'Cancel for this week',
                    'style':
                    'padding: 2px 7px; font-size: 9px; font-weight: bold; border-radius: 4px; cursor: pointer; '
                        'border: 1px solid ${isCanceled ? "#16a34a" : "#ef4444"}; '
                        'background: ${isCanceled ? "#ecfdf5" : "white"}; '
                        'color: ${isCanceled ? "#16a34a" : "#ef4444"};',
                  },
                  events: {'click': (e) => _toggleFanzineCancellation(fanzine)},
                  [Component.text(isCanceled ? 'restore' : 'cancel this week')],
                ),
                button(
                  attributes: const {
                    'type': 'button',
                    'title': 'Remove permanently from schedule',
                    'style': 'border: none; background: transparent; cursor: pointer; color: #94a3b8; padding: 2px;',
                  },
                  events: {'click': (e) => _deleteScheduledFanzine(fanzine.id)},
                  [span(classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 15px; color: #ef4444;'}, [Component.text('delete')])],
                ),
              ],
            ),
          ],
        ),

        // Bottom Row: Metadata Badges (vol, num, whole num, series, 24p template)
        div(
          attributes: const {'style': 'display: flex; align-items: center; gap: 6px; flex-wrap: wrap;'},
          [
            if (fanzine.volume.isNotEmpty)
              span(
                [Component.text('vol. ${fanzine.volume}')],
                attributes: const {'style': 'font-size: 9px; font-family: monospace; font-weight: bold; color: #475569; background: #f1f5f9; padding: 1px 4px; border-radius: 3px;'},
              ),
            if (fanzine.issue.isNotEmpty)
              span(
                [Component.text('num. ${fanzine.issue}')],
                attributes: const {'style': 'font-size: 9px; font-family: monospace; font-weight: bold; color: #475569; background: #f1f5f9; padding: 1px 4px; border-radius: 3px;'},
              ),
            if (fanzine.wholeNumber.isNotEmpty)
              span(
                [Component.text('whole num. ${fanzine.wholeNumber}')],
                attributes: const {'style': 'font-size: 9px; font-family: monospace; font-weight: bold; color: #475569; background: #f1f5f9; padding: 1px 4px; border-radius: 3px;'},
              ),
            if (seriesLabel.isNotEmpty && seriesLabel != 'no series / independent')
              span(
                [Component.text(seriesLabel)],
                attributes: const {'style': 'font-size: 9px; font-weight: bold; color: #6750A4; background: #f3f0fb; padding: 1px 5px; border-radius: 3px; border: 1px solid #e9d5ff;'},
              ),
            span(
              [Component.text('${fanzine.pageCount}p template')],
              attributes: const {'style': 'font-size: 9px; font-weight: bold; color: #16a34a; background: #ecfdf5; padding: 1px 5px; border-radius: 3px; border: 1px solid #bbf7d0;'},
            ),
            if (isCanceled)
              span(
                [Component.text('CANCELED')],
                attributes: const {'style': 'font-size: 9px; font-weight: 900; color: #ef4444; background: #fef2f2; padding: 1px 5px; border-radius: 3px; border: 1px solid #fecaca; letter-spacing: 0.4px;'},
              ),
          ],
        ),
      ],
    );
  }

  Component _buildCreateFanzineModal(PublishingWeek week) {
    return div(
      classes: 'global-modal-overlay',
      attributes: const {
        'style':
        'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.6); '
            'z-index: 10000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(4px);',
      },
      [
        div(
          classes: 'white-sticker',
          attributes: const {
            'style':
            'width: 90%; max-width: 440px; background: white; border-radius: 10px; padding: 20px; '
                'box-sizing: border-box; display: flex; flex-direction: column; gap: 12px; max-height: 90vh; overflow-y: auto;',
          },
          [
            div(
              attributes: const {'style': 'display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #e2e8f0; padding-bottom: 8px;'},
              [
                div([
                  h3(
                    [Component.text('Create Template Fanzine')],
                    attributes: const {'style': 'margin: 0; font-size: 14px; font-weight: bold; color: #1e293b;'},
                  ),
                  span(
                    [Component.text('Week ${week.weekNumber.toString().padLeft(2, "0")} · 24-page template folio')],
                    attributes: const {'style': 'font-size: 11px; color: #64748b; font-weight: 500;'},
                  ),
                ]),
                button(
                  attributes: const {'style': 'border: none; background: transparent; cursor: pointer; color: #888; padding: 2px;'},
                  events: {'click': (e) => setState(() => _showCreateFanzineModal = false)},
                  [span(classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 18px;'}, [Component.text('close')])],
                ),
              ],
            ),

            // Title Field (Exact curator label & placeholder)
            div([
              span(
                [Component.text('Fanzine Title *')],
                attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;'},
              ),
              input(
                attributes: {
                  'type': 'text',
                  'placeholder': 'new folio name',
                  'value': _formTitle,
                  'style': 'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                },
                events: {'input': (e) => setState(() => _formTitle = getInputValue(e))},
              ),
            ]),

            // Series Dropdown Field (Exact curator choices)
            div([
              span(
                [Component.text('part of a series:')],
                attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;'},
              ),
              select(
                attributes: const {
                  'style':
                  'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; '
                      'font-size: 12px; background-color: white; outline: none; cursor: pointer; box-sizing: border-box; margin: 0;'
                },
                events: {
                  'change': (e) => setState(() => _formSeries = getInputValue(e)),
                },
                [
                  for (var entry in _seriesOptionsMap.entries)
                    option(
                      attributes: {
                        'value': entry.key,
                        if (_formSeries == entry.key) 'selected': 'true',
                      },
                      [Component.text(entry.value)],
                    )
                ],
              ),
            ]),

            // vol., num., whole num. Row (Exact curator wording)
            div(
              attributes: const {'style': 'display: flex; gap: 8px; width: 100%;'},
              [
                div(
                  attributes: const {'style': 'flex: 1;'},
                  [
                    span([Component.text('vol.')], attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;'}),
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'vol.',
                        'value': _formVolume,
                        'style': 'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                      },
                      events: {'input': (e) => setState(() => _formVolume = getInputValue(e))},
                    ),
                  ],
                ),
                div(
                  attributes: const {'style': 'flex: 1;'},
                  [
                    span([Component.text('num.')], attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;'}),
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'num.',
                        'value': _formIssue,
                        'style': 'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                      },
                      events: {'input': (e) => setState(() => _formIssue = getInputValue(e))},
                    ),
                  ],
                ),
                div(
                  attributes: const {'style': 'flex: 1;'},
                  [
                    span([Component.text('whole num.')], attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;'}),
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'whole num.',
                        'value': _formWholeNumber,
                        'style': 'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                      },
                      events: {'input': (e) => setState(() => _formWholeNumber = getInputValue(e))},
                    ),
                  ],
                ),
              ],
            ),

            // Format Info Callout
            div(
              attributes: const {
                'style': 'background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; padding: 10px 12px; font-size: 11px; color: #64748b; line-height: 1.4;'
              },
              [
                span([Component.text('Format: ')], attributes: const {'style': 'font-weight: bold; color: #1e293b;'}),
                Component.text('Standard 24-page template folio (5:8 aspect ratio). Auto-creates 24 pages on the publisher baseline grid.'),
              ],
            ),

            if (_formError != null)
              span(
                [Component.text(_formError!)],
                attributes: const {'style': 'font-size: 11px; font-weight: bold; color: #ef4444;'},
              ),

            div(
              attributes: const {'style': 'display: flex; justify-content: flex-end; gap: 8px; margin-top: 8px; border-top: 1px solid #f1f5f9; padding-top: 10px;'},
              [
                button(
                  classes: 'profile-btn',
                  attributes: const {
                    'type': 'button',
                    'style': 'padding: 6px 14px; font-size: 11px; font-weight: bold; border: 1px solid #ccc; background: white; cursor: pointer; border-radius: 6px;',
                  },
                  events: {'click': (e) => setState(() => _showCreateFanzineModal = false)},
                  [Component.text('cancel')],
                ),
                button(
                  classes: 'btn-primary nav-pill mb-0',
                  attributes: {
                    'type': 'button',
                    'style':
                    'padding: 6px 16px; font-size: 11px; font-weight: bold; background-color: #6750A4; color: white; border: none; border-radius: 16px; cursor: pointer;',
                    if (_isCreatingFanzine) 'disabled': 'true',
                  },
                  events: {'click': (e) => _submitNewFanzineForm()},
                  [Component.text(_isCreatingFanzine ? 'creating...' : 'create fanzine')],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Component _buildCategoryAllocationCard() {
    return div(
      attributes: const {
        'style':
        'background: white; border: 1px solid #cbd5e1; border-radius: 8px; padding: 14px 16px; '
            'display: flex; flex-direction: column; gap: 10px; box-sizing: border-box; box-shadow: 0 1px 3px rgba(0,0,0,0.03);',
      },
      [
        div(
          attributes: const {
            'style':
            'display: flex; justify-content: space-between; align-items: center; '
                'border-bottom: 1px solid #f1f5f9; padding-bottom: 6px;',
          },
          [
            span(
              [Component.text('CATEGORY ALLOCATION (72P BUNDLE)')],
              attributes: const {
                'style':
                'font-size: 10px; font-weight: 900; color: #475569; letter-spacing: 0.5px; text-transform: uppercase;',
              },
            ),
            if (_activeCategoryFilter != null)
              button(
                attributes: const {
                  'type': 'button',
                  'style':
                  'border: none; background: transparent; font-size: 10px; font-weight: bold; '
                      'color: #6750A4; cursor: pointer; text-decoration: underline; padding: 0;',
                },
                events: {
                  'click': (e) => setState(() => _activeCategoryFilter = null),
                },
                [Component.text('reset highlight')],
              ),
          ],
        ),
        div(
          attributes: const {
            'style':
            'display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 6px; width: 100%; box-sizing: border-box;',
          },
          [
            _buildCategoryFilterChip('ad', 'Advertisements', '22p (30%)', '#F59E0B', '#fef3c7', '#d97706'),
            _buildCategoryFilterChip('letters', 'Radius Letters', '24p (33%)', '#10B981', '#ecfdf5', '#059669'),
            _buildCategoryFilterChip('articles', 'Articles / Essays', '16p (22%)', '#3B82F6', '#eff6ff', '#2563eb'),
            _buildCategoryFilterChip('cover', 'Covers & Indicia', '6p (8%)', '#6750A4', '#f3f0fb', '#6750A4'),
            _buildCategoryFilterChip('filler', 'Fillers & Art', '4p (6%)', '#94A3B8', '#f8fafc', '#64748b', colSpan: 2),
          ],
        ),
      ],
    );
  }

  Component _buildCategoryFilterChip(
      String cat,
      String label,
      String badge,
      String swatchColor,
      String bgColor,
      String borderColor, {
        int colSpan = 1,
      }) {
    final bool isSelected = _activeCategoryFilter == cat;
    return div(
      attributes: {
        'style':
        'cursor: pointer; display: flex; align-items: center; justify-content: space-between; '
            'padding: 6px 8px; border-radius: 6px; border: 1px solid ${isSelected ? "#000000" : borderColor}; '
            'background-color: ${isSelected ? "#f1f5f9" : bgColor}; transition: all 0.15s ease; '
            '${colSpan > 1 ? "grid-column: span $colSpan / span $colSpan;" : ""}',
      },
      events: {
        'click': (e) => _toggleCategoryFilter(cat),
      },
      [
        div(
          attributes: const {'style': 'display: flex; align-items: center; gap: 6px;'},
          [
            span(
              attributes: {
                'style':
                'width: 100px; height: 10px; border-radius: 2px; background-color: $swatchColor; '
                    'display: inline-block; flex-shrink: 0;',
              },
              [],
            ),
            span(
              [Component.text(label)],
              attributes: const {
                'style': 'font-size: 11px; font-weight: bold; color: #1e293b;',
              },
            ),
          ],
        ),
        span(
          [Component.text(badge)],
          attributes: const {
            'style': 'font-size: 10px; font-family: monospace; font-weight: 900; color: #0f172a;',
          },
        ),
      ],
    );
  }

  Component _buildCirculationPage(PublishingWeek week) {
    final weekId = week.weekId;
    final recipients = _circulationCache[weekId] ?? [];

    return div(
      classes: 'flex-col gap-4 w-full',
      attributes: const {
        'style':
        'display: flex; flex-direction: column; gap: 16px; width: 100%; box-sizing: border-box;',
      },
      [
        // Top Navigation & Return Header
        div(
          classes: 'flex-row items-center justify-between pb-2 border-b border-gray-300',
          attributes: const {
            'style':
            'display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #cbd5e1; padding-bottom: 8px;',
          },
          [
            button(
              classes: 'profile-btn',
              attributes: const {
                'type': 'button',
                'style':
                'display: inline-flex; align-items: center; gap: 4px; padding: 4px 10px; font-size: 11px; '
                    'font-weight: bold; border: 1px solid #cbd5e1; background: white; border-radius: 14px; cursor: pointer;',
              },
              events: {
                'click': (e) => _closeCirculation(),
              },
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {'style': 'font-size: 15px; line-height: 1;'},
                  [Component.text('arrow_back')],
                ),
                Component.text(_activeWeekDashboard != null ? 'week dashboard' : 'schedule'),
              ],
            ),
            div(
              attributes: const {'style': 'display: flex; align-items: baseline; gap: 8px;'},
              [
                span(
                  [Component.text('WEEK ${week.weekNumber.toString().padLeft(2, '0')}')],
                  attributes: const {
                    'style':
                    'font-size: 11px; font-weight: 900; letter-spacing: 0.5px; color: #6750A4;',
                  },
                ),
                span(
                  [Component.text('· ${recipients.length} queued')],
                  attributes: const {'style': 'font-size: 10px; color: #64748b; font-weight: 500;'},
                ),
              ],
            ),
          ],
        ),

        // Sub-page Headline Banner
        div(
          attributes: const {
            'style':
            'background: white; border: 1px solid #cbd5e1; border-radius: 8px; padding: 14px 16px; box-sizing: border-box;',
          },
          [
            div(
              attributes: const {
                'style': 'display: flex; align-items: center; justify-content: space-between;',
              },
              [
                div(
                  attributes: const {'style': 'display: flex; align-items: center; gap: 8px;'},
                  [
                    span(
                      classes: 'material-symbols-outlined',
                      attributes: const {'style': 'font-size: 18px; color: #6750A4;'},
                      [Component.text('mark_email_read')],
                    ),
                    span(
                      [Component.text('CIRCULATION DESK')],
                      attributes: const {
                        'style':
                        'font-size: 12px; font-weight: 900; letter-spacing: 0.5px; color: #1e293b; text-transform: uppercase;',
                      },
                    ),
                  ],
                ),
                span(
                  [Component.text(week.startDateString)],
                  attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #64748b;'},
                ),
              ],
            ),
            p(
              [
                Component.text('Manage the recipients receiving printed fanzine copies for the week starting '),
                span(
                  [Component.text(week.startDateString)],
                  attributes: const {'style': 'font-weight: bold; color: #1e293b;'},
                ),
                Component.text('.'),
              ],
              attributes: const {
                'style':
                'font-size: 11px; color: #64748b; line-height: 1.4; margin: 4px 0 0 0;',
              },
            ),
          ],
        ),

        _buildSearchAndAddBar(week),

        // Form to add a recipient who does not have an app profile
        if (_showAddManualForm)
          _buildManualContactForm(week),

        _buildRecipientsList(week, recipients),

        // Address edit modal overlay if editing a recipient
        if (_editingRecipient != null)
          _buildEditAddressModal(week),
      ],
    );
  }

  Component _buildSearchAndAddBar(PublishingWeek week) {
    final filtered = _allProfiles.where((p) {
      final q = _userSearchQuery.trim().toLowerCase();
      if (q.isEmpty) return false;
      final name = (p['displayName'] ?? '').toString().toLowerCase();
      final user = (p['username'] ?? '').toString().toLowerCase();
      final first = (p['firstName'] ?? '').toString().toLowerCase();
      final last = (p['lastName'] ?? '').toString().toLowerCase();
      return name.contains(q) || user.contains(q) || first.contains(q) || last.contains(q);
    }).toList();

    return div(
      attributes: const {
        'style':
        'background: white; border: 1px solid #cbd5e1; border-radius: 8px; padding: 14px; '
            'display: flex; flex-direction: column; gap: 10px; width: 100%; box-sizing: border-box; position: relative;',
      },
      [
        div(
          attributes: const {
            'style': 'display: flex; justify-content: space-between; align-items: center;',
          },
          [
            span(
              [Component.text('ADD RECIPIENT TO THIS ISSUE')],
              attributes: const {
                'style':
                'font-size: 10px; font-weight: bold; color: #475569; letter-spacing: 0.5px; text-transform: uppercase;',
              },
            ),
            button(
              classes: 'profile-btn',
              attributes: {
                'type': 'button',
                'style':
                'border: 1px solid ${_showAddManualForm ? "#6750A4" : "#cbd5e1"}; '
                    'background: ${_showAddManualForm ? "#f3f0fb" : "white"}; '
                    'color: ${_showAddManualForm ? "#6750A4" : "#475569"}; '
                    'padding: 3px 10px; font-size: 10px; font-weight: bold; border-radius: 12px; cursor: pointer; '
                    'display: inline-flex; align-items: center; gap: 4px;',
              },
              events: {
                'click': (e) {
                  setState(() {
                    _showAddManualForm = !_showAddManualForm;
                    _searchDropdownOpen = false;
                    _manualFormError = null;
                  });
                },
              },
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {'style': 'font-size: 13px;'},
                  [Component.text(_showAddManualForm ? 'close' : 'person_add')],
                ),
                Component.text(_showAddManualForm ? 'cancel manual' : 'contact without profile'),
              ],
            ),
          ],
        ),

        // Live Profile Search Box with Dropdown Autocomplete
        div(
          attributes: const {'style': 'position: relative; width: 100%; box-sizing: border-box;'},
          [
            input(
              attributes: {
                'type': 'text',
                'placeholder': 'search user by username or real name...',
                'value': _userSearchQuery,
                'style':
                'width: 100%; padding: 8px 12px; border: 1px solid #cbd5e1; border-radius: 6px; '
                    'font-size: 12px; background: white; outline: none; box-sizing: border-box; margin: 0;',
              },
              events: {
                'focus': (e) {
                  if (_userSearchQuery.trim().isNotEmpty) {
                    setState(() => _searchDropdownOpen = true);
                  }
                },
                'input': (e) {
                  final val = getInputValue(e);
                  setState(() {
                    _userSearchQuery = val;
                    _searchDropdownOpen = val.trim().isNotEmpty;
                  });
                },
              },
            ),

            if (_userSearchQuery.trim().isNotEmpty)
              button(
                attributes: const {
                  'type': 'button',
                  'style':
                  'position: absolute; right: 8px; top: 50%; transform: translateY(-50%); '
                      'border: none; background: transparent; cursor: pointer; color: #888; padding: 2px;',
                },
                events: {
                  'click': (e) {
                    setState(() {
                      _userSearchQuery = '';
                      _searchDropdownOpen = false;
                    });
                  },
                },
                [
                  span(
                    classes: 'material-symbols-outlined',
                    attributes: const {'style': 'font-size: 15px;'},
                    [Component.text('close')],
                  ),
                ],
              ),
          ],
        ),

        // Dropdown Overlay Menu for Profile Search Matches
        if (_searchDropdownOpen && _userSearchQuery.trim().isNotEmpty) ...[
          div(
            attributes: const {
              'style':
              'position: fixed; top: 0; left: 0; right: 0; bottom: 0; z-index: 99;',
            },
            events: {
              'click': (e) => setState(() => _searchDropdownOpen = false),
            },
            [],
          ),
          div(
            classes: 'search-results-menu',
            attributes: const {
              'style':
              'position: absolute; top: 82px; left: 14px; right: 14px; max-height: 220px; '
                  'overflow-y: auto; background: white; border: 1px solid #cbd5e1; border-radius: 6px; '
                  'box-shadow: 0 4px 16px rgba(0,0,0,0.15); z-index: 100; box-sizing: border-box;',
            },
            [
              if (filtered.isEmpty)
                div(
                  [Component.text('no matching user profiles found.')],
                  attributes: const {
                    'style':
                    'padding: 12px; font-size: 11px; color: #888; font-style: italic; text-align: center;',
                  },
                )
              else
                for (final profile in filtered.take(12))
                  _buildProfileSearchResultItem(profile),
            ],
          ),
        ],
      ],
    );
  }

  Component _buildProfileSearchResultItem(Map<String, dynamic> profile) {
    final week = _activeCirculationWeek ?? _activeWeekDashboard;
    final currentList = week != null ? (_circulationCache[week.weekId] ?? []) : <CirculationRecipient>[];
    final String uid = profile['uid'] ?? profile['id'] ?? '';
    final bool isAlreadyAdded = currentList.any((r) => r.id == uid);

    final String displayName = (profile['displayName'] ?? profile['username'] ?? 'User').toString();
    final String username = (profile['username'] ?? '').toString();
    final String? photoUrl = profile['photoUrl']?.toString();
    final String city = (profile['city'] ?? '').toString().trim();
    final String state = (profile['state'] ?? '').toString().trim();
    final String locSummary = [if (city.isNotEmpty) city, if (state.isNotEmpty) state].join(', ');

    return div(
      attributes: {
        'style':
        'display: flex; align-items: center; justify-content: space-between; padding: 8px 12px; '
            'border-bottom: 1px solid #f1f5f9; cursor: ${isAlreadyAdded ? "default" : "pointer"}; '
            'background: ${isAlreadyAdded ? "#f8fafc" : "white"}; transition: background 0.15s;',
      },
      events: {
        'click': (e) {
          if (!isAlreadyAdded) {
            _addUserProfileToCirculation(profile);
          }
        },
      },
      [
        div(
          attributes: const {'style': 'display: flex; align-items: center; gap: 10px; overflow: hidden;'},
          [
            div(
              attributes: const {
                'style':
                'width: 28px; height: 28px; border-radius: 50%; overflow: hidden; background: #eee; '
                    'display: flex; align-items: center; justify-content: center; flex-shrink: 0;',
              },
              [
                if (photoUrl != null && photoUrl.isNotEmpty)
                  img(src: photoUrl, attributes: const {'style': 'width: 100%; height: 100%; object-fit: cover;'})
                else
                  span(
                    [Component.text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?')],
                    attributes: const {'style': 'font-size: 11px; font-weight: bold; color: #666;'},
                  ),
              ],
            ),
            div(
              attributes: const {'style': 'display: flex; flex-direction: column; text-align: left; overflow: hidden;'},
              [
                span(
                  [Component.text(displayName)],
                  attributes: const {
                    'style':
                    'font-size: 12px; font-weight: bold; color: #1e293b; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;',
                  },
                ),
                div(
                  attributes: const {'style': 'display: flex; align-items: center; gap: 6px;'},
                  [
                    if (username.isNotEmpty)
                      span(
                        [Component.text('@$username')],
                        attributes: const {'style': 'font-size: 10px; color: #64748b; font-family: monospace;'},
                      ),
                    if (locSummary.isNotEmpty)
                      span(
                        [Component.text('· $locSummary')],
                        attributes: const {'style': 'font-size: 10px; color: #94a3b8;'},
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
        span(
          [Component.text(isAlreadyAdded ? 'added' : '+ add')],
          attributes: {
            'style':
            'font-size: 10px; font-weight: bold; padding: 2px 8px; border-radius: 10px; '
                'background: ${isAlreadyAdded ? "#e2e8f0" : "#E8DEF8"}; '
                'color: ${isAlreadyAdded ? "#64748b" : "#6750A4"};',
          },
        ),
      ],
    );
  }

  Component _buildManualContactForm(PublishingWeek week) {
    return div(
      attributes: const {
        'style':
        'background: white; border: 2px dashed #6750A4; border-radius: 8px; padding: 16px; '
            'display: flex; flex-direction: column; gap: 10px; width: 100%; box-sizing: border-box;',
      },
      [
        div(
          attributes: const {'style': 'display: flex; justify-content: space-between; align-items: center;'},
          [
            span(
              [Component.text('NEW RECIPIENT (NO APP PROFILE)')],
              attributes: const {
                'style':
                'font-size: 11px; font-weight: 900; color: #6750A4; letter-spacing: 0.5px; text-transform: uppercase;',
              },
            ),
            span(
              [Component.text('Stores address info without creating a profile')],
              attributes: const {'style': 'font-size: 9px; color: #64748b; font-style: italic;'},
            ),
          ],
        ),

        // Real Name Input
        div([
          span(
            [Component.text('Real Name / Full Name *')],
            attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;'},
          ),
          input(
            attributes: {
              'type': 'text',
              'placeholder': 'e.g. Robert A. Heinlein',
              'value': _manualDisplayName,
              'style':
              'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
            },
            events: {'input': (e) => setState(() => _manualDisplayName = getInputValue(e))},
          ),
        ]),

        // Street Address 1
        div([
          span(
            [Component.text('Street Address Line 1')],
            attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;'},
          ),
          input(
            attributes: {
              'type': 'text',
              'placeholder': 'e.g. 123 Sci-Fi Way',
              'value': _manualStreet1,
              'style':
              'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
            },
            events: {'input': (e) => setState(() => _manualStreet1 = getInputValue(e))},
          ),
        ]),

        // Street Address 2
        div([
          span(
            [Component.text('Address Line 2 (Apt / Suite / Unit)')],
            attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;'},
          ),
          input(
            attributes: {
              'type': 'text',
              'placeholder': 'Apt 4B',
              'value': _manualStreet2,
              'style':
              'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
            },
            events: {'input': (e) => setState(() => _manualStreet2 = getInputValue(e))},
          ),
        ]),

        // City & State Row
        div(
          attributes: const {'style': 'display: flex; gap: 8px; width: 100%;'},
          [
            div(
              attributes: const {'style': 'flex: 2;'},
              [
                span(
                  [Component.text('City')],
                  attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;'},
                ),
                input(
                  attributes: {
                    'type': 'text',
                    'placeholder': 'City',
                    'value': _manualCity,
                    'style':
                    'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                  },
                  events: {'input': (e) => setState(() => _manualCity = getInputValue(e))},
                ),
              ],
            ),
            div(
              attributes: const {'style': 'flex: 1.2;'},
              [
                span(
                  [Component.text('State / Prov')],
                  attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;'},
                ),
                input(
                  attributes: {
                    'type': 'text',
                    'placeholder': 'State',
                    'value': _manualState,
                    'style':
                    'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                  },
                  events: {'input': (e) => setState(() => _manualState = getInputValue(e))},
                ),
              ],
            ),
          ],
        ),

        // ZIP & Country Row
        div(
          attributes: const {'style': 'display: flex; gap: 8px; width: 100%;'},
          [
            div(
              attributes: const {'style': 'flex: 1.5;'},
              [
                span(
                  [Component.text('ZIP / Postal Code')],
                  attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;'},
                ),
                input(
                  attributes: {
                    'type': 'text',
                    'placeholder': 'ZIP Code',
                    'value': _manualZip,
                    'style':
                    'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                  },
                  events: {'input': (e) => setState(() => _manualZip = getInputValue(e))},
                ),
              ],
            ),
            div(
              attributes: const {'style': 'flex: 1.5;'},
              [
                span(
                  [Component.text('Country')],
                  attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;'},
                ),
                input(
                  attributes: {
                    'type': 'text',
                    'placeholder': 'USA',
                    'value': _manualCountry,
                    'style':
                    'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                  },
                  events: {'input': (e) => setState(() => _manualCountry = getInputValue(e))},
                ),
              ],
            ),
          ],
        ),

        // Optional Distribution Notes
        div([
          span(
            [Component.text('Circulation Notes (Optional)')],
            attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;'},
          ),
          input(
            attributes: {
              'type': 'text',
              'placeholder': 'e.g. Mail signed copy, Subscriber #402',
              'value': _manualNotes,
              'style':
              'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
            },
            events: {'input': (e) => setState(() => _manualNotes = getInputValue(e))},
          ),
        ]),

        if (_manualFormError != null)
          span(
            [Component.text(_manualFormError!)],
            attributes: const {'style': 'font-size: 11px; font-weight: bold; color: #ef4444;'},
          ),

        div(
          attributes: const {'style': 'display: flex; justify-content: flex-end; gap: 8px; margin-top: 4px;'},
          [
            button(
              classes: 'profile-btn',
              attributes: const {
                'type': 'button',
                'style': 'padding: 6px 14px; font-size: 11px; font-weight: bold; border: 1px solid #ccc; background: white; cursor: pointer; border-radius: 6px;',
              },
              events: {'click': (e) => setState(() => _showAddManualForm = false)},
              [Component.text('cancel')],
            ),
            button(
              classes: 'btn-primary nav-pill mb-0',
              attributes: const {
                'type': 'button',
                'style':
                'padding: 6px 16px; font-size: 11px; font-weight: bold; background-color: #6750A4; color: white; border: none; border-radius: 16px; cursor: pointer; display: inline-flex; align-items: center; gap: 4px;',
              },
              events: {'click': (e) => _submitManualRecipient()},
              [
                span(classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px;'}, [Component.text('check')]),
                Component.text('add to this issue'),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Component _buildRecipientsList(PublishingWeek week, List<CirculationRecipient> recipients) {
    if (recipients.isEmpty) {
      return div(
        attributes: const {
          'style':
          'background: white; border: 1px dashed #cbd5e1; border-radius: 8px; padding: 36px 16px; '
              'display: flex; flex-direction: column; align-items: center; justify-content: center; '
              'text-align: center; box-sizing: border-box;',
        },
        [
          span(
            classes: 'material-symbols-outlined',
            attributes: const {'style': 'font-size: 36px; color: #94a3b8; margin-bottom: 6px;'},
            [Component.text('outgoing_mail')],
          ),
          h3(
            [Component.text('No Recipients Queued Yet')],
            attributes: const {
              'style': 'font-size: 13px; font-weight: bold; color: #1e293b; margin: 0 0 4px 0;',
            },
          ),
          p(
            [Component.text('Search registered users above or enter contact details for non-profile recipients.')],
            attributes: const {
              'style': 'font-size: 11px; color: #94a3b8; margin: 0; max-width: 320px;',
            },
          ),
        ],
      );
    }

    return div(
      attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px; width: 100%; box-sizing: border-box;'},
      [
        div(
          attributes: const {'style': 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 2px;'},
          [
            span(
              [Component.text('ISSUE RECIPIENTS (${recipients.length})')],
              attributes: const {
                'style':
                'font-size: 10px; font-weight: 900; color: #475569; letter-spacing: 0.5px; text-transform: uppercase;',
              },
            ),
            span(
              [Component.text('Print & Mailing Queue')],
              attributes: const {'style': 'font-size: 10px; color: #94a3b8; font-style: italic;'},
            ),
          ],
        ),

        for (int i = 0; i < recipients.length; i++)
          _buildRecipientCard(recipients[i], i),
      ],
    );
  }

  Component _buildRecipientCard(CirculationRecipient recipient, int index) {
    return div(
      attributes: const {
        'style':
        'background: white; border: 1px solid #e2e8f0; border-radius: 8px; padding: 12px 14px; '
            'display: flex; flex-direction: column; gap: 8px; width: 100%; box-sizing: border-box; box-shadow: 0 1px 3px rgba(0,0,0,0.03);',
      },
      [
        // Top Header of Recipient Card
        div(
          attributes: const {
            'style': 'display: flex; align-items: flex-start; justify-content: space-between; width: 100%; gap: 8px;',
          },
          [
            div(
              attributes: const {'style': 'display: flex; align-items: center; gap: 10px; overflow: hidden;'},
              [
                // Avatar / Badge
                div(
                  attributes: const {
                    'style':
                    'width: 32px; height: 32px; border-radius: 50%; overflow: hidden; background: #f1f5f9; '
                        'border: 1px solid #cbd5e1; display: flex; align-items: center; justify-content: center; flex-shrink: 0;',
                  },
                  [
                    if (recipient.photoUrl != null && recipient.photoUrl!.isNotEmpty)
                      img(src: recipient.photoUrl!, attributes: const {'style': 'width: 100%; height: 100%; object-fit: cover;'})
                    else if (recipient.hasProfile)
                      span(
                        [Component.text(recipient.displayName.isNotEmpty ? recipient.displayName[0].toUpperCase() : '?')],
                        attributes: const {'style': 'font-size: 13px; font-weight: bold; color: #6750A4;'},
                      )
                    else
                      span(
                        classes: 'material-symbols-outlined',
                        attributes: const {'style': 'font-size: 18px; color: #64748b;'},
                        [Component.text('person')],
                      ),
                  ],
                ),

                // Name and Profile Handle / Manual Badge
                div(
                  attributes: const {'style': 'display: flex; flex-direction: column; text-align: left; overflow: hidden;'},
                  [
                    span(
                      [Component.text(recipient.displayName)],
                      attributes: const {
                        'style':
                        'font-size: 13px; font-weight: bold; color: #1e293b; line-height: 1.2; '
                            'white-space: nowrap; overflow: hidden; text-overflow: ellipsis;',
                      },
                    ),
                    div(
                      attributes: const {'style': 'display: flex; align-items: center; gap: 6px; margin-top: 2px;'},
                      [
                        if (recipient.hasProfile && recipient.username != null)
                          a(
                            [Component.text('@${recipient.username}')],
                            href: '/@${recipient.username}',
                            classes: 'hover:underline',
                            attributes: const {
                              'style': 'font-size: 10px; font-weight: bold; color: #6750A4; text-decoration: none; font-family: monospace;',
                            },
                          )
                        else
                          span(
                            [Component.text('EXTERNAL (NO PROFILE)')],
                            attributes: const {
                              'style':
                              'font-size: 8px; font-weight: bold; background: #f1f5f9; color: #475569; '
                                  'padding: 1px 5px; border-radius: 4px; border: 1px solid #cbd5e1; letter-spacing: 0.3px;',
                            },
                          ),
                        if (recipient.notes != null)
                          span(
                            [Component.text('· ${recipient.notes}')],
                            attributes: const {'style': 'font-size: 10px; color: #94a3b8; font-style: italic;'},
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),

            // Top action buttons: Edit Address & Remove
            div(
              attributes: const {'style': 'display: flex; align-items: center; gap: 4px; flex-shrink: 0;'},
              [
                button(
                  classes: 'profile-btn',
                  attributes: const {
                    'type': 'button',
                    'title': 'Edit mailing address',
                    'style':
                    'padding: 3px 8px; font-size: 10px; font-weight: bold; color: #475569; '
                        'border: 1px solid #cbd5e1; background: white; border-radius: 4px; cursor: pointer; '
                        'display: inline-flex; align-items: center; gap: 2px;',
                  },
                  events: {'click': (e) => _openEditAddress(recipient)},
                  [
                    span(classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 12px;'}, [Component.text('edit')]),
                    Component.text('address'),
                  ],
                ),
                button(
                  attributes: const {
                    'type': 'button',
                    'title': 'Remove recipient from this issue',
                    'style':
                    'border: none; background: transparent; cursor: pointer; color: #94a3b8; padding: 2px 4px; '
                        'display: inline-flex; align-items: center; transition: color 0.15s;',
                  },
                  events: {'click': (e) => _removeRecipient(recipient.id)},
                  [
                    span(classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px; color: #ef4444;'}, [Component.text('close')]),
                  ],
                ),
              ],
            ),
          ],
        ),

        // Mailing Address Box
        div(
          attributes: const {
            'style':
            'background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; padding: 8px 10px; '
                'display: flex; align-items: flex-start; gap: 8px;',
          },
          [
            span(
              classes: 'material-symbols-outlined',
              attributes: {
                'style':
                'font-size: 15px; line-height: 1.2; '
                    'color: ${recipient.hasAddress ? "#16a34a" : "#ca8a04"};',
              },
              [Component.text(recipient.hasAddress ? 'location_on' : 'warning')],
            ),
            div(
              attributes: const {'style': 'display: flex; flex-direction: column; gap: 1px; flex: 1;'},
              [
                if (recipient.hasAddress)
                  p(
                    [Component.text(recipient.formattedAddress)],
                    attributes: const {
                      'style':
                      'font-family: Georgia, serif; font-size: 11px; line-height: 1.35; '
                          'color: #334155; margin: 0; white-space: pre-line;',
                    },
                  )
                else
                  span(
                    [Component.text('No mailing address entered for this recipient.')],
                    attributes: const {
                      'style': 'font-size: 10px; color: #ca8a04; font-style: italic; font-weight: 500;',
                    },
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Component _buildEditAddressModal(PublishingWeek week) {
    final target = _editingRecipient;
    if (target == null) return div([]);

    return div(
      classes: 'global-modal-overlay',
      attributes: const {
        'style':
        'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.6); '
            'z-index: 10000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(4px);',
      },
      [
        div(
          classes: 'white-sticker',
          attributes: const {
            'style':
            'width: 90%; max-width: 440px; background: white; border-radius: 10px; padding: 20px; '
                'box-sizing: border-box; display: flex; flex-direction: column; gap: 12px; max-height: 90vh; overflow-y: auto;',
          },
          [
            div(
              attributes: const {'style': 'display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #e2e8f0; padding-bottom: 8px;'},
              [
                div([
                  h3(
                    [Component.text('Edit Mailing Address')],
                    attributes: const {'style': 'margin: 0; font-size: 14px; font-weight: bold; color: #1e293b;'},
                  ),
                  span(
                    [Component.text('Recipient: ${target.displayName}')],
                    attributes: const {'style': 'font-size: 11px; color: #64748b; font-weight: 500;'},
                  ),
                ]),
                button(
                  attributes: const {'style': 'border: none; background: transparent; cursor: pointer; color: #888; padding: 2px;'},
                  events: {'click': (e) => setState(() => _editingRecipient = null)},
                  [span(classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 18px;'}, [Component.text('close')])],
                ),
              ],
            ),

            // Street 1
            div([
              span([Component.text('Street Address Line 1')], attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;'}),
              input(
                attributes: {
                  'type': 'text',
                  'placeholder': '123 Main St',
                  'value': _editStreet1,
                  'style': 'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                },
                events: {'input': (e) => setState(() => _editStreet1 = getInputValue(e))},
              ),
            ]),

            // Street 2
            div([
              span([Component.text('Address Line 2 (Apt / Suite / Unit)')], attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;'}),
              input(
                attributes: {
                  'type': 'text',
                  'placeholder': 'Apt 4B',
                  'value': _editStreet2,
                  'style': 'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                },
                events: {'input': (e) => setState(() => _editStreet2 = getInputValue(e))},
              ),
            ]),

            // City & State Row
            div(
              attributes: const {'style': 'display: flex; gap: 8px; width: 100%;'},
              [
                div(
                  attributes: const {'style': 'flex: 2;'},
                  [
                    span([Component.text('City')], attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;'}),
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'City',
                        'value': _editCity,
                        'style': 'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                      },
                      events: {'input': (e) => setState(() => _editCity = getInputValue(e))},
                    ),
                  ],
                ),
                div(
                  attributes: const {'style': 'flex: 1.2;'},
                  [
                    span([Component.text('State')], attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;'}),
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'State',
                        'value': _editState,
                        'style': 'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                      },
                      events: {'input': (e) => setState(() => _editState = getInputValue(e))},
                    ),
                  ],
                ),
              ],
            ),

            // ZIP & Country Row
            div(
              attributes: const {'style': 'display: flex; gap: 8px; width: 100%;'},
              [
                div(
                  attributes: const {'style': 'flex: 1.5;'},
                  [
                    span([Component.text('ZIP / Postal Code')], attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;'}),
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'ZIP Code',
                        'value': _editZip,
                        'style': 'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                      },
                      events: {'input': (e) => setState(() => _editZip = getInputValue(e))},
                    ),
                  ],
                ),
                div(
                  attributes: const {'style': 'flex: 1.5;'},
                  [
                    span([Component.text('Country')], attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;'}),
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'Country',
                        'value': _editCountry,
                        'style': 'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                      },
                      events: {'input': (e) => setState(() => _editCountry = getInputValue(e))},
                    ),
                  ],
                ),
              ],
            ),

            // Notes
            div([
              span([Component.text('Circulation Notes')], attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;'}),
              input(
                attributes: {
                  'type': 'text',
                  'placeholder': 'Special mailing instructions or notes...',
                  'value': _editNotes,
                  'style': 'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                },
                events: {'input': (e) => setState(() => _editNotes = getInputValue(e))},
              ),
            ]),

            div(
              attributes: const {'style': 'display: flex; justify-content: flex-end; gap: 8px; margin-top: 8px; border-top: 1px solid #f1f5f9; padding-top: 10px;'},
              [
                button(
                  classes: 'profile-btn',
                  attributes: const {'type': 'button', 'style': 'padding: 6px 14px; font-size: 11px; font-weight: bold; border: 1px solid #ccc; background: white; cursor: pointer; border-radius: 6px;'},
                  events: {'click': (e) => setState(() => _editingRecipient = null)},
                  [Component.text('cancel')],
                ),
                button(
                  classes: 'btn-primary nav-pill mb-0',
                  attributes: const {
                    'type': 'button',
                    'style': 'padding: 6px 16px; font-size: 11px; font-weight: bold; background-color: #6750A4; color: white; border: none; border-radius: 16px; cursor: pointer;',
                  },
                  events: {'click': (e) => _saveEditedAddress()},
                  [Component.text('save address')],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Backward-compatible alias for the publisher panel
typedef PublisherPanel = PublisherColumnPanel;