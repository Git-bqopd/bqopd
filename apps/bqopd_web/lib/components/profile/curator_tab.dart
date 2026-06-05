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
  bool _showCatalogDrawer = false;

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
            Future.delayed(const Duration(seconds: 3), () {
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
      // Auto-generate standard shortcode
      final shortCode = ShortcodeGenerator.generateStandardCode();

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

      // Register in master shortcodes
      await fsSetDoc('shortcodes/${shortCode.toUpperCase()}', jsonEncode({
        'type': 'fanzine',
        'contentId': fanzineId,
        'displayCode': shortCode,
        'createdAt': WebFieldValue.serverTimestamp(),
      }), true);

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

  /// Renders the correct workspace based on the active sub-tab.
  /// Isolating this helper prevents Jaspr's diffing engine from mismatching stateful elements.
  Component _buildActiveSubTabContent() {
    switch (_activeSubTab) {
      case 0:
      // curator: shows draft PDFs (sourceFile != null && isLive != true)
        return _buildWorksGridSchema(_userWorks.where((w) => w['sourceFile'] != null && w['isLive'] != true).toList());
      case 1:
      // publisher: shows folios and published fanzines (sourceFile == null || isLive == true)
        return _buildWorksGridSchema(_userWorks.where((w) => w['sourceFile'] == null || w['isLive'] == true).toList());
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
        [
          for (var w in works)
            CuratorWorkGridTile(fanzineData: w, key: ValueKey(w['id'] ?? ''))
        ],
        attributes: const {
          'style': 'display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 16px; width: 100%; box-sizing: border-box;'
        }
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
        [
          h2([text("AI REINFORCEMENT BASELINES")], classes: 'font-bold text-sm text-gray mb-2', attributes: const {'style': 'margin-top: 0; margin-bottom: 8px;'}),
          for (var item in _aiTrainingData)
            div(
                [
                  if (item['fileUrl'] != null)
                    img(src: item['fileUrl'], attributes: const {'style': 'width: 48px; height: 48px; object-fit: cover; border-radius: 4px; border: 1px solid #ccc;'}),
                  span([], attributes: const {'style': 'display: inline-block; width: 16px;'}),
                  div(
                      [
                        span([text(item['title'] ?? 'Archival Page')], attributes: const {'style': 'font-weight: bold;'}),
                        span([
                          text("Correction Score: ${item['correctionScore'] ?? 0} | Link Score: ${item['linkingScore'] ?? 0}")
                        ], attributes: const {'style': 'font-size: 11px; color: #666;'}
                        )
                      ],
                      attributes: const {'style': 'display: flex; flex-direction: column; gap: 4px;'}
                  )
                ],
                attributes: const {'style': 'display: flex; align-items: center; padding: 12px; border: 1px solid #eee; border-radius: 8px; font-size: 13px;'}
            )
        ],
        classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-4',
        attributes: const {'style': 'display: flex; flex-direction: column; gap: 16px; padding: 24px; background: white;'}
    );
  }

  @override
  Component build(BuildContext context) {
    if (!kIsWeb) {
      return div(
        [p([text('Loading curator queue...')])],
        classes: 'p-16 text-center text-gray italic text-sm',
      );
    }
    return div(
      [
        // Navigation segment
        div(
            [
              // Updated 'catalog' button - styled EXACTLY like the 'make' button (normal weight, same font, no icon, border-radius: 0)
              button(
                  [
                    text("catalog")
                  ],
                  classes: 'transition-all cursor-pointer flex items-center',
                  attributes: {
                    'style': 'height: 32px; display: inline-flex; align-items: center; justify-content: center; padding: 0 16px; border: 1px solid #ccc; background: ${_showCatalogDrawer ? "black" : "transparent"}; color: ${_showCatalogDrawer ? "white" : "black"}; font-size: 13px; text-transform: lowercase; font-family: inherit; cursor: pointer; border-radius: 0; font-weight: normal;'
                  },
                  events: {
                    'click': (e) => setState(() => _showCatalogDrawer = !_showCatalogDrawer)
                  }
              ),
              span([text('|')], classes: 'text-xs text-gray-300', attributes: const {'style': 'display: inline-block; margin: 0 12px;'}),
              // 'curator' text subtab with no icon
              span(
                  [text("curator")],
                  classes: _activeSubTab == 0
                      ? 'text-xs font-bold text-black border-b-2 border-black cursor-pointer pb-1'
                      : 'text-xs text-gray-500 hover:text-black cursor-pointer transition-colors',
                  events: {
                    'click': (e) => setState(() => _activeSubTab = 0)
                  }
              ),
              span([text('|')], classes: 'text-xs text-gray-300', attributes: const {'style': 'display: inline-block; margin: 0 12px;'}),
              // 'publisher' text subtab
              span(
                  [text("publisher")],
                  classes: _activeSubTab == 1
                      ? 'text-xs font-bold text-black border-b-2 border-black cursor-pointer pb-1'
                      : 'text-xs text-gray-500 hover:text-black cursor-pointer transition-colors',
                  events: {
                    'click': (e) => setState(() => _activeSubTab = 1)
                  }
              ),
              span([text('|')], classes: 'text-xs text-gray-300', attributes: const {'style': 'display: inline-block; margin: 0 12px;'}),
              // 'entities' text subtab
              span(
                  [text("entities")],
                  classes: _activeSubTab == 2
                      ? 'text-xs font-bold text-black border-b-2 border-black cursor-pointer pb-1'
                      : 'text-xs text-gray-500 hover:text-black cursor-pointer transition-colors',
                  events: {
                    'click': (e) => setState(() => _activeSubTab = 2)
                  }
              ),
              span([text('|')], classes: 'text-xs text-gray-300', attributes: const {'style': 'display: inline-block; margin: 0 12px;'}),
              // 'ai training data' text subtab
              span(
                  [text("ai training data")],
                  classes: _activeSubTab == 3
                      ? 'text-xs font-bold text-black border-b-2 border-black cursor-pointer pb-1'
                      : 'text-xs text-gray-500 hover:text-black cursor-pointer transition-colors',
                  events: {
                    'click': (e) => setState(() => _activeSubTab = 3)
                  }
              ),
            ],
            classes: 'bg-white rounded-md p-4 shadow-sm',
            // Updated to 'justify-content: center;' to perfectly center the entire sub-tab selector list
            attributes: const {'style': 'display: flex; flex-wrap: wrap; justify-content: center; align-items: center; gap: 4px; box-sizing: border-box; width: 100%; margin-bottom: 16px;'}
        ),
        // Action Toolbar: Only visible when Catalog is toggled on to control PDF uploads
        if (_showCatalogDrawer)
          div(
              classes: 'bg-white rounded-md p-4 shadow-sm flex-row items-center justify-between mb-4',
              attributes: const {'style': 'display: flex; flex-direction: row; align-items: center; justify-content: space-between; margin-bottom: 16px;'},
              [
                div(classes: 'flex-row gap-3', [
                  button(
                      [
                        span([text('upload_file')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 18px; margin-right: 6px;'}),
                        text(_isUploadingPdf ? 'uploading...' : 'ingest PDF')
                      ],
                      classes: 'profile-btn',
                      attributes: {
                        'style': 'height: 36px; display: inline-flex; align-items: center; justify-content: center; font-weight: bold; border-radius: 0px; border: 1px solid black; background: white;',
                        if (_isUploadingPdf) 'disabled': 'true'
                      },
                      events: {
                        'click': (e) => _triggerPdfUpload()
                      }
                  ),
                  button(
                      [
                        span([text('add_circle')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 18px; margin-right: 6px;'}),
                        text('add blank archival')
                      ],
                      classes: 'profile-btn',
                      attributes: const {
                        'style': 'height: 36px; display: inline-flex; align-items: center; justify-content: center; font-weight: bold; border-radius: 0px; border: 1px solid black; background: white;'
                      },
                      events: {
                        'click': (e) => _createArchivalFanzine()
                      }
                  ),
                ]),
                div(
                    classes: 'text-right flex-1',
                    attributes: const {'style': 'margin-left: 20px; font-size: 12px; color: #555;'},
                    [
                      if (_uploadStatusMessage.isNotEmpty)
                        span(
                            [text(_uploadStatusMessage)],
                            attributes: const {'style': 'font-style: italic; font-weight: bold; color: #16a34a;'}
                        )
                      else
                        span([text('upload archival PDFs to automatically run Vision OCR transcriptions')])
                    ]
                )
              ]
          ),
        // Sub-Tab Content Router: Render using isolated safe switcher to prevent DOM reuse collisions
        _buildActiveSubTabContent(),
        // Safe Confirmation dialog modal
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

/// Stateful tile component mimicking the Flutter fanzine thumbnail builder.
/// Dynamically queries Page 1 in Firestore if fanzineData['gridCoverImage'] is null.
class CuratorWorkGridTile extends StatefulComponent {
  final Map<String, dynamic> fanzineData;

  const CuratorWorkGridTile({required this.fanzineData, super.key});

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
        [
          div(
              [
                // High fidelity layered metadata badge overlays
                div(
                    attributes: const {
                      'style': 'position: absolute; top: 12px; left: 12px; right: 12px; display: flex; flex-direction: column; gap: 4px; pointer-events: none;'
                    },
                    [
                      // Badge 1: Type & Page count
                      div(
                          [text("$fanzineType   $resolvedPageCount pages")],
                          attributes: const {
                            'style': 'background-color: rgba(33, 33, 33, 0.85); color: white; font-size: 10px; font-weight: bold; padding: 4px 8px; border-radius: 2px; text-align: center; text-transform: lowercase;'
                          }
                      ),
                      // Badge 2: Year info
                      if (resolvedYear.isNotEmpty)
                        div(
                            [text(resolvedYear)],
                            attributes: const {
                              'style': 'background-color: rgba(0, 0, 0, 0.7); color: white; font-size: 10px; font-weight: bold; padding: 4px 8px; border-radius: 2px; text-align: center;'
                            }
                        )
                    ]
                )
              ],
              attributes: {
                'style': 'aspect-ratio: 5/8; background-color: #f3f4f6; background-image: url("$coverUrl"); background-size: cover; background-position: center; position: relative;'
              }
          ),
          div(
              [
                span([text(title)], attributes: const {'style': 'font-size: 13px; font-weight: bold; color: black; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'}),
              ],
              attributes: const {'style': 'padding: 12px; display: flex; flex-direction: column; gap: 4px;'}
          )
        ],
        href: '/$codeKey', // Unified routing pattern matching standard vanity/shortcode pathways!
        classes: 'bg-white rounded-lg shadow-sm overflow-hidden transition-all',
        attributes: const {'style': 'display: flex; flex-direction: column; border: 1px solid #ddd; cursor: pointer; text-decoration: none;'}
    );
  }
}