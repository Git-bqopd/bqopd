import 'dart:async';
import 'dart:convert';
import 'package:bqopd_core/bqopd_core.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../../utils/spread_image_generator.dart';
import '../../utils/web_utils.dart';

/// Parsed business profile entry used by the Share Panel dropdown and Hours Sign generator.
class ShareBusinessOption {
  final String uid;
  final String displayName;
  final String username;
  final List<String> addressLines;
  final Map<String, BusinessDayHours> businessHours;

  const ShareBusinessOption({
    required this.uid,
    required this.displayName,
    required this.username,
    required this.addressLines,
    required this.businessHours,
  });

  String get dropdownLabel {
    final cleanHandle = username.trim().replaceAll('@', '');
    if (displayName.trim().isNotEmpty && cleanHandle.isNotEmpty) {
      return '${displayName.trim()} (@$cleanHandle)';
    }
    if (displayName.trim().isNotEmpty) return displayName.trim();
    if (cleanHandle.isNotEmpty) return '@$cleanHandle';
    return 'Business ($uid)';
  }

  BusinessHoursSignData toSignData() {
    return BusinessHoursSignData(
      displayName: displayName,
      username: username,
      addressLines: addressLines,
      rows: [
        for (final day in kBusinessDaysOfWeek)
          BusinessHoursRowData(
            dayLabel: kBusinessDayLabels[day] ?? day,
            isOpen: (businessHours[day] ?? const BusinessDayHours()).isOpen,
            open: (businessHours[day] ?? const BusinessDayHours()).open,
            close: (businessHours[day] ?? const BusinessDayHours()).close,
          ),
      ],
    );
  }
}

List<ShareBusinessOption>? _cachedBusinessOptions;
Future<List<ShareBusinessOption>>? _inflightBusinessFetch;

List<String> _extractMailingAddressLines(Map<String, dynamic> data) {
  final String street1 = (data['street1'] ?? '').toString().trim();
  final String street2 = (data['street2'] ?? '').toString().trim();
  final String city = (data['city'] ?? '').toString().trim();
  final String state = (data['state'] ?? '').toString().trim();
  final String zip = (data['zipCode'] ?? '').toString().trim();
  final String country = (data['country'] ?? '').toString().trim();

  final List<String> lines = [];
  if (street1.isNotEmpty && street2.isNotEmpty) {
    lines.add('$street1, $street2');
  } else if (street1.isNotEmpty) {
    lines.add(street1);
  } else if (street2.isNotEmpty) {
    lines.add(street2);
  }

  final String cityState = [
    if (city.isNotEmpty) city,
    if (state.isNotEmpty) state,
  ].join(', ');
  final String cityStateZip =
      ('$cityState${zip.isNotEmpty ? " $zip" : ""}').trim();
  if (cityStateZip.isNotEmpty) {
    lines.add(cityStateZip);
  }

  if (country.isNotEmpty &&
      country.toLowerCase() != 'us' &&
      country.toLowerCase() != 'usa' &&
      country.toLowerCase() != 'united states') {
    lines.add(country);
  }

  if (lines.isEmpty) {
    final String loc = (data['location'] ?? '').toString().trim();
    if (loc.isNotEmpty) {
      lines.add(loc);
    } else if (data['geo'] is Map) {
      final String formatted =
          ((data['geo'] as Map)['formatted'] ?? '').toString().trim();
      if (formatted.isNotEmpty) {
        lines.add(formatted);
      }
    }
  }
  return lines;
}

Future<List<ShareBusinessOption>> _loadBusinessProfiles() {
  if (_cachedBusinessOptions != null) {
    return Future.value(_cachedBusinessOptions!);
  }
  if (_inflightBusinessFetch != null) {
    return _inflightBusinessFetch!;
  }

  final future = () async {
    final List<ShareBusinessOption> businesses = [];
    try {
      final res = await fsQuery('profiles', '', '', '', '');
      final List decoded = jsonDecode(res) as List;
      for (final entry in decoded) {
        final rawData = entry['data'];
        if (rawData is! Map) continue;
        final data = Map<String, dynamic>.from(rawData);
        final bool isBiz = data['profileType']?.toString() == 'business' ||
            data['isBusiness'] == true;
        if (!isBiz) continue;

        final String uid = (entry['id'] ?? data['uid'] ?? '').toString();
        if (uid.isEmpty) continue;

        List<String> addressLines = _extractMailingAddressLines(data);
        final String rawStreet1 = (data['street1'] ?? '').toString().trim();

        // If full street mailing address isn't populated on public `profiles/$uid`,
        // attempt to read `Users/$uid` when permitted (e.g. owner/admin session).
        if (rawStreet1.isEmpty) {
          try {
            final userRes = await fsGetDoc('Users/$uid');
            final userDoc = jsonDecode(userRes);
            if (userDoc['exists'] == true && userDoc['data'] is Map) {
              final userMap = Map<String, dynamic>.from(userDoc['data'] as Map);
              final privateLines = _extractMailingAddressLines(userMap);
              if (privateLines.isNotEmpty) {
                addressLines = privateLines;
              }
            }
          } catch (_) {}
        }

        final String displayName =
            (data['displayName'] ?? data['username'] ?? 'Business')
                .toString()
                .trim();
        final String username = (data['username'] ?? '').toString().trim();
        final hours = parseBusinessHours(data['businessHours']);

        businesses.add(
          ShareBusinessOption(
            uid: uid,
            displayName: displayName,
            username: username,
            addressLines: addressLines,
            businessHours: hours,
          ),
        );
      }

      businesses.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
      if (businesses.isNotEmpty) {
        _cachedBusinessOptions = businesses;
      }
    } catch (_) {}
    _inflightBusinessFetch = null;
    return businesses;
  }();

  _inflightBusinessFetch = future;
  return future;
}

/// Computed spread alignment and natural companion page for a given page in a fanzine.
class SpreadPagePlacement {
  final int spreadIndex;
  final bool currentIsLeft;
  final Map<String, dynamic>? facingPage;
  final String facingRelationLabel;

  const SpreadPagePlacement({
    required this.spreadIndex,
    required this.currentIsLeft,
    this.facingPage,
    this.facingRelationLabel = 'Facing Page',
  });
}

/// Resolves which half (Left vs. Right) [pageIndex] occupies when printed as a
/// two-page spread, and identifies its natural facing page in [pages].
SpreadPagePlacement resolveSpreadPlacement({
  required List<Map<String, dynamic>> pages,
  required int pageIndex,
  required bool hasCover,
}) {
  if (pages.isEmpty || pageIndex < 0 || pageIndex >= pages.length) {
    return const SpreadPagePlacement(spreadIndex: 0, currentIsLeft: false);
  }

  // Build exact spread pairs matching FanzineGridRenderer
  final List<(Map<String, dynamic>?, Map<String, dynamic>?)> spreads = [];
  Map<String, dynamic>? curLeft;
  Map<String, dynamic>? curRight;
  int idx = 0;
  bool nextIsLeft = false;

  if (hasCover) {
    curRight = pages[0];
    spreads.add((null, curRight));
    curLeft = null;
    curRight = null;
    idx = 1;
    nextIsLeft = true;
  } else {
    spreads.add((null, null));
    nextIsLeft = true;
  }

  while (idx < pages.length) {
    final page = pages[idx];
    final String pref = (page['sidePreference'] ?? 'either').toString();

    if (nextIsLeft) {
      if (pref == 'right') {
        spreads.add((null, page));
        nextIsLeft = true;
      } else {
        curLeft = page;
        nextIsLeft = false;
      }
    } else {
      if (pref == 'left') {
        spreads.add((curLeft, null));
        curLeft = page;
        nextIsLeft = false;
      } else {
        spreads.add((curLeft, page));
        curLeft = null;
        nextIsLeft = true;
      }
    }
    idx++;
  }

  if (!nextIsLeft && curLeft != null) {
    spreads.add((curLeft, null));
  }

  final targetPage = pages[pageIndex];
  for (int s = 0; s < spreads.length; s++) {
    final (leftP, rightP) = spreads[s];
    if (identical(leftP, targetPage)) {
      if (rightP != null) {
        final pNum = rightP['pageNumber'] ?? '';
        return SpreadPagePlacement(
          spreadIndex: s,
          currentIsLeft: true,
          facingPage: rightP,
          facingRelationLabel: 'With Page $pNum (Fanzine Spread)',
        );
      }
      // Back cover (left-only final spread) pairs with Front Cover when saddle-stitched!
      if (hasCover && pages.length > 1 && pageIndex == pages.length - 1) {
        return SpreadPagePlacement(
          spreadIndex: s,
          currentIsLeft: true,
          facingPage: pages.first,
          facingRelationLabel: 'With Front Cover (Outer Sheet)',
        );
      }
      return SpreadPagePlacement(spreadIndex: s, currentIsLeft: true);
    }

    if (identical(rightP, targetPage)) {
      if (leftP != null) {
        final pNum = leftP['pageNumber'] ?? '';
        return SpreadPagePlacement(
          spreadIndex: s,
          currentIsLeft: false,
          facingPage: leftP,
          facingRelationLabel: 'With Page $pNum (Fanzine Spread)',
        );
      }
      // Front cover (right-only Spread 0) pairs with Back Cover on outer print sheet!
      if (hasCover && pages.length > 1 && pageIndex == 0) {
        final backPage = pages.last;
        final backNum = backPage['pageNumber'] ?? pages.length;
        return SpreadPagePlacement(
          spreadIndex: s,
          currentIsLeft: false,
          facingPage: backPage,
          facingRelationLabel: 'With Page $backNum (Outer Cover Spread)',
        );
      }
      return SpreadPagePlacement(spreadIndex: s, currentIsLeft: false);
    }
  }

  return SpreadPagePlacement(
    spreadIndex: 0,
    currentIsLeft: pageIndex.isOdd,
  );
}

/// Detects candidate Advertisement pages inside [pages] using template metadata,
/// hashtags, or OCR/text markers.
List<Map<String, dynamic>> detectFanzineAdPages({
  required List<Map<String, dynamic>> pages,
  required int excludePageIndex,
  required Map<String, Map<String, dynamic>> imageStats,
}) {
  final List<Map<String, dynamic>> found = [];

  for (int i = 0; i < pages.length; i++) {
    if (i == excludePageIndex) continue;
    final p = pages[i];
    final String imgId = (p['imageId'] ?? '').toString();
    final Map<String, dynamic> stats = imageStats[imgId] ?? const {};

    final String templateId = (p['templateId'] ?? '').toString().toLowerCase();
    final String category =
        (p['category'] ?? stats['category'] ?? '').toString().toLowerCase();
    final bool explicitAd = p['isAd'] == true ||
        stats['isAd'] == true ||
        templateId.contains('ad') ||
        category == 'ad';

    bool tagAd = false;
    final rawTags = stats['hashtags'] ?? stats['tags'] ?? p['hashtags'];
    if (rawTags is Iterable) {
      for (final t in rawTags) {
        final clean = t.toString().toLowerCase().replaceAll('#', '').trim();
        if (clean == 'ad' ||
            clean == 'ads' ||
            clean == 'advertisement' ||
            clean == 'classifieds' ||
            clean == 'sponsor') {
          tagAd = true;
          break;
        }
      }
    }

    final String textSample =
        '${p['text'] ?? ''} ${stats['text_corrected'] ?? stats['text'] ?? ''}'
            .toLowerCase();
    final bool textLooksLikeAd = textSample.contains('sponsor ad') ||
        textSample.contains('advertisement') ||
        textSample.contains('classifieds');

    if (explicitAd || tagAd || textLooksLikeAd) {
      found.add(p);
    }
  }

  // In full-length zines (8+ pages), the back cover is traditionally an ad plate
  if (found.isEmpty &&
      pages.length >= 8 &&
      excludePageIndex != pages.length - 1) {
    found.add(pages.last);
  }

  return found;
}

/// Inline Bonus Row Share Panel (mobile / single-column view).
class ShareRowPanel extends StatelessComponent {
  final String fanzineId;
  final String? shortCode;
  final String? fanzineTitle;
  final String? masterIndicia;
  final int? startMonth;
  final int? startYear;
  final bool hasCover;
  final List<Map<String, dynamic>> pages;
  final Map<String, dynamic> pageData;
  final int pageIndex;
  final Map<String, Map<String, dynamic>> preloadedImageStats;
  final bool isTarget;

  const ShareRowPanel({
    required this.fanzineId,
    this.shortCode,
    this.fanzineTitle,
    this.masterIndicia,
    this.startMonth,
    this.startYear,
    this.hasCover = true,
    required this.pages,
    required this.pageData,
    required this.pageIndex,
    this.preloadedImageStats = const {},
    this.isTarget = true,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    return _ShareSpreadOptionsBody(
      fanzineId: fanzineId,
      shortCode: shortCode,
      fanzineTitle: fanzineTitle,
      masterIndicia: masterIndicia,
      startMonth: startMonth,
      startYear: startYear,
      hasCover: hasCover,
      pages: pages,
      pageData: pageData,
      pageIndex: pageIndex,
      preloadedImageStats: preloadedImageStats,
      eagerLoadComments: isTarget,
      isCompactRow: true,
    );
  }
}

/// Desktop 3rd Column Share Panel (synchronized per-page cards in `PanelColumnRenderer`).
class ShareColumnPanel extends StatelessComponent {
  final String fanzineId;
  final String? shortCode;
  final String? fanzineTitle;
  final String? masterIndicia;
  final int? startMonth;
  final int? startYear;
  final bool hasCover;
  final List<Map<String, dynamic>> pages;
  final Map<String, dynamic> pageData;
  final int pageIndex;
  final Map<String, Map<String, dynamic>> preloadedImageStats;
  final bool isTarget;

  const ShareColumnPanel({
    required this.fanzineId,
    this.shortCode,
    this.fanzineTitle,
    this.masterIndicia,
    this.startMonth,
    this.startYear,
    this.hasCover = true,
    required this.pages,
    required this.pageData,
    required this.pageIndex,
    this.preloadedImageStats = const {},
    this.isTarget = false,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    return _ShareSpreadOptionsBody(
      fanzineId: fanzineId,
      shortCode: shortCode,
      fanzineTitle: fanzineTitle,
      masterIndicia: masterIndicia,
      startMonth: startMonth,
      startYear: startYear,
      hasCover: hasCover,
      pages: pages,
      pageData: pageData,
      pageIndex: pageIndex,
      preloadedImageStats: preloadedImageStats,
      eagerLoadComments: isTarget,
      isCompactRow: false,
    );
  }
}

class _ShareChoiceDescriptor {
  final String id;
  final String title;
  final String subtitle;
  final String iconName;
  final SpreadCompanionKind kind;
  final Map<String, dynamic>? companionPage;

  const _ShareChoiceDescriptor({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.iconName,
    required this.kind,
    this.companionPage,
  });
}

class _ShareSpreadOptionsBody extends StatefulComponent {
  final String fanzineId;
  final String? shortCode;
  final String? fanzineTitle;
  final String? masterIndicia;
  final int? startMonth;
  final int? startYear;
  final bool hasCover;
  final List<Map<String, dynamic>> pages;
  final Map<String, dynamic> pageData;
  final int pageIndex;
  final Map<String, Map<String, dynamic>> preloadedImageStats;
  final bool eagerLoadComments;
  final bool isCompactRow;

  const _ShareSpreadOptionsBody({
    required this.fanzineId,
    this.shortCode,
    this.fanzineTitle,
    this.masterIndicia,
    this.startMonth,
    this.startYear,
    required this.hasCover,
    required this.pages,
    required this.pageData,
    required this.pageIndex,
    required this.preloadedImageStats,
    required this.eagerLoadComments,
    required this.isCompactRow,
  });

  @override
  State<_ShareSpreadOptionsBody> createState() =>
      _ShareSpreadOptionsBodyState();
}

class _ShareSpreadOptionsBodyState extends State<_ShareSpreadOptionsBody> {
  late bool _currentPageOnLeft;
  bool _copiedFeedback = true;
  Timer? _copiedTimer;

  List<Map<String, dynamic>> _comments = [];
  bool _commentsLoaded = false;
  bool _loadingComments = false;

  List<ShareBusinessOption> _businesses = [];
  bool _businessesLoaded = false;
  bool _loadingBusinesses = false;
  String? _selectedBusinessUid;

  String? _generatingChoiceId;
  String? _downloadedChoiceId;
  String? _errorMessage;
  Timer? _downloadStatusTimer;

  // Optional custom ad/page override when picking from multi-page fanzines
  int? _customAdPageIndex;

  @override
  void initState() {
    super.initState();
    final placement = resolveSpreadPlacement(
      pages: component.pages,
      pageIndex: component.pageIndex,
      hasCover: component.hasCover,
    );
    _currentPageOnLeft = placement.currentIsLeft;

    _copiedTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _copiedFeedback = false);
      }
    });

    if (_cachedBusinessOptions != null && _cachedBusinessOptions!.isNotEmpty) {
      _businesses = _cachedBusinessOptions!;
      _businessesLoaded = true;
      _selectedBusinessUid = _businesses.first.uid;
    } else if (kIsWeb) {
      _fetchBusinessesIfNeeded();
    }

    if (component.eagerLoadComments && kIsWeb) {
      _fetchCommentsIfNeeded();
    }
  }

  @override
  void didUpdateComponent(_ShareSpreadOptionsBody oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.pageIndex != component.pageIndex ||
        oldComponent.pageData['imageId'] != component.pageData['imageId']) {
      final placement = resolveSpreadPlacement(
        pages: component.pages,
        pageIndex: component.pageIndex,
        hasCover: component.hasCover,
      );
      _currentPageOnLeft = placement.currentIsLeft;
      _comments = [];
      _commentsLoaded = false;
      _customAdPageIndex = null;
      if (component.eagerLoadComments && kIsWeb) {
        _fetchCommentsIfNeeded();
      }
    } else if (!oldComponent.eagerLoadComments &&
        component.eagerLoadComments &&
        kIsWeb) {
      _fetchCommentsIfNeeded();
    }
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _downloadStatusTimer?.cancel();
    super.dispose();
  }

  String get _canonicalUrl {
    final String sc = (component.shortCode != null &&
            component.shortCode!.trim().isNotEmpty)
        ? component.shortCode!.trim()
        : component.fanzineId;
    final int pNum =
        (component.pageData['pageNumber'] as int?) ?? (component.pageIndex + 1);
    if (sc.isEmpty) return 'https://bqopd.com';
    if (pNum > 1) return 'https://bqopd.com/$sc/$pNum';
    return 'https://bqopd.com/$sc';
  }

  int get _resolvedPageNumber =>
      (component.pageData['pageNumber'] as int?) ?? (component.pageIndex + 1);

  String? _bestThumbnailUrl(Map<String, dynamic>? page) {
    if (page == null) return null;
    final String imgId = (page['imageId'] ?? '').toString();
    final stats = component.preloadedImageStats[imgId];
    return (page['gridUrl'] ??
            page['listUrl'] ??
            page['imageUrl'] ??
            stats?['gridUrl'] ??
            stats?['listUrl'] ??
            stats?['fileUrl'])
        ?.toString();
  }

  String? _bestHighResUrl(Map<String, dynamic>? page) {
    if (page == null) return null;
    final String imgId = (page['imageId'] ?? '').toString();
    final stats = component.preloadedImageStats[imgId];
    return (stats?['fileUrl'] ??
            page['fileUrl'] ??
            page['imageUrl'] ??
            stats?['imageUrl'] ??
            page['listUrl'] ??
            stats?['listUrl'] ??
            page['gridUrl'])
        ?.toString();
  }

  Future<void> _fetchCommentsIfNeeded() async {
    if (_commentsLoaded || _loadingComments || !kIsWeb) return;
    final String imageId = (component.pageData['imageId'] ?? '').toString();
    if (imageId.isEmpty || imageId.startsWith('preview_')) {
      _commentsLoaded = true;
      return;
    }

    setState(() => _loadingComments = true);
    try {
      final res = await fsQuery(
        'artifacts/bqopd/public/data/comments',
        'contentId',
        '==',
        jsonEncode(imageId),
        '',
      );
      final List decoded = jsonDecode(res) as List;
      final List<Map<String, dynamic>> loaded = decoded.map((d) {
        final data = Map<String, dynamic>.from(d['data'] as Map? ?? {});
        data['_id'] = d['id'];
        return data;
      }).toList();

      loaded.sort((a, b) {
        final aT = (a['createdAt'] ?? a['timestamp'] ?? '').toString();
        final bT = (b['createdAt'] ?? b['timestamp'] ?? '').toString();
        return aT.compareTo(bT);
      });

      if (mounted) {
        setState(() {
          _comments = loaded;
          _commentsLoaded = true;
          _loadingComments = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _commentsLoaded = true;
          _loadingComments = false;
        });
      }
    }
  }

  ShareBusinessOption? get _selectedBusiness {
    if (_businesses.isEmpty) return null;
    if (_selectedBusinessUid != null) {
      for (final b in _businesses) {
        if (b.uid == _selectedBusinessUid) return b;
      }
    }
    return _businesses.first;
  }

  Future<void> _fetchBusinessesIfNeeded() async {
    if (_businessesLoaded || _loadingBusinesses || !kIsWeb) return;
    setState(() => _loadingBusinesses = true);
    final loaded = await _loadBusinessProfiles();
    if (!mounted) return;
    setState(() {
      _businesses = loaded;
      _businessesLoaded = true;
      _loadingBusinesses = false;
      if (_selectedBusinessUid == null && loaded.isNotEmpty) {
        _selectedBusinessUid = loaded.first.uid;
      }
    });
  }

  void _copyLinkAgain() {
    copyToClipboard(_canonicalUrl);
    setState(() => _copiedFeedback = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copiedFeedback = false);
      }
    });
  }

  Future<void> _handleThumbnailClick(_ShareChoiceDescriptor choice) async {
    if (_generatingChoiceId != null) return;

    setState(() {
      _generatingChoiceId = choice.id;
      _downloadedChoiceId = null;
      _errorMessage = null;
    });

    if (choice.kind == SpreadCompanionKind.pageComments && !_commentsLoaded) {
      await _fetchCommentsIfNeeded();
    }
    if (choice.kind == SpreadCompanionKind.businessHours && !_businessesLoaded) {
      await _fetchBusinessesIfNeeded();
    }

    final DateTime now = DateTime.now();
    final int calMonth = component.startMonth ?? now.month;
    final int calYear = component.startYear ?? now.year;

    final String cleanSlug = ((component.shortCode?.isNotEmpty == true)
            ? component.shortCode!
            : (component.fanzineTitle ?? 'bqopd'))
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '-')
        .replaceAll(RegExp(r'-+'), '-');

    final String fileName =
        '$cleanSlug-p$_resolvedPageNumber-${choice.id}-spread.jpg';

    final companionPage = choice.companionPage;
    final int? companionNum = companionPage != null
        ? (companionPage['pageNumber'] as int?)
        : null;

    final request = PrintableSpreadRequest(
      fileName: fileName,
      fanzineTitle: component.fanzineTitle ?? 'bqopd Fanzine',
      canonicalUrl: _canonicalUrl,
      shortCode: component.shortCode ?? component.fanzineId,
      masterIndicia: component.masterIndicia,
      pageNumber: _resolvedPageNumber,
      currentPageOnLeft: _currentPageOnLeft,
      primaryImageUrl: _bestHighResUrl(component.pageData),
      primaryFallbackText: component.pageData['text']?.toString(),
      primaryTemplateId: component.pageData['templateId']?.toString(),
      companionKind: choice.kind,
      companionImageUrl: _bestHighResUrl(companionPage),
      companionFallbackText: companionPage?['text']?.toString(),
      companionPageNumber: companionNum,
      calendarStartMonth: calMonth,
      calendarStartYear: calYear,
      comments: _comments,
      businessSign: _selectedBusiness?.toSignData(),
    );

    final bool ok = await generateAndDownloadSpreadJpg(request);

    if (!mounted) return;
    setState(() {
      _generatingChoiceId = null;
      if (ok) {
        _downloadedChoiceId = choice.id;
      } else {
        _errorMessage = 'Could not generate spread JPG. Please try again.';
      }
    });

    if (ok) {
      _downloadStatusTimer?.cancel();
      _downloadStatusTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _downloadedChoiceId = null);
        }
      });
    }
  }

  @override
  Component build(BuildContext context) {
    final placement = resolveSpreadPlacement(
      pages: component.pages,
      pageIndex: component.pageIndex,
      hasCover: component.hasCover,
    );

    final adPages = detectFanzineAdPages(
      pages: component.pages,
      excludePageIndex: component.pageIndex,
      imageStats: component.preloadedImageStats,
    );

    Map<String, dynamic>? selectedAdPage;
    if (_customAdPageIndex != null &&
        _customAdPageIndex! >= 0 &&
        _customAdPageIndex! < component.pages.length &&
        _customAdPageIndex != component.pageIndex) {
      selectedAdPage = component.pages[_customAdPageIndex!];
    } else if (adPages.isNotEmpty) {
      selectedAdPage = adPages.first;
    }

    final List<_ShareChoiceDescriptor> choices = [
      if (placement.facingPage != null)
        _ShareChoiceDescriptor(
          id: 'fanzine-spread',
          title: 'Fanzine Spread',
          subtitle: placement.facingRelationLabel,
          iconName: 'menu_book',
          kind: SpreadCompanionKind.fanzinePage,
          companionPage: placement.facingPage,
        ),
      _ShareChoiceDescriptor(
        id: 'wall-calendar',
        title: 'Wall Calendar',
        subtitle: '6-month pin-up calendar + notes',
        iconName: 'calendar_month',
        kind: SpreadCompanionKind.wallCalendar,
      ),
      _ShareChoiceDescriptor(
        id: 'fanzine-ad',
        title: selectedAdPage != null
            ? 'Fanzine Ad (Page ${selectedAdPage['pageNumber'] ?? ''})'
            : 'Fanzine House Ad',
        subtitle: selectedAdPage != null
            ? 'Paired with ad page from this issue'
            : 'Vintage zine print ad + issue link',
        iconName: 'campaign',
        kind: selectedAdPage != null
            ? SpreadCompanionKind.fanzinePage
            : SpreadCompanionKind.houseAd,
        companionPage: selectedAdPage,
      ),
      _ShareChoiceDescriptor(
        id: 'business-hours',
        title: 'Business Hours',
        subtitle: _selectedBusiness != null
            ? '${_selectedBusiness!.displayName} · Door sign'
            : 'Front-door hours of operation sign',
        iconName: 'storefront',
        kind: SpreadCompanionKind.businessHours,
      ),
      _ShareChoiceDescriptor(
        id: 'page-comments',
        title: 'Page Comments',
        subtitle: _commentsLoaded
            ? (_comments.isEmpty
                  ? 'Reader notes & reply lines'
                  : '${_comments.length} ${_comments.length == 1 ? "comment" : "comments"} + margin notes')
            : 'Comments & letters on this page',
        iconName: 'forum',
        kind: SpreadCompanionKind.pageComments,
      ),
      _ShareChoiceDescriptor(
        id: 'same-page-2up',
        title: 'Same Image (2-Up)',
        subtitle: 'Two copies — cut & give to a friend',
        iconName: 'content_cut',
        kind: SpreadCompanionKind.duplicatePage,
        companionPage: component.pageData,
      ),
    ];

    return div(
      classes: 'flex-col w-full',
      attributes: const {
        'style': 'display: flex; flex-direction: column; gap: 12px; width: 100%;'
      },
      [
        // 1. Canonical Link Copied Bar
        div(
          attributes: const {
            'style':
                'display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 8px 12px; background-color: #EEF2FF; border: 1px solid #C7D2FE; border-radius: 8px; flex-wrap: wrap;'
          },
          [
            div(
              attributes: const {
                'style':
                    'display: flex; align-items: center; gap: 8px; min-width: 0; flex: 1;'
              },
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {
                    'style': 'font-size: 16px; color: #4F46E5; flex-shrink: 0;'
                  },
                  [Component.text(_copiedFeedback ? 'check_circle' : 'link')],
                ),
                div(
                  attributes: const {
                    'style': 'min-width: 0; overflow: hidden;'
                  },
                  [
                    div(
                      attributes: const {
                        'style':
                            'font-size: 10px; font-weight: 800; letter-spacing: 0.5px; text-transform: uppercase; color: #4338CA;'
                      },
                      [
                        Component.text(
                          _copiedFeedback
                              ? 'Page URL copied to clipboard'
                              : 'Direct link to Page $_resolvedPageNumber',
                        )
                      ],
                    ),
                    div(
                      attributes: const {
                        'style':
                            'font-size: 11px; color: #312E81; font-family: monospace; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'
                      },
                      [Component.text(_canonicalUrl)],
                    ),
                  ],
                ),
              ],
            ),
            button(
              attributes: const {
                'type': 'button',
                'style':
                    'padding: 5px 10px; font-size: 11px; font-weight: 700; color: #4338CA; background-color: #FFFFFF; border: 1px solid #A5B4FC; border-radius: 999px; cursor: pointer; flex-shrink: 0;'
              },
              events: {
                'click': (e) {
                  e.stopPropagation();
                  _copyLinkAgain();
                }
              },
              [Component.text(_copiedFeedback ? 'Copied!' : 'Copy URL')],
            ),
          ],
        ),

        // 2. Spread Header + Left/Right Side Orientation Toggle
        div(
          attributes: const {
            'style':
                'display: flex; align-items: center; justify-content: space-between; gap: 8px; flex-wrap: wrap;'
          },
          [
            div(
              [
                div(
                  attributes: const {
                    'style':
                        'font-size: 12px; font-weight: 800; color: #0F172A; letter-spacing: 0.3px;'
                  },
                  [Component.text('Download Printable 2-Page Spread (JPG)')],
                ),
                div(
                  attributes: const {
                    'style': 'font-size: 11px; color: #64748B;'
                  },
                  [
                    Component.text(
                      'Click any thumbnail to download a 300-DPI 11×8.5" sheet to print, pin up, or share.',
                    )
                  ],
                ),
              ],
            ),
            button(
              attributes: const {
                'type': 'button',
                'title': 'Swap which side of the spread this page appears on',
                'style':
                    'display: inline-flex; align-items: center; gap: 4px; padding: 4px 10px; font-size: 10px; font-weight: 700; color: #334155; background-color: #F1F5F9; border: 1px solid #CBD5E1; border-radius: 999px; cursor: pointer;'
              },
              events: {
                'click': (e) {
                  e.stopPropagation();
                  setState(() => _currentPageOnLeft = !_currentPageOnLeft);
                }
              },
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {'style': 'font-size: 14px;'},
                  [Component.text('swap_horiz')],
                ),
                Component.text(
                  _currentPageOnLeft
                      ? 'Page $_resolvedPageNumber on Left'
                      : 'Page $_resolvedPageNumber on Right',
                ),
              ],
            ),
          ],
        ),

        // 2B. Business Selector Dropdown for the Business Hours Door Sign
        div(
          attributes: const {
            'style':
                'display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 8px 10px; background-color: #F8FAFC; border: 1px solid #E2E8F0; border-radius: 8px; flex-wrap: wrap;'
          },
          [
            div(
              attributes: const {
                'style': 'display: flex; align-items: center; gap: 6px;'
              },
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {
                    'style': 'font-size: 16px; color: #334155;'
                  },
                  [Component.text('storefront')],
                ),
                span(
                  attributes: const {
                    'style':
                        'font-size: 11px; font-weight: 700; color: #1E293B;'
                  },
                  [Component.text('Business for Hours Sign:')],
                ),
              ],
            ),
            select(
              attributes: {
                'style':
                    'padding: 5px 10px; font-size: 11px; font-weight: 600; border: 1px solid #CBD5E1; border-radius: 6px; background-color: #FFFFFF; color: #0F172A; cursor: pointer; min-width: 170px; max-width: 100%;',
                if (_businesses.isEmpty) 'disabled': 'true',
              },
              events: {
                'click': (e) => e.stopPropagation(),
                'change': (e) {
                  final val = getInputValue(e);
                  if (val.isNotEmpty) {
                    setState(() => _selectedBusinessUid = val);
                  }
                }
              },
              [
                if (_loadingBusinesses && _businesses.isEmpty)
                  option(
                    attributes: const {'value': ''},
                    [Component.text('Loading businesses…')],
                  )
                else if (_businesses.isEmpty)
                  option(
                    attributes: const {'value': ''},
                    [Component.text('No business profiles found')],
                  )
                else
                  for (final biz in _businesses)
                    option(
                      attributes: {
                        'value': biz.uid,
                        if (_selectedBusiness?.uid == biz.uid)
                          'selected': 'selected',
                      },
                      [Component.text(biz.dropdownLabel)],
                    ),
              ],
            ),
          ],
        ),

        if (_errorMessage != null)
          div(
            attributes: const {
              'style':
                  'padding: 8px 10px; font-size: 11px; font-weight: 600; color: #B91C1C; background-color: #FEF2F2; border: 1px solid #FECACA; border-radius: 6px;'
            },
            [Component.text(_errorMessage!)],
          ),

        // 3. Thumbnail Grid of 2-Page Spread Choices
        div(
          attributes: {
            'style': component.isCompactRow
                ? 'display: grid; grid-template-columns: repeat(auto-fill, minmax(175px, 1fr)); gap: 12px; width: 100%;'
                : 'display: grid; grid-template-columns: repeat(auto-fill, minmax(195px, 1fr)); gap: 12px; width: 100%;'
          },
          [
            for (final choice in choices) _buildSpreadThumbnailCard(choice),
          ],
        ),

        // 4. Optional Ad / Companion Page Picker when the fanzine has multiple pages
        if (component.pages.length > 2)
          div(
            attributes: const {
              'style':
                  'display: flex; align-items: center; justify-content: space-between; gap: 8px; padding-top: 4px; border-top: 1px dashed #E2E8F0; flex-wrap: wrap;'
            },
            [
              span(
                attributes: const {
                  'style': 'font-size: 11px; color: #64748B; font-weight: 600;'
                },
                [Component.text('Ad / Zine page slot:')],
              ),
              select(
                attributes: const {
                  'style':
                      'padding: 4px 8px; font-size: 11px; border: 1px solid #CBD5E1; border-radius: 6px; background-color: #FFFFFF; color: #1E293B; cursor: pointer;'
                },
                events: {
                  'click': (e) => e.stopPropagation(),
                  'change': (e) {
                    final val = getInputValue(e);
                    setState(() {
                      if (val == 'house') {
                        _customAdPageIndex = -1;
                      } else if (val.isEmpty) {
                        _customAdPageIndex = null;
                      } else {
                        _customAdPageIndex = int.tryParse(val);
                      }
                    });
                  }
                },
                [
                  option(
                    attributes: {
                      'value': '',
                      if (_customAdPageIndex == null) 'selected': 'selected',
                    },
                    [
                      Component.text(
                        adPages.isNotEmpty
                            ? 'Auto (Page ${adPages.first['pageNumber'] ?? ''})'
                            : 'Auto (bqopd House Ad)',
                      )
                    ],
                  ),
                  if (adPages.isNotEmpty)
                    option(
                      attributes: {
                        'value': 'house',
                        if (_customAdPageIndex == -1) 'selected': 'selected',
                      },
                      [Component.text('bqopd Vintage House Ad')],
                    ),
                  for (int i = 0; i < component.pages.length; i++)
                    if (i != component.pageIndex)
                      option(
                        attributes: {
                          'value': '$i',
                          if (_customAdPageIndex == i) 'selected': 'selected',
                        },
                        [
                          Component.text(
                            'Page ${component.pages[i]['pageNumber'] ?? (i + 1)} from this zine',
                          )
                        ],
                      ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  Component _buildSpreadThumbnailCard(_ShareChoiceDescriptor choice) {
    // Allow explicit selection of House Ad when _customAdPageIndex == -1
    final _ShareChoiceDescriptor effectiveChoice =
        (choice.id == 'fanzine-ad' && _customAdPageIndex == -1)
            ? const _ShareChoiceDescriptor(
                id: 'fanzine-ad',
                title: 'Fanzine House Ad',
                subtitle: 'Vintage zine print ad + issue link',
                iconName: 'campaign',
                kind: SpreadCompanionKind.houseAd,
              )
            : choice;

    final bool isGenerating = _generatingChoiceId == effectiveChoice.id;
    final bool isDownloaded = _downloadedChoiceId == effectiveChoice.id;

    final Component primaryHalf = _buildPrimaryMiniHalf();
    final Component companionHalf = _buildCompanionMiniHalf(effectiveChoice);

    final Component leftHalf = _currentPageOnLeft ? primaryHalf : companionHalf;
    final Component rightHalf =
        _currentPageOnLeft ? companionHalf : primaryHalf;

    return button(
      attributes: {
        'type': 'button',
        'title': 'Click to download ${effectiveChoice.title} spread JPG',
        'style':
            'display: flex; flex-direction: column; align-items: stretch; text-align: left; padding: 8px; background-color: #FFFFFF; border: ${isDownloaded ? "2px solid #16A34A" : (isGenerating ? "2px solid #6750A4" : "1px solid #CBD5E1")}; border-radius: 8px; cursor: ${isGenerating ? "wait" : "pointer"}; box-shadow: 0 1px 4px rgba(15, 23, 42, 0.06); transition: transform 0.14s ease, box-shadow 0.14s ease, border-color 0.14s ease;'
      },
      events: {
        'click': (e) {
          e.stopPropagation();
          _handleThumbnailClick(effectiveChoice);
        }
      },
      [
        // Miniature 11 x 8.5 Paper Spread Preview
        div(
          attributes: const {
            'style':
                'position: relative; width: 100%; aspect-ratio: 11 / 8.5; background-color: #F1F5F9; border: 1px solid #E2E8F0; border-radius: 4px; padding: 5px; box-sizing: border-box; display: flex; align-items: stretch; justify-content: center; overflow: hidden;'
          },
          [
            div(
              attributes: const {
                'style':
                    'position: relative; width: 100%; height: 100%; background-color: #FFFFFF; box-shadow: 0 2px 6px rgba(0, 0, 0, 0.10); border-radius: 2px; padding: 3%; box-sizing: border-box; display: flex; flex-direction: row; gap: 3%;'
              },
              [
                // Left half
                div(
                  attributes: const {
                    'style':
                        'flex: 1; height: 100%; overflow: hidden; border: 1px solid #E2E8F0; background-color: #FFFFFF; display: flex; align-items: center; justify-content: center;'
                  },
                  [leftHalf],
                ),
                // Center fold shadow line
                div(
                  attributes: const {
                    'style':
                        'width: 1px; align-self: stretch; background: repeating-linear-gradient(to bottom, #CBD5E1 0, #CBD5E1 3px, transparent 3px, transparent 6px); flex-shrink: 0;'
                  },
                  [],
                ),
                // Right half
                div(
                  attributes: const {
                    'style':
                        'flex: 1; height: 100%; overflow: hidden; border: 1px solid #E2E8F0; background-color: #FFFFFF; display: flex; align-items: center; justify-content: center;'
                  },
                  [rightHalf],
                ),
              ],
            ),

            // Status overlay when generating or downloaded
            if (isGenerating || isDownloaded)
              div(
                attributes: {
                  'style':
                      'position: absolute; inset: 0; background-color: ${isDownloaded ? "rgba(22, 163, 74, 0.86)" : "rgba(15, 23, 42, 0.72)"}; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 4px; color: #FFFFFF; font-size: 11px; font-weight: 800;'
                },
                [
                  span(
                    classes: 'material-symbols-outlined',
                    attributes: const {'style': 'font-size: 22px;'},
                    [
                      Component.text(
                        isDownloaded ? 'download_done' : 'downloading',
                      )
                    ],
                  ),
                  span([
                    Component.text(
                      isDownloaded ? 'JPG Downloaded!' : 'Rendering 300 DPI…',
                    )
                  ]),
                ],
              ),
          ],
        ),

        // Caption & Download Pill Row
        div(
          attributes: const {
            'style':
                'display: flex; align-items: center; justify-content: space-between; gap: 6px; margin-top: 8px;'
          },
          [
            div(
              attributes: const {'style': 'min-width: 0; flex: 1;'},
              [
                div(
                  attributes: const {
                    'style':
                        'display: flex; align-items: center; gap: 4px; font-size: 11px; font-weight: 800; color: #0F172A; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'
                  },
                  [
                    span(
                      classes: 'material-symbols-outlined',
                      attributes: const {
                        'style': 'font-size: 14px; color: #6750A4;'
                      },
                      [Component.text(effectiveChoice.iconName)],
                    ),
                    span(
                      attributes: const {
                        'style':
                            'overflow: hidden; text-overflow: ellipsis; white-space: nowrap;'
                      },
                      [Component.text(effectiveChoice.title)],
                    ),
                  ],
                ),
                div(
                  attributes: const {
                    'style':
                        'font-size: 10px; color: #64748B; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; margin-top: 1px;'
                  },
                  [Component.text(effectiveChoice.subtitle)],
                ),
              ],
            ),
            span(
              classes: 'material-symbols-outlined',
              attributes: const {
                'style':
                    'font-size: 16px; color: #475569; background-color: #F1F5F9; padding: 4px; border-radius: 50%; flex-shrink: 0;'
              },
              [Component.text('download')],
            ),
          ],
        ),
      ],
    );
  }

  Component _buildPrimaryMiniHalf() {
    final String? thumb = _bestThumbnailUrl(component.pageData);
    if (thumb != null && thumb.isNotEmpty) {
      return img(
        src: thumb,
        attributes: const {
          'style':
              'width: 100%; height: 100%; object-fit: contain; display: block;',
          'loading': 'lazy',
        },
      );
    }
    return div(
      attributes: const {
        'style':
            'padding: 4px; font-size: 8px; font-weight: 700; color: #334155; text-align: center;'
      },
      [Component.text('PAGE $_resolvedPageNumber')],
    );
  }

  Component _buildCompanionMiniHalf(_ShareChoiceDescriptor choice) {
    switch (choice.kind) {
      case SpreadCompanionKind.duplicatePage:
        return _buildPrimaryMiniHalf();

      case SpreadCompanionKind.fanzinePage:
        final String? thumb = _bestThumbnailUrl(choice.companionPage);
        if (thumb != null && thumb.isNotEmpty) {
          return img(
            src: thumb,
            attributes: const {
              'style':
                  'width: 100%; height: 100%; object-fit: contain; display: block;',
              'loading': 'lazy',
            },
          );
        }
        final pNum = choice.companionPage?['pageNumber'] ?? '';
        return div(
          attributes: const {
            'style':
                'padding: 4px; font-size: 8px; font-weight: 700; color: #334155; text-align: center;'
          },
          [Component.text('PAGE $pNum')],
        );

      case SpreadCompanionKind.houseAd:
        return div(
          attributes: const {
            'style':
                'width: 100%; height: 100%; box-sizing: border-box; border: 2px solid #0F172A; background-color: #FFFDF7; padding: 4px; display: flex; flex-direction: column; align-items: center; justify-content: space-between; text-align: center;'
          },
          [
            div(
              attributes: const {
                'style':
                    'width: 100%; background-color: #0F172A; color: #F1B255; font-size: 6px; font-weight: 900; padding: 2px 0; letter-spacing: 0.4px;'
              },
              [Component.text('★ BQOPD PRESS ★')],
            ),
            div(
              attributes: const {
                'style':
                    'font-size: 8px; font-weight: 900; color: #0F172A; line-height: 1.15;'
              },
              [
                Component.text(
                  (component.fanzineTitle ?? 'FANZINE').toUpperCase(),
                )
              ],
            ),
            div(
              attributes: const {
                'style':
                    'width: 90%; border: 1px dashed #334155; padding: 2px; font-size: 6px; font-weight: 800; color: #6750A4;'
              },
              [Component.text('bqopd.com')],
            ),
          ],
        );

      case SpreadCompanionKind.wallCalendar:
        final DateTime now = DateTime.now();
        final int sm = component.startMonth ?? now.month;
        const shortM = [
          'JAN',
          'FEB',
          'MAR',
          'APR',
          'MAY',
          'JUN',
          'JUL',
          'AUG',
          'SEP',
          'OCT',
          'NOV',
          'DEC'
        ];
        return div(
          attributes: const {
            'style':
                'width: 100%; height: 100%; box-sizing: border-box; border: 1.5px solid #0F172A; background-color: #FFFFFF; display: flex; flex-direction: column;'
          },
          [
            div(
              attributes: const {
                'style':
                    'background-color: #0F172A; color: #FFFFFF; font-size: 6px; font-weight: 900; padding: 2px 3px; text-align: left; letter-spacing: 0.3px;'
              },
              [Component.text('WALL CALENDAR')],
            ),
            div(
              attributes: const {
                'style':
                    'flex: 1; display: grid; grid-template-columns: 1fr 1fr; grid-template-rows: 1fr 1fr 1fr; border-bottom: 1px solid #0F172A;'
              },
              [
                for (int m = 0; m < 6; m++)
                  div(
                    attributes: const {
                      'style':
                          'border: 0.5px solid #CBD5E1; padding: 2px; display: flex; flex-direction: column; justify-content: space-between;'
                    },
                    [
                      div(
                        attributes: const {
                          'style':
                              'font-size: 5.5px; font-weight: 900; color: #0F172A;'
                        },
                        [Component.text(shortM[(sm - 1 + m) % 12])],
                      ),
                      div(
                        attributes: const {
                          'style':
                              'flex: 1; background-image: radial-gradient(#94A3B8 0.7px, transparent 0.7px); background-size: 4px 4px; opacity: 0.75;'
                        },
                        [],
                      ),
                    ],
                  ),
              ],
            ),
            div(
              attributes: const {
                'style':
                    'height: 16%; padding: 2px 3px; display: flex; flex-direction: column; justify-content: space-evenly;'
              },
              [
                div(
                  attributes: const {
                    'style': 'height: 1px; background-color: #CBD5E1;'
                  },
                  [],
                ),
                div(
                  attributes: const {
                    'style': 'height: 1px; background-color: #CBD5E1;'
                  },
                  [],
                ),
              ],
            ),
          ],
        );

      case SpreadCompanionKind.pageComments:
        return div(
          attributes: const {
            'style':
                'width: 100%; height: 100%; box-sizing: border-box; border: 1.5px solid #0F172A; background-color: #FFFFFF; display: flex; flex-direction: column;'
          },
          [
            div(
              attributes: const {
                'style':
                    'background-color: #0F172A; color: #FFFFFF; font-size: 5.5px; font-weight: 900; padding: 2px 3px; letter-spacing: 0.3px;'
              },
              [Component.text('COMMENTS & NOTES')],
            ),
            div(
              attributes: const {
                'style':
                    'flex: 1; display: flex; flex-direction: row; padding: 3px; gap: 3px;'
              },
              [
                div(
                  attributes: const {
                    'style':
                        'flex: 1; display: flex; flex-direction: column; gap: 2px;'
                  },
                  [
                    if (_comments.isNotEmpty)
                      div(
                        attributes: const {
                          'style':
                              'font-size: 5px; line-height: 1.2; color: #1E293B; overflow: hidden; text-align: left;'
                        },
                        [
                          Component.text(
                            (_comments.first['text'] ?? '').toString(),
                          )
                        ],
                      )
                    else ...[
                      div(
                        attributes: const {
                          'style': 'height: 2px; background: #94A3B8; width: 70%;'
                        },
                        [],
                      ),
                      div(
                        attributes: const {
                          'style': 'height: 1.5px; background: #CBD5E1; width: 100%;'
                        },
                        [],
                      ),
                      div(
                        attributes: const {
                          'style': 'height: 1.5px; background: #CBD5E1; width: 90%;'
                        },
                        [],
                      ),
                    ]
                  ],
                ),
                div(
                  attributes: const {
                    'style': 'width: 1px; background-color: #0F172A;'
                  },
                  [],
                ),
                div(
                  attributes: const {
                    'style':
                        'flex: 1; display: flex; flex-direction: column; gap: 3px;'
                  },
                  [
                    div(
                      attributes: const {
                        'style': 'height: 1.5px; background: #CBD5E1; width: 100%;'
                      },
                      [],
                    ),
                    div(
                      attributes: const {
                        'style': 'height: 1.5px; background: #CBD5E1; width: 100%;'
                      },
                      [],
                    ),
                    div(
                      attributes: const {
                        'style': 'height: 1.5px; background: #CBD5E1; width: 85%;'
                      },
                      [],
                    ),
                  ],
                ),
              ],
            ),
          ],
        );

      case SpreadCompanionKind.businessHours:
        final biz = _selectedBusiness;
        const shortDays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
        return div(
          attributes: const {
            'style':
                'width: 100%; height: 100%; box-sizing: border-box; border: 2px solid #0F172A; background-color: #FFFFFF; padding: 2px; display: flex; flex-direction: column; justify-content: space-between;'
          },
          [
            div(
              attributes: const {
                'style':
                    'background-color: #111111; color: #FFFFFF; font-size: 5.5px; font-weight: 900; padding: 2px 1px; text-align: center; letter-spacing: 0.3px;'
              },
              [Component.text('BUSINESS HOURS')],
            ),
            div(
              attributes: const {
                'style':
                    'flex: 1; display: flex; flex-direction: column; justify-content: space-evenly; padding: 2px 3px; border-bottom: 1px solid #0F172A;'
              },
              [
                for (int d = 0; d < kBusinessDaysOfWeek.length; d++)
                  _buildMiniBusinessDayRow(
                    shortDays[d],
                    biz?.businessHours[kBusinessDaysOfWeek[d]] ??
                        const BusinessDayHours(),
                  ),
              ],
            ),
            div(
              attributes: const {
                'style':
                    'padding: 2px 2px 1px 2px; text-align: center; overflow: hidden;'
              },
              [
                div(
                  attributes: const {
                    'style':
                        'font-size: 5px; font-weight: 900; color: #0F172A; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'
                  },
                  [
                    Component.text(
                      (biz?.displayName ?? 'BUSINESS').toUpperCase(),
                    )
                  ],
                ),
                if (biz != null && biz.username.trim().isNotEmpty)
                  div(
                    attributes: const {
                      'style':
                          'font-size: 4.2px; font-weight: 700; color: #4338CA; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'
                    },
                    [
                      Component.text(
                        '@${biz.username.trim().replaceAll("@", "")}',
                      )
                    ],
                  ),
                if (biz != null && biz.addressLines.isNotEmpty)
                  div(
                    attributes: const {
                      'style':
                          'font-size: 4px; font-weight: 600; color: #475569; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'
                    },
                    [Component.text(biz.addressLines.first)],
                  ),
              ],
            ),
          ],
        );
    }
  }

  Component _buildMiniBusinessDayRow(String shortDay, BusinessDayHours dh) {
    final String openStr =
        dh.isOpen ? (dh.open.isNotEmpty ? dh.open : 'Open') : 'CLOSED';
    final String closeStr =
        dh.isOpen ? (dh.close.isNotEmpty ? dh.close : '—') : '—';
    return div(
      attributes: const {
        'style':
            'display: grid; grid-template-columns: 1.1fr 1fr 1fr; align-items: center; font-size: 4.2px; line-height: 1;'
      },
      [
        span(
          attributes: const {
            'style': 'font-weight: 800; color: #0F172A; text-align: left;'
          },
          [Component.text(shortDay)],
        ),
        span(
          attributes: {
            'style':
                'color: ${dh.isOpen ? "#0F172A" : "#94A3B8"}; font-weight: 700; text-align: center; white-space: nowrap; overflow: hidden;'
          },
          [Component.text(openStr)],
        ),
        span(
          attributes: {
            'style':
                'color: ${dh.isOpen ? "#0F172A" : "#94A3B8"}; font-weight: 700; text-align: right; white-space: nowrap; overflow: hidden;'
          },
          [Component.text(closeStr)],
        ),
      ],
    );
  }
}

