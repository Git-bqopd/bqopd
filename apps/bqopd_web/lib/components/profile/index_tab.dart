import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/firebase_mocks.dart';

/// Module displaying mentions list grids and user comments.
class ProfileIndexTab extends StatefulComponent {
  final String targetUserId;
  final String profileName;
  final IUserRepository userRepository;

  const ProfileIndexTab({
    required this.targetUserId,
    required this.profileName,
    required this.userRepository,
    super.key,
  });

  @override
  State<ProfileIndexTab> createState() => _ProfileIndexTabState();
}

class _ProfileIndexTabState extends State<ProfileIndexTab> {
  int _activeSubTab = 0; // 0: mentions, 1: comments

  List<Map<String, dynamic>> _mentions = [];
  bool _loadingMentions = true;
  StreamSubscription? _mentionsSub;

  List<Map<String, dynamic>> _comments = [];
  bool _loadingComments = true;
  FirebaseSubscription? _commentsSub;

  @override
  void initState() {
    super.initState();

    // SERVER PRE-RENDERING GUARD: Defer listener setup to client only
    if (kIsWeb) {
      Future.microtask(() {
        if (mounted) {
          _listenToMentions();
          _listenToComments();
        }
      });
    }
  }

  @override
  void didUpdateComponent(ProfileIndexTab oldComponent) {
    super.didUpdateComponent(oldComponent);
    if ((oldComponent.targetUserId != component.targetUserId || oldComponent.profileName != component.profileName) && kIsWeb) {
      _listenToMentions();
      _listenToComments();
    }
  }

  @override
  void dispose() {
    _mentionsSub?.cancel();
    _commentsSub?.callAsFunction();
    super.dispose();
  }

  void _listenToMentions() {
    _mentionsSub?.cancel();
    setState(() => _loadingMentions = true);

    _mentionsSub = component.userRepository.watchUserMentions(component.targetUserId).listen((mentions) {
      if (mounted) {
        setState(() {
          _mentions = mentions;
          _loadingMentions = false;
        });
      }
    });
  }

  void _listenToComments() {
    _commentsSub?.callAsFunction();
    _commentsSub = null;
    setState(() => _loadingComments = true);

    _commentsSub = fsListenQuery('artifacts/bqopd/public/data/comments', 'userId', '==', jsonEncode(component.targetUserId), '', false, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        final list = decoded.map((d) {
          final data = restoreTimestamps(d['data'] as Map<String, dynamic>);
          data['_id'] = d['id'];
          return data;
        }).toList();

        list.sort((a, b) {
          final DateTime? tA = a['createdAt'] as DateTime?;
          final DateTime? tB = b['createdAt'] as DateTime?;
          if (tA == null) return 1;
          if (tB == null) return -1;
          return tB.compareTo(tA);
        });

        if (mounted) {
          setState(() {
            _comments = list;
            _loadingComments = false;
          });
        }
      } catch (e) {
        print("Error parsing comments inside ProfileIndexTab: $e");
        if (mounted) setState(() => _loadingComments = false);
      }
    });
  }

  Component _buildWorksGridSchema() {
    if (_loadingMentions) {
      return div(
        [p([text('Loading mentions...')])],
        classes: 'p-16 text-center text-gray italic text-sm',
      );
    }

    if (_mentions.isEmpty) {
      return div(
        [
          span([text('library_books')], classes: 'material-symbols-outlined text-gray-300', attributes: const {'style': 'font-size: 48px;'}),
          p([text('No mentions available yet.')], classes: 'text-sm text-gray italic mt-4', attributes: const {'style': 'margin-top: 16px;'})
        ],
        classes: 'bg-white rounded-lg p-16 shadow-sm text-center',
      );
    }
    return div(
        [
          for (var w in _mentions)
            MentionsWorkGridTile(fanzineData: w, key: ValueKey('mentions_tile_${w['id']}'))
        ],
        attributes: const {
          'style': 'display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 16px; width: 100%; box-sizing: border-box;'
        }
    );
  }

  Component _buildCommentsListSubView() {
    if (_loadingComments) {
      return div(
        [p([text('Loading thoughts...')])],
        classes: 'p-16 text-center text-gray italic text-sm',
      );
    }

    if (_comments.isEmpty) {
      return div(
        [
          span([text('chat_bubble')], classes: 'material-symbols-outlined text-gray-300', attributes: const {'style': 'font-size: 48px;'}),
          p([text('No comments posted by this profile.')], classes: 'text-sm text-gray italic mt-4', attributes: const {'style': 'margin-top: 16px;'})
        ],
        classes: 'bg-white rounded-lg p-16 shadow-sm text-center',
      );
    }
    return div(
        [
          h2([text("COMMENTS POSTED")], classes: 'font-bold text-sm text-gray mb-4', attributes: const {'style': 'margin-top: 0; margin-bottom: 16px;'}),
          for (var c in _comments)
            div(
                [
                  div(
                      [
                        span([text(c['createdAt'] is DateTime ? (c['createdAt'] as DateTime).toIso8601String().split('T').first : '')]),
                        if (c['context'] != null && c['context']['fanzineTitle'] != null)
                          span([text("via ${c['context']['fanzineTitle']}")], attributes: const {'style': 'font-style: italic;'})
                      ],
                      attributes: const {'style': 'display: flex; align-items: center; justify-content: space-between; font-size: 11px; color: #888; margin-bottom: 8px;'}
                  ),
                  p([text(c['text'] ?? '')], attributes: const {'style': 'border-bottom: 1px solid #f0f0f0; padding-bottom: 16px; margin-bottom: 16px; margin-top: 0;'})
                ],
                attributes: const {'style': 'border-bottom: 1px solid #f0f0f0; padding-bottom: 16px; margin-bottom: 16px; display: flex; flex-direction: column;'}
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
        [p([text('Loading index...')])],
        classes: 'p-16 text-center text-gray italic text-sm',
      );
    }

    final currentUid = getCurrentUserId();
    final bool isMe = currentUid != null && currentUid == component.targetUserId;

    final bool showMentions = isMe || _mentions.isNotEmpty;
    final bool showComments = isMe || _comments.isNotEmpty;

    if (!showMentions && !showComments) {
      return div([]);
    }

    // Safely auto-route if one of the sub-tabs is hidden
    int activeSubTab = _activeSubTab;
    if (!showMentions) {
      activeSubTab = 1;
    } else if (!showComments) {
      activeSubTab = 0;
    }

    final List<Component> subTabSpans = [];
    if (showMentions) {
      subTabSpans.add(
          span(
              [text("mentions (${_mentions.length})")],
              classes: activeSubTab == 0 ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer',
              events: {
                'click': (e) => setState(() => _activeSubTab = 0)
              }
          )
      );
    }
    if (showMentions && showComments) {
      subTabSpans.add(span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}));
    }
    if (showComments) {
      subTabSpans.add(
          span(
              [text("comments (${_comments.length})")],
              classes: activeSubTab == 1 ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer',
              events: {
                'click': (e) => setState(() => _activeSubTab = 1)
              }
          )
      );
    }

    return div(
      [
        // Subtab row selector (always visible if at least one sub-tab is qualified)
        if (subTabSpans.isNotEmpty)
          div(
              subTabSpans,
              classes: 'bg-white rounded-md p-4 shadow-sm',
              attributes: const {'style': 'display: flex; justify-content: center; align-items: center; box-sizing: border-box; width: 100%; margin-bottom: 16px;'}
          ),

        if (activeSubTab == 0 && showMentions)
          _buildWorksGridSchema()
        else if (activeSubTab == 1 && showComments)
          _buildCommentsListSubView()
        else
          div([])
      ],
    );
  }
}

/// Dynamic, self-resolving grid tile for showing mentioned fanzines.
/// Seamlessly loads the cover image (Page 1) dynamically from pages or images if not cached in gridCoverImage.
class MentionsWorkGridTile extends StatefulComponent {
  final Map<String, dynamic> fanzineData;

  const MentionsWorkGridTile({
    required this.fanzineData,
    super.key,
  });

  @override
  State<MentionsWorkGridTile> createState() => _MentionsWorkGridTileState();
}

class _MentionsWorkGridTileState extends State<MentionsWorkGridTile> {
  String? _resolvedCoverUrl;
  int _pagesCount = 0;

  @override
  void initState() {
    super.initState();
    _resolveThumbnail();
  }

  @override
  void didUpdateComponent(MentionsWorkGridTile oldComponent) {
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
      print("[MentionsWorkGridTile] Error resolving cover thumbnail: $e");
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
    final String volume = component.fanzineData['volume'] ?? '';
    final String issue = component.fanzineData['issue'] ?? '';
    final String wholeNumber = component.fanzineData['wholeNumber'] ?? '';

    String displaySuffix = '';
    if (volume.isNotEmpty) displaySuffix += " Vol. $volume";
    if (issue.isNotEmpty) displaySuffix += " No. $issue";
    if (wholeNumber.isNotEmpty) displaySuffix += " ($wholeNumber)";

    final String codeKey = component.fanzineData['shortCode'] ?? fanzineId;

    return a(
        [
          div(
              [], // Removed status/type badge to keep the cover preview completely clean as requested!
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
        attributes: const {'style': 'display: flex; flex-direction: column; border: 1px solid #ddd; cursor: pointer; text-decoration: none;'}
    );
  }
}