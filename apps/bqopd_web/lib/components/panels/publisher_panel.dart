import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:jaspr/jaspr.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';
import '../../utils/unsaved_fanzine_registry.dart';
import 'publisher/publisher_schedule_view.dart';
import 'publisher/publisher_week_dashboard.dart';
import 'publisher/publisher_circulation_view.dart';

/// The central studio coordinator for the dedicated `/publisher` production desk.
/// Orchestrates Firestore streams, 52-week schedule carryover, Circulation recipients,
/// and the 24-page personalized Blueprint Engine preview in Columns 1 & 2.
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

  // Interactive 72-page visualizer filter state & active Blueprint selection
  String? _activeCategoryFilter;
  String? _activeBlueprintId;
  String _selectedPreviewUserKey = 'persona_terminal';

  // Scheduled Fanzines per week (cache & firestore subscription)
  final Map<String, List<ScheduledFanzine>> _weeklyFanzinesCache = {};
  FirebaseSubscription? _scheduledFanzinesSub;

  // Series selection map (loaded dynamically from database, falls back to default choices)
  Map<String, String> _seriesOptionsMap =
      Map.from(defaultPublisherSeriesOptions);
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
    _seriesSub = fsListenQuery(
      'artifacts/bqopd/public/data/series',
      '',
      '',
      '',
      '',
      false,
      (String jsonStr) {
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
          for (var e in defaultPublisherSeriesOptions.entries) {
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
      },
    );
  }

  void _listenToProfiles() {
    _profilesSub?.callAsFunction();
    _profilesSub = fsListenQuery(
      'profiles',
      '',
      '',
      '',
      '',
      false,
      (String jsonStr) {
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
      },
    );
  }

  void _listenToPublishedIssues() {
    _fanzinesSub?.callAsFunction();
    _fanzinesSub = fsListenQuery(
      'fanzines',
      'isLive',
      '==',
      'true',
      '',
      false,
      (String jsonStr) {
        try {
          final List decoded = jsonDecode(jsonStr);
          final Map<int, int> counts = {};

          for (var item in decoded) {
            final data = item['data'] as Map<String, dynamic>? ?? {};
            DateTime? pubDate;

            if (data['publishedAt'] != null && data['publishedAt'] is int) {
              pubDate =
                  DateTime.fromMillisecondsSinceEpoch(data['publishedAt'] as int);
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
              final firstMonday =
                  jan1.subtract(Duration(days: jan1.weekday - DateTime.monday));
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
      },
    );
  }

  void _rebuildWeeks() {
    _weeks = generatePublishingWeeks(
      _selectedYear,
      publishedCounts: _publishedCounts,
    );

    if (_weeks.isNotEmpty) {
      final hasCurrentSelection =
          _weeks.any((w) => w.weekNumber == _selectedWeekNumber);
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

  /// Resolves the active [RecipientFeedContext] from the user's dropdown selection
  /// so the Blueprint Engine can simulate personalized 24-page mixes in real time.
  RecipientFeedContext _resolveActiveRecipientContext() {
    if (_selectedPreviewUserKey == 'persona_standard') {
      return const RecipientFeedContext(
        userId: 'persona_standard',
        displayName: 'Maya Lin (Standard Reader)',
        city: 'Seattle',
        state: 'WA',
        playsTerminalGame: false,
        followedCreatorIds: {'u_1', 'u_2', 'u_5'},
        likedHashtags: {'comics', 'indie', 'print'},
      );
    }

    if (_selectedPreviewUserKey.startsWith('recipient:')) {
      final recId = _selectedPreviewUserKey.substring('recipient:'.length);
      final week = _activeWeekDashboard;
      final list =
          week != null ? (_circulationCache[week.weekId] ?? []) : <CirculationRecipient>[];
      for (final r in list) {
        if (r.id == recId) {
          return RecipientFeedContext(
            userId: r.id,
            displayName: r.displayName,
            city: r.city.isNotEmpty ? r.city : 'Austin',
            state: r.state.isNotEmpty ? r.state : 'TX',
            playsTerminalGame: r.hasProfile,
            followedCreatorIds: {'u_0', 'u_2', 'u_3'},
            likedHashtags: {'zine', 'local', 'scifi'},
          );
        }
      }
    }

    if (_selectedPreviewUserKey.startsWith('profile:')) {
      final uid = _selectedPreviewUserKey.substring('profile:'.length);
      for (final p in _allProfiles) {
        final pId = (p['uid'] ?? p['id'] ?? '').toString();
        if (pId == uid) {
          final city = (p['city'] ?? '').toString().trim();
          final state = (p['state'] ?? '').toString().trim();
          return RecipientFeedContext(
            userId: pId,
            displayName:
                (p['displayName'] ?? p['username'] ?? 'User').toString(),
            city: city.isNotEmpty ? city : 'Austin',
            state: state.isNotEmpty ? state : 'TX',
            playsTerminalGame: true,
            followedCreatorIds: {'u_1', 'u_3', 'u_4'},
            likedHashtags: {'scifi', 'zine', 'art'},
          );
        }
      }
    }

    // Default: Active Combat Terminal Player
    return const RecipientFeedContext(
      userId: 'persona_terminal',
      displayName: 'Cmdr. Vance (Terminal Player)',
      city: 'Austin',
      state: 'TX',
      playsTerminalGame: true,
      followedCreatorIds: {'u_0', 'u_1', 'u_4'},
      likedHashtags: {'scifi', 'zine', 'terminal'},
    );
  }

  /// Runs [FanzineBlueprintEngine] for [blueprint] and loads the resulting
  /// 24 hypothetical [FanzinePage] items directly into Columns 1 & 2 of `/publisher`.
  void _syncBlueprintPreviewToWorkspace(
    ScheduledFanzine blueprint, {
    int slotIndex = 1,
    PublishingWeek? weekOverride,
  }) {
    final week = weekOverride ?? _activeWeekDashboard;
    final currentUid = getCurrentUserId() ?? 'system';
    final recipient = _resolveActiveRecipientContext();

    final ensuredBlueprint = blueprint.slotRules.isNotEmpty
        ? blueprint
        : blueprint.copyWith(
            slotRules: defaultBlueprintRulesForSlot(slotIndex),
          );

    final pages = FanzineBlueprintEngine.assembleHypotheticalPages(
      blueprint: ensuredBlueprint,
      recipient: recipient,
      slotIndex: slotIndex,
    );

    final fz = Fanzine(
      id: ensuredBlueprint.id,
      title: ensuredBlueprint.title,
      series: ensuredBlueprint.series,
      volume: ensuredBlueprint.volume,
      issue: ensuredBlueprint.issue,
      wholeNumber: ensuredBlueprint.wholeNumber,
      type: FanzineType.folio,
      isLive: false,
      processingStatus: 'ready',
      ownerId: currentUid,
      twoPage: true,
      hasCover: true,
      shortCode: ensuredBlueprint.shortCode,
      publishedDate: week?.startDateString,
    );

    UnsavedFanzineRegistry.add(fz, pages);
    UnsavedFanzineRegistry.setActivePublisherFanzine(ensuredBlueprint.id);
  }

  void _selectBlueprint(ScheduledFanzine fanzine, int slotIndex) {
    setState(() {
      _activeBlueprintId = fanzine.id;
    });
    _syncBlueprintPreviewToWorkspace(fanzine, slotIndex: slotIndex);
  }

  void _onPreviewUserChanged(String previewUserKey) {
    setState(() {
      _selectedPreviewUserKey = previewUserKey;
    });
    final week = _activeWeekDashboard;
    if (week == null) return;
    final list = _weeklyFanzinesCache[week.weekId] ?? [];
    for (int i = 0; i < list.length; i++) {
      if (list[i].id == _activeBlueprintId && !list[i].isCanceled) {
        _syncBlueprintPreviewToWorkspace(list[i], slotIndex: i + 1);
        return;
      }
    }
    final firstActiveIdx = list.indexWhere((f) => !f.isCanceled);
    if (firstActiveIdx != -1) {
      setState(() => _activeBlueprintId = list[firstActiveIdx].id);
      _syncBlueprintPreviewToWorkspace(
        list[firstActiveIdx],
        slotIndex: firstActiveIdx + 1,
      );
    }
  }

  Future<void> _updateBlueprintRule(
    ScheduledFanzine fanzine,
    int ruleIndex,
    BlueprintSlotRule updatedRule,
  ) async {
    final week = _activeWeekDashboard;
    if (week == null) return;
    final weekId = week.weekId;
    final currentList =
        List<ScheduledFanzine>.from(_weeklyFanzinesCache[weekId] ?? []);
    final idx = currentList.indexWhere((f) => f.id == fanzine.id);
    if (idx == -1) return;

    final currentRules = currentList[idx].slotRules.isNotEmpty
        ? List<BlueprintSlotRule>.from(currentList[idx].slotRules)
        : List<BlueprintSlotRule>.from(defaultBlueprintRulesForSlot(idx + 1));

    if (ruleIndex >= 0 && ruleIndex < currentRules.length) {
      currentRules[ruleIndex] = updatedRule;
    }

    final updatedFanzine = currentList[idx].copyWith(slotRules: currentRules);
    currentList[idx] = updatedFanzine;

    setState(() {
      _activeBlueprintId = updatedFanzine.id;
    });
    _syncBlueprintPreviewToWorkspace(updatedFanzine, slotIndex: idx + 1);
    await _persistWeeklyFanzines(weekId, currentList);
  }

  Future<void> _resetBlueprintRules(
    ScheduledFanzine fanzine,
    int slotIndex,
  ) async {
    final week = _activeWeekDashboard;
    if (week == null) return;
    final weekId = week.weekId;
    final currentList =
        List<ScheduledFanzine>.from(_weeklyFanzinesCache[weekId] ?? []);
    final idx = currentList.indexWhere((f) => f.id == fanzine.id);
    if (idx == -1) return;

    final resetFanzine = currentList[idx].copyWith(
      slotRules: defaultBlueprintRulesForSlot(slotIndex),
    );
    currentList[idx] = resetFanzine;

    setState(() {
      _activeBlueprintId = resetFanzine.id;
    });
    _syncBlueprintPreviewToWorkspace(resetFanzine, slotIndex: slotIndex);
    await _persistWeeklyFanzines(weekId, currentList);
  }

  void _loadFanzinesForWeek(PublishingWeek week) {
    final weekId = week.weekId;

    // 1. Check local cache first
    final cachedJson = getLocalPreference('publisher_schedule_$weekId');
    if (cachedJson != null && cachedJson.isNotEmpty) {
      try {
        final List decoded = jsonDecode(cachedJson);
        final list = decoded
            .map((m) => ScheduledFanzine.fromMap(m as Map<String, dynamic>))
            .toList();
        setState(() {
          _weeklyFanzinesCache[weekId] = list;
        });
        _autoPreviewFirstActiveBlueprint(list, week);
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
          final list = <ScheduledFanzine>[];
          for (final raw in rawList.whereType<Map>()) {
            final parsed = ScheduledFanzine.fromMap(
              Map<String, dynamic>.from(raw),
            );
            list.add(parsed);
          }
          if (mounted) {
            setState(() {
              _weeklyFanzinesCache[weekId] = list;
            });
            saveLocalPreference(
              'publisher_schedule_$weekId',
              jsonEncode(list.map((f) => f.toMap()).toList()),
            );
            _autoPreviewFirstActiveBlueprint(list, week);
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

  void _autoPreviewFirstActiveBlueprint(
    List<ScheduledFanzine> list,
    PublishingWeek week,
  ) {
    if (list.isEmpty) return;
    final existingIdx = list.indexWhere(
      (f) => f.id == _activeBlueprintId && !f.isCanceled,
    );
    if (existingIdx != -1) {
      _syncBlueprintPreviewToWorkspace(
        list[existingIdx],
        slotIndex: existingIdx + 1,
        weekOverride: week,
      );
      return;
    }
    final firstActiveIdx = list.indexWhere((f) => !f.isCanceled);
    if (firstActiveIdx != -1) {
      _activeBlueprintId = list[firstActiveIdx].id;
      _syncBlueprintPreviewToWorkspace(
        list[firstActiveIdx],
        slotIndex: firstActiveIdx + 1,
        weekOverride: week,
      );
    }
  }

  /// Finds the prior week's active publications and automatically carries them forward into [week].
  Future<void> _executeAutomaticCarryover(PublishingWeek week) async {
    final currentUid = getCurrentUserId() ?? 'system';
    final currentWeekIndex =
        _weeks.indexWhere((w) => w.weekNumber == week.weekNumber);
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
            candidateList = dec
                .map((m) => ScheduledFanzine.fromMap(m as Map<String, dynamic>))
                .toList();
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
      final String fanzineId =
          'folio_${DateTime.now().millisecondsSinceEpoch}_${carriedOverList.length}';
      final String shortCode = ShortcodeGenerator.generateStandardCode();
      final int slotIndex = carriedOverList.length + 1;

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
        slotRules: prev.slotRules.isNotEmpty
            ? prev.slotRules
            : defaultBlueprintRulesForSlot(slotIndex),
      );

      carriedOverList.add(carriedFanzine);

      // Register the carried-over fanzine model in database as a 24-page blueprint folio
      _createFanzineDocumentInBackend(
        fanzine: carriedFanzine,
        startDateString: week.startDateString,
        ownerId: currentUid,
        slotIndex: slotIndex,
      );
    }

    await _persistWeeklyFanzines(currentWeekId, carriedOverList);
    _autoPreviewFirstActiveBlueprint(carriedOverList, week);
  }

  Future<void> _persistWeeklyFanzines(
    String weekId,
    List<ScheduledFanzine> list,
  ) async {
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
    required int slotIndex,
  }) async {
    try {
      // Assemble initial 24 hypothetical pages using the Blueprint Engine
      final recipient = _resolveActiveRecipientContext();
      final pages = FanzineBlueprintEngine.assembleHypotheticalPages(
        blueprint: fanzine,
        recipient: recipient,
        slotIndex: slotIndex,
      );

      // Register into memory registry first for instant zero-latency preview in /publisher
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
        'slotRules': fanzine.slotRules.map((r) => r.toMap()).toList(),
        'draftEntities': [],
        'masterCreators': [],
      };

      await fsSetDoc('fanzines/${fanzine.id}', jsonEncode(fzData), true);

      for (final p in pages) {
        await fsSetDoc(
          'fanzines/${fanzine.id}/pages/${p.id}',
          jsonEncode({
            'pageNumber': p.pageNumber,
            'status': p.status,
            'templateId': p.templateId,
            'imageUrl': p.imageUrl,
            'gridUrl': p.gridUrl,
            'listUrl': p.listUrl,
            'text': p.text,
            'textHtml': p.textHtml,
            'sidePreference': p.sidePreference,
            'spreadPosition': p.spreadPosition,
            'width': p.width,
            'height': p.height,
            'is5x8': p.is5x8 ?? true,
            'createdAt': WebFieldValue.serverTimestamp(),
          }),
          true,
        );
      }

      await fsSetDoc(
        'shortcodes/${fanzine.shortCode.toUpperCase()}',
        jsonEncode({
          'type': 'fanzine',
          'contentId': fanzine.id,
          'displayCode': fanzine.shortCode,
          'createdAt': WebFieldValue.serverTimestamp(),
        }),
        true,
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
      setState(() => _formError = 'Please enter a blueprint title.');
      return;
    }

    setState(() {
      _isCreatingFanzine = true;
      _formError = null;
    });

    final currentUid = getCurrentUserId() ?? 'system';
    final weekId = week.weekId;
    final currentList =
        List<ScheduledFanzine>.from(_weeklyFanzinesCache[weekId] ?? []);
    final int slotIndex = currentList.length + 1;

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
      slotRules: defaultBlueprintRulesForSlot(slotIndex),
    );

    await _createFanzineDocumentInBackend(
      fanzine: newFanzine,
      startDateString: week.startDateString,
      ownerId: currentUid,
      slotIndex: slotIndex,
    );

    currentList.add(newFanzine);
    await _persistWeeklyFanzines(weekId, currentList);

    setState(() {
      _showCreateFanzineModal = false;
      _activeBlueprintId = newFanzine.id;
      _formTitle = '';
      _formSeries = '';
      _formVolume = '1';
      _formIssue = '1';
      _formWholeNumber = '1';
      _isCreatingFanzine = false;
      _formError = null;
    });

    _syncBlueprintPreviewToWorkspace(newFanzine, slotIndex: slotIndex);
  }

  Future<void> _toggleFanzineCancellation(ScheduledFanzine fanzine) async {
    final week = _activeWeekDashboard;
    if (week == null) return;

    final weekId = week.weekId;
    final currentList =
        List<ScheduledFanzine>.from(_weeklyFanzinesCache[weekId] ?? []);
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
    final currentList =
        List<ScheduledFanzine>.from(_weeklyFanzinesCache[weekId] ?? [])
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
        final list = decoded
            .map((m) => CirculationRecipient.fromMap(m as Map<String, dynamic>))
            .toList();
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
              .map(
                (m) => CirculationRecipient.fromMap(
                  Map<String, dynamic>.from(m),
                ),
              )
              .toList();
          if (mounted) {
            setState(() {
              _circulationCache[weekId] = list;
            });
            saveLocalPreference(
              'circulation_$weekId',
              jsonEncode(list.map((r) => r.toMap()).toList()),
            );
          }
        }
      } catch (e) {
        print('[PublisherColumnPanel] Error listening to circulation doc: $e');
      }
    });
  }

  Future<void> _persistCirculation(
    String weekId,
    List<CirculationRecipient> list,
  ) async {
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
      print(
        '[PublisherColumnPanel] Error persisting circulation to Firestore: $e',
      );
    }
  }

  Future<void> _addUserProfileToCirculation(
    Map<String, dynamic> profile,
  ) async {
    final week = _activeCirculationWeek ?? _activeWeekDashboard;
    if (week == null) return;

    final weekId = week.weekId;
    final currentList =
        List<CirculationRecipient>.from(_circulationCache[weekId] ?? []);
    final String uid = profile['uid'] ?? profile['id'] ?? '';

    if (currentList.any((r) => r.id == uid)) {
      setState(() {
        _searchDropdownOpen = false;
        _userSearchQuery = '';
      });
      return;
    }

    final String displayName =
        (profile['displayName'] ?? profile['username'] ?? 'User').toString();
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
          if (s1.isEmpty && uData['street1'] != null) {
            s1 = uData['street1'].toString();
          }
          if (s2.isEmpty && uData['street2'] != null) {
            s2 = uData['street2'].toString();
          }
          if (city.isEmpty && uData['city'] != null) {
            city = uData['city'].toString();
          }
          if (state.isEmpty && uData['state'] != null) {
            state = uData['state'].toString();
          }
          if (zip.isEmpty && uData['zipCode'] != null) {
            zip = uData['zipCode'].toString();
          }
          if (country.isEmpty && uData['country'] != null) {
            country = uData['country'].toString();
          }
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
    final currentList =
        List<CirculationRecipient>.from(_circulationCache[weekId] ?? []);
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
    final currentList =
        List<CirculationRecipient>.from(_circulationCache[weekId] ?? [])
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
    final currentList =
        List<CirculationRecipient>.from(_circulationCache[weekId] ?? []);
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
      final week = _activeCirculationWeek!;
      return PublisherCirculationView(
        week: week,
        hasActiveWeekDashboard: _activeWeekDashboard != null,
        recipients: _circulationCache[week.weekId] ?? [],
        allProfiles: _allProfiles,
        userSearchQuery: _userSearchQuery,
        searchDropdownOpen: _searchDropdownOpen,
        showAddManualForm: _showAddManualForm,
        manualDisplayName: _manualDisplayName,
        manualStreet1: _manualStreet1,
        manualStreet2: _manualStreet2,
        manualCity: _manualCity,
        manualState: _manualState,
        manualZip: _manualZip,
        manualCountry: _manualCountry,
        manualNotes: _manualNotes,
        manualFormError: _manualFormError,
        editingRecipient: _editingRecipient,
        editStreet1: _editStreet1,
        editStreet2: _editStreet2,
        editCity: _editCity,
        editState: _editState,
        editZip: _editZip,
        editCountry: _editCountry,
        editNotes: _editNotes,
        onCloseCirculation: _closeCirculation,
        onToggleManualForm: () {
          setState(() {
            _showAddManualForm = !_showAddManualForm;
            _searchDropdownOpen = false;
            _manualFormError = null;
          });
        },
        onSearchQueryChanged: (val, open) {
          setState(() {
            _userSearchQuery = val;
            _searchDropdownOpen = open;
          });
        },
        onSearchDropdownVisibilityChanged: (open) {
          setState(() => _searchDropdownOpen = open);
        },
        onAddUserProfileToCirculation: _addUserProfileToCirculation,
        onManualDisplayNameChanged: (v) =>
            setState(() => _manualDisplayName = v),
        onManualStreet1Changed: (v) => setState(() => _manualStreet1 = v),
        onManualStreet2Changed: (v) => setState(() => _manualStreet2 = v),
        onManualCityChanged: (v) => setState(() => _manualCity = v),
        onManualStateChanged: (v) => setState(() => _manualState = v),
        onManualZipChanged: (v) => setState(() => _manualZip = v),
        onManualCountryChanged: (v) => setState(() => _manualCountry = v),
        onManualNotesChanged: (v) => setState(() => _manualNotes = v),
        onSubmitManualRecipient: _submitManualRecipient,
        onOpenEditAddress: _openEditAddress,
        onCloseEditAddress: () => setState(() => _editingRecipient = null),
        onEditStreet1Changed: (v) => setState(() => _editStreet1 = v),
        onEditStreet2Changed: (v) => setState(() => _editStreet2 = v),
        onEditCityChanged: (v) => setState(() => _editCity = v),
        onEditStateChanged: (v) => setState(() => _editState = v),
        onEditZipChanged: (v) => setState(() => _editZip = v),
        onEditCountryChanged: (v) => setState(() => _editCountry = v),
        onEditNotesChanged: (v) => setState(() => _editNotes = v),
        onSaveEditedAddress: _saveEditedAddress,
        onRemoveRecipient: _removeRecipient,
      );
    }

    if (_activeWeekDashboard != null) {
      final week = _activeWeekDashboard!;
      final scheduledFanzines = _weeklyFanzinesCache[week.weekId] ?? [];
      return PublisherWeekDashboard(
        week: week,
        scheduledFanzines: scheduledFanzines,
        recipients: _circulationCache[week.weekId] ?? [],
        allProfiles: _allProfiles,
        seriesOptionsMap: _seriesOptionsMap,
        activeBlueprintId: _activeBlueprintId,
        selectedPreviewUserKey: _selectedPreviewUserKey,
        activeCategoryFilter: _activeCategoryFilter,
        showCreateFanzineModal: _showCreateFanzineModal,
        formTitle: _formTitle,
        formSeries: _formSeries,
        formVolume: _formVolume,
        formIssue: _formIssue,
        formWholeNumber: _formWholeNumber,
        isCreatingFanzine: _isCreatingFanzine,
        formError: _formError,
        onCloseWeekDashboard: _closeWeekDashboard,
        onOpenCirculation: _openCirculation,
        onToggleCategoryFilter: _toggleCategoryFilter,
        onClearCategoryFilter: () =>
            setState(() => _activeCategoryFilter = null),
        onSelectBlueprint: _selectBlueprint,
        onPreviewUserChanged: _onPreviewUserChanged,
        onUpdateBlueprintRule: _updateBlueprintRule,
        onResetBlueprintRules: _resetBlueprintRules,
        onOpenCreateFanzineModal: () {
          setState(() {
            _showCreateFanzineModal = true;
            _formTitle = '';
            _formSeries = '';
            _formVolume = '1';
            _formIssue = '${scheduledFanzines.length + 1}';
            _formWholeNumber = '${scheduledFanzines.length + 1}';
            _formError = null;
          });
        },
        onCloseCreateFanzineModal: () =>
            setState(() => _showCreateFanzineModal = false),
        onFormTitleChanged: (v) => setState(() => _formTitle = v),
        onFormSeriesChanged: (v) => setState(() => _formSeries = v),
        onFormVolumeChanged: (v) => setState(() => _formVolume = v),
        onFormIssueChanged: (v) => setState(() => _formIssue = v),
        onFormWholeNumberChanged: (v) => setState(() => _formWholeNumber = v),
        onSubmitNewFanzineForm: _submitNewFanzineForm,
        onToggleFanzineCancellation: _toggleFanzineCancellation,
        onDeleteScheduledFanzine: _deleteScheduledFanzine,
      );
    }

    return PublisherScheduleView(
      selectedYear: _selectedYear,
      selectedWeekNumber: _selectedWeekNumber,
      weeks: _weeks,
      circulationCache: _circulationCache,
      onOpenWeekDashboard: _openWeekDashboard,
      onOpenCirculation: _openCirculation,
    );
  }
}

/// Backward-compatible alias for the publisher panel
typedef PublisherPanel = PublisherColumnPanel;
