import 'dart:async';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';
import '../../repositories/repositories.dart';

/// Clean BLoC-driven Comments panel.
/// Reads from InteractionBloc and writes comments through IEngagementRepository.
class CommentsPanel extends StatefulComponent {
  final String imageId;
  final String? fanzineId;
  final String? fanzineTitle;

  const CommentsPanel({
    required this.imageId,
    this.fanzineId,
    this.fanzineTitle,
    super.key,
  });

  @override
  State<CommentsPanel> createState() => _CommentsPanelState();
}

class _CommentsPanelState extends State<CommentsPanel> {
  late final InteractionBloc _bloc;
  StreamSubscription? _blocSub;
  InteractionState _blocState = const InteractionState();
  String _newCommentText = "";

  @override
  void initState() {
    super.initState();
    _bloc = InteractionBloc(repository: createEngagementRepository());
    _bloc.add(LoadCommentsRequested(component.imageId));

    _blocSub = _bloc.stream.listen((state) {
      if (mounted) {
        setState(() {
          _blocState = state;
        });
      }
    });
  }

  @override
  void didUpdateComponent(CommentsPanel oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.imageId != component.imageId) {
      _bloc.add(LoadCommentsRequested(component.imageId));
    }
  }

  @override
  void dispose() {
    _blocSub?.cancel();
    _bloc.close();
    super.dispose();
  }

  void _submitComment() {
    final textVal = _newCommentText.trim();
    if (textVal.isEmpty) return;

    final uid = getCurrentUserId();
    if (uid == null) {
      GlobalModalBus.show();
      return;
    }

    // Resolve user profile for display metadata
    createUserRepository().watchUser(uid).first.then((profile) {
      _bloc.add(AddCommentRequested(
        imageId: component.imageId,
        text: textVal,
        fanzineId: component.fanzineId,
        fanzineTitle: component.fanzineTitle,
        displayName: profile?.displayName,
        username: profile?.username,
      ));

      if (mounted) {
        setState(() {
          _newCommentText = "";
        });
      }
    });
  }

  Component _buildSkeletonComments() {
    return div(
      [
        for (int i = 0; i < 2; i++)
          div(
            [
              div([], classes: 'w-10 h-10 rounded-full shimmer-bg flex-shrink-0', attributes: const {'style': 'width: 40px; height: 40px; border-radius: 50%;'}),
              div(
                [
                  div([], classes: 'skeleton-line short shimmer-bg', attributes: const {'style': 'height: 12px; border-radius: 4px; width: 60%;'}),
                  div([], classes: 'skeleton-line medium shimmer-bg', attributes: const {'style': 'height: 12px; border-radius: 4px; width: 85%;'}),
                ],
                classes: 'flex-1 flex-col gap-2',
                attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px; flex: 1;'},
              )
            ],
            classes: 'flex-row gap-3 py-4 border-b border-gray-100 items-start',
            attributes: const {'style': 'display: flex; gap: 12px; align-items: flex-start;'},
          )
      ],
      classes: 'flex-col gap-4 py-2',
    );
  }

  @override
  Component build(BuildContext context) {
    final comments = _blocState.comments;
    final isLoading = _blocState.isLoadingComments;

    return div(
      [
        if (isLoading)
          _buildSkeletonComments()
        else if (comments.isEmpty)
          div(
            [text('No thoughts shared yet.')],
            classes: 'p-8 text-center text-gray text-sm italic',
          )
        else
          for (var comment in comments)
            CommentItem(data: comment, key: ValueKey(comment['_id'] ?? '')),

        // Composer row
        div(
          [
            div(
              [
                input(
                  attributes: {
                    'placeholder': 'Add a thought...',
                    'value': _newCommentText,
                    'style': 'width: 100%; box-sizing: border-box; margin: 0; padding: 8px; border: 1px solid #ccc; border-radius: 4px; font-size: 14px;'
                  },
                  classes: 'w-full p-2 border border-gray-200 rounded-md text-sm',
                  events: {
                    'input': (e) => _newCommentText = getInputValue(e),
                    'click': (e) {
                      if (getCurrentUserId() == null) {
                        GlobalModalBus.show();
                      }
                    }
                  },
                ),
              ],
              classes: 'flex-1',
              attributes: const {'style': 'flex: 1;'},
            ),
            button(
              [
                span([text('send')], classes: 'material-symbols-outlined text-sm')
              ],
              classes: 'nav-pill mb-0',
              attributes: const {
                'style': 'margin-bottom: 0; height: 32px; display: inline-flex; align-items: center; justify-content: center; border-radius: 16px; padding: 0 16px; border: 1px solid #ccc; cursor: pointer; background: white;'
              },
              events: {'click': (e) => _submitComment()},
            )
          ],
          classes: 'flex-row gap-2 mt-4 p-2 bg-gray-50 rounded-lg items-center',
          attributes: const {
            'style': 'display: flex; flex-direction: row; gap: 8px; align-items: center; margin-top: 16px; padding: 8px; background-color: #f9f9f9; border-radius: 8px;'
          },
        )
      ],
      classes: 'flex-col',
      attributes: const {'style': 'display: flex; flex-direction: column; width: 100%;'},
    );
  }
}

class CommentItem extends StatefulComponent {
  final Map<String, dynamic> data;
  const CommentItem({required this.data, super.key});

  @override
  State createState() => _CommentItemState();
}

class _CommentItemState extends State<CommentItem> {
  UserProfile? _profile;
  bool _isLiked = false;
  StreamSubscription? _likeSub;

  final IUserRepository _userRepo = createUserRepository();
  final IEngagementRepository _engagementRepo = createEngagementRepository();

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _listenToLikes();
  }

  @override
  void dispose() {
    _likeSub?.cancel();
    super.dispose();
  }

  void _loadProfile() {
    final uid = component.data['userId'];
    if (uid == null) return;

    _userRepo.watchUser(uid).first.then((profile) {
      if (profile != null && mounted) {
        setState(() => _profile = profile);
      }
    });
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

    _engagementRepo.toggleCommentLike(commentId, _isLiked);
  }

  @override
  Component build(BuildContext context) {
    final String displayName = _profile?.displayName ?? component.data['displayName'] ?? 'user';
    final String username = _profile?.username ?? component.data['username'] ?? 'anonymous';
    final String? photoUrl = _profile?.photoUrl;
    final String textContent = component.data['text'] ?? '';
    final int likeCount = component.data['likeCount'] ?? 0;

    String dateStr = '';
    final createdAt = component.data['createdAt'];
    if (createdAt is DateTime) {
      dateStr = '${createdAt.month.toString().padLeft(2, '0')}.${createdAt.day.toString().padLeft(2, '0')}.${createdAt.year.toString().substring(2)}';
    }

    return div(
      [
        // Avatar leading
        div(
          [
            if (photoUrl != null && photoUrl.isNotEmpty)
              img(
                  src: photoUrl,
                  attributes: const {'style': 'width: 100%; height: 100%; object-fit: cover;'}
              )
            else
              div(
                [text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?')],
                attributes: const {'style': 'font-weight: bold; color: #9ca3af; font-size: 14px;'},
              )
          ],
          classes: 'w-10 h-10 rounded-full bg-gray-100 overflow-hidden flex-shrink-0 border border-gray-200',
          attributes: const {'style': 'width: 40px; height: 40px; border-radius: 50%; overflow: hidden; flex-shrink: 0; display: flex; align-items: center; justify-content: center; background-color: #f3f4f6; border: 1px solid #ddd;'},
        ),

        // Info container
        div(
          [
            div(
              [
                div(
                  [
                    div(
                      [
                        span([text(displayName)], classes: 'font-bold text-sm text-black', attributes: const {'style': 'font-weight: bold; font-size: 14px; color: black;'}),
                        span([text('@$username')], classes: 'text-gray-500 text-xs', attributes: const {'style': 'color: #6b7280; font-size: 12px;'}),
                      ],
                      classes: 'flex-row items-center gap-1',
                      attributes: const {'style': 'display: flex; flex-direction: row; align-items: center; gap: 4px;'},
                    ),
                    span([text(dateStr)], classes: 'text-gray-400 text-xs mt-0.5', attributes: const {'style': 'color: #9ca3af; font-size: 11px; margin-top: 2px;'})
                  ],
                  classes: 'flex-col',
                  attributes: const {'style': 'display: flex; flex-direction: column;'},
                ),

                button(
                  [
                    span(
                        [text(likeCount > 0 ? '$likeCount' : '')],
                        classes: 'text-xs font-bold ${_isLiked ? 'text-red-500' : 'text-gray-400'}',
                        attributes: {
                          'style': 'font-size: 11px; font-weight: bold; color: ${_isLiked ? "#ef4444" : "#9ca3af"};'
                        }
                    ),
                    span(
                        [text('favorite')],
                        classes: 'material-symbols-outlined text-sm ${_isLiked ? 'text-red-500' : 'text-gray-300'}',
                        attributes: {
                          'style': 'font-size: 16px; color: ${_isLiked ? "#ef4444" : "#d1d5db"};'
                        }
                    ),
                  ],
                  classes: 'flex-row items-center gap-1 bg-transparent border-none cursor-pointer group p-1 rounded hover:bg-gray-50',
                  attributes: const {'style': 'display: inline-flex; align-items: center; gap: 4px; border: none; background: transparent; cursor: pointer; padding: 4px;'},
                  events: {'click': (e) => _handleLike()},
                ),
              ],
              classes: 'flex-row justify-between items-start',
              attributes: const {'style': 'display: flex; flex-direction: row; justify-content: space-between; align-items: flex-start;'},
            ),

            p([text(textContent)], classes: 'text-sm text-gray-800 mt-2 leading-relaxed', attributes: const {'style': 'margin: 8px 0 0 0; font-size: 14px; color: #1f2937; line-height: 1.5; text-align: left;'})
          ],
          classes: 'flex-1 flex-col',
          attributes: const {'style': 'flex: 1; display: flex; flex-direction: column; overflow: hidden;'},
        )
      ],
      classes: 'flex-row gap-3 py-4 border-b border-gray-100 items-start',
      attributes: const {'style': 'display: flex; flex-direction: row; gap: 12px; align-items: flex-start; padding: 16px 0; border-bottom: 1px solid #eee; width: 100%; box-sizing: border-box;'},
    );
  }
}