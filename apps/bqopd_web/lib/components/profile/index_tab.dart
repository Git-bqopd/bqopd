import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/firebase_mocks.dart';
import '../../utils/unsaved_fanzine_registry.dart';
import '../../repositories/repositories.dart';

/// Module displaying mentions list grids and user comments.
class ProfileIndexTab extends StatefulComponent {
  final String targetUserId;
  final String profileName;
  final IUserRepository userRepository;
  final String? initialSubTab;
  final ValueChanged<String>? onSubTabChanged;

  const ProfileIndexTab({
    required this.targetUserId,
    required this.profileName,
    required this.userRepository,
    this.initialSubTab,
    this.onSubTabChanged,
    super.key,
  });

  @override
  State<ProfileIndexTab> createState() => _ProfileIndexTabState();
}

class _ProfileIndexTabState extends State<ProfileIndexTab> {
  @override
  ProfileIndexTab get component => super.component as ProfileIndexTab;

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
    _resolveActiveSubTab();
    if (kIsWeb) {
      Future.microtask(() {
        if (mounted) {
          _listenToMentions();
          _listenToComments();
        }
      });
    }
  }

  void _resolveActiveSubTab() {
    if (component.initialSubTab != null) {
      if (component.initialSubTab == 'comments') {
        _activeSubTab = 1;
      } else if (component.initialSubTab == 'mentions') {
        _activeSubTab = 0;
      }
    }
  }

  String _getSubTabName(int index) {
    return index == 1 ? 'comments' : 'mentions';
  }

  void _selectSubTab(int index) {
    setState(() => _activeSubTab = index);
    if (component.onSubTabChanged != null) {
      component.onSubTabChanged!(_getSubTabName(index));
    }
  }

  @override
  void didUpdateComponent(ProfileIndexTab oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.initialSubTab != component.initialSubTab) {
      _resolveActiveSubTab();
    }
    if ((oldComponent.targetUserId != component.targetUserId ||
        oldComponent.profileName != component.profileName) &&
        kIsWeb) {
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
    _mentionsSub = component.userRepository
        .watchUserMentions(component.targetUserId)
        .listen((mentions) {
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
    _commentsSub = fsListenQuery(
      'artifacts/bqopd/public/data/comments',
      'userId',
      '==',
      jsonEncode(component.targetUserId),
      '',
      false,
          (String jsonStr) {
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
      },
    );
  }

  Component _buildWorksGridSchema() {
    if (_loadingMentions) {
      return div(
        [p([Component.text('Loading mentions...')])],
        classes: 'p-16 text-center text-gray italic text-sm',
      );
    }
    if (_mentions.isEmpty) {
      return div(
        [
          span(
            [Component.text('library_books')],
            classes: 'material-symbols-outlined text-gray-300',
            attributes: const {'style': 'font-size: 48px;'},
          ),
          p(
            [Component.text('No mentions available yet.')],
            classes: 'text-sm text-gray italic mt-4',
            attributes: const {'style': 'margin-top: 16px;'},
          )
        ],
        classes: 'bg-white rounded-lg p-16 shadow-sm text-center',
      );
    }
    return div(
      [
        for (var w in _mentions)
          MentionsWorkGridTile(
            fanzineData: w,
            key: ValueKey('mentions_tile_${w['id']}'),
          )
      ],
      attributes: const {
        'style':
        'display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 16px; width: 100%; box-sizing: border-box;'
      },
    );
  }

  Component _buildCommentsListSubView() {
    if (_loadingComments) {
      return div(
        [p([Component.text('Loading thoughts...')])],
        classes: 'p-16 text-center text-gray italic text-sm',
      );
    }
    if (_comments.isEmpty) {
      return div(
        [
          span(
            [Component.text('chat_bubble')],
            classes: 'material-symbols-outlined text-gray-300',
            attributes: const {'style': 'font-size: 48px;'},
          ),
          p(
            [Component.text('No comments posted by this profile.')],
            classes: 'text-sm text-gray italic mt-4',
            attributes: const {'style': 'margin-top: 16px;'},
          )
        ],
        classes: 'bg-white rounded-lg p-16 shadow-sm text-center',
      );
    }
    return div(
      [
        h2(
          [Component.text("COMMENTS POSTED")],
          classes: 'font-bold text-sm text-gray mb-4',
          attributes: const {
            'style': 'margin-top: 0; margin-bottom: 16px;'
          },
        ),
        for (var c in _comments)
          ProfileCommentItem(
            data: c,
            key: ValueKey(c['_id'] ?? ''),
          )
      ],
      classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-4',
      attributes: const {
        'style':
        'display: flex; flex-direction: column; gap: 8px; padding: 24px; background: white;'
      },
    );
  }

  @override
  Component build(BuildContext context) {
    if (!kIsWeb) {
      return div(
        [p([Component.text('Loading index...')])],
        classes: 'p-16 text-center text-gray italic text-sm',
      );
    }
    final currentUid = getCurrentUserId();
    final bool isMe =
        currentUid != null && currentUid == component.targetUserId;
    final bool showMentions = isMe || _mentions.isNotEmpty;
    final bool showComments = isMe || _comments.isNotEmpty;

    if (!showMentions && !showComments) {
      return div([]);
    }

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
          [Component.text("mentions (${_mentions.length})")],
          classes: activeSubTab == 0
              ? 'text-xs font-bold text-black border-b border-black cursor-pointer'
              : 'text-xs text-gray cursor-pointer',
          events: {
            'click': (e) => _selectSubTab(0),
          },
        ),
      );
    }
    if (showMentions && showComments) {
      subTabSpans.add(
        span(
          [Component.text('|')],
          classes: 'text-xs text-gray',
          attributes: const {'style': 'display: inline-block; margin: 0 8px;'},
        ),
      );
    }
    if (showComments) {
      subTabSpans.add(
        span(
          [Component.text("comments (${_comments.length})")],
          classes: activeSubTab == 1
              ? 'text-xs font-bold text-black border-b border-black cursor-pointer'
              : 'text-xs text-gray cursor-pointer',
          events: {
            'click': (e) => _selectSubTab(1),
          },
        ),
      );
    }

    return div(
      [
        if (subTabSpans.isNotEmpty)
          div(
            subTabSpans,
            classes: 'bg-white rounded-md p-4 shadow-sm',
            attributes: const {
              'style':
              'display: flex; justify-content: center; align-items: center; box-sizing: border-box; width: 100%; margin-bottom: 16px;'
            },
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

/// Comment item rendering fanzine cover thumbnail, title, optional @username,
/// submission timestamp, interactive like toggle, and comment text.
class ProfileCommentItem extends StatefulComponent {
  final Map<String, dynamic> data;

  const ProfileCommentItem({required this.data, super.key});

  @override
  State<ProfileCommentItem> createState() => _ProfileCommentItemState();
}

class _ProfileCommentItemState extends State<ProfileCommentItem> {
  @override
  ProfileCommentItem get component => super.component as ProfileCommentItem;

  String _fanzineTitle = '';
  String? _fanzineUsername;
  String? _shortCode;
  String? _fanzineId;
  String? _coverUrl;
  bool _loadingFanzine = true;

  bool _isLiked = false;
  int _likeCount = 0;
  StreamSubscription? _likeSub;
  final IEngagementRepository _engagementRepo = createEngagementRepository();

  @override
  void initState() {
    super.initState();
    _likeCount = component.data['likeCount'] ?? 0;
    _fanzineTitle = component.data['context']?['fanzineTitle'] ?? '';
    _fanzineId = component.data['context']?['fanzineId'];

    if (kIsWeb) {
      _loadFanzineInfo();
      _listenToLikes();
    } else {
      _loadingFanzine = false;
    }
  }

  @override
  void didUpdateComponent(ProfileCommentItem oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.data['_id'] != component.data['_id']) {
      _likeCount = component.data['likeCount'] ?? 0;
      _fanzineTitle = component.data['context']?['fanzineTitle'] ?? '';
      _fanzineId = component.data['context']?['fanzineId'];
      _loadFanzineInfo();
      _listenToLikes();
    }
  }

  @override
  void dispose() {
    _likeSub?.cancel();
    super.dispose();
  }

  void _listenToLikes() {
    final commentId = component.data['_id'];
    if (commentId == null) return;
    _likeSub?.cancel();
    _likeSub = _engagementRepo.isCommentLiked(commentId).listen((isLiked) {
      if (mounted) {
        setState(() => _isLiked = isLiked);
      }
    });
  }

  void _handleLike() {
    final commentId = component.data['_id'];
    if (getCurrentUserId() == null || commentId == null) {
      GlobalModalBus.show();
      return;
    }
    final currentStatus = _isLiked;
    setState(() {
      _isLiked = !currentStatus;
      _likeCount += (!currentStatus) ? 1 : -1;
      if (_likeCount < 0) _likeCount = 0;
    });
    _engagementRepo.toggleCommentLike(commentId, currentStatus);
  }

  Future<void> _loadFanzineInfo() async {
    String? fzId = component.data['context']?['fanzineId'] as String?;
    final String initialTitle =
        component.data['context']?['fanzineTitle']?.toString() ?? '';
    final String? imageId = component.data['contentId']?.toString();

    // 1. Check local unsaved memory registry first
    if (fzId != null &&
        fzId.isNotEmpty &&
        UnsavedFanzineRegistry.fanzines.containsKey(fzId)) {
      final fz = UnsavedFanzineRegistry.fanzines[fzId]!;
      final pgs = UnsavedFanzineRegistry.pages[fzId] ?? [];
      String? cover =
      pgs.isNotEmpty ? (pgs.first.gridUrl ?? pgs.first.imageUrl) : null;
      if (mounted) {
        setState(() {
          _fanzineId = fz.id;
          _fanzineTitle = fz.title.isNotEmpty
              ? fz.title
              : (initialTitle.isNotEmpty ? initialTitle : 'Untitled Fanzine');
          _shortCode = fz.shortCode;
          _coverUrl = cover;
          _loadingFanzine = false;
        });
      }
      return;
    }

    // 2. Fallback to image doc to resolve parent folio if fzId is missing from context
    if ((fzId == null || fzId.isEmpty) && imageId != null && imageId.isNotEmpty) {
      try {
        final imgRes = await fsGetDoc('images/$imageId');
        final imgDoc = jsonDecode(imgRes);
        if (imgDoc['exists'] == true) {
          final imgData = imgDoc['data'] as Map<String, dynamic>? ?? {};
          final folioContext = imgData['folioContext'] as String?;
          if (folioContext != null && folioContext.isNotEmpty) {
            fzId = folioContext;
          } else {
            final List usedIn = imgData['usedInFanzines'] ?? [];
            if (usedIn.isNotEmpty) fzId = usedIn.first.toString();
          }
          if (_coverUrl == null || _coverUrl!.isEmpty) {
            _coverUrl = imgData['gridUrl'] ?? imgData['fileUrl'];
          }
        }
      } catch (_) {}
    }

    // 3. Query parent fanzine doc for title, cover, and username
    if (fzId != null && fzId.isNotEmpty) {
      try {
        final fzRes = await fsGetDoc('fanzines/$fzId');
        final fzDoc = jsonDecode(fzRes);
        if (fzDoc['exists'] == true) {
          final fzData = fzDoc['data'] as Map<String, dynamic>? ?? {};
          final String title = fzData['title']?.toString() ?? initialTitle;
          final String? shortCode = fzData['shortCode']?.toString();
          final String? username =
          (fzData['username'] ?? fzData['handle'])?.toString();
          String? cover = fzData['gridCoverImage']?.toString();

          // Resolve first page cover if gridCoverImage is unassigned
          if (cover == null || cover.isEmpty) {
            final pRes = await fsQuery('fanzines/$fzId/pages', '', '', '', 'pageNumber');
            final List pList = jsonDecode(pRes);
            if (pList.isNotEmpty) {
              final firstP = pList.first['data'] as Map<String, dynamic>? ?? {};
              cover = firstP['gridUrl'] ?? firstP['imageUrl'];
            }
          }

          if (mounted) {
            setState(() {
              _fanzineId = fzId;
              _fanzineTitle = title.isNotEmpty ? title : 'Untitled Fanzine';
              _fanzineUsername = username;
              _shortCode = shortCode;
              _coverUrl ??= cover;
              _loadingFanzine = false;
            });
            return;
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        if (_fanzineTitle.isEmpty) {
          _fanzineTitle =
          initialTitle.isNotEmpty ? initialTitle : 'Archival Work';
        }
        _loadingFanzine = false;
      });
    }
  }

  Component _buildCoverThumbnail(String? targetHref) {
    final coverContainer = div(
      [
        if (_coverUrl != null && _coverUrl!.isNotEmpty)
          img(
            src: _coverUrl!,
            attributes: const {
              'style':
              'width: 100%; height: 100%; object-fit: cover; display: block;'
            },
          )
        else if (_loadingFanzine)
          div(
            [],
            classes: 'shimmer-bg',
            attributes: const {'style': 'width: 100%; height: 100%;'},
          )
        else
          span(
            [Component.text('menu_book')],
            classes: 'material-symbols-outlined text-gray-400',
            attributes: const {
              'style': 'font-size: 20px; color: #9ca3af;'
            },
          )
      ],
      classes: 'fanzine-cover-container',
      attributes: const {
        'style':
        'width: 38px; height: 60px; aspect-ratio: 5 / 8; border-radius: 4px; overflow: hidden; background-color: #f3f4f6; border: 1px solid #e2e8f0; flex-shrink: 0; display: flex; align-items: center; justify-content: center; box-shadow: 0 1px 3px rgba(0,0,0,0.08);'
      },
    );

    if (targetHref != null && targetHref.isNotEmpty) {
      return a(
        [coverContainer],
        href: targetHref,
        attributes: const {
          'style': 'text-decoration: none; flex-shrink: 0; display: block;'
        },
      );
    }
    return coverContainer;
  }

  @override
  Component build(BuildContext context) {
    final String textContent = component.data['text'] ?? '';
    final String? codeKey = _shortCode ?? _fanzineId;
    final String? targetHref =
    codeKey != null && codeKey.isNotEmpty ? '/$codeKey' : null;

    String dateStr = '';
    final createdAt = component.data['createdAt'];
    if (createdAt is DateTime) {
      dateStr =
      '${createdAt.month.toString().padLeft(2, '0')}.${createdAt.day.toString().padLeft(2, '0')}.${createdAt.year.toString().substring(2)}';
    }

    return div(
      [
        // Left: 5:8 Fanzine Cover Thumbnail
        _buildCoverThumbnail(targetHref),

        // Right: Content Column
        div(
          [
            // Top Row: Title, Optional Handle, Timestamp, and Like Button
            div(
              [
                div(
                  [
                    div(
                      [
                        if (targetHref != null)
                          a(
                            [Component.text(_fanzineTitle)],
                            href: targetHref,
                            classes:
                            'font-bold text-sm text-black hover:underline',
                            attributes: const {
                              'style':
                              'font-weight: bold; font-size: 14px; color: black; text-decoration: none;'
                            },
                          )
                        else
                          span(
                            [Component.text(_fanzineTitle)],
                            classes: 'font-bold text-sm text-black',
                            attributes: const {
                              'style':
                              'font-weight: bold; font-size: 14px; color: black;'
                            },
                          ),
                        if (_fanzineUsername != null &&
                            _fanzineUsername!.isNotEmpty)
                          span(
                            [Component.text('@$_fanzineUsername')],
                            classes: 'text-gray-500 text-xs',
                            attributes: const {
                              'style': 'color: #6b7280; font-size: 12px;'
                            },
                          ),
                      ],
                      classes: 'flex-row items-center gap-1.5',
                      attributes: const {
                        'style':
                        'display: flex; flex-direction: row; align-items: center; gap: 6px; flex-wrap: wrap;'
                      },
                    ),
                    if (dateStr.isNotEmpty)
                      span(
                        [Component.text(dateStr)],
                        classes: 'text-gray-400 text-xs mt-0.5',
                        attributes: const {
                          'style':
                          'color: #9ca3af; font-size: 11px; margin-top: 2px;'
                        },
                      ),
                  ],
                  classes: 'flex-col',
                  attributes: const {
                    'style': 'display: flex; flex-direction: column;'
                  },
                ),

                // Interactive Like / Heart Button
                button(
                  [
                    span(
                      [Component.text(_likeCount > 0 ? '$_likeCount' : '')],
                      classes:
                      'text-xs font-bold ${_isLiked ? 'text-red-500' : 'text-gray-400'}',
                      attributes: {
                        'style':
                        'font-size: 11px; font-weight: bold; color: ${_isLiked ? "#ef4444" : "#9ca3af"};'
                      },
                    ),
                    span(
                      [Component.text('favorite')],
                      classes:
                      'material-symbols-outlined text-sm ${_isLiked ? 'text-red-500' : 'text-gray-300'}',
                      attributes: {
                        'style':
                        'font-size: 16px; color: ${_isLiked ? "#ef4444" : "#d1d5db"}; font-variation-settings: "FILL" ${_isLiked ? 1 : 0};'
                      },
                    ),
                  ],
                  classes:
                  'flex-row items-center gap-1 bg-transparent border-none cursor-pointer group p-1 rounded hover:bg-gray-50',
                  attributes: const {
                    'type': 'button',
                    'style':
                    'display: inline-flex; align-items: center; gap: 4px; border: none; background: transparent; cursor: pointer; padding: 4px;'
                  },
                  events: {'click': (e) => _handleLike()},
                ),
              ],
              classes: 'flex-row justify-between items-start',
              attributes: const {
                'style':
                'display: flex; flex-direction: row; justify-content: space-between; align-items: flex-start;'
              },
            ),

            // Comment text
            p(
              [Component.text(textContent)],
              classes: 'text-sm text-gray-800 mt-2 leading-relaxed',
              attributes: const {
                'style':
                'margin: 8px 0 0 0; font-size: 13.5px; color: #1f2937; line-height: 1.5; text-align: left; white-space: pre-wrap; word-break: break-word;'
              },
            )
          ],
          classes: 'flex-1 flex-col',
          attributes: const {
            'style':
            'flex: 1; display: flex; flex-direction: column; overflow: hidden;'
          },
        )
      ],
      classes: 'flex-row gap-3 py-4 border-b border-gray-100 items-start',
      attributes: const {
        'style':
        'display: flex; flex-direction: row; gap: 14px; align-items: flex-start; padding: 14px 0; border-bottom: 1px solid #f0f0f0; width: 100%; box-sizing: border-box;'
      },
    );
  }
}

/// Dynamic, self-resolving grid tile for showing mentioned fanzines.
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
  @override
  MentionsWorkGridTile get component => super.component as MentionsWorkGridTile;

  String? _resolvedCoverUrl;

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
      final pagesRes = await fsQuery(
          'fanzines/$fanzineId/pages', '', '', '', 'pageNumber');
      final List decodedPages = jsonDecode(pagesRes);
      if (decodedPages.isNotEmpty) {
        final firstPage = decodedPages.firstWhere(
                (p) => p['data']['pageNumber'] == 1,
            orElse: () => decodedPages.first);
        final rawData = firstPage['data'];
        final Map<String, dynamic> data =
        rawData is Map ? Map<String, dynamic>.from(rawData) : {};
        final url =
            data['gridUrl'] ?? data['thumbnailUrl'] ?? data['imageUrl'];
        if (url != null && url.toString().isNotEmpty) {
          if (mounted) {
            setState(() {
              _resolvedCoverUrl = url.toString();
            });
          }
          return;
        }
      }

      final imagesRes = await fsQuery(
          'images', 'folioContext', '==', jsonEncode(fanzineId), '');
      final List decodedImages = jsonDecode(imagesRes);
      if (decodedImages.isNotEmpty) {
        decodedImages.sort((a, b) {
          final aT = a['data']?['timestamp'] ?? 0;
          final bT = b['data']?['timestamp'] ?? 0;
          return bT.toString().compareTo(aT.toString());
        });
        final firstImgRaw = decodedImages.first['data'];
        final Map<String, dynamic> firstImg = firstImgRaw is Map
            ? Map<String, dynamic>.from(firstImgRaw)
            : {};
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
    final String coverUrl = _resolvedCoverUrl ??
        'https://placehold.co/450x720/png?text=Loading...';
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
          [],
          attributes: {
            'style':
            'aspect-ratio: 5/8; background-color: #f3f4f6; background-image: url("$coverUrl"); background-size: cover; background-position: center; position: relative;'
          },
        ),
        div(
          [
            span(
              [Component.text(title)],
              attributes: const {
                'style':
                'font-size: 13px; font-weight: bold; color: black; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'
              },
            ),
            if (displaySuffix.isNotEmpty)
              span(
                [Component.text(displaySuffix)],
                attributes: const {'style': 'font-size: 11px; color: #666;'},
              )
          ],
          attributes: const {
            'style': 'padding: 12px; display: flex; flex-direction: column; gap: 4px;'
          },
        )
      ],
      href: '/$codeKey',
      classes: 'bg-white rounded-lg shadow-sm overflow-hidden transition-all',
      attributes: const {
        'style':
        'display: flex; flex-direction: column; border: 1px solid #ddd; cursor: pointer; text-decoration: none;'
      },
    );
  }
}