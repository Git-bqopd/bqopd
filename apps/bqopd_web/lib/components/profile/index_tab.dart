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

  Component _buildWorkGridTile(Map<String, dynamic> w) {
    final String fanzineId = w['id'] ?? '';
    final String title = w['title'] ?? 'Untitled Fanzine';
    final String volume = w['volume'] ?? '';
    final String issue = w['issue'] ?? '';
    final String wholeNumber = w['wholeNumber'] ?? '';
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
                })
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
        attributes: const {'style': 'display: flex; flex-direction: column; border: 1px solid #ddd; cursor: pointer; text-decoration: none;'}
    );
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
            _buildWorkGridTile(w)
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

    return div(
      [
        // Subtab row selector
        div(
            [
              span(
                  [text("mentions (${_mentions.length})")],
                  classes: _activeSubTab == 0 ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer',
                  events: {
                    'click': (e) => setState(() => _activeSubTab = 0)
                  }
              ),
              span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
              span(
                  [text("comments (${_comments.length})")],
                  classes: _activeSubTab == 1 ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer',
                  events: {
                    'click': (e) => setState(() => _activeSubTab = 1)
                  }
              ),
            ],
            classes: 'bg-white rounded-md p-4 shadow-sm',
            attributes: const {'style': 'display: flex; justify-content: center; align-items: center; box-sizing: border-box; width: 100%; margin-bottom: 16px;'}
        ),

        if (_activeSubTab == 0)
          _buildWorksGridSchema()
        else
          _buildCommentsListSubView()
      ],
    );
  }
}