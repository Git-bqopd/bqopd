import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/unsaved_fanzine_registry.dart';
import './maker_upload_form.dart';

/// Maker Tab content displaying publications and folios.
/// Streams live works using clean repositories instead of direct DB lookups.
class ProfileMakerTab extends StatefulComponent {
  final String targetUserId;
  final bool isMe;
  final bool canSeeDrafts;
  final IUserRepository userRepository;
  final AuthState? authState;
  final String? initialSubTab;
  final ValueChanged<String>? onSubTabChanged;

  const ProfileMakerTab({
    required this.targetUserId,
    required this.isMe,
    required this.canSeeDrafts,
    required this.userRepository,
    this.authState,
    this.initialSubTab,
    this.onSubTabChanged,
    super.key,
  });

  @override
  State<ProfileMakerTab> createState() => _ProfileMakerTabState();
}

class _ProfileMakerTabState extends State<ProfileMakerTab> {
  bool _showDrafts = false;
  bool _showMakerModal = false;
  String _makerModalMode = 'options'; // 'options', 'upload'
  List<Map<String, dynamic>> _userWorks = [];
  StreamSubscription? _worksSub;
  bool _loading = true;

  // Holds the ID of the folio currently queued for deletion
  String? _pendingDeleteId;
  // Holds the shortcode of the folio currently queued for deletion
  String? _pendingDeleteShortcode;

  @override
  void initState() {
    super.initState();
    if (component.initialSubTab == 'drafts') {
      _showDrafts = true;
    } else if (component.initialSubTab == 'published') {
      _showDrafts = false;
    }

    // SERVER PRE-RENDERING GUARD: Defer listener setup to client only
    if (kIsWeb) {
      Future.microtask(() {
        if (mounted) {
          _listenToWorks();
        }
      });
    }
  }

  @override
  void didUpdateComponent(ProfileMakerTab oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.initialSubTab != component.initialSubTab) {
      if (component.initialSubTab == 'drafts') {
        _showDrafts = true;
      } else if (component.initialSubTab == 'published') {
        _showDrafts = false;
      }
    }
    if (oldComponent.targetUserId != component.targetUserId && kIsWeb) {
      _listenToWorks();
    }
  }

  @override
  void dispose() {
    _worksSub?.cancel();
    super.dispose();
  }

  void _selectDraftMode(bool showDrafts) {
    setState(() => _showDrafts = showDrafts);
    if (component.onSubTabChanged != null) {
      component.onSubTabChanged!(showDrafts ? 'drafts' : 'published');
    }
  }

  void _listenToWorks() {
    _worksSub?.cancel();
    setState(() => _loading = true);
    _worksSub = component.userRepository.watchUserWorks(component.targetUserId).listen((works) {
      if (mounted) {
        setState(() {
          _userWorks = works;
          _loading = false;
        });
      }
    });
  }

  DateTime? _parseDateValue(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Map) {
      if (value['__type'] == 'timestamp' && value['iso'] != null) {
        return DateTime.tryParse(value['iso'].toString());
      }
    }
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {}
    return null;
  }

  List<Map<String, dynamic>> get _publishedWorks {
    final list = _userWorks.where((w) => w['isLive'] == true).toList();
    list.sort((a, b) {
      final aTime = _parseDateValue(a['publishedAt'] ?? a['updatedAt'] ?? a['creationDate'] ?? a['timestamp']);
      final bTime = _parseDateValue(b['publishedAt'] ?? b['updatedAt'] ?? b['creationDate'] ?? b['timestamp']);
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime); // Descending (most recent first)
    });
    return list;
  }

  List<Map<String, dynamic>> get _draftWorks {
    final list = _userWorks.where((w) => w['isLive'] != true).toList();
    list.sort((a, b) {
      final aTime = _parseDateValue(a['updatedAt'] ?? a['creationDate'] ?? a['timestamp']);
      final bTime = _parseDateValue(b['updatedAt'] ?? b['creationDate'] ?? b['timestamp']);
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime); // Descending (most recent first)
    });
    return list;
  }

  Future<String> _generateUniqueTempShortcode() async {
    final String? email = component.authState?.user?.email;
    final bool useVanity = email != null && email.trim().toLowerCase() == 'kevin@712liberty.com';

    bool isUnique = false;
    String code = "";
    int retries = 0;

    while (!isUnique && retries < 15) {
      final String candidate = useVanity
          ? ShortcodeGenerator.generateVanityCode()
          : ShortcodeGenerator.generateStandardCode();

      final String codeUpper = candidate.toUpperCase();
      final docRes = await fsGetDoc('shortcodes/$codeUpper');
      final Map<String, dynamic> doc = jsonDecode(docRes);
      final isLocalCollision = UnsavedFanzineRegistry.hasCode(candidate);

      if (doc['exists'] != true && !isLocalCollision) {
        isUnique = true;
        code = candidate;
      }
      retries++;
    }

    if (code.isEmpty) {
      code = 'TEMP_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    }
    return code;
  }

  Future<void> _createFolio() async {
    try {
      final fanzineId = 'folio_${DateTime.now().millisecondsSinceEpoch}';
      final shortCode = await _generateUniqueTempShortcode();

      final newFanzine = Fanzine(
        id: fanzineId,
        title: 'new folio name',
        ownerId: component.targetUserId,
        type: FanzineType.folio,
        isLive: false,
        processingStatus: 'complete',
        shortCode: shortCode,
        twoPage: true,
        hasCover: true,
      );

      UnsavedFanzineRegistry.add(newFanzine, []);
      setState(() => _showMakerModal = false);
      Router.of(context).replace('/$shortCode');
    } catch (e) {
      print("Error creating folio: $e");
    }
  }

  Future<void> _createCalendar() async {
    try {
      final fanzineId = 'calendar_${DateTime.now().millisecondsSinceEpoch}';
      final shortCode = await _generateUniqueTempShortcode();

      final newFanzine = Fanzine(
        id: fanzineId,
        title: 'Convention Calendar 2026',
        ownerId: component.targetUserId,
        type: FanzineType.calendar,
        isLive: false,
        processingStatus: 'complete',
        shortCode: shortCode,
        twoPage: true,
        hasCover: true,
      );

      final page1Id = 'page1_${DateTime.now().millisecondsSinceEpoch}';
      final page2Id = 'page2_${DateTime.now().millisecondsSinceEpoch}';

      final List<FanzinePage> pages = [
        FanzinePage(id: page1Id, pageNumber: 1, templateId: 'calendar_left', status: 'ready'),
        FanzinePage(id: page2Id, pageNumber: 2, templateId: 'calendar_right', status: 'ready'),
      ];

      UnsavedFanzineRegistry.add(newFanzine, pages);
      setState(() => _showMakerModal = false);
      Router.of(context).replace('/$shortCode');
    } catch (e) {
      print("Error creating calendar: $e");
    }
  }

  Component _buildMakerOptionsContent() {
    return div(
      [
        h1([text('maker options')], classes: 'font-bold text-lg text-center mb-6', attributes: const {'style': 'margin-top: 0;'}),
        button(
            [text("single image")],
            classes: 'profile-btn mb-4',
            attributes: const {
              'style': 'width: 100%; height: 40px; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; border: 1px solid #ddd; border-radius: 0px !important; cursor: pointer; background: white; margin-bottom: 16px; text-transform: none;'
            },
            events: {'click': (e) => setState(() => _makerModalMode = 'upload')}
        ),
        button(
            [text("folio")],
            classes: 'profile-btn mb-4',
            attributes: const {
              'style': 'width: 100%; height: 40px; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; border: 1px solid #ddd; border-radius: 0px !important; cursor: pointer; background: white; margin-bottom: 16px; text-transform: none;'
            },
            events: {'click': (e) => _createFolio()}
        ),
        button(
            [text("calendar")],
            classes: 'profile-btn mb-4',
            attributes: const {
              'style': 'width: 100%; height: 40px; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; border: 1px solid #ddd; border-radius: 0px !important; cursor: pointer; background: white; margin-bottom: 16px; text-transform: none;'
            },
            events: {'click': (e) => _createCalendar()}
        ),
      ],
      classes: 'white-sticker p-6 w-full h-full flex flex-col justify-center items-center',
      attributes: const {'style': 'display: flex; flex-direction: column; justify-content: center; align-items: center; padding: 24px; box-sizing: border-box; width: 100%; height: 100%;'},
    );
  }

  Component _buildMakerModalOverlay() {
    final bool isUploadMode = _makerModalMode == 'upload';
    return div(
        [
          if (!isUploadMode)
            div(
                [
                  button(
                      [text('×')],
                      classes: 'modal-close-btn',
                      attributes: const {'style': 'position: absolute; top: 12px; right: 12px; border: none; background: rgba(255,255,255,0.8); border-radius: 50%; width: 32px; height: 32px; display: flex; align-items: center; justify-content: center; cursor: pointer; font-size: 16px; font-weight: bold; z-index: 200;'},
                      events: {'click': (e) => setState(() => _showMakerModal = false)}
                  ),
                  _buildMakerOptionsContent()
                ],
                classes: 'manila-envelope',
                attributes: const {'style': 'max-width: 420px; max-height: 580px; border-radius: 12px; overflow: hidden; position: relative;'}
            )
          else
            div(
                [
                  button(
                      [text('×')],
                      classes: 'modal-close-btn',
                      attributes: const {'style': 'position: absolute; top: 24px; right: 24px; border: none; background: rgba(255,255,255,0.9); border-radius: 50%; width: 32px; height: 32px; display: flex; align-items: center; justify-content: center; cursor: pointer; font-size: 16px; font-weight: bold; z-index: 1000;'},
                      events: {'click': (e) => setState(() => _showMakerModal = false)}
                  ),
                  MakerUploadForm(
                      targetUserId: component.targetUserId,
                      authState: component.authState,
                      onBack: () => setState(() => _makerModalMode = 'options'),
                      onUploadComplete: (shortcode) {
                        setState(() => _showMakerModal = false);
                        Router.of(context).replace('/$shortcode');
                      }
                  )
                ],
                classes: 'upload-list-wrapper',
                attributes: const {'style': 'width: 100%; max-width: 500px; max-height: 90vh; display: flex; flex-direction: column; gap: 16px; box-sizing: border-box; padding: 16px; position: relative; overflow-y: auto;'}
            )
        ],
        classes: 'global-modal-overlay',
        attributes: const {'style': 'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.65); z-index: 10000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(6px);'}
    );
  }

  /// Renders a design-consistent modal overlay to confirm destructive folio deletions
  Component _buildDeleteConfirmModal() {
    return div(
        classes: 'global-modal-overlay',
        attributes: const {'style': 'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.65); z-index: 10000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(6px);'},
        [
          div(
              classes: 'white-sticker p-6',
              attributes: const {'style': 'max-width: 400px; padding: 24px; border-radius: 12px; display: flex; flex-direction: column; gap: 16px; background: white; text-align: left; box-sizing: border-box;'},
              [
                h3([text("Delete Folio?")], attributes: const {'style': 'margin-top: 0; font-size: 18px; font-weight: bold; color: black;'}),
                p([text("Are you sure you want to delete this folio forever? This will remove all associated pages and database configurations.")], attributes: const {'style': 'font-size: 13.5px; color: #555; line-height: 1.5; margin: 0;'}),
                div(
                    attributes: const {'style': 'display: flex; gap: 12px; justify-content: flex-end; margin-top: 8px;'},
                    [
                      button(
                          [text("cancel")],
                          classes: 'profile-btn',
                          attributes: const {'style': 'padding: 8px 16px; font-size: 12px; border: 1px solid #ddd; background: white; cursor: pointer; height: 32px;'},
                          events: {'click': (e) => setState(() {
                            _pendingDeleteId = null;
                            _pendingDeleteShortcode = null;
                          })}
                      ),
                      button(
                          [text("delete")],
                          classes: 'profile-btn',
                          attributes: const {'style': 'padding: 8px 16px; font-size: 12px; border: 1px solid #ff5252; background: #ff5252; color: white; cursor: pointer; height: 32px;'},
                          events: {'click': (e) async {
                            final fid = _pendingDeleteId;
                            final sc = _pendingDeleteShortcode;
                            setState(() {
                              _pendingDeleteId = null;
                              _pendingDeleteShortcode = null;
                            });

                            if (fid != null) {
                              await fsDeleteDoc('fanzines/$fid');
                              if (sc != null && sc.isNotEmpty) {
                                await fsDeleteDoc('shortcodes/${sc.toUpperCase()}');
                              }
                            }
                          }}
                      )
                    ]
                )
              ]
          )
        ]
    );
  }

  Component _buildWorksGridSchema(List<Map<String, dynamic>> works) {
    if (_loading) {
      return div(
        [p([text('Loading maker assets...')])],
        classes: 'p-16 text-center text-gray italic text-sm',
      );
    }

    if (works.isEmpty) {
      return div(
        [
          span([text('library_books')], classes: 'material-symbols-outlined text-gray-300', attributes: const {'style': 'font-size: 48px;'}),
          p([text('No items available in this category.')], classes: 'text-sm text-gray italic mt-4', attributes: const {'style': 'margin-top: 16px;'})
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

  Component _buildWorkGridTile(Map<String, dynamic> w) {
    final String fanzineId = w['id'] ?? '';
    final String title = w['title'] ?? 'Untitled Fanzine';
    final String volume = w['volume'] ?? '';
    final String issue = w['issue'] ?? '';
    final String wholeNumber = w['wholeNumber'] ?? '';
    final String shortCode = w['shortCode'] ?? '';

    String displaySuffix = '';
    if (volume.isNotEmpty) displaySuffix += " Vol. $volume";
    if (issue.isNotEmpty) displaySuffix += " No. $issue";
    if (wholeNumber.isNotEmpty) displaySuffix += " ($wholeNumber)";

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
                }),
                // Display delete action button only if the viewer owns this folio
                if (component.isMe)
                  button(
                      [span([text('delete')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px;'})],
                      attributes: const {
                        'style': 'position: absolute; top: 8px; right: 8px; border: none; background: rgba(0,0,0,0.7); border-radius: 50%; width: 24px; height: 24px; display: flex; align-items: center; justify-content: center; cursor: pointer; color: #ff5252; border: 1px solid rgba(255,255,255,0.4); z-index: 10;'
                      },
                      events: {
                        'click': (dynamic e) {
                          // Prevent triggering the link navigation of the surrounding <a> card element
                          try {
                            e.preventDefault();
                            e.stopPropagation();
                          } catch (_) {}
                          setState(() {
                            _pendingDeleteId = fanzineId;
                            _pendingDeleteShortcode = shortCode;
                          });
                        }
                      }
                  )
              ],
              attributes: {
                'style': 'aspect-ratio: 5/8; background-color: #f3f4f6; background-image: url("$coverUrl"); background-size: cover; background-position: center; position: relative;'
              }
          ),
          div(
              [
                span([text(title)], attributes: const {'style': 'font-size: 13px; font-weight: bold; color: black; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'}),
                if (displaySuffix.isNotEmpty)
                  span([text(displaySuffix)], attributes: const {'style': 'font-size: 11px; color: #666;'})
              ],
              attributes: const {'style': 'padding: 12px; display: flex; flex-direction: column; gap: 4px;'}
          )
        ],
        href: '/$codeKey',
        classes: 'bg-white rounded-lg shadow-sm overflow-hidden transition-all',
        attributes: const {'style': 'display: flex; flex-decoration: none; flex-direction: column; border: 1px solid #ddd; cursor: pointer; text-decoration: none; position: relative;'}
    );
  }

  @override
  Component build(BuildContext context) {
    if (!kIsWeb) {
      return div(
        [p([text('Loading maker assets...')])],
        classes: 'p-16 text-center text-gray italic text-sm',
      );
    }

    return div(
      [
        // Toolbar switch published / drafts
        div(
            [
              div(
                  [
                    if (component.isMe) ...[
                      button(
                          [text("make")],
                          classes: 'profile-btn',
                          attributes: const {'style': 'width: 100px; height: 28px; display: inline-flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; text-align: center; border: 1px solid #ddd; border-radius: 0px !important; cursor: pointer; background: white;'},
                          events: {'click': (e) => setState(() {
                            _showMakerModal = true;
                            _makerModalMode = 'options';
                          })}
                      ),
                      span([], attributes: const {'style': 'display: inline-block; width: 12px;'}),
                    ],
                    span(
                        [text("published")],
                        classes: !_showDrafts ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer',
                        events: {
                          'click': (e) => _selectDraftMode(false)
                        }
                    ),
                    if (component.canSeeDrafts) ...[
                      span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
                      span(
                          [text("drafts")],
                          classes: _showDrafts ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer',
                          events: {
                            'click': (e) => _selectDraftMode(true)
                          }
                      ),
                    ]
                  ],
                  attributes: const {'style': 'display: flex; align-items: center; justify-content: center; width: 100%;'}
              )
            ],
            classes: 'bg-white rounded-md p-4 shadow-sm flex-row items-center justify-center',
            attributes: const {'style': 'display: flex; flex-wrap: wrap; gap: 12px; box-sizing: border-box; width: 100%; margin-bottom: 16px;'}
        ),

        _buildWorksGridSchema(_showDrafts ? _draftWorks : _publishedWorks),

        if (_showMakerModal)
          _buildMakerModalOverlay(),

        if (_pendingDeleteId != null)
          _buildDeleteConfirmModal()
      ],
    );
  }
}