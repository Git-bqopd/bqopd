import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';
import '../../repositories/repositories.dart';
import '../segmented_button.dart';

String normalizeHandle(String input) {
  return input
      .trim()
      .toLowerCase()
      .replaceAll(' ', '-')
      .replaceAll(RegExp(r'[^a-z0-9_-]'), '');
}

/// Dedicated inline accordion drawer (bonusRow) comments panel.
/// Renders standard conversation in reader mode and the letters transcriber in curator mode.
class CommentsRowPanel extends StatefulComponent {
  final String imageId;
  final String? fanzineId;
  final String? fanzineTitle;

  const CommentsRowPanel({
    required this.imageId,
    this.fanzineId,
    this.fanzineTitle,
    super.key,
  });

  @override
  State<CommentsRowPanel> createState() => _CommentsRowPanelState();
}

class _CommentsRowPanelState extends State<CommentsRowPanel> {
  late final InteractionBloc _bloc;
  StreamSubscription? _blocSub;
  InteractionState _blocState = const InteractionState();

  String _viewMode = 'reader'; // 'reader' or 'curator'
  bool _isCurator = false;

  // Standard reader comment input
  String _newCommentText = "";

  // Curator letters transcriber fields
  String _authorName = "";
  String _authorHandle = "";
  String _authorLocation = "";
  String _letterText = "";
  String _letterDate = "";

  // Profile lookup & creation state for the letter writer
  bool _profileFound = false;
  String? _resolvedAuthorUid;
  bool _isCreatingProfile = false;
  String? _curatorFeedback;
  bool _isCuratorError = false;

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
    if (kIsWeb) {
      _checkCuratorStatus();
    }
  }

  @override
  void didUpdateComponent(CommentsRowPanel oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.imageId != component.imageId) {
      _bloc.add(LoadCommentsRequested(component.imageId));
      if (kIsWeb) {
        _checkCuratorStatus();
      }
    }
  }

  @override
  void dispose() {
    _blocSub?.cancel();
    _bloc.close();
    super.dispose();
  }

  Future<void> _checkCuratorStatus() async {
    final uid = getCurrentUserId();
    if (uid == null) {
      if (mounted) setState(() => _isCurator = false);
      return;
    }

    bool hasAccess = false;
    final fzId = component.fanzineId;

    if (fzId != null && fzId.isNotEmpty) {
      try {
        final res = await fsGetDoc('fanzines/$fzId');
        final decoded = jsonDecode(res);
        if (decoded['exists'] == true) {
          final data = decoded['data'] as Map<String, dynamic>? ?? {};
          final List curators = data['curators'] ?? [];
          final List editors = data['editors'] ?? [];
          final String ownerId = data['ownerId'] ?? data['editorId'] ?? '';
          if (curators.contains(uid) || ownerId == uid || editors.contains(uid)) {
            hasAccess = true;
          }
        }
      } catch (_) {}
    }

    if (!hasAccess) {
      try {
        final profRes = await fsGetDoc('profiles/$uid');
        final profDoc = jsonDecode(profRes);
        if (profDoc['exists'] == true) {
          final pData = profDoc['data'] as Map<String, dynamic>? ?? {};
          if (pData['isCurator'] == true || pData['isAdmin'] == true) {
            hasAccess = true;
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _isCurator = hasAccess;
      });
    }
  }

  void _onAuthorNameChanged(String val) {
    _authorName = val;
    final suggested = normalizeHandle(val);
    _authorHandle = suggested;
    _resolvedAuthorUid = null;
    _profileFound = false;

    if (suggested.isNotEmpty) {
      _checkAuthorHandle(suggested);
    }
  }

  Future<void> _checkAuthorHandle(String handle) async {
    try {
      final res = await fsGetDoc('usernames/$handle');
      final decoded = jsonDecode(res);
      if (decoded['exists'] == true && mounted) {
        final data = decoded['data'] as Map<String, dynamic>? ?? {};
        setState(() {
          _profileFound = true;
          _resolvedAuthorUid = data['uid'];
          _curatorFeedback = "Profile linked: @$handle";
          _isCuratorError = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _profileFound = false;
            _resolvedAuthorUid = null;
            _curatorFeedback = null;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _createManagedProfileForAuthor() async {
    final name = _authorName.trim();
    final handle = normalizeHandle(_authorHandle.isNotEmpty ? _authorHandle : name);
    if (name.isEmpty || handle.isEmpty) return;

    setState(() {
      _isCreatingProfile = true;
      _curatorFeedback = "Generating managed profile @$handle...";
      _isCuratorError = false;
    });

    try {
      final uid = getCurrentUserId() ?? 'system';
      final profileId = 'profile_managed_${handle}_${DateTime.now().millisecondsSinceEpoch}';

      String firstName = name;
      String lastName = "";
      if (name.contains(' ')) {
        final parts = name.split(' ');
        firstName = parts.first;
        lastName = parts.sublist(1).join(' ');
      }

      final profileData = {
        'uid': profileId,
        'username': handle,
        'displayName': name,
        'firstName': firstName,
        'lastName': lastName,
        'photoUrl': '',
        'bio': _authorLocation.isNotEmpty
            ? 'Historical letter writer from $_authorLocation.'
            : 'Historical letter writer.',
        'isManaged': true,
        'isCurator': false,
        'isAdmin': false,
        'managers': [uid],
        'followerCount': 0,
        'followingCount': 0,
        'createdAt': WebFieldValue.serverTimestamp(),
        'updatedAt': WebFieldValue.serverTimestamp(),
      };

      await fsSetDoc('profiles/$profileId', jsonEncode(profileData), true);
      await fsSetDoc('usernames/$handle', jsonEncode({
        'uid': profileId,
        'isManaged': true,
        'createdAt': WebFieldValue.serverTimestamp(),
      }), true);
      await fsSetDoc('shortcodes/${handle.toUpperCase()}', jsonEncode({
        'type': 'user',
        'contentId': profileId,
        'displayCode': handle,
        'createdAt': WebFieldValue.serverTimestamp(),
      }), true);

      if (mounted) {
        setState(() {
          _isCreatingProfile = false;
          _profileFound = true;
          _resolvedAuthorUid = profileId;
          _curatorFeedback = "Managed profile @$handle created and linked!";
          _isCuratorError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCreatingProfile = false;
          _curatorFeedback = "Failed to create profile: $e";
          _isCuratorError = true;
        });
      }
    }
  }

  Future<void> _transcribeLetter() async {
    final text = _letterText.trim();
    if (text.isEmpty) {
      setState(() {
        _curatorFeedback = "Please enter the letter text.";
        _isCuratorError = true;
      });
      return;
    }

    final authorName = _authorName.trim().isNotEmpty ? _authorName.trim() : 'Anonymous Reader';
    final handle = _authorHandle.trim().isNotEmpty ? normalizeHandle(_authorHandle) : 'reader';
    final authorUid = _resolvedAuthorUid ?? 'archival_${DateTime.now().millisecondsSinceEpoch}';

    setState(() {
      _curatorFeedback = "Committing archival letter...";
      _isCuratorError = false;
    });

    try {
      final commentDoc = {
        'contentId': component.imageId,
        'userId': authorUid,
        'displayName': authorName,
        'username': handle,
        'location': _authorLocation.trim(),
        'historicalDate': _letterDate.trim(),
        'text': text,
        'sourceType': 'letter_column',
        'createdAt': WebFieldValue.serverTimestamp(),
        'likeCount': 0,
        'context': {
          'fanzineId': component.fanzineId,
          'fanzineTitle': component.fanzineTitle,
        }
      };

      await fsAddDoc('artifacts/bqopd/public/data/comments', jsonEncode(commentDoc));

      if (component.imageId.isNotEmpty) {
        await fsUpdateDoc('images/${component.imageId}', jsonEncode({
          'commentCount': WebFieldValue.increment(1),
        })).catchError((_) => null);
      }

      // Add to fanzine's draft entities so index recognizes the writer
      if (component.fanzineId != null && component.fanzineId!.isNotEmpty && authorName.isNotEmpty) {
        await fsUpdateDoc('fanzines/${component.fanzineId}', jsonEncode({
          'draftEntities': WebFieldValue.arrayUnion([authorName]),
        })).catchError((_) => null);
      }

      if (mounted) {
        setState(() {
          _letterText = "";
          _authorName = "";
          _authorHandle = "";
          _authorLocation = "";
          _curatorFeedback = "Letter transcribed and linked to @$handle!";
          _isCuratorError = false;
          _profileFound = false;
          _resolvedAuthorUid = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _curatorFeedback = "Error submitting letter: $e";
          _isCuratorError = true;
        });
      }
    }
  }

  void _submitReaderComment() {
    final textVal = _newCommentText.trim();
    if (textVal.isEmpty) return;
    final uid = getCurrentUserId();
    if (uid == null) {
      GlobalModalBus.show();
      return;
    }
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

  Component _buildHeaderBar() {
    return div(
      attributes: const {
        'style':
        'display: flex; justify-content: space-between; align-items: center; width: 100%; margin-bottom: 12px; border-bottom: 1px solid #f0f0f0; padding-bottom: 8px;'
      },
      [
        span(
          [Component.text('COMMENTS')],
          attributes: const {
            'style':
            'font-size: 11px; font-weight: bold; color: #475569; letter-spacing: 0.8px; text-transform: uppercase;'
          },
        ),
        if (_isCurator)
          SegmentedButton<String>(
            segments: const ['reader', 'curator'],
            selected: _viewMode,
            labelBuilder: (m) => m,
            showSelectedCheckmark: true,
            onSelectionChanged: (m) {
              setState(() => _viewMode = m);
            },
          ),
      ],
    );
  }

  Component _buildCuratorView(List<Map<String, dynamic>> comments) {
    final letters = comments.where((c) => c['sourceType'] == 'letter_column').toList();

    return div(
      classes: 'flex-col gap-3',
      attributes: const {'style': 'display: flex; flex-direction: column; gap: 12px; width: 100%;'},
      [
        // Transcriber Box
        div(
          attributes: const {
            'style':
            'background-color: #fcfcfc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 14px; display: flex; flex-direction: column; gap: 10px; width: 100%; box-sizing: border-box;'
          },
          [
            div(
              attributes: const {
                'style': 'display: flex; justify-content: space-between; align-items: center;'
              },
              [
                span(
                  [Component.text('TRANSCRIBE LETTER COLUMN ENTRY')],
                  attributes: const {
                    'style':
                    'font-size: 11px; font-weight: bold; color: #6750A4; text-transform: uppercase; letter-spacing: 0.5px;'
                  },
                ),
                span(
                  [Component.text('links letter to commenter index')],
                  attributes: const {'style': 'font-size: 10px; color: #888; font-style: italic;'},
                ),
              ],
            ),
            // Writer & Handle row
            div(
              attributes: const {
                'style': 'display: flex; gap: 8px; width: 100%; flex-wrap: wrap;'
              },
              [
                div(
                  attributes: const {'style': 'flex: 2; min-width: 140px;'},
                  [
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'Letter writer name (e.g. Wesley A. Kauder)',
                        'value': _authorName,
                        'style':
                        'width: 100%; padding: 8px 10px; border: 1px solid #ccc; border-radius: 6px; font-size: 12px; background: white; outline: none; box-sizing: border-box; margin: 0;'
                      },
                      events: {
                        'input': (e) {
                          setState(() {
                            _onAuthorNameChanged(getInputValue(e));
                          });
                        }
                      },
                    )
                  ],
                ),
                div(
                  attributes: const {'style': 'flex: 1.5; min-width: 120px;'},
                  [
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': '@handle',
                        'value': _authorHandle,
                        'style':
                        'width: 100%; padding: 8px 10px; border: 1px solid #ccc; border-radius: 6px; font-size: 12px; background: white; outline: none; box-sizing: border-box; margin: 0; font-family: monospace;'
                      },
                      events: {
                        'input': (e) {
                          final h = getInputValue(e);
                          setState(() {
                            _authorHandle = h;
                            _checkAuthorHandle(normalizeHandle(h));
                          });
                        }
                      },
                    )
                  ],
                ),
              ],
            ),
            // Location and Date row
            div(
              attributes: const {
                'style': 'display: flex; gap: 8px; width: 100%; flex-wrap: wrap;'
              },
              [
                div(
                  attributes: const {'style': 'flex: 2; min-width: 140px;'},
                  [
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'Location (e.g. Jamestown, N. D.)',
                        'value': _authorLocation,
                        'style':
                        'width: 100%; padding: 8px 10px; border: 1px solid #ccc; border-radius: 6px; font-size: 12px; background: white; outline: none; box-sizing: border-box; margin: 0;'
                      },
                      events: {
                        'input': (e) {
                          setState(() {
                            _authorLocation = getInputValue(e);
                          });
                        }
                      },
                    )
                  ],
                ),
                div(
                  attributes: const {'style': 'flex: 1.5; min-width: 120px;'},
                  [
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'Historical date (e.g. March 1927)',
                        'value': _letterDate,
                        'style':
                        'width: 100%; padding: 8px 10px; border: 1px solid #ccc; border-radius: 6px; font-size: 12px; background: white; outline: none; box-sizing: border-box; margin: 0;'
                      },
                      events: {
                        'input': (e) {
                          setState(() {
                            _letterDate = getInputValue(e);
                          });
                        }
                      },
                    )
                  ],
                ),
              ],
            ),
            // Profile Linking Prompt / One-click Creator
            if (_authorName.trim().isNotEmpty && !_profileFound)
              div(
                attributes: const {
                  'style':
                  'background: #fff8e1; border: 1px solid #ffe082; border-radius: 6px; padding: 8px 12px; display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 8px;'
                },
                [
                  span(
                    [Component.text('No profile exists yet for @$_authorHandle')],
                    attributes: const {'style': 'font-size: 11px; color: #856404; font-weight: 500;'},
                  ),
                  button(
                    [
                      span([Component.text('person_add')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px; margin-right: 4px;'}),
                      Component.text(_isCreatingProfile ? 'creating...' : 'create managed profile')
                    ],
                    classes: 'profile-btn',
                    attributes: {
                      'type': 'button',
                      'style':
                      'padding: 4px 10px; font-size: 10px; font-weight: bold; background: #6750A4; color: white; border: none; border-radius: 4px; cursor: pointer; display: inline-flex; align-items: center;',
                      if (_isCreatingProfile) 'disabled': 'true',
                    },
                    events: {'click': (e) => _createManagedProfileForAuthor()},
                  ),
                ],
              ),
            // Letter text textarea
            textarea(
              classes: 'border border-gray-300 rounded-md',
              attributes: {
                'placeholder': 'Type or paste letter content from the scan...',
                'style':
                'width: 100%; min-height: 90px; padding: 8px 10px; font-size: 13px; font-family: inherit; line-height: 1.5; border: 1px solid #ccc; border-radius: 6px; box-sizing: border-box; outline: none; background: white; margin: 0;',
              },
              events: {
                'input': (e) {
                  setState(() {
                    _letterText = getInputValue(e);
                  });
                }
              },
              [Component.text(_letterText)],
            ),
            // Actions & Feedback
            div(
              attributes: const {
                'style': 'display: flex; justify-content: space-between; align-items: center; width: 100%;'
              },
              [
                if (_curatorFeedback != null)
                  span(
                    [Component.text(_curatorFeedback!)],
                    attributes: {
                      'style':
                      'font-size: 11px; font-weight: bold; color: ${_isCuratorError ? "#ef4444" : "#16a34a"};'
                    },
                  )
                else
                  span([], attributes: const {'style': 'display: inline-block;'}),
                button(
                  [
                    span([Component.text('post_add')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px; margin-right: 4px;'}),
                    Component.text('save letter as comment')
                  ],
                  classes: 'btn-primary nav-pill mb-0',
                  attributes: const {
                    'type': 'button',
                    'style':
                    'padding: 8px 16px; font-size: 11px; font-weight: bold; background-color: #6750A4; color: white; border: none; border-radius: 50px; cursor: pointer; display: inline-flex; align-items: center;'
                  },
                  events: {'click': (e) => _transcribeLetter()},
                ),
              ],
            ),
          ],
        ),
        // Transcribed Letters on this page
        if (letters.isNotEmpty) ...[
          div(
            attributes: const {
              'style':
              'font-size: 11px; font-weight: bold; color: #666; text-transform: uppercase; letter-spacing: 0.5px; margin-top: 8px;'
            },
            [Component.text('Transcribed Letters on This Page (${letters.length})')],
          ),
          for (var comment in letters)
            CommentItem(
              data: comment,
              isCuratorMode: true,
              key: ValueKey('curator_letter_${comment['_id']}'),
            ),
        ] else
          div(
            [Component.text('No archival letters transcribed on this page yet.')],
            classes: 'p-4 text-center text-gray text-xs italic',
          ),
      ],
    );
  }

  Component _buildReaderView(List<Map<String, dynamic>> comments, bool isLoading) {
    return div(
      classes: 'flex-col',
      attributes: const {'style': 'display: flex; flex-direction: column; width: 100%;'},
      [
        if (isLoading)
          div(
            [
              div([], classes: 'w-8 h-8 rounded-full shimmer-bg flex-shrink-0', attributes: const {'style': 'width: 32px; height: 32px; border-radius: 50%;'}),
              div([], classes: 'skeleton-line medium shimmer-bg', attributes: const {'style': 'height: 12px; border-radius: 4px; width: 85%;'}),
            ],
            classes: 'flex-row gap-3 py-4 border-b border-gray-100 items-start',
            attributes: const {'style': 'display: flex; gap: 12px; align-items: flex-start;'},
          )
        else if (comments.isEmpty)
          div(
            [Component.text('No thoughts shared yet.')],
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
              [span([Component.text('send')], classes: 'material-symbols-outlined text-sm')],
              classes: 'nav-pill mb-0',
              attributes: const {
                'style':
                'margin-bottom: 0; height: 32px; display: inline-flex; align-items: center; justify-content: center; border-radius: 16px; padding: 0 16px; border: 1px solid #ccc; cursor: pointer; background: white;'
              },
              events: {'click': (e) => _submitReaderComment()},
            )
          ],
          classes: 'flex-row gap-2 mt-4 p-2 bg-gray-50 rounded-lg items-center',
          attributes: const {
            'style': 'display: flex; flex-direction: row; gap: 8px; align-items: center; margin-top: 16px; padding: 8px; background-color: #f9f9f9; border-radius: 8px;'
          },
        )
      ],
    );
  }

  @override
  Component build(BuildContext context) {
    final comments = _blocState.comments;
    final isLoading = _blocState.isLoadingComments;

    return div(
      classes: 'flex-col',
      attributes: const {'style': 'display: flex; flex-direction: column; width: 100%;'},
      [
        _buildHeaderBar(),
        if (_viewMode == 'curator')
          _buildCuratorView(comments)
        else
          _buildReaderView(comments, isLoading),
      ],
    );
  }
}

/// Dedicated desktop 3rd column (bonusColumn) comments panel.
/// Embeds the M3 single-select mode switcher and full letters workstation for curators.
class CommentsColumnPanel extends StatefulComponent {
  final String imageId;
  final String? fanzineId;
  final String? fanzineTitle;

  const CommentsColumnPanel({
    required this.imageId,
    this.fanzineId,
    this.fanzineTitle,
    super.key,
  });

  @override
  State<CommentsColumnPanel> createState() => _CommentsColumnPanelState();
}

class _CommentsColumnPanelState extends State<CommentsColumnPanel> {
  late final InteractionBloc _bloc;
  StreamSubscription? _blocSub;
  InteractionState _blocState = const InteractionState();

  String _viewMode = 'reader';
  bool _isCurator = false;
  String _newCommentText = "";

  // Curator letters transcriber fields
  String _authorName = "";
  String _authorHandle = "";
  String _authorLocation = "";
  String _letterText = "";
  String _letterDate = "";

  bool _profileFound = false;
  String? _resolvedAuthorUid;
  bool _isCreatingProfile = false;
  String? _curatorFeedback;
  bool _isCuratorError = false;

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
    if (kIsWeb) {
      _checkCuratorStatus();
    }
  }

  @override
  void didUpdateComponent(CommentsColumnPanel oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.imageId != component.imageId) {
      _bloc.add(LoadCommentsRequested(component.imageId));
      if (kIsWeb) {
        _checkCuratorStatus();
      }
    }
  }

  @override
  void dispose() {
    _blocSub?.cancel();
    _bloc.close();
    super.dispose();
  }

  Future<void> _checkCuratorStatus() async {
    final uid = getCurrentUserId();
    if (uid == null) {
      if (mounted) setState(() => _isCurator = false);
      return;
    }

    bool hasAccess = false;
    final fzId = component.fanzineId;

    if (fzId != null && fzId.isNotEmpty) {
      try {
        final res = await fsGetDoc('fanzines/$fzId');
        final decoded = jsonDecode(res);
        if (decoded['exists'] == true) {
          final data = decoded['data'] as Map<String, dynamic>? ?? {};
          final List curators = data['curators'] ?? [];
          final List editors = data['editors'] ?? [];
          final String ownerId = data['ownerId'] ?? data['editorId'] ?? '';
          if (curators.contains(uid) || ownerId == uid || editors.contains(uid)) {
            hasAccess = true;
          }
        }
      } catch (_) {}
    }

    if (!hasAccess) {
      try {
        final profRes = await fsGetDoc('profiles/$uid');
        final profDoc = jsonDecode(profRes);
        if (profDoc['exists'] == true) {
          final pData = profDoc['data'] as Map<String, dynamic>? ?? {};
          if (pData['isCurator'] == true || pData['isAdmin'] == true) {
            hasAccess = true;
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _isCurator = hasAccess;
      });
    }
  }

  void _onAuthorNameChanged(String val) {
    _authorName = val;
    final suggested = normalizeHandle(val);
    _authorHandle = suggested;
    _resolvedAuthorUid = null;
    _profileFound = false;

    if (suggested.isNotEmpty) {
      _checkAuthorHandle(suggested);
    }
  }

  Future<void> _checkAuthorHandle(String handle) async {
    try {
      final res = await fsGetDoc('usernames/$handle');
      final decoded = jsonDecode(res);
      if (decoded['exists'] == true && mounted) {
        final data = decoded['data'] as Map<String, dynamic>? ?? {};
        setState(() {
          _profileFound = true;
          _resolvedAuthorUid = data['uid'];
          _curatorFeedback = "Profile linked: @$handle";
          _isCuratorError = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _profileFound = false;
            _resolvedAuthorUid = null;
            _curatorFeedback = null;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _createManagedProfileForAuthor() async {
    final name = _authorName.trim();
    final handle = normalizeHandle(_authorHandle.isNotEmpty ? _authorHandle : name);
    if (name.isEmpty || handle.isEmpty) return;

    setState(() {
      _isCreatingProfile = true;
      _curatorFeedback = "Generating managed profile @$handle...";
      _isCuratorError = false;
    });

    try {
      final uid = getCurrentUserId() ?? 'system';
      final profileId = 'profile_managed_${handle}_${DateTime.now().millisecondsSinceEpoch}';

      String firstName = name;
      String lastName = "";
      if (name.contains(' ')) {
        final parts = name.split(' ');
        firstName = parts.first;
        lastName = parts.sublist(1).join(' ');
      }

      final profileData = {
        'uid': profileId,
        'username': handle,
        'displayName': name,
        'firstName': firstName,
        'lastName': lastName,
        'photoUrl': '',
        'bio': _authorLocation.isNotEmpty
            ? 'Historical letter writer from $_authorLocation.'
            : 'Historical letter writer.',
        'isManaged': true,
        'isCurator': false,
        'isAdmin': false,
        'managers': [uid],
        'followerCount': 0,
        'followingCount': 0,
        'createdAt': WebFieldValue.serverTimestamp(),
        'updatedAt': WebFieldValue.serverTimestamp(),
      };

      await fsSetDoc('profiles/$profileId', jsonEncode(profileData), true);
      await fsSetDoc('usernames/$handle', jsonEncode({
        'uid': profileId,
        'isManaged': true,
        'createdAt': WebFieldValue.serverTimestamp(),
      }), true);
      await fsSetDoc('shortcodes/${handle.toUpperCase()}', jsonEncode({
        'type': 'user',
        'contentId': profileId,
        'displayCode': handle,
        'createdAt': WebFieldValue.serverTimestamp(),
      }), true);

      if (mounted) {
        setState(() {
          _isCreatingProfile = false;
          _profileFound = true;
          _resolvedAuthorUid = profileId;
          _curatorFeedback = "Managed profile @$handle created and linked!";
          _isCuratorError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCreatingProfile = false;
          _curatorFeedback = "Failed to create profile: $e";
          _isCuratorError = true;
        });
      }
    }
  }

  Future<void> _transcribeLetter() async {
    final text = _letterText.trim();
    if (text.isEmpty) {
      setState(() {
        _curatorFeedback = "Please enter the letter text.";
        _isCuratorError = true;
      });
      return;
    }

    final authorName = _authorName.trim().isNotEmpty ? _authorName.trim() : 'Anonymous Reader';
    final handle = _authorHandle.trim().isNotEmpty ? normalizeHandle(_authorHandle) : 'reader';
    final authorUid = _resolvedAuthorUid ?? 'archival_${DateTime.now().millisecondsSinceEpoch}';

    setState(() {
      _curatorFeedback = "Committing archival letter...";
      _isCuratorError = false;
    });

    try {
      final commentDoc = {
        'contentId': component.imageId,
        'userId': authorUid,
        'displayName': authorName,
        'username': handle,
        'location': _authorLocation.trim(),
        'historicalDate': _letterDate.trim(),
        'text': text,
        'sourceType': 'letter_column',
        'createdAt': WebFieldValue.serverTimestamp(),
        'likeCount': 0,
        'context': {
          'fanzineId': component.fanzineId,
          'fanzineTitle': component.fanzineTitle,
        }
      };

      await fsAddDoc('artifacts/bqopd/public/data/comments', jsonEncode(commentDoc));

      if (component.imageId.isNotEmpty) {
        await fsUpdateDoc('images/${component.imageId}', jsonEncode({
          'commentCount': WebFieldValue.increment(1),
        })).catchError((_) => null);
      }

      if (component.fanzineId != null && component.fanzineId!.isNotEmpty && authorName.isNotEmpty) {
        await fsUpdateDoc('fanzines/${component.fanzineId}', jsonEncode({
          'draftEntities': WebFieldValue.arrayUnion([authorName]),
        })).catchError((_) => null);
      }

      if (mounted) {
        setState(() {
          _letterText = "";
          _authorName = "";
          _authorHandle = "";
          _authorLocation = "";
          _curatorFeedback = "Letter transcribed and linked to @$handle!";
          _isCuratorError = false;
          _profileFound = false;
          _resolvedAuthorUid = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _curatorFeedback = "Error submitting letter: $e";
          _isCuratorError = true;
        });
      }
    }
  }

  void _submitReaderComment() {
    final textVal = _newCommentText.trim();
    if (textVal.isEmpty) return;
    final uid = getCurrentUserId();
    if (uid == null) {
      GlobalModalBus.show();
      return;
    }
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

  Component _buildHeaderBar() {
    return div(
      attributes: const {
        'style':
        'display: flex; justify-content: space-between; align-items: center; width: 100%; margin-bottom: 12px; border-bottom: 1px solid #e2e8f0; padding-bottom: 8px;'
      },
      [
        span(
          [Component.text('COMMENTS')],
          attributes: const {
            'style':
            'font-size: 11px; font-weight: bold; color: #475569; letter-spacing: 0.8px; text-transform: uppercase;'
          },
        ),
        if (_isCurator)
          SegmentedButton<String>(
            segments: const ['reader', 'curator'],
            selected: _viewMode,
            labelBuilder: (m) => m,
            showSelectedCheckmark: true,
            onSelectionChanged: (m) {
              setState(() => _viewMode = m);
            },
          ),
      ],
    );
  }

  Component _buildCuratorView(List<Map<String, dynamic>> comments) {
    final letters = comments.where((c) => c['sourceType'] == 'letter_column').toList();

    return div(
      classes: 'flex-col gap-3',
      attributes: const {'style': 'display: flex; flex-direction: column; gap: 14px; width: 100%;'},
      [
        div(
          attributes: const {
            'style':
            'background-color: #f8fafc; border: 1px solid #cbd5e1; border-radius: 8px; padding: 16px; display: flex; flex-direction: column; gap: 12px; width: 100%; box-sizing: border-box;'
          },
          [
            div(
              attributes: const {
                'style': 'display: flex; justify-content: space-between; align-items: center;'
              },
              [
                span(
                  [Component.text('TRANSCRIBE LETTER COLUMN ENTRY')],
                  attributes: const {
                    'style':
                    'font-size: 11px; font-weight: bold; color: #6750A4; text-transform: uppercase; letter-spacing: 0.5px;'
                  },
                ),
                span(
                  [Component.text('curator archival workbench')],
                  attributes: const {'style': 'font-size: 10px; color: #64748b; font-style: italic;'},
                ),
              ],
            ),
            div(
              attributes: const {
                'style': 'display: flex; gap: 10px; width: 100%;'
              },
              [
                div(
                  attributes: const {'style': 'flex: 2;'},
                  [
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'Letter writer name (e.g. Wesley A. Kauder)',
                        'value': _authorName,
                        'style':
                        'width: 100%; padding: 8px 12px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; outline: none; box-sizing: border-box;'
                      },
                      events: {
                        'input': (e) {
                          setState(() {
                            _onAuthorNameChanged(getInputValue(e));
                          });
                        }
                      },
                    )
                  ],
                ),
                div(
                  attributes: const {'style': 'flex: 1.5;'},
                  [
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': '@handle',
                        'value': _authorHandle,
                        'style':
                        'width: 100%; padding: 8px 12px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; outline: none; box-sizing: border-box; font-family: monospace;'
                      },
                      events: {
                        'input': (e) {
                          final h = getInputValue(e);
                          setState(() {
                            _authorHandle = h;
                            _checkAuthorHandle(normalizeHandle(h));
                          });
                        }
                      },
                    )
                  ],
                ),
              ],
            ),
            div(
              attributes: const {
                'style': 'display: flex; gap: 10px; width: 100%;'
              },
              [
                div(
                  attributes: const {'style': 'flex: 2;'},
                  [
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'Location (e.g. Jamestown, N. D.)',
                        'value': _authorLocation,
                        'style':
                        'width: 100%; padding: 8px 12px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; outline: none; box-sizing: border-box;'
                      },
                      events: {
                        'input': (e) {
                          setState(() {
                            _authorLocation = getInputValue(e);
                          });
                        }
                      },
                    )
                  ],
                ),
                div(
                  attributes: const {'style': 'flex: 1.5;'},
                  [
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'Historical date (e.g. March 1927)',
                        'value': _letterDate,
                        'style':
                        'width: 100%; padding: 8px 12px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; outline: none; box-sizing: border-box;'
                      },
                      events: {
                        'input': (e) {
                          setState(() {
                            _letterDate = getInputValue(e);
                          });
                        }
                      },
                    )
                  ],
                ),
              ],
            ),
            if (_authorName.trim().isNotEmpty && !_profileFound)
              div(
                attributes: const {
                  'style':
                  'background: #fff8e1; border: 1px solid #ffe082; border-radius: 6px; padding: 8px 12px; display: flex; justify-content: space-between; align-items: center;'
                },
                [
                  span(
                    [Component.text('No managed profile for @$_authorHandle')],
                    attributes: const {'style': 'font-size: 11px; color: #856404; font-weight: 500;'},
                  ),
                  button(
                    [
                      span([Component.text('person_add')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px; margin-right: 4px;'}),
                      Component.text(_isCreatingProfile ? 'creating...' : 'create managed profile')
                    ],
                    classes: 'profile-btn',
                    attributes: {
                      'type': 'button',
                      'style':
                      'padding: 4px 12px; font-size: 10px; font-weight: bold; background: #6750A4; color: white; border: none; border-radius: 4px; cursor: pointer; display: inline-flex; align-items: center;',
                      if (_isCreatingProfile) 'disabled': 'true',
                    },
                    events: {'click': (e) => _createManagedProfileForAuthor()},
                  ),
                ],
              ),
            textarea(
              classes: 'border border-gray-300 rounded-md',
              attributes: {
                'placeholder': 'Type or paste letter content from the scan...',
                'style':
                'width: 100%; min-height: 100px; padding: 10px; font-size: 13px; font-family: inherit; line-height: 1.5; border: 1px solid #cbd5e1; border-radius: 6px; box-sizing: border-box; outline: none; background: white;',
              },
              events: {
                'input': (e) {
                  setState(() {
                    _letterText = getInputValue(e);
                  });
                }
              },
              [Component.text(_letterText)],
            ),
            div(
              attributes: const {
                'style': 'display: flex; justify-content: space-between; align-items: center; width: 100%;'
              },
              [
                if (_curatorFeedback != null)
                  span(
                    [Component.text(_curatorFeedback!)],
                    attributes: {
                      'style':
                      'font-size: 11px; font-weight: bold; color: ${_isCuratorError ? "#ef4444" : "#16a34a"};'
                    },
                  )
                else
                  span([], attributes: const {'style': 'display: inline-block;'}),
                button(
                  [
                    span([Component.text('post_add')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px; margin-right: 4px;'}),
                    Component.text('save letter as comment')
                  ],
                  classes: 'btn-primary nav-pill mb-0',
                  attributes: const {
                    'type': 'button',
                    'style':
                    'padding: 8px 18px; font-size: 11px; font-weight: bold; background-color: #6750A4; color: white; border: none; border-radius: 50px; cursor: pointer; display: inline-flex; align-items: center;'
                  },
                  events: {'click': (e) => _transcribeLetter()},
                ),
              ],
            ),
          ],
        ),
        if (letters.isNotEmpty) ...[
          div(
            attributes: const {
              'style':
              'font-size: 11px; font-weight: bold; color: #64748b; text-transform: uppercase; letter-spacing: 0.5px; margin-top: 8px;'
            },
            [Component.text('Transcribed Letters on This Page (${letters.length})')],
          ),
          for (var comment in letters)
            CommentItem(
              data: comment,
              isCuratorMode: true,
              key: ValueKey('curator_col_letter_${comment['_id']}'),
            ),
        ] else
          div(
            [Component.text('No archival letters transcribed on this page yet.')],
            classes: 'p-4 text-center text-gray text-xs italic',
          ),
      ],
    );
  }

  Component _buildReaderView(List<Map<String, dynamic>> comments, bool isLoading) {
    return div(
      classes: 'flex-col',
      attributes: const {'style': 'display: flex; flex-direction: column; width: 100%;'},
      [
        if (isLoading)
          div(
            [
              div([], classes: 'w-8 h-8 rounded-full shimmer-bg flex-shrink-0', attributes: const {'style': 'width: 32px; height: 32px; border-radius: 50%;'}),
              div([], classes: 'skeleton-line medium shimmer-bg', attributes: const {'style': 'height: 12px; border-radius: 4px; width: 85%;'}),
            ],
            classes: 'flex-row gap-3 py-4 border-b border-gray-100 items-start',
            attributes: const {'style': 'display: flex; gap: 12px; align-items: flex-start;'},
          )
        else if (comments.isEmpty)
          div(
            [Component.text('No comments posted for this page.')],
            classes: 'p-6 text-center text-gray text-xs italic',
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
                    'style': 'width: 100%; box-sizing: border-box; margin: 0; padding: 8px 12px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 13px;'
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
              [span([Component.text('send')], classes: 'material-symbols-outlined text-sm')],
              classes: 'nav-pill mb-0',
              attributes: const {
                'style':
                'margin-bottom: 0; height: 34px; display: inline-flex; align-items: center; justify-content: center; border-radius: 6px; padding: 0 14px; border: 1px solid #cbd5e1; cursor: pointer; background: white;'
              },
              events: {'click': (e) => _submitReaderComment()},
            )
          ],
          classes: 'flex-row gap-2 mt-4 p-2 bg-gray-50 rounded-lg items-center',
          attributes: const {
            'style': 'display: flex; flex-direction: row; gap: 8px; align-items: center; margin-top: 14px; padding: 8px; background-color: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0;'
          },
        )
      ],
    );
  }

  @override
  Component build(BuildContext context) {
    final comments = _blocState.comments;
    final isLoading = _blocState.isLoadingComments;

    return div(
      classes: 'flex-col',
      attributes: const {'style': 'display: flex; flex-direction: column; width: 100%;'},
      [
        _buildHeaderBar(),
        if (_viewMode == 'curator')
          _buildCuratorView(comments)
        else
          _buildReaderView(comments, isLoading),
      ],
    );
  }
}

typedef CommentsPanel = CommentsRowPanel;

class CommentItem extends StatefulComponent {
  final Map<String, dynamic> data;
  final bool isCuratorMode;

  const CommentItem({
    required this.data,
    this.isCuratorMode = false,
    super.key,
  });

  @override
  State<CommentItem> createState() => _CommentItemState();
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

  Future<void> _handleDelete() async {
    final commentId = component.data['_id'];
    final imageId = component.data['contentId'] ?? '';
    if (commentId == null) return;
    try {
      await fsDeleteDoc('artifacts/bqopd/public/data/comments/$commentId');
      if (imageId.isNotEmpty) {
        await fsUpdateDoc('images/$imageId', jsonEncode({
          'commentCount': WebFieldValue.increment(-1),
        })).catchError((_) => null);
      }
    } catch (e) {
      print("Error deleting comment: $e");
    }
  }

  @override
  Component build(BuildContext context) {
    final String displayName = _profile?.displayName ?? component.data['displayName'] ?? 'user';
    final String username = _profile?.username ?? component.data['username'] ?? 'anonymous';
    final String? photoUrl = _profile?.photoUrl;
    final String textContent = component.data['text'] ?? '';
    final int likeCount = component.data['likeCount'] ?? 0;
    final bool isLetter = component.data['sourceType'] == 'letter_column';
    final String? location = component.data['location'];
    final String? historicalDate = component.data['historicalDate'];

    String dateStr = '';
    final createdAt = component.data['createdAt'];
    if (createdAt is DateTime) {
      dateStr = '${createdAt.month.toString().padLeft(2, '0')}.${createdAt.day.toString().padLeft(2, '0')}.${createdAt.year.toString().substring(2)}';
    }

    final targetProfileHref = '/@$username';

    return div(
      [
        // Left Column: Avatar
        a(
          [
            if (photoUrl != null && photoUrl.isNotEmpty)
              img(
                src: photoUrl,
                attributes: const {
                  'style': 'width: 100%; height: 100%; object-fit: cover; display: block; border-radius: 50%;'
                },
              )
            else
              div(
                [Component.text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?')],
                attributes: const {
                  'style': 'font-weight: bold; color: #9ca3af; font-size: 12px; line-height: 1; text-align: center;'
                },
              )
          ],
          href: targetProfileHref,
          classes: 'w-8 h-8 rounded-full bg-gray-100 overflow-hidden flex-shrink-0 border border-gray-200',
          attributes: const {
            'style':
            'width: 32px; height: 32px; min-width: 32px; min-height: 32px; max-width: 32px; max-height: 32px; flex: 0 0 32px; aspect-ratio: 1 / 1; border-radius: 50%; overflow: hidden; display: flex; align-items: center; justify-content: center; background-color: #f3f4f6; border: 1px solid #ddd; box-sizing: border-box; text-decoration: none;'
          },
        ),
        // Right Column: Details
        div(
          [
            div(
              [
                div(
                  [
                    div(
                      [
                        a(
                          [Component.text(displayName)],
                          href: targetProfileHref,
                          classes: 'font-bold text-sm text-black hover:underline',
                          attributes: const {
                            'style': 'font-weight: bold; font-size: 13px; color: black; text-decoration: none;'
                          },
                        ),
                        a(
                          [Component.text('@$username')],
                          href: targetProfileHref,
                          classes: 'text-gray-500 text-xs hover:underline',
                          attributes: const {
                            'style': 'color: #6b7280; font-size: 11px; text-decoration: none;'
                          },
                        ),
                        if (isLetter)
                          span(
                            [Component.text('letter')],
                            attributes: const {
                              'style':
                              'font-size: 8px; font-weight: bold; background: #e0e7ff; color: #3730a3; padding: 1px 4px; border-radius: 4px; text-transform: uppercase;'
                            },
                          ),
                      ],
                      classes: 'flex-row items-center gap-1',
                      attributes: const {
                        'style': 'display: flex; flex-direction: row; align-items: center; gap: 6px; flex-wrap: wrap;'
                      },
                    ),
                    div(
                      [
                        if (location != null && location.isNotEmpty)
                          span(
                            [
                              span([Component.text('pin_drop')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 12px; margin-right: 2px; vertical-align: middle;'}),
                              Component.text(location)
                            ],
                            attributes: const {
                              'style': 'color: #64748b; font-size: 10px; font-weight: 500; margin-right: 6px;'
                            },
                          ),
                        if (historicalDate != null && historicalDate.isNotEmpty)
                          span([Component.text(historicalDate)], attributes: const {'style': 'color: #94a3b8; font-size: 10px; margin-right: 6px;'})
                        else if (dateStr.isNotEmpty)
                          span([Component.text(dateStr)], attributes: const {'style': 'color: #94a3b8; font-size: 10px;'}),
                      ],
                      attributes: const {
                        'style': 'display: flex; align-items: center; flex-wrap: wrap; margin-top: 2px;'
                      },
                    ),
                  ],
                  classes: 'flex-col',
                  attributes: const {'style': 'display: flex; flex-direction: column;'},
                ),
                div(
                  attributes: const {'style': 'display: flex; align-items: center; gap: 4px;'},
                  [
                    if (component.isCuratorMode)
                      button(
                        [span([Component.text('delete')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px; color: #ef4444;'})],
                        attributes: const {
                          'type': 'button',
                          'style': 'background: transparent; border: none; cursor: pointer; padding: 2px;'
                        },
                        events: {'click': (e) => _handleDelete()},
                      ),
                    button(
                      [
                        span(
                          [Component.text(likeCount > 0 ? '$likeCount' : '')],
                          classes: 'text-xs font-bold ${_isLiked ? 'text-red-500' : 'text-gray-400'}',
                          attributes: {
                            'style': 'font-size: 11px; font-weight: bold; color: ${_isLiked ? "#ef4444" : "#9ca3af"};'
                          },
                        ),
                        span(
                          [Component.text('favorite')],
                          classes: 'material-symbols-outlined text-sm ${_isLiked ? 'text-red-500' : 'text-gray-300'}',
                          attributes: {
                            'style': 'font-size: 16px; color: ${_isLiked ? "#ef4444" : "#d1d5db"};'
                          },
                        ),
                      ],
                      classes: 'flex-row items-center gap-1 bg-transparent border-none cursor-pointer group p-1 rounded hover:bg-gray-50',
                      attributes: const {
                        'type': 'button',
                        'style': 'display: inline-flex; align-items: center; gap: 4px; border: none; background: transparent; cursor: pointer; padding: 4px;'
                      },
                      events: {'click': (e) => _handleLike()},
                    ),
                  ],
                ),
              ],
              classes: 'flex-row justify-between items-start',
              attributes: const {
                'style': 'display: flex; flex-direction: row; justify-content: space-between; align-items: flex-start;'
              },
            ),
            p(
              [Component.text(textContent)],
              classes: 'text-sm text-gray-800 mt-2 leading-relaxed',
              attributes: const {
                'style': 'margin: 6px 0 0 0; font-size: 13px; color: #1f2937; line-height: 1.5; text-align: left; white-space: pre-wrap; word-break: break-word;'
              },
            ),
          ],
          classes: 'flex-1 flex-col',
          attributes: const {
            'style': 'flex: 1; display: flex; flex-direction: column; overflow: hidden;'
          },
        ),
      ],
      classes: 'flex-row gap-3 py-3 border-b border-gray-100 items-start',
      attributes: const {
        'style': 'display: flex; flex-direction: row; gap: 12px; align-items: flex-start; padding: 12px 0; border-bottom: 1px solid #f0f0f0; width: 100%; box-sizing: border-box;'
      },
    );
  }
}