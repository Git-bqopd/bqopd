import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart'; // Standard Jaspr Router
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/firebase_mocks.dart';
import '../../utils/web_utils.dart';
import '../../utils/web_shortcode_service.dart';
import '../../utils/unsaved_fanzine_registry.dart';
import '../../repositories/repositories.dart';
import '../editor/modals/confirm_modal.dart';
import 'curator_upload_helper.dart'; // Server-safe conditional upload utility
import 'curator_entities_directory.dart'; // Decoupled entities component

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
/// Streams live curator drafts and training images using abstract repositories.
class ProfileCuratorTab extends StatefulComponent {
  final String targetUserId;
  final IUserRepository userRepository;

  const ProfileCuratorTab({
    required this.targetUserId,
    required this.userRepository,
    super.key,
  });

  @override
  State<ProfileCuratorTab> createState() => _ProfileCuratorTabState();
}

class _ProfileCuratorTabState extends State<ProfileCuratorTab> {
  // 0: curator, 1: publisher, 2: entities, 3: ai training data
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

  @override
  void didUpdateComponent(ProfileCuratorTab oldComponent) {
    super.didUpdateComponent(oldComponent);
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

    // Query ALL fanzines without complex field orderings to prevent index exceptions
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

          // Sort list manually in memory to conform with Rule 2
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
        // Set up error page observers for draft/ingested zines
        _syncPageErrorObservers(works);
      }
    });
  }

  /// Sets up real-time observers to track how many pages are on error status for each fanzine
  void _syncPageErrorObservers(List<Map<String, dynamic>> works) {
    final activeIds = works.map((w) => w['id'] as String?).where((id) => id != null).cast<String>().toSet();

    // Cancel observers for fanzines no longer present
    final keysToRemove = _fanzinePagesSubscriptions.keys.where((k) => !activeIds.contains(k)).toList();
    for (var key in keysToRemove) {
      _fanzinePagesSubscriptions[key]?.callAsFunction();
      _fanzinePagesSubscriptions.remove(key);
      _fanzineErrorCounts.remove(key);
    }

    // Subscribe to new fanzines
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

  /// Reads selected PDF from the device, uploads to Storage, and triggers backend ingest.
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
          // Build storage path
          final String path = 'uploads/raw_pdfs/$fileName';
          // Execute GCS upload
          await stUpload(path, bytes, 'image/jpeg');
          if (mounted) {
            setState(() {
              _uploadStatusMessage = 'PDF Upload complete! Processing backend ingest pipeline...';
            });
            // Hide progress after short delay
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

  /// Generates a placeholder Ingested fanzine metadata object directly
  Future _createArchivalFanzine() async {
    final uid = getCurrentUserId() ?? 'system';
    setState(() => _loadingWorks = true);
    try {
      final fanzineId = 'ingested_${DateTime.now().millisecondsSinceEpoch}';

      // ALIGNED SHORTCODE LOGIC: Matches Maker tab shortcode selection checks & vanity triggers
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

  /// Confirms and deletes a fanzine
  Future _deleteFanzine() async {
    final fid = _pendingDeleteId;
    if (fid == null) return;
    setState(() {
      _pendingDeleteId = null;
      _pendingDeleteTitle = null;
      _loadingWorks = true;
    });
    try {
      // 1. Fetch shortcode from fanzine doc to purge
      final docRes = await fsGetDoc('fanzines/$fid');
      final doc = jsonDecode(docRes);
      if (doc['exists'] == true) {
        final String? shortCode = doc['data']['shortCode'];
        if (shortCode != null && shortCode.isNotEmpty) {
          await fsDeleteDoc('shortcodes/${shortCode.toUpperCase()}');
        }
      }
      // 2. Clear fanzine record
      await fsDeleteDoc('fanzines/$fid');
      _showToast("Fanzine deleted successfully.");
    } catch (e) {
      _showToast("Failed deleting fanzine: $e", isError: true);
    } finally {
      if (mounted) setState(() => _loadingWorks = false);
    }
  }

  /// Custom comparison logic to sort fanzines based on publishedDate (newest first).
  /// Falls back smoothly to creation/upload timestamps if publishedDate is empty.
  int _comparePublishedDates(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aDate = a['publishedDate']?.toString() ?? '';
    final bDate = b['publishedDate']?.toString() ?? '';

    if (aDate.isEmpty && bDate.isEmpty) {
      final aT = a['creationDate'] ?? a['createdAt'] ?? '';
      final bT = b['creationDate'] ?? b['createdAt'] ?? '';
      return bT.toString().compareTo(aT.toString());
    }
    if (aDate.isEmpty) return 1; // Send unpopulated dates to bottom
    if (bDate.isEmpty) return -1; // Pull populated dates to top

    return bDate.compareTo(aDate); // Alphabetical comparison works for YYYY-MM-DD descending
  }

  /// Renders the correct workspace based on the active sub-tab.
  /// Isolating this helper prevents Jaspr's diffing engine from mismatching stateful elements.
  Component _buildActiveSubTabContent() {
    switch (_activeSubTab) {
      case 0:
      // curator: shows draft PDFs (sourceFile != null && isLive != true) sorted by publishedDate
        final list = _userWorks.where((w) => w['sourceFile'] != null && w['isLive'] != true).toList();
        list.sort((a, b) => _comparePublishedDates(a, b));
        return _buildWorksGridSchema(list);
      case 1:
      // publisher: shows folios and published fanzines (sourceFile == null || isLive == true) sorted by publishedDate
        final list = _userWorks.where((w) => w['sourceFile'] == null || w['isLive'] == true).toList();
        list.sort((a, b) => _comparePublishedDates(a, b));
        return _buildWorksGridSchema(list);
      case 2:
        return CuratorEntitiesDirectory(userWorks: _userWorks, isLoading: _loadingWorks);
      case 3:
      default:
        return _buildAITrainingDataPortal();
    }
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
                _createArchivalFanzine();
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
                    [text('X')]
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
            classes: 'bg-white rounded-md p-4 shadow-sm',
            attributes: const {'style': 'display: flex; flex-wrap: wrap; justify-content: center; align-items: center; gap: 4px; box-sizing: border-box; width: 100%; margin-bottom: 16px;'},
            [
              // Catalog trigger button (Now triggers a premium options modal)
              button(
                  classes: 'transition-all cursor-pointer flex items-center',
                  attributes: {
                    'style': 'height: 32px; display: inline-flex; align-items: center; justify-content: center; padding: 0 16px; border: 1px solid #ccc; background: ${_showCatalogModal ? "black" : "transparent"}; color: ${_showCatalogModal ? "white" : "black"}; font-size: 13px; text-transform: lowercase; font-family: inherit; cursor: pointer; border-radius: 0; font-weight: normal;'
                  },
                  events: {
                    'click': (e) => setState(() => _showCatalogModal = true)
                  },
                  [text("catalog")]
              ),
              span([text('|')], classes: 'text-xs text-gray-300', attributes: const {'style': 'display: inline-block; margin: 0 12px;'}),
              // 'curator' text subtab
              span(
                  classes: _activeSubTab == 0
                      ? 'text-xs font-bold text-black border-b-2 border-black cursor-pointer pb-1'
                      : 'text-xs text-gray-500 hover:text-black cursor-pointer transition-colors',
                  events: {
                    'click': (e) => setState(() => _activeSubTab = 0)
                  },
                  [text("curator")]
              ),
              span([text('|')], classes: 'text-xs text-gray-300', attributes: const {'style': 'display: inline-block; margin: 0 12px;'}),
              // 'publisher' text subtab
              span(
                  classes: _activeSubTab == 1
                      ? 'text-xs font-bold text-black border-b-2 border-black cursor-pointer pb-1'
                      : 'text-xs text-gray-500 hover:text-black cursor-pointer transition-colors',
                  events: {
                    'click': (e) => setState(() => _activeSubTab = 1)
                  },
                  [text("publisher")]
              ),
              span([text('|')], classes: 'text-xs text-gray-300', attributes: const {'style': 'display: inline-block; margin: 0 12px;'}),
              // 'entities' text subtab
              span(
                  classes: _activeSubTab == 2
                      ? 'text-xs font-bold text-black border-b-2 border-black cursor-pointer pb-1'
                      : 'text-xs text-gray-500 hover:text-black cursor-pointer transition-colors',
                  events: {
                    'click': (e) => setState(() => _activeSubTab = 2)
                  },
                  [text("entities")]
              ),
              span([text('|')], classes: 'text-xs text-gray-300', attributes: const {'style': 'display: inline-block; margin: 0 12px;'}),
              // 'ai training data' text subtab
              span(
                  classes: _activeSubTab == 3
                      ? 'text-xs font-bold text-black border-b-2 border-black cursor-pointer pb-1'
                      : 'text-xs text-gray-500 hover:text-black cursor-pointer transition-colors',
                  events: {
                    'click': (e) => setState(() => _activeSubTab = 3)
                  },
                  [text("ai training data")]
              ),
            ]
        ),

        // Prominent live upload status bar
        if (_uploadStatusMessage.isNotEmpty)
          div(
              classes: 'bg-white rounded-md p-4 shadow-sm mb-4 text-center',
              attributes: const {'style': 'margin-bottom: 16px;'},
              [
                span(
                    attributes: const {'style': 'font-style: italic; font-weight: bold; color: #16a34a; font-size: 13px;'},
                    [text(_uploadStatusMessage)]
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

/// Dynamic Tab Component supporting automated pipeline statistics and direct callable trigger actions.
class EditorOcrEntitiesTab extends StatefulComponent {
  final String frefFanzineId;
  final Fanzine fanzine;
  final List<FanzinePage> pages;
  final FanzineEditorBloc bloc;

  const EditorOcrEntitiesTab({
    required this.frefFanzineId,
    required this.fanzine,
    required this.pages,
    required this.bloc,
    super.key,
  });

  @override
  State<EditorOcrEntitiesTab> createState() => _EditorOcrEntitiesTabState();
}

class _EditorOcrEntitiesTabState extends State<EditorOcrEntitiesTab> {
  int _rawDone = 0;
  int _masterVerified = 0;
  int _linkedPending = 0;
  bool _calculating = true;
  FirebaseSubscription? _imagesSub;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _listenToOcrProgress();
    }
  }

  @override
  void didUpdateComponent(EditorOcrEntitiesTab oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.frefFanzineId != component.frefFanzineId && kIsWeb) {
      _imagesSub?.callAsFunction();
      _listenToOcrProgress();
    }
  }

  @override
  void dispose() {
    _imagesSub?.callAsFunction();
    super.dispose();
  }

  void _listenToOcrProgress() {
    setState(() => _calculating = true);
    _imagesSub = fsListenQuery('images', 'usedInFanzines', 'array-contains', jsonEncode(component.frefFanzineId), '', false, (jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        int raw = 0;
        int master = 0;
        int linked = 0;

        for (var doc in decoded) {
          final data = doc['data'] as Map<String, dynamic>? ?? {};
          final rawText = data['text_raw']?.toString() ?? '';
          final correctedText = data['text_corrected']?.toString() ?? '';
          final needsAi = data['needs_ai_cleaning'] == true;
          final needsLink = data['needs_linking'] == true;

          if (rawText.isNotEmpty && rawText != "[No text detected]") raw++;
          if (correctedText.isNotEmpty && !needsAi) master++;
          if (needsLink) linked++;
        }

        if (mounted) {
          setState(() {
            _rawDone = raw;
            _masterVerified = master;
            _linkedPending = linked;
            _calculating = false;
          });
        }
      } catch (e) {
        print("Error streaming OCR stats: $e");
        if (mounted) setState(() => _calculating = false);
      }
    });
  }

  @override
  Component build(BuildContext context) {
    final draftEntities = component.fanzine.draftEntities;

    return div(
      classes: 'flex-col text-left gap-4',
      attributes: const {'style': 'display: flex; flex-direction: column; gap: 16px;'},
      [
        div(
          classes: 'flex-row justify-around items-center py-2 bg-gray-50 rounded-md border border-gray-150',
          attributes: const {'style': 'display: flex; flex-direction: row; justify-content: space-around; align-items: center; padding: 12px 0;'},
          [
            _buildCounterSquare("Raw Done", _rawDone, '#2563eb'),
            _buildCounterSquare("Master Verified", _masterVerified, '#16a34a'),
            _buildCounterSquare("Linked Pending", _linkedPending, '#ea580c'),
          ],
        ),

        div(
          classes: 'flex-row gap-3 mt-2',
          attributes: const {'style': 'display: flex; flex-direction: row; gap: 12px; justify-content: center;'},
          [
            button(
                classes: 'profile-btn',
                attributes: const {'style': 'height: 36px; display: inline-flex; align-items: center; justify-content: center; padding: 0 16px; font-weight: bold; border-radius: 18px; border: 1px solid #16a34a; color: #16a34a; background: white; cursor: pointer;'},
                events: {'click': (e) => component.bloc.add(TriggerAiCleanRequested())},
                [
                  span(classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px; margin-right: 6px;'}, [text('auto_fix_high')]),
                  text("Step 2: AI Clean")
                ]
            ),
            button(
                classes: 'profile-btn',
                attributes: const {'style': 'height: 36px; display: inline-flex; align-items: center; justify-content: center; padding: 0 16px; font-weight: bold; border-radius: 18px; border: 1px solid #ea580c; color: #ea580c; background: white; cursor: pointer;'},
                events: {'click': (e) => component.bloc.add(TriggerGenerateLinksRequested())},
                [
                  span(classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px; margin-right: 6px;'}, [text('link')]),
                  text("Step 3: Generate Links")
                ]
            ),
          ],
        ),

        div([], attributes: const {'style': 'height: 1px; background-color: #eee; margin: 8px 0;'}),

        h3([text("Detected Entities Archive")], classes: 'text-xs font-bold text-gray uppercase tracking-wider mb-1'),
        if (draftEntities.isEmpty)
          p([text("No entities registered in this issue's index pipeline yet.")], classes: 'text-xs text-gray italic text-center py-4')
        else
          div(
            classes: 'flex-col gap-2',
            attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px;'},
            [
              for (var entity in draftEntities)
                OcrWorkspaceEntityRow(name: entity, key: ValueKey(entity)),
            ],
          ),
      ],
    );
  }

  Component _buildCounterSquare(String label, int val, String color) {
    return div(
      attributes: const {'style': 'display: flex; flex-direction: column; align-items: center;'},
      [
        span([text(_calculating ? "..." : "$val")], attributes: {
          'style': 'font-size: 24px; font-weight: 900; color: $color; line-height: 1;'
        }),
        span([text(label.toLowerCase())], attributes: const {
          'style': 'font-size: 10px; color: #666; font-weight: bold; margin-top: 4px;'
        }),
      ],
    );
  }
}

/// Stateful row widget observing username registration hooks in real-time.
class OcrWorkspaceEntityRow extends StatefulComponent {
  final String name;

  const OcrWorkspaceEntityRow({required this.name, super.key});

  @override
  State<OcrWorkspaceEntityRow> createState() => _OcrWorkspaceEntityRowState();
}

class _OcrWorkspaceEntityRowState extends State<OcrWorkspaceEntityRow> {
  bool _loading = true;
  bool _exists = false;
  String? _profileId;
  bool _isAlias = false;
  String? _redirectHandle;
  FirebaseSubscription? _listener;

  bool _showAliasInput = false;
  String _targetAliasInputText = '';

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _startObserver();
    }
  }

  @override
  void dispose() {
    _listener?.callAsFunction();
    super.dispose();
  }

  void _startObserver() {
    final handle = normalizeHandle(component.name);
    _listener = fsListenDoc('usernames/$handle', (jsonStr) {
      try {
        final doc = jsonDecode(jsonStr);
        if (doc['exists'] == true) {
          final data = doc['data'] as Map<String, dynamic>? ?? {};
          if (mounted) {
            setState(() {
              _exists = true;
              _isAlias = data['isAlias'] == true;
              _profileId = data['uid'];
              _redirectHandle = data['redirect'];
              _loading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _exists = false;
              _isAlias = false;
              _profileId = null;
              _redirectHandle = null;
              _loading = false;
            });
          }
        }
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  Future<void> _createProfile() async {
    setState(() => _loading = true);
    try {
      final handle = normalizeHandle(component.name);
      final String profileId = 'profile_managed_${handle}_${DateTime.now().millisecondsSinceEpoch}';
      final uid = getCurrentUserId() ?? 'system';

      String firstName = component.name;
      String lastName = "";
      if (component.name.contains(' ')) {
        final parts = component.name.split(' ');
        firstName = parts.first;
        lastName = parts.sublist(1).join(' ');
      }

      await fsSetDoc('profiles/$profileId', jsonEncode({
        'uid': profileId,
        'username': handle,
        'displayName': component.name,
        'firstName': firstName,
        'lastName': lastName,
        'photoUrl': '',
        'bio': 'Managed curator profile page for canonical entity: ${component.name}.',
        'isManaged': true,
        'isCurator': false,
        'managers': [uid],
        'followerCount': 0,
        'followingCount': 0,
        'createdAt': WebFieldValue.serverTimestamp(),
        'updatedAt': WebFieldValue.serverTimestamp()
      }), true);

      await fsSetDoc('usernames/$handle', jsonEncode({
        'uid': profileId,
        'isManaged': true,
        'createdAt': WebFieldValue.serverTimestamp()
      }), true);

      await fsSetDoc('shortcodes/${handle.toUpperCase()}', jsonEncode({
        'type': 'user',
        'contentId': profileId,
        'displayCode': handle,
        'createdAt': WebFieldValue.serverTimestamp()
      }), true);
    } catch (e) {
      print("Error creating entity profile: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitAliasRedirect() async {
    final cleanTarget = normalizeHandle(_targetAliasInputText);
    if (cleanTarget.isEmpty) return;

    setState(() => _loading = true);
    try {
      final aliasHandle = normalizeHandle(component.name);
      final uid = getCurrentUserId() ?? 'system';

      final checkRes = await fsGetDoc('usernames/$cleanTarget');
      final targetDoc = jsonDecode(checkRes);

      if (targetDoc['exists'] != true) {
        setState(() {
          _loading = false;
          _showAliasInput = false;
        });
        return;
      }

      await fsSetDoc('usernames/$aliasHandle', jsonEncode({
        'redirect': cleanTarget,
        'createdBy': uid,
        'isAlias': true,
        'createdAt': WebFieldValue.serverTimestamp()
      }), true);

      setState(() {
        _showAliasInput = false;
        _targetAliasInputText = '';
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(
          attributes: const {'style': 'padding: 8px;'},
          [span([text("syncing... @${normalizeHandle(component.name)}")], attributes: const {'style': 'font-style: italic; color: #999; font-size: 12px;'})]
      );
    }

    return div(
      classes: 'flex-row justify-between items-center bg-gray-50 border border-gray-150 p-2 rounded-md',
      attributes: const {'style': 'display: flex; align-items: center; justify-content: space-between; padding: 10px 12px; background-color: #f9f9f9; border: 1px solid #eee; border-radius: 6px; box-sizing: border-box; width: 100%; margin-bottom: 6px;'},
      [
        div(
          classes: 'flex-col',
          attributes: const {'style': 'display: flex; flex-direction: column; gap: 2px;'},
          [
            span([text(component.name)], attributes: const {'style': 'font-weight: bold; font-size: 13px; color: black;'}),
            if (_isAlias && _redirectHandle != null)
              span([text("aliases to @$_redirectHandle")], attributes: const {'style': 'font-size: 10px; color: #2563eb; font-weight: bold;'})
          ],
        ),

        div(
          [
            if (_exists)
              a(
                  href: '/profile?userId=$_profileId',
                  attributes: const {'style': 'font-size: 11px; font-weight: bold; color: #16a34a; text-decoration: none; display: inline-flex; align-items: center;'},
                  [
                    span(classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px; margin-right: 4px; vertical-align: middle;'}, [text('account_circle')]),
                    text("view profile")
                  ]
              )
            else if (!_showAliasInput) ...[
              button(
                  classes: 'profile-btn',
                  attributes: const {'style': 'padding: 4px 8px; font-size: 10px; font-weight: bold; background: white; border: 1px solid #ccc; cursor: pointer;'},
                  events: {'click': (e) => _createProfile()},
                  [text("create")]
              ),
              span([], attributes: const {'style': 'display: inline-block; width: 6px;'}),
              button(
                  classes: 'profile-btn',
                  attributes: const {'style': 'padding: 4px 8px; font-size: 10px; font-weight: bold; background: white; border: 1px solid #ccc; cursor: pointer;'},
                  events: {'click': (e) => setState(() => _showAliasInput = true)},
                  [text("alias")]
              ),
            ] else
              div(
                attributes: const {'style': 'display: flex; gap: 4px; align-items: center;'},
                [
                  input(
                      type: InputType.text,
                      attributes: const {
                        'placeholder': 'target handle...',
                        'style': 'padding: 4px 6px; border: 1px solid #ccc; font-size: 10px; width: 100px; height: 24px; box-sizing: border-box;'
                      },
                      events: {
                        'input': (e) {
                          _targetAliasInputText = (e.target as dynamic).value ?? '';
                        }
                      }
                  ),
                  button(
                      attributes: const {'style': 'border: none; background: transparent; color: #16a34a; cursor: pointer;'},
                      events: {'click': (e) => _submitAliasRedirect()},
                      [
                        span(classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 13px;'}, [text('done')])
                      ]
                  ),
                  button(
                      attributes: const {'style': 'border: none; background: transparent; color: #ef4444; cursor: pointer;'},
                      events: {'click': (e) => setState(() => _showAliasInput = false)},
                      [
                        span(classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 13px;'}, [text('close')])
                      ]
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Stateful tile component mimicking the Flutter fanzine thumbnail builder.
/// Dynamically queries Page 1 in Firestore if fanzineData['gridCoverImage'] is null.
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

  Future<void> _resolveThumbnail() async {
    final String fanzineId = component.fanzineData['id'] ?? '';
    final String? coverUrl = component.fanzineData['gridCoverImage'];
    if (coverUrl != null && coverUrl.isNotEmpty) {
      if (mounted) {
        setState(() {
          _resolvedCoverUrl = coverUrl;
        });
      }
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
      // 1. Query pages subcollection for page number 1 and calculate page total length
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
      // 2. Fallback: Query associated master images under this folioContext
      final imagesRes = await fsQuery('images', 'folioContext', '==', jsonEncode(fanzineId), '');
      final List decodedImages = jsonDecode(imagesRes);
      if (decodedImages.isNotEmpty) {
        decodedImages.sort((a, b) {
          final aT = a['data']?['timestamp'] ?? 0;
          final bT = b['data']?['timestamp'] ?? 0;
          return bT.toString().compareTo(bT.toString());
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

    // Resolve shortcode URL binding cleanly similar to the other workspaces
    final String codeKey = component.fanzineData['shortCode'] ?? fanzineId;

    // Format publishing date nicely using precision choices and guess configurations
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
        classes: 'bg-white rounded-lg shadow-sm overflow-hidden transition-all',
        attributes: const {'style': 'display: flex; flex-direction: column; border: 1px solid #ddd; cursor: pointer; text-decoration: none;'},
        href: '/$codeKey', // Unified routing pattern matching standard vanity/shortcode pathways!
        [
          div(
              attributes: {
                'style': 'aspect-ratio: 5/8; background-color: #f3f4f6; background-image: url("$coverUrl"); background-size: cover; background-position: center; position: relative;'
              },
              [
                // High fidelity layered metadata badge overlays (narrowed to make room for delete action)
                div(
                    attributes: const {
                      'style': 'position: absolute; top: 12px; left: 12px; right: 44px; display: flex; flex-direction: column; gap: 4px; pointer-events: none;'
                    },
                    [
                      // Badge 1: Type & Page count
                      div(
                          attributes: const {
                            'style': 'background-color: rgba(33, 33, 33, 0.85); color: white; font-size: 10px; font-weight: bold; padding: 4px 8px; border-radius: 2px; text-align: center; text-transform: lowercase;'
                          },
                          [text("$fanzineType • $resolvedPageCount pages")]
                      ),
                      // Badge 2: Year info
                      if (resolvedYear.isNotEmpty)
                        div(
                            attributes: const {
                              'style': 'background-color: rgba(0, 0, 0, 0.7); color: white; font-size: 10px; font-weight: bold; padding: 4px 8px; border-radius: 2px; text-align: center;'
                            },
                            [text(resolvedYear)]
                        )
                    ]
                ),
                // High-fidelity delete button positioned top-right of the card thumbnail
                if (component.onDelete != null)
                  button(
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
                      [
                        span(classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px;'}, [text('delete')])
                      ]
                  )
              ]
          ),
          div(
              attributes: const {'style': 'padding: 12px; display: flex; flex-direction: column; gap: 4px;'},
              [
                span(attributes: const {'style': 'font-size: 13px; font-weight: bold; color: black; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'}, [text(title)]),
              ]
          )
        ]
    );
  }
}