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

/// Local utility to normalize user-provided names/handles by converting them to lowercase
/// and removing any whitespace or special characters to match standard database indexes.
String normalizeHandle(String input) {
  return input.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
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
  // 0: catalog, 1: curator, 2: publisher, 3: entities, 4: ai training data
  int _activeSubTab = 0;

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

  /// Streams ALL unpublished and draft fanzines globally (Rule 1) to match the Flutter curator dataset
  void _listenToWorks() {
    _worksSub?.cancel();
    _worksFirebaseSub?.callAsFunction();
    _worksFirebaseSub = null;
    setState(() => _loadingWorks = true);

    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();

    // Query ALL fanzines to allow comprehensive, multi-issue curation
    _worksFirebaseSub = fsListenQuery('fanzines', '', '', '', 'creationDate', true, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        final list = decoded.map((d) {
          final data = d['data'] as Map<String, dynamic>;
          data['id'] = d['id'];
          return data;
        }).toList();
        if (!controller.isClosed) {
          controller.add(list);
        }
      } catch (e) {
        print("Error streaming global fanzines: $e");
      }
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
          try {
            final List decoded = jsonDecode(jsonStr);
            int errors = 0;
            for (var d in decoded) {
              final data = d['data'] as Map<String, dynamic>? ?? {};
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
      try {
        final List decoded = jsonDecode(jsonStr);
        final list = decoded.map((d) {
          final data = d['data'] as Map<String, dynamic>;
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
          await stUpload(path, bytes, 'application/pdf');

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
      final shortcodeService = createFanzineRepository();

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
        Router.of(context).push('/editor/$fanzineId');
      }
    } catch (e) {
      print("Error creating archival zine: $e");
      if (mounted) setState(() => _loadingWorks = false);
    }
  }

  /// Triggers full batch OCR reprocessing
  Future _rescanFanzine(String fid) async {
    try {
      await createPipelineRepository().rescanFanzine(fid);
      _showToast("Zine re-process triggered successfully.");
    } catch (e) {
      _showToast("Error triggering rescan: $e", isError: true);
    }
  }

  /// Toggles AI Gemini cleaning
  Future _triggerAiClean(String fid) async {
    try {
      await createPipelineRepository().triggerAiClean(fid);
      _showToast("Gemini AI transcription cleaning triggered.");
    } catch (e) {
      _showToast("Error triggering AI Clean: $e", isError: true);
    }
  }

  /// Triggers Wiki Link generation pipeline
  Future _triggerGenerateLinks(String fid) async {
    try {
      await createPipelineRepository().triggerGenerateLinks(fid);
      _showToast("Wikilink entity-linking pipeline triggered.");
    } catch (e) {
      _showToast("Error triggering Wikilink pipeline: $e", isError: true);
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

  Component _buildWorkGridTile(Map<String, dynamic> w) {
    final String fanzineId = w['id'] ?? '';
    final String title = w['title'] ?? 'Untitled Fanzine';
    final String coverUrl = w['gridCoverImage'] ?? (w['sourceFile'] != null
        ? 'https://placehold.co/450x720/png?text=Archival+Ingest'
        : 'https://placehold.co/450x720/png?text=Folio');
    final String codeKey = w['shortCode'] ?? fanzineId;

    return a(
        [
          div(
              [
                div([text(w['type'] ?? 'ingested')], attributes: const {
                  'style': 'position: absolute; top: 8px; left: 8px; background-color: rgba(0,0,0,0.7); color: white; padding: 2px 8px; border-radius: 4px; font-size: 8px; font-weight: bold; text-transform: uppercase;'
                })
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
        href: '/$codeKey',
        classes: 'bg-white rounded-lg shadow-sm overflow-hidden transition-all',
        attributes: const {'style': 'display: flex; flex-direction: column; border: 1px solid #ddd; cursor: pointer; text-decoration: none;'}
    );
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
            _buildWorkGridTile(w)
        ],
        attributes: const {
          'style': 'display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 16px; width: 100%; box-sizing: border-box;'
        }
    );
  }

  /// Builds a high-fidelity control dashboard table matching the Flutter curator workspace layout
  Component _buildCuratorInboxesDashboard(List<Map<String, dynamic>> drafts) {
    if (_loadingWorks) {
      return div(
        [p([text('Loading queue...')])],
        classes: 'p-16 text-center text-gray italic text-sm',
      );
    }

    if (drafts.isEmpty) {
      return div(
        [
          span([text('fact_check')], classes: 'material-symbols-outlined text-gray-300', attributes: const {'style': 'font-size: 48px;'}),
          p([text('All ingested PDFs are currently live. Queue clear!')], classes: 'text-sm text-gray italic mt-4', attributes: const {'style': 'margin-top: 16px;'})
        ],
        classes: 'bg-white rounded-lg p-16 shadow-sm text-center',
      );
    }

    return div(
        classes: 'stats-table-wrapper bg-white rounded-lg p-4 shadow-sm border border-gray-200',
        [
          table(
              classes: 'stats-table text-left w-full',
              [
                thead([
                  tr([
                    th([text('Fanzine Title & Details')]),
                    th([text('Pipeline Status')]),
                    th([text('Errors (OCR)')]),
                    th([text('Workspace Management Actions')]),
                  ])
                ]),
                tbody([
                  for (var zine in drafts)
                    _buildCuratorDashboardRow(zine)
                ])
              ]
          )
        ]
    );
  }

  Component _buildCuratorDashboardRow(Map<String, dynamic> zine) {
    final String id = zine['id'] ?? '';
    final String title = zine['title'] ?? 'Untitled Ingest';
    final String code = zine['shortCode'] ?? 'pending';
    final String status = zine['processingStatus'] ?? 'idle';
    final int errorCount = _fanzineErrorCounts[id] ?? 0;

    // Status Styling mapping
    String statusBg = '#f3f4f6';
    String statusColor = '#374151';
    if (status == 'needs_ingest') { statusBg = '#fef3c7'; statusColor = '#d97706'; }
    else if (status == 'extracting_images') { statusBg = '#dbeafe'; statusColor = '#2563eb'; }
    else if (status == 'images_ready') { statusBg = '#ecfdf5'; statusColor = '#059669'; }
    else if (status == 'processing_ocr') { statusBg = '#ffedd5'; statusColor = '#ea580c'; }
    else if (status == 'aggregating') { statusBg = '#e0e7ff'; statusColor = '#4f46e5'; }
    else if (status == 'complete') { statusBg = '#f0fdf4'; statusColor = '#16a34a'; }
    else if (status == 'error') { statusBg = '#fee2e2'; statusColor = '#dc2626'; }

    return tr([
      // Title Block
      td([
        div(classes: 'flex-col gap-1', [
          span([text(title)], attributes: const {'style': 'font-weight: bold; font-size: 13.5px;'}),
          span([text('ID: $id | Code: ${code.toUpperCase()}')], attributes: const {'style': 'font-size: 10px; color: #777; font-family: monospace;'})
        ])
      ]),
      // Status Chip
      td([
        span(
            [text(status.toLowerCase())],
            attributes: {
              'style': 'background-color: $statusBg; color: $statusColor; padding: 4px 10px; border-radius: 100px; font-size: 10px; font-weight: bold; text-transform: uppercase; letter-spacing: 0.5px; display: inline-block;'
            }
        )
      ]),
      // Error counter
      td([
        if (errorCount > 0)
          span(
              [text('$errorCount errors')],
              attributes: const {'style': 'color: #dc2626; font-weight: bold; font-size: 11px;'}
          )
        else
          span(
              [text('OK')],
              attributes: const {'style': 'color: #16a34a; font-weight: bold; font-size: 11px;'}
          )
      ]),
      // Actions
      td([
        div(
            attributes: const {'style': 'display: flex; gap: 8px; align-items: center;'},
            [
              // Workbench Link
              a(
                  [text('workbench')],
                  href: '/editor/$id',
                  classes: 'profile-btn',
                  attributes: const {'style': 'padding: 4px 12px; font-size: 11px; background: white; font-weight: bold; border: 1px solid #ccc;'}
              ),
              // Rescan Callable
              button(
                  [span([text('refresh')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px;'})],
                  classes: 'p-1 cursor-pointer',
                  attributes: const {
                    'title': 'Reprocess/Rescan Ingest Pages',
                    'style': 'border: none; background: transparent; padding: 4px; display: inline-flex; cursor: pointer; color: #2563eb;'
                  },
                  events: {'click': (e) => _rescanFanzine(id)}
              ),
              // AI Clean Callable
              button(
                  [span([text('auto_fix_high')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px;'})],
                  classes: 'p-1 cursor-pointer',
                  attributes: const {
                    'title': 'AI Clean Transcriptions',
                    'style': 'border: none; background: transparent; padding: 4px; display: inline-flex; cursor: pointer; color: #16a34a;'
                  },
                  events: {'click': (e) => _triggerAiClean(id)}
              ),
              // Link builder
              button(
                  [span([text('link')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px;'})],
                  classes: 'p-1 cursor-pointer',
                  attributes: const {
                    'title': 'AI Generate Wiki-Links',
                    'style': 'border: none; background: transparent; padding: 4px; display: inline-flex; cursor: pointer; color: #ea580c;'
                  },
                  events: {'click': (e) => _triggerGenerateLinks(id)}
              ),
              // Delete Fanzine Trigger
              button(
                  [span([text('delete_forever')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px;'})],
                  classes: 'p-1 cursor-pointer',
                  attributes: const {
                    'title': 'Delete Draft Ingest',
                    'style': 'border: none; background: transparent; padding: 4px; display: inline-flex; cursor: pointer; color: #dc2626;'
                  },
                  events: {
                    'click': (e) => setState(() {
                      _pendingDeleteId = id;
                      _pendingDeleteTitle = title;
                    })
                  }
              ),
            ]
        )
      ]),
    ]);
  }

  /// Renders high-fidelity interactive Entities Tab matching Flutter with live list aggregation and stateful rows.
  Component _buildCuratorEntitiesList() {
    final Map<String, int> entityCounts = {};
    for (var fz in _userWorks) {
      // Pull only from draft archival fanzines, matching the Flutter criteria
      if (fz['isLive'] == true) continue;
      final List entities = fz['draftEntities'] ?? [];
      for (var ent in entities) {
        entityCounts[ent.toString()] = (entityCounts[ent.toString()] ?? 0) + 1;
      }
    }

    if (entityCounts.isEmpty) {
      return div(
          classes: 'bg-white rounded-lg p-12 text-center shadow-sm border border-gray-100 flex flex-col items-center gap-4',
          [
            span([text('fingerprint')], classes: 'material-symbols-outlined text-gray-300', attributes: const {'style': 'font-size: 48px;'}),
            p([text("No entities detected in draft curator pipeline.")], classes: 'text-sm text-gray italic'),
          ]
      );
    }

    // Sort entities dynamically by descending occurrences count
    final sortedNames = entityCounts.keys.toList()
      ..sort((a, b) => entityCounts[b]!.compareTo(entityCounts[a]!));

    return div(
        classes: 'bg-white rounded-lg p-6 shadow-sm border border-gray-200',
        [
          // Control header
          div(
              attributes: const {'style': 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; border-bottom: 1px solid #f0f0f0; padding-bottom: 12px;'},
              [
                div([
                  h2([text("CANONICAL ENTITIES DIRECTORY")], attributes: const {'style': 'margin: 0; font-size: 15px; font-weight: bold; letter-spacing: 0.5px;'}),
                  span([text("Manage alternative name aliases and create curator-owned wiki profile pages.")], attributes: const {'style': 'font-size: 11px; color: #666;'})
                ]),
              ]
          ),

          table(
              classes: 'stats-table text-left w-full',
              [
                thead([
                  tr([
                    th([text('Canonical Identity & Aliases')]),
                    th([text('Total Appearances')]),
                    th([text('Profile Status')]),
                    th([text('Actions')]),
                  ])
                ]),
                tbody([
                  for (var name in sortedNames)
                    EntityRowComponent(
                      name: name,
                      count: entityCounts[name]!,
                      key: ValueKey(name),
                    )
                ])
              ]
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
                        ], attributes: const {'style': 'font-size: 11px; color: #666;'})
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
                  attributes: const {
                    'style': 'height: 32px; display: inline-flex; align-items: center; justify-content: center; padding: 0 16px; border: 1px solid #ccc; background: transparent; color: black; font-size: 13px; text-transform: lowercase; font-family: inherit; cursor: pointer; border-radius: 0; font-weight: normal;'
                  },
                  events: {
                    'click': (e) => setState(() => _activeSubTab = 0)
                  }
              ),
              span([text('|')], classes: 'text-xs text-gray-300', attributes: const {'style': 'display: inline-block; margin: 0 12px;'}),

              // 'curator' text subtab with no icon
              span(
                  [text("curator")],
                  classes: _activeSubTab == 1
                      ? 'text-xs font-bold text-black border-b-2 border-black cursor-pointer pb-1'
                      : 'text-xs text-gray-500 hover:text-black cursor-pointer transition-colors',
                  events: {
                    'click': (e) => setState(() => _activeSubTab = 1)
                  }
              ),
              span([text('|')], classes: 'text-xs text-gray-300', attributes: const {'style': 'display: inline-block; margin: 0 12px;'}),

              // 'publisher' text subtab
              span(
                  [text("publisher")],
                  classes: _activeSubTab == 2
                      ? 'text-xs font-bold text-black border-b-2 border-black cursor-pointer pb-1'
                      : 'text-xs text-gray-500 hover:text-black cursor-pointer transition-colors',
                  events: {
                    'click': (e) => setState(() => _activeSubTab = 2)
                  }
              ),
              span([text('|')], classes: 'text-xs text-gray-300', attributes: const {'style': 'display: inline-block; margin: 0 12px;'}),

              // 'entities' text subtab
              span(
                  [text("entities")],
                  classes: _activeSubTab == 3
                      ? 'text-xs font-bold text-black border-b-2 border-black cursor-pointer pb-1'
                      : 'text-xs text-gray-500 hover:text-black cursor-pointer transition-colors',
                  events: {
                    'click': (e) => setState(() => _activeSubTab = 3)
                  }
              ),
              span([text('|')], classes: 'text-xs text-gray-300', attributes: const {'style': 'display: inline-block; margin: 0 12px;'}),

              // 'ai training data' text subtab
              span(
                  [text("ai training data")],
                  classes: _activeSubTab == 4
                      ? 'text-xs font-bold text-black border-b-2 border-black cursor-pointer pb-1'
                      : 'text-xs text-gray-500 hover:text-black cursor-pointer transition-colors',
                  events: {
                    'click': (e) => setState(() => _activeSubTab = 4)
                  }
              ),
            ],
            classes: 'bg-white rounded-md p-4 shadow-sm',
            // Updated to 'justify-content: center;' to perfectly center the entire sub-tab selector list
            attributes: const {'style': 'display: flex; flex-wrap: wrap; justify-content: center; align-items: center; gap: 4px; box-sizing: border-box; width: 100%; margin-bottom: 16px;'}
        ),

        // Action Toolbar: Only visible when active on 'curator' dashboard to control PDF uploads
        if (_activeSubTab == 1)
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
                        'style': 'height: 36px; display: inline-flex; align-items: center; justify-content: center; font-weight: bold; border-radius: 18px; border: 1px solid black; background: white;',
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
                        'style': 'height: 36px; display: inline-flex; align-items: center; justify-content: center; font-weight: bold; border-radius: 18px; border: 1px solid black; background: white;'
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

        // Sub-Tab Content Router
        if (_activeSubTab == 0)
          _buildWorksGridSchema(_userWorks.where((w) => w['sourceFile'] == null || w['isLive'] == true).toList())
        else if (_activeSubTab == 1)
          _buildCuratorInboxesDashboard(_userWorks.where((w) => w['sourceFile'] != null && w['isLive'] != true).toList())
        else if (_activeSubTab == 2)
            _buildWorksGridSchema(_userWorks.where((w) => w['isLive'] != true).toList())
          else if (_activeSubTab == 3)
              _buildCuratorEntitiesList()
            else
              _buildAITrainingDataPortal(),

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

/// Stateful row widget that observes its own handle status independently, preventing master UI locks.
class EntityRowComponent extends StatefulComponent {
  final String name;
  final int count;

  const EntityRowComponent({required this.name, required this.count, super.key});

  @override
  State<EntityRowComponent> createState() => _EntityRowComponentState();
}

class _EntityRowComponentState extends State<EntityRowComponent> {
  bool _loading = true;
  bool _exists = false;
  String? _profileId;
  bool _isAlias = false;
  String? _redirectHandle;

  // Real-time listener subscription hook
  FirebaseSubscription? _listener;

  // Inline alias editor toggle state
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
  void didUpdateComponent(EntityRowComponent oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.name != component.name && kIsWeb) {
      _listener?.callAsFunction();
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
    setState(() => _loading = true);

    _listener = fsListenDoc('usernames/$handle', (jsonStr) {
      try {
        final doc = jsonDecode(jsonStr);
        if (doc['exists'] == true) {
          final data = doc['data'] as Map<String, dynamic>? ?? {};
          final bool isAlias = data['isAlias'] == true;
          if (mounted) {
            setState(() {
              _exists = true;
              _isAlias = isAlias;
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
      } catch (e) {
        print("Error observing username details: $e");
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  /// Triggers managed profile generation and maps registration hooks, matching Flutter's workflow
  Future<void> _triggerCreateProfile() async {
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

      final profileData = {
        'uid': profileId,
        'username': handle,
        'displayName': component.name,
        'firstName': firstName,
        'lastName': lastName,
        'photoUrl': '',
        'bio': 'Managed curator profile page for canonical entity: ${component.name}.',
        'isManaged': true,
        'isCurator': false,
        'isAdmin': false,
        'managers': [uid],
        'followerCount': 0,
        'followingCount': 0,
        'createdAt': WebFieldValue.serverTimestamp(),
        'updatedAt': WebFieldValue.serverTimestamp()
      };

      final usernameData = {
        'uid': profileId,
        'isManaged': true,
        'createdAt': WebFieldValue.serverTimestamp()
      };

      final shortcodeData = {
        'type': 'user',
        'contentId': profileId,
        'displayCode': handle,
        'createdAt': WebFieldValue.serverTimestamp()
      };

      await fsSetDoc('profiles/$profileId', jsonEncode(profileData), true);
      await fsSetDoc('usernames/$handle', jsonEncode(usernameData), true);
      await fsSetDoc('shortcodes/${handle.toUpperCase()}', jsonEncode(shortcodeData), true);
    } catch (e) {
      print("Failed creating managed entity profile: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Directs alias triggers to point to another profile handle
  Future<void> _submitAliasRedirect() async {
    final cleanTarget = normalizeHandle(_targetAliasInputText);
    if (cleanTarget.isEmpty) return;

    setState(() => _loading = true);
    try {
      final aliasHandle = normalizeHandle(component.name);
      final uid = getCurrentUserId() ?? 'system';

      // Check if target exists first
      final checkRes = await fsGetDoc('usernames/$cleanTarget');
      final targetDoc = jsonDecode(checkRes);

      if (targetDoc['exists'] != true) {
        print("[ERROR] Target handle @$cleanTarget does not exist.");
        setState(() {
          _loading = false;
          _showAliasInput = false;
        });
        return;
      }

      final aliasData = {
        'redirect': cleanTarget,
        'createdBy': uid,
        'isAlias': true,
        'createdAt': WebFieldValue.serverTimestamp()
      };

      await fsSetDoc('usernames/$aliasHandle', jsonEncode(aliasData), true);
      setState(() {
        _showAliasInput = false;
        _targetAliasInputText = '';
      });
    } catch (e) {
      print("Failed submitting alias redirection: $e");
    } finally {
      if (mounted) setState(() => _loadingValue());
    }
  }

  void _loadingValue() {
    if (mounted) setState(() => _loading = false);
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return tr([
        td([span([text(component.name)], attributes: const {'style': 'font-weight: bold; font-size: 13.5px; opacity: 0.5;'})]),
        td([span([text('${component.count} occurrences')], attributes: const {'style': 'color: #999;'})]),
        td([span([text('syncing...')], attributes: const {'style': 'font-style: italic; color: #999;'})]),
        td([]),
      ]);
    }

    return tr([
      // Canonical Display Label
      td([
        div(classes: 'flex-col gap-1', [
          span([text(component.name)], attributes: const {'style': 'font-weight: bold; font-size: 13.5px; color: black;'}),
          if (_isAlias && _redirectHandle != null)
            span(
                [text('alias redirects to: @$_redirectHandle')],
                attributes: const {'style': 'font-size: 11px; color: #2563eb; font-weight: bold;'}
            )
        ])
      ]),

      // Appearance instances
      td([
        span([text('${component.count} occurrences')], attributes: const {'style': 'font-size: 12px; font-weight: 500; color: #4b5563;'})
      ]),

      // Linked Profile mapping Status
      td([
        if (_exists && _profileId != null)
          a(
              [
                span([text('account_circle')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px; margin-right: 4px;'}),
                text(_isAlias ? 'view target profile' : 'view profile')
              ],
              href: '/profile?userId=$_profileId',
              classes: 'text-green-600 hover:underline inline-flex items-center',
              attributes: const {'style': 'font-size: 12px; font-weight: bold; color: #16a34a; text-decoration: none;'}
          )
        else
          span(
              [text('unlinked')],
              attributes: const {'style': 'font-size: 11px; color: #999; font-weight: 500; letter-spacing: 0.5px; text-transform: uppercase;'}
          )
      ]),

      // Interactive Action Triggers (Match Flutter exactly)
      td([
        if (!_exists)
          div(
              attributes: const {'style': 'display: flex; gap: 8px; align-items: center;'},
              [
                if (!_showAliasInput) ...[
                  button(
                      [text('create')],
                      classes: 'profile-btn',
                      attributes: const {'style': 'padding: 4px 10px; font-size: 11px; background: white; border: 1px solid #ccc; font-weight: bold; border-radius: 4px; cursor: pointer;'},
                      events: {'click': (e) => _triggerCreateProfile()}
                  ),
                  button(
                      [text('alias')],
                      classes: 'profile-btn',
                      attributes: const {'style': 'padding: 4px 10px; font-size: 11px; background: white; border: 1px solid #ccc; font-weight: bold; border-radius: 4px; cursor: pointer;'},
                      events: {'click': (e) => setState(() => _showAliasInput = true)}
                  ),
                ] else
                // Inline alias compositor input
                  div(
                      attributes: const {'style': 'display: flex; gap: 4px; align-items: center;'},
                      [
                        input(
                            type: InputType.text,
                            attributes: const {
                              'placeholder': 'target handle...',
                              'style': 'padding: 4px 8px; border: 1px solid #ccc; border-radius: 4px; font-size: 11px; width: 110px; height: 26px; box-sizing: border-box;'
                            },
                            events: {
                              'input': (e) {
                                _targetAliasInputText = (e.target as dynamic).value ?? '';
                              }
                            }
                        ),
                        button(
                            [span([text('done')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px;'})],
                            attributes: const {'style': 'border: none; background: transparent; padding: 2px; color: #16a34a; cursor: pointer;'},
                            events: {'click': (e) => _submitAliasRedirect()}
                        ),
                        button(
                            [span([text('close')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px;'})],
                            attributes: const {'style': 'border: none; background: transparent; padding: 2px; color: #ef4444; cursor: pointer;'},
                            events: {'click': (e) => setState(() => _showAliasInput = false)}
                        ),
                      ]
                  )
              ]
          )
        else
          span([text('OK')], attributes: const {'style': 'color: #16a34a; font-weight: bold; font-size: 11px; letter-spacing: 0.5px;'})
      ])
    ]);
  }
}