import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/firebase_mocks.dart';
import '../../utils/web_utils.dart';
import '../../utils/web_shortcode_service.dart';
import '../../utils/unsaved_fanzine_registry.dart';
import '../../repositories/repositories.dart';
import '../editor/modals/confirm_modal.dart';
import 'curator_upload_helper.dart';
import 'curator_entities_directory.dart';

/// Local utility to normalize handles inside the curator scope consistently with settings and database.
String normalizeHandle(String input) {
  return input
      .trim()
      .toLowerCase()
      .replaceAll(' ', '-')
      .replaceAll(RegExp(r'[^a-z0-9_-]'), '');
}

/// Helper to formatted date dynamically based on precision mode and estimated guess toggle.
String formatDisplayDate(String? dateStr, String? mode, bool isGuess) {
  if (dateStr == null || dateStr.trim().isEmpty) return '';
  try {
    final parts = dateStr.split('-');
    if (parts.isEmpty) return '';
    final year = parts[0];
    final monthInt = parts.length > 1 ? int.tryParse(parts[1]) : null;
    final dayInt = parts.length > 2 ? int.tryParse(parts[2]) : null;

    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    String result = '';
    if (mode == 'day') {
      if (monthInt != null && monthInt >= 1 && monthInt <= 12) {
        final monthName = months[monthInt - 1];
        final day = dayInt != null ? '$dayInt, ' : '';
        result = '$monthName $day$year';
      } else {
        result = dateStr;
      }
    } else if (mode == 'month') {
      if (monthInt != null && monthInt >= 1 && monthInt <= 12) {
        final monthName = months[monthInt - 1];
        result = '$monthName, $year';
      } else {
        result = year;
      }
    } else {
      result = year;
    }

    if (isGuess) {
      result += '?';
    }
    return result;
  } catch (_) {
    return dateStr + (isGuess ? '?' : '');
  }
}

/// Curator Tab containing review lists, queue allocations, and baseline parameters.
class ProfileCuratorTab extends StatefulComponent {
  final String targetUserId;
  final IUserRepository userRepository;
  final String? initialSubTab;
  final ValueChanged<String>? onSubTabChanged;

  const ProfileCuratorTab({
    required this.targetUserId,
    required this.userRepository,
    this.initialSubTab,
    this.onSubTabChanged,
    super.key,
  });

  @override
  State<ProfileCuratorTab> createState() => _ProfileCuratorTabState();
}

class _ProfileCuratorTabState extends State<ProfileCuratorTab> {
  // 0: curator, 1: curator list, 2: entities, 3: ai training data
  int _activeSubTab = 0;
  bool _showCatalogModal = false;

  List<Map<String, dynamic>> _userWorks = [];
  bool _loadingWorks = true;
  StreamSubscription? _worksSub;
  FirebaseSubscription? _worksFirebaseSub;

  List<Map<String, dynamic>> _aiTrainingData = [];
  bool _loadingTraining = true;
  StreamSubscription? _trainingSub;
  FirebaseSubscription? _trainingFirebaseSub;

  // Real-time error page counting
  Map<String, int> _fanzineErrorCounts = {};
  final Map<String, FirebaseSubscription> _fanzinePagesSubscriptions = {};

  // Uploading and Processing States
  bool _isUploadingPdf = false;
  double _uploadProgress = 0.0;
  String _uploadStatusMessage = '';

  // Deletion and Dialog confirmation modal states
  String? _pendingDeleteId;
  String? _pendingDeleteTitle;

  @override
  void initState() {
    super.initState();
    _resolveActiveSubTab();

    // SERVER PRE-RENDERING GUARD: Defer listener setup to client only
    if (kIsWeb) {
      Future.microtask(() {
        if (mounted) {
          _listenToWorks();
          _listenToTrainingData();
        }
      });
    }
  }

  void _resolveActiveSubTab() {
    if (component.initialSubTab != null) {
      switch (component.initialSubTab) {
        case 'curator':
        case 'queue':
          _activeSubTab = 0;
          break;
        case 'curator_list':
        case 'curator-list':
        case 'list':
          _activeSubTab = 1;
          break;
        case 'entities':
          _activeSubTab = 2;
          break;
        case 'ai_training_data':
        case 'ai-training-data':
        case 'training':
          _activeSubTab = 3;
          break;
        default:
          _activeSubTab = 0;
      }
    }
  }

  String _getSubTabName(int index) {
    switch (index) {
      case 0:
        return 'curator';
      case 1:
        return 'curator_list';
      case 2:
        return 'entities';
      case 3:
      default:
        return 'ai_training_data';
    }
  }

  void _selectSubTab(int index) {
    setState(() => _activeSubTab = index);
    if (component.onSubTabChanged != null) {
      component.onSubTabChanged!(_getSubTabName(index));
    }
  }

  @override
  void didUpdateComponent(ProfileCuratorTab oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.initialSubTab != component.initialSubTab) {
      _resolveActiveSubTab();
    }
    if (oldComponent.targetUserId != component.targetUserId && kIsWeb) {
      _listenToWorks();
    }
  }

  @override
  void dispose() {
    _worksSub?.cancel();
    _worksFirebaseSub?.callAsFunction();
    _trainingSub?.cancel();
    _trainingFirebaseSub?.callAsFunction();
    for (var unsub in _fanzinePagesSubscriptions.values) {
      unsub.callAsFunction();
    }
    super.dispose();
  }

  /// Streams ALL fanzines globally to match the Flutter curator dataset
  void _listenToWorks() {
    _worksSub?.cancel();
    _worksFirebaseSub?.callAsFunction();
    _worksFirebaseSub = null;

    setState(() => _loadingWorks = true);

    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();

    _worksFirebaseSub = fsListenQuery('fanzines', '', '', '', '', false, (String jsonStr) {
      scheduleMicrotask(() {
        try {
          final List decoded = jsonDecode(jsonStr);
          final list = decoded.map((d) {
            final rawData = d['data'];
            final Map<String, dynamic> data = rawData is Map ? Map<String, dynamic>.from(rawData) : {};
            data['id'] = d['id'];
            return data;
          }).toList();

          list.sort((a, b) {
            final aT = a['creationDate'] ?? a['createdAt'] ?? '';
            final bT = b['creationDate'] ?? b['createdAt'] ?? '';
            return bT.toString().compareTo(aT.toString());
          });

          if (!controller.isClosed) {
            controller.add(list);
          }
        } catch (e) {
          print("Error streaming global fanzines: $e");
        }
      });
    });

    _worksSub = controller.stream.listen((works) {
      if (mounted) {
        setState(() {
          _userWorks = works;
          _loadingWorks = false;
        });
        _syncPageErrorObservers(works);
      }
    });
  }

  void _syncPageErrorObservers(List<Map<String, dynamic>> works) {
    final activeIds = works.map((w) => w['id'] as String?).where((id) => id != null).cast<String>().toSet();

    final keysToRemove = _fanzinePagesSubscriptions.keys.where((k) => !activeIds.contains(k)).toList();
    for (var key in keysToRemove) {
      _fanzinePagesSubscriptions[key]?.callAsFunction();
      _fanzinePagesSubscriptions.remove(key);
      _fanzineErrorCounts.remove(key);
    }

    for (var fid in activeIds) {
      if (!_fanzinePagesSubscriptions.containsKey(fid)) {
        _fanzinePagesSubscriptions[fid] = fsListenQuery('fanzines/$fid/pages', '', '', '', '', false, (jsonStr) {
          scheduleMicrotask(() {
            try {
              final List decoded = jsonDecode(jsonStr);
              int errors = 0;
              for (var d in decoded) {
                final rawData = d['data'];
                final Map<String, dynamic> data = rawData is Map ? Map<String, dynamic>.from(rawData) : {};
                if (data['status'] == 'error') {
                  errors++;
                }
              }
              if (mounted) {
                setState(() {
                  _fanzineErrorCounts[fid] = errors;
                });
              }
            } catch (e) {
              print("Error counting page errors: $e");
            }
          });
        });
      }
    }
  }

  void _listenToTrainingData() {
    _trainingSub?.cancel();
    _trainingFirebaseSub?.callAsFunction();
    _trainingFirebaseSub = null;

    setState(() => _loadingTraining = true);

    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();

    _trainingFirebaseSub = fsListenQuery('images', 'isTrainingData', '==', 'true', '', false, (String jsonStr) {
      scheduleMicrotask(() {
        try {
          final List decoded = jsonDecode(jsonStr);
          final list = decoded.map((d) {
            final rawData = d['data'];
            final Map<String, dynamic> data = rawData is Map ? Map<String, dynamic>.from(rawData) : {};
            data['id'] = d['id'];
            return data;
          }).toList();

          if (!controller.isClosed) {
            controller.add(list);
          }
        } catch (e) {
          print("Error streaming AI training images: $e");
        }
      });
    });

    _trainingSub = controller.stream.listen((list) {
      if (mounted) {
        setState(() {
          _aiTrainingData = list;
          _loadingTraining = false;
        });
      }
    });
  }

  void _triggerPdfUpload() {
    if (!kIsWeb) return;
    CuratorUploadHelper.pickAndUploadPdf(
      onStatus: (message) {
        if (mounted) {
          setState(() {
            _isUploadingPdf = true;
            _uploadStatusMessage = message;
          });
        }
      },
      onUpload: (bytes, fileName) async {
        if (mounted) {
          setState(() {
            _uploadStatusMessage = 'Uploading "$fileName" to storage...';
          });
        }
        try {
          final String path = 'uploads/raw_pdfs/$fileName';
          await stUpload(path, bytes, 'image/jpeg');

          if (mounted) {
            setState(() {
              _uploadStatusMessage = 'PDF Upload complete! Processing backend ingest pipeline...';
            });
            Future.delayed(const Duration(seconds: 4), () {
              if (mounted) {
                setState(() {
                  _isUploadingPdf = false;
                  _uploadStatusMessage = '';
                });
              }
            });
          }
        } catch (err) {
          _handleUploadError(err.toString());
        }
      },
      onError: (errorMessage) {
        _handleUploadError(errorMessage);
      },
    );
  }

  void _handleUploadError(String err) {
    print("Error picking/uploading PDF: $err");
    if (mounted) {
      setState(() {
        _isUploadingPdf = false;
        _uploadStatusMessage = 'Upload failed: $err';
      });
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() {
            _isUploadingPdf = false;
            _uploadStatusMessage = '';
          });
        }
      });
    }
  }

  Future _createArchivalFanzine(String userId) async {
    final uid = getCurrentUserId() ?? 'system';
    setState(() => _loadingWorks = true);
    try {
      final fanzineId = 'ingested_${DateTime.now().millisecondsSinceEpoch}';
      final String? email = createAuthRepository().currentUser?.email;
      final bool useVanity = email != null && email.trim().toLowerCase() == 'kevin@712liberty.com';

      final shortCode = await WebShortcodeService.assignShortcode(
        contentType: 'fanzine',
        contentId: fanzineId,
        isVanity: useVanity,
      ) ?? ShortcodeGenerator.generateStandardCode();

      final data = {
        'title': 'New Archival Ingest',
        'ownerId': uid,
        'editorId': uid,
        'editors': [],
        'isLive': false,
        'inCurator': true,
        'processingStatus': 'images_ready',
        'creationDate': WebFieldValue.serverTimestamp(),
        'type': 'ingested',
        'shortCode': shortCode,
        'shortCodeKey': shortCode.toUpperCase(),
        'twoPage': true,
        'hasCover': true,
        'draftEntities': [],
        'masterCreators': [],
      };

      await fsSetDoc('fanzines/$fanzineId', jsonEncode(data), true);
      if (mounted) {
        setState(() => _loadingWorks = false);
        Router.of(context).push('/$shortCode');
      }
    } catch (e) {
      print("Error creating archival zine: $e");
      if (mounted) setState(() => _loadingWorks = false);
    }
  }

  void _showToast(String message, {bool isError = false}) {
    print("[CURATOR DASHBOARD] $message");
    setState(() {
      _uploadStatusMessage = message;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _uploadStatusMessage = '';
        });
      }
    });
  }

  Future _deleteFanzine() async {
    final fid = _pendingDeleteId;
    if (fid == null) return;
    setState(() {
      _pendingDeleteId = null;
      _pendingDeleteTitle = null;
      _loadingWorks = true;
    });
    try {
      final docRes = await fsGetDoc('fanzines/$fid');
      final doc = jsonDecode(docRes);
      if (doc['exists'] == true) {
        final String? shortCode = doc['data']['shortCode'];
        if (shortCode != null && shortCode.isNotEmpty) {
          await fsDeleteDoc('shortcodes/${shortCode.toUpperCase()}');
        }
      }
      await fsDeleteDoc('fanzines/$fid');
      _showToast("Fanzine deleted successfully.");
    } catch (e) {
      _showToast("Failed deleting fanzine: $e", isError: true);
    } finally {
      if (mounted) setState(() => _loadingWorks = false);
    }
  }

  Future _toggleInCurator(String fanzineId, bool currentVal) async {
    if (fanzineId.isEmpty) return;
    final bool newVal = !currentVal;
    try {
      await fsSetDoc('fanzines/$fanzineId', jsonEncode({'inCurator': newVal}), true);
    } catch (e) {
      _showToast("Error updating curator state: $e", isError: true);
    }
  }

  bool _isCuratedByUser(Map<String, dynamic> w) {
    final owner = w['ownerId'] ?? w['editorId'] ?? w['uploaderId'] ?? '';
    final List editors = w['editors'] ?? [];
    if (owner == '' && editors.isEmpty) {
      return true;
    }
    return owner == component.targetUserId ||
        editors.contains(component.targetUserId) ||
        w['editorId'] == component.targetUserId ||
        w['uploaderId'] == component.targetUserId ||
        owner == 'system';
  }

  bool _isCuratedFanzine(Map<String, dynamic> w) {
    return w['sourceFile'] != null || w['type'] == 'ingested';
  }

  int _comparePublishedDates(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aDate = a['publishedDate']?.toString() ?? '';
    final bDate = b['publishedDate']?.toString() ?? '';
    if (aDate.isEmpty && bDate.isEmpty) {
      final aT = a['creationDate'] ?? a['createdAt'] ?? '';
      final bT = b['creationDate'] ?? b['createdAt'] ?? '';
      return bT.toString().compareTo(aT.toString());
    }
    if (aDate.isEmpty) return 1;
    if (bDate.isEmpty) return -1;
    return bDate.compareTo(aDate);
  }

  Component _buildActiveSubTabContent() {
    switch (_activeSubTab) {
      case 0:
        final list = _userWorks.where((w) {
          return _isCuratedFanzine(w) && _isCuratedByUser(w) && (w['inCurator'] ?? true) == true;
        }).toList();
        list.sort((a, b) => _comparePublishedDates(a, b));
        return _buildWorksGridSchema(list);
      case 1:
        final list = _userWorks.where((w) {
          return _isCuratedFanzine(w) && _isCuratedByUser(w);
        }).toList();
        list.sort((a, b) => _comparePublishedDates(a, b));
        return _buildCuratorListSubView(list);
      case 2:
        final filteredWorks = _userWorks.where((w) {
          return _isCuratedFanzine(w) && _isCuratedByUser(w) && (w['inCurator'] ?? true) == true;
        }).toList();
        return CuratorEntitiesDirectory(userWorks: filteredWorks, isLoading: _loadingWorks);
      case 3:
      default:
        return _buildAITrainingDataPortal();
    }
  }

  Component _buildCuratorListSubView(List<Map<String, dynamic>> works) {
    if (_loadingWorks) {
      return div(
        [p([text('Loading curated list...')])],
        classes: 'p-16 text-center text-gray italic text-sm',
      );
    }

    if (works.isEmpty) {
      return div(
        [
          span([text('library_books')], classes: 'material-symbols-outlined text-gray-300', attributes: const {'style': 'font-size: 48px;'}),
          p([text('No curated fanzines found for this profile.')], classes: 'text-sm text-gray italic mt-4', attributes: const {'style': 'margin-top: 16px;'})
        ],
        classes: 'bg-white rounded-lg p-16 shadow-sm text-center border border-gray-100 flex flex-col items-center justify-center w-full mt-4',
      );
    }

    return div(
      classes: 'bg-white rounded-lg p-6 shadow-sm border border-gray-200 w-full mt-4',
      [
        div(
          attributes: const {'style': 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; border-bottom: 1px solid #f0f0f0; padding-bottom: 12px;'},
          [
            div([
              h2([text("CURATED FANZINES")], attributes: const {'style': 'margin: 0; font-size: 15px; font-weight: bold; letter-spacing: 0.5px;'}),
              span([text("A complete historical log of all ingested fanzines curated by this profile.")], attributes: const {'style': 'font-size: 11px; color: #666;'})
            ]),
          ],
        ),
        table(
          classes: 'stats-table text-left w-full',
          [
            thead([
              tr([
                th([text('Fanzine Title')]),
                th([text('Visibility')]),
                th([text('Pipeline Status')]),
                th([text('In Curator')], attributes: const {'style': 'text-align: center; width: 110px;'}),
              ])
            ]),
            tbody([
              for (var w in works)
                _buildCuratorListRow(w)
            ])
          ],
        ),
      ],
    );
  }

  Component _buildCuratorListRow(Map<String, dynamic> w) {
    final String title = w['title'] ?? 'Untitled';
    final bool isLive = w['isLive'] == true;
    final String processingStatus = w['processingStatus'] ?? 'idle';
    final String fanzineId = w['id'] ?? '';
    final bool inCurator = w['inCurator'] ?? true;

    return tr([
      td([
        div(
            attributes: const {'style': 'display: flex; flex-direction: column; gap: 2px;'},
            [
              span([text(title)], attributes: const {'style': 'font-weight: bold; font-size: 13.5px; color: black;'}),
              if (fanzineId.isNotEmpty)
                span([text('ID: $fanzineId')], attributes: const {'style': 'font-size: 9px; color: #888; font-family: monospace;'})
            ]
        )
      ]),
      td([
        span(
            [text(isLive ? 'visible' : 'hidden')],
            attributes: {
              'style': 'font-size: 11px; font-weight: bold; text-transform: uppercase; color: ${isLive ? "#16a34a" : "#ca8a04"};'
            }
        )
      ]),
      td([
        span(
            [text(processingStatus)],
            attributes: const {'style': 'font-size: 11px; font-weight: 500; font-family: monospace; color: #4b5563;'}
        )
      ]),
      td(
        [
          label(
              attributes: const {
                'style': 'position: relative; display: inline-block; width: 44px; height: 24px; vertical-align: middle;'
              },
              [
                input(
                    type: InputType.checkbox,
                    attributes: {
                      'style': 'opacity: 0; width: 0; height: 0;',
                      if (inCurator) 'checked': 'true',
                    },
                    events: {
                      'change': (dynamic e) {
                        _toggleInCurator(fanzineId, inCurator);
                      }
                    }
                ),
                span(
                    attributes: {
                      'style': 'position: absolute; cursor: pointer; top: 0; left: 0; right: 0; bottom: 0; background-color: ${inCurator ? "#16a34a" : "#ccc"}; transition: .3s; border-radius: 24px;'
                    },
                    [
                      span(
                          [],
                          attributes: {
                            'style': 'position: absolute; content: ""; height: 16px; width: 16px; left: 4px; bottom: 4px; background-color: white; transition: .3s; border-radius: 50%; transform: ${inCurator ? "translateX(20px)" : "translateX(0px)"};'
                          }
                      )
                    ]
                )
              ]
          )
        ],
        attributes: const {'style': 'text-align: center; vertical-align: middle;'},
      )
    ]);
  }

  Component _buildWorksGridSchema(List<Map<String, dynamic>> works) {
    if (_loadingWorks) {
      return div(
        [p([text('Loading queue...')])],
        classes: 'p-16 text-center text-gray italic text-sm',
      );
    }

    if (works.isEmpty) {
      return div(
        [
          span([text('library_books')], classes: 'material-symbols-outlined text-gray-300', attributes: const {'style': 'font-size: 48px;'}),
          p([text('No items in queue.')], classes: 'text-sm text-gray italic mt-4', attributes: const {'style': 'margin-top: 16px;'})
        ],
        classes: 'bg-white rounded-lg p-16 shadow-sm text-center',
      );
    }

    return div(
        attributes: const {
          'style': 'display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 16px; width: 100%; box-sizing: border-box;'
        },
        [
          for (var w in works)
            CuratorWorkGridTile(
              fanzineData: w,
              key: ValueKey(w['id'] ?? ''),
              onDelete: (id, title) {
                setState(() {
                  _pendingDeleteId = id;
                  _pendingDeleteTitle = title;
                });
              },
            )
        ]
    );
  }

  Component _buildAITrainingDataPortal() {
    if (_loadingTraining) {
      return div(
        [p([text('Loading AI training logs...')])],
        classes: 'p-16 text-center text-gray italic text-sm',
      );
    }

    if (_aiTrainingData.isEmpty) {
      return div(
        [
          p([text("No training data yet.")], classes: 'text-sm text-gray italic', attributes: const {'style': 'margin: 0;'})
        ],
        classes: 'bg-white rounded-lg p-16 shadow-sm text-center',
      );
    }

    return div(
        classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-4',
        attributes: const {'style': 'display: flex; flex-direction: column; gap: 16px; padding: 24px; background: white;'},
        [
          h2([text("AI REINFORCEMENT BASELINES")], classes: 'font-bold text-sm text-gray mb-2', attributes: const {'style': 'margin-top: 0; margin-bottom: 8px;'}),
          for (var item in _aiTrainingData)
            div(
                attributes: const {'style': 'display: flex; align-items: center; padding: 12px; border: 1px solid #eee; border-radius: 8px; font-size: 13px;'},
                [
                  if (item['fileUrl'] != null)
                    img(src: item['fileUrl'], attributes: const {'style': 'width: 48px; height: 48px; object-fit: cover; border-radius: 4px; border: 1px solid #ccc;'}),
                  span([], attributes: const {'style': 'display: inline-block; width: 16px;'}),
                  div(
                      attributes: const {'style': 'display: flex; flex-direction: column; gap: 4px;'},
                      [
                        span([text(item['title'] ?? 'Archival Page')], attributes: const {'style': 'font-weight: bold;'}),
                        span([
                          text("Correction Score: ${item['correctionScore'] ?? 0} | Link Score: ${item['linkingScore'] ?? 0}")
                        ], attributes: const {'style': 'font-size: 11px; color: #666;'}
                        )
                      ]
                  )
                ]
            )
        ]
    );
  }

  Component _buildCatalogOptionsContent() {
    return div(
      classes: 'white-sticker p-6 w-full h-full flex flex-col justify-center items-center',
      attributes: const {'style': 'display: flex; flex-direction: column; justify-content: center; align-items: center; padding: 24px; box-sizing: border-box; width: 100%; height: 100%;'},
      [
        h1([text('curator options')], classes: 'font-bold text-lg text-center mb-6', attributes: const {'style': 'margin-top: 0;'}),
        button(
            classes: 'profile-btn mb-4',
            attributes: const {
              'style': 'width: 100%; height: 40px; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; border: 1px solid #ddd; border-radius: 0px !important; cursor: pointer; background: white; margin-bottom: 16px; text-transform: none;'
            },
            events: {
              'click': (e) {
                setState(() => _showCatalogModal = false);
                _triggerPdfUpload();
              }
            },
            [text("upload PDF")]
        ),
        button(
            classes: 'profile-btn mb-4',
            attributes: const {
              'style': 'width: 100%; height: 40px; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; border: 1px solid #ddd; border-radius: 0px !important; cursor: pointer; background: white; margin-bottom: 16px; text-transform: none;'
            },
            events: {
              'click': (e) {
                setState(() => _showCatalogModal = false);
                _createArchivalFanzine(component.targetUserId);
              }
            },
            [text("upload images")]
        ),
      ],
    );
  }

  Component _buildCatalogModalOverlay() {
    return div(
        classes: 'global-modal-overlay',
        attributes: const {'style': 'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.65); z-index: 10000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(6px);'},
        [
          div(
              classes: 'manila-envelope',
              attributes: const {'style': 'max-width: 420px; max-height: 580px; border-radius: 12px; overflow: hidden; position: relative;'},
              [
                button(
                    classes: 'modal-close-btn',
                    attributes: const {'style': 'position: absolute; top: 12px; right: 12px; border: none; background: rgba(255,255,255,0.8); border-radius: 50%; width: 32px; height: 32px; display: flex; align-items: center; justify-content: center; cursor: pointer; font-size: 16px; font-weight: bold; z-index: 200;'},
                    events: {'click': (e) => setState(() => _showCatalogModal = false)},
                    [text('×')]
                ),
                _buildCatalogOptionsContent()
              ]
          )
        ]
    );
  }

  @override
  Component build(BuildContext context) {
    if (!kIsWeb) {
      return div(
          classes: 'p-16 text-center text-gray italic text-sm',
          [p([text('Loading curator queue...')])]
      );
    }

    return div(
      [
        // Navigation segment
        div(
          [
            // Catalog trigger button
            button(
              [text("catalog")],
              classes: 'transition-all cursor-pointer flex items-center',
              attributes: {
                'style': 'height: 32px; display: inline-flex; align-items: center; justify-content: center; padding: 0 16px; border: 1px solid #ccc; background: ${_showCatalogModal ? "black" : "transparent"}; color: ${_showCatalogModal ? "white" : "black"}; font-size: 13px; text-transform: lowercase; font-family: inherit; cursor: pointer; border-radius: 0; font-weight: normal;'
              },
              events: {
                'click': (e) => setState(() => _showCatalogModal = true)
              },
            ),
            span([text('|')], classes: 'text-xs text-gray-300', attributes: const {'style': 'display: inline-block; margin: 0 12px;'}),

            // 'curator' text subtab
            span(
              [text("curator")],
              classes: _activeSubTab == 0
                  ? 'text-xs font-bold text-black border-b-2 border-black cursor-pointer pb-1'
                  : 'text-xs text-gray-500 hover:text-black cursor-pointer transition-colors',
              events: {
                'click': (e) => _selectSubTab(0)
              },
            ),
            span([text('|')], classes: 'text-xs text-gray-300', attributes: const {'style': 'display: inline-block; margin: 0 12px;'}),

            // 'curator list' text subtab
            span(
              [text("curator list")],
              classes: _activeSubTab == 1
                  ? 'text-xs font-bold text-black border-b-2 border-black cursor-pointer pb-1'
                  : 'text-xs text-gray-500 hover:text-black cursor-pointer transition-colors',
              events: {
                'click': (e) => _selectSubTab(1)
              },
            ),
            span([text('|')], classes: 'text-xs text-gray-300', attributes: const {'style': 'display: inline-block; margin: 0 12px;'}),

            // 'entities' text subtab
            span(
              [text("entities")],
              classes: _activeSubTab == 2
                  ? 'text-xs font-bold text-black border-b-2 border-black cursor-pointer pb-1'
                  : 'text-xs text-gray-500 hover:text-black cursor-pointer transition-colors',
              events: {
                'click': (e) => _selectSubTab(2)
              },
            ),
            span([text('|')], classes: 'text-xs text-gray-300', attributes: const {'style': 'display: inline-block; margin: 0 12px;'}),

            // 'ai training data' text subtab
            span(
              [text("ai training data")],
              classes: _activeSubTab == 3
                  ? 'text-xs font-bold text-black border-b-2 border-black cursor-pointer pb-1'
                  : 'text-xs text-gray-500 hover:text-black cursor-pointer transition-colors',
              events: {
                'click': (e) => _selectSubTab(3)
              },
            ),
          ],
          classes: 'bg-white rounded-md p-4 shadow-sm',
          attributes: const {'style': 'display: flex; flex-wrap: wrap; justify-content: center; align-items: center; gap: 4px; box-sizing: border-box; width: 100%; margin-bottom: 16px;'},
        ),

        // Prominent live upload status bar
        if (_uploadStatusMessage.isNotEmpty)
          div(
              classes: 'bg-white rounded-md p-4 shadow-sm mb-4 text-center',
              attributes: const {'style': 'margin-bottom: 16px;'},
              [
                span(
                  [text(_uploadStatusMessage)],
                  attributes: const {'style': 'font-style: italic; font-weight: bold; color: #16a34a; font-size: 13px;'},
                )
              ]
          ),

        // Sub-Tab Content Routing
        _buildActiveSubTabContent(),

        // Dynamic Modal Overlays
        if (_showCatalogModal)
          _buildCatalogModalOverlay(),

        // Delete verification dialog modal
        if (_pendingDeleteId != null)
          ConfirmModal(
            title: 'Delete Fanzine Draft?',
            message: 'Are you sure you want to delete "${_pendingDeleteTitle}" forever? This will remove all mapped layouts and metadata from the database.',
            confirmLabel: 'DELETE',
            isDestructive: true,
            onCancel: () => setState(() {
              _pendingDeleteId = null;
              _pendingDeleteTitle = null;
            }),
            onConfirm: () => _deleteFanzine(),
          )
      ],
    );
  }
}

/// Dynamic, self-resolving grid tile for showing curated fanzines.
class CuratorWorkGridTile extends StatefulComponent {
  final Map<String, dynamic> fanzineData;
  final void Function(String id, String title)? onDelete;

  const CuratorWorkGridTile({
    required this.fanzineData,
    this.onDelete,
    super.key,
  });

  @override
  State<CuratorWorkGridTile> createState() => _CuratorWorkGridTileState();
}

class _CuratorWorkGridTileState extends State<CuratorWorkGridTile> {
  String? _resolvedCoverUrl;
  int _pagesCount = 0;

  @override
  void initState() {
    super.initState();
    _resolveThumbnail();
  }

  @override
  void didUpdateComponent(CuratorWorkGridTile oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.fanzineData['id'] != component.fanzineData['id']) {
      _resolveThumbnail();
    }
  }

  Future _resolveThumbnail() async {
    final String fanzineId = component.fanzineData['id'] ?? '';
    final String? coverUrl = component.fanzineData['gridCoverImage'];
    if (coverUrl != null && coverUrl.isNotEmpty) {
      if (mounted) {
        setState(() {
          _resolvedCoverUrl = coverUrl;
        });
      }
      return;
    }

    final fallbackUrl = component.fanzineData['sourceFile'] != null
        ? 'https://placehold.co/450x720/png?text=Archival+Ingest'
        : 'https://placehold.co/450x720/png?text=Folio';

    if (!kIsWeb || fanzineId.isEmpty) {
      if (mounted) {
        setState(() {
          _resolvedCoverUrl ??= fallbackUrl;
        });
      }
      return;
    }

    try {
      final pagesRes = await fsQuery('fanzines/$fanzineId/pages', '', '', '', 'pageNumber');
      final List decodedPages = jsonDecode(pagesRes);
      if (mounted) {
        setState(() {
          _pagesCount = decodedPages.length;
        });
      }

      if (decodedPages.isNotEmpty) {
        final firstPage = decodedPages.firstWhere((p) => p['data']['pageNumber'] == 1, orElse: () => decodedPages.first);
        final rawData = firstPage['data'];
        final Map<String, dynamic> data = rawData is Map ? Map<String, dynamic>.from(rawData) : {};
        final url = data['gridUrl'] ?? data['thumbnailUrl'] ?? data['imageUrl'];
        if (url != null && url.toString().isNotEmpty) {
          if (mounted) {
            setState(() {
              _resolvedCoverUrl = url.toString();
            });
          }
          return;
        }
      }

      final imagesRes = await fsQuery('images', 'folioContext', '==', jsonEncode(fanzineId), '');
      final List decodedImages = jsonDecode(imagesRes);
      if (decodedImages.isNotEmpty) {
        decodedImages.sort((a, b) {
          final aT = a['data']?['timestamp'] ?? 0;
          final bT = b['data']?['timestamp'] ?? 0;
          return bT.toString().compareTo(aT.toString());
        });
        final firstImgRaw = decodedImages.first['data'];
        final Map<String, dynamic> firstImg = firstImgRaw is Map ? Map<String, dynamic>.from(firstImgRaw) : {};
        final url = firstImg['gridUrl'] ?? firstImg['fileUrl'];
        if (url != null && url.toString().isNotEmpty) {
          if (mounted) {
            setState(() {
              _resolvedCoverUrl = url.toString();
            });
          }
          return;
        }
      }
    } catch (e) {
      print("[CuratorWorkGridTile] Error resolving cover thumbnail: $e");
    }

    if (mounted && _resolvedCoverUrl == null) {
      setState(() {
        _resolvedCoverUrl = fallbackUrl;
      });
    }
  }

  @override
  Component build(BuildContext context) {
    final String fanzineId = component.fanzineData['id'] ?? '';
    final String title = component.fanzineData['title'] ?? 'Untitled Fanzine';
    final String coverUrl = _resolvedCoverUrl ?? 'https://placehold.co/450x720/png?text=Loading...';
    final String fanzineType = component.fanzineData['type'] ?? 'ingested';
    final String displayYear = (component.fanzineData['startYear'] ?? '').toString();
    final int resolvedPageCount = component.fanzineData['pageCount'] ?? _pagesCount;
    final String codeKey = component.fanzineData['shortCode'] ?? fanzineId;

    final String? publishedDateVal = component.fanzineData['publishedDate'];
    final String? publishedDateMode = component.fanzineData['publishedDateMode'] ?? 'year';
    final bool publishedDateGuess = component.fanzineData['publishedDateGuess'] ?? false;
    String resolvedYear = '';

    if (publishedDateVal != null && publishedDateVal.isNotEmpty) {
      resolvedYear = formatDisplayDate(publishedDateVal, publishedDateMode, publishedDateGuess);
    } else if (displayYear.isNotEmpty) {
      resolvedYear = displayYear + (publishedDateGuess ? '?' : '');
    } else if (component.fanzineData['creationDate'] != null) {
      try {
        final dateMap = component.fanzineData['creationDate'];
        if (dateMap is Map && dateMap['iso'] != null) {
          resolvedYear = DateTime.parse(dateMap['iso'].toString()).year.toString() + (publishedDateGuess ? '?' : '');
        }
      } catch (_) {}
    }

    return a(
      [
        div(
          [
            div(
                [
                  div(
                      [text("$fanzineType   $resolvedPageCount pages")],
                      attributes: const {
                        'style': 'background-color: rgba(33, 33, 33, 0.85); color: white; font-size: 10px; font-weight: bold; padding: 4px 8px; border-radius: 2px; text-align: center; text-transform: lowercase;'
                      }
                  ),
                  if (resolvedYear.isNotEmpty)
                    div(
                        [text(resolvedYear)],
                        attributes: const {
                          'style': 'background-color: rgba(0, 0, 0, 0.7); color: white; font-size: 10px; font-weight: bold; padding: 4px 8px; border-radius: 2px; text-align: center;'
                        }
                    )
                ],
                attributes: const {
                  'style': 'position: absolute; top: 12px; left: 12px; right: 44px; display: flex; flex-direction: column; gap: 4px; pointer-events: none;'
                }
            ),
            if (component.onDelete != null)
              button(
                [
                  span([text('delete')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px;'})
                ],
                attributes: const {
                  'style': 'position: absolute; top: 12px; right: 12px; border: none; background: rgba(0, 0, 0, 0.7); border-radius: 50%; width: 24px; height: 24px; display: flex; align-items: center; justify-content: center; cursor: pointer; color: #ff5252; border: 1px solid rgba(255, 255, 255, 0.4); z-index: 10; pointer-events: auto;'
                },
                events: {
                  'click': (dynamic e) {
                    try {
                      e.preventDefault();
                      e.stopPropagation();
                    } catch (_) {}
                    component.onDelete!(fanzineId, title);
                  }
                },
              )
          ],
          attributes: {
            'style': 'aspect-ratio: 5/8; background-color: #f3f4f6; background-image: url("$coverUrl"); background-size: cover; background-position: center; position: relative;'
          },
        ),
        div(
          [
            span([text(title)], attributes: const {'style': 'font-size: 13px; font-weight: bold; color: black; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'}),
          ],
          attributes: const {'style': 'padding: 12px; display: flex; flex-direction: column; gap: 4px;'},
        )
      ],
      classes: 'bg-white rounded-lg shadow-sm overflow-hidden transition-all',
      attributes: const {'style': 'display: flex; flex-direction: column; border: 1px solid #ddd; cursor: pointer; text-decoration: none;'},
      href: '/$codeKey',
    );
  }
}