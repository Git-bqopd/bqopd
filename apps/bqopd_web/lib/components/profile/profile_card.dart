import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';

/// Squared premium presentation profile card.
/// Eliminates direct mutations, relying on follow-toggle callbacks and mini-tabs.
class ProfileCard extends StatefulComponent {
  final UserProfile profile;
  final bool isMe;
  final bool isFollowing;
  final VoidCallback onFollowToggle;

  const ProfileCard({
    required this.profile,
    required this.isMe,
    required this.isFollowing,
    required this.onFollowToggle,
    super.key,
  });

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<ProfileCard> {
  int _socialSubTabIndex = 0; // 0: socials, 1: affiliations, 2: upcoming
  bool _showModal = false;
  String _modalTitle = '';
  String _modalCollection = '';

  void _openFollowModal(String title, String collectionName) {
    setState(() {
      _modalTitle = title;
      _modalCollection = collectionName;
      _showModal = true;
    });
  }

  Component _buildLeftCardDetailsPart(bool isMobile) {
    final displayName = component.profile.displayName.isNotEmpty
        ? component.profile.displayName
        : component.profile.username;
    final username = component.profile.username;
    final bio = component.profile.bio;
    final photoUrl = component.profile.photoUrl;

    final String editHref = component.isMe
        ? '/edit-info'
        : '/edit-info?userId=${component.profile.uid}';

    return div(
      [
        div(
            [
              // Avatar Circle
              div(
                [
                  if (photoUrl.isNotEmpty)
                    img(src: photoUrl, attributes: const {'style': 'width: 100%; height: 100%; object-fit: cover; display: block;'})
                  else
                    span([
                      text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?')
                    ], attributes: const {'style': 'font-size: 28px; font-weight: bold; color: #9ca3af;'})
                ],
                attributes: const {
                  'style': 'width: 72px; height: 72px; border-radius: 50%; background-color: #f3f4f6; overflow: hidden; border: 2px solid #ccc; display: flex; justify-content: center; align-items: center;'
                },
              ),
              span([], attributes: const {'style': 'display: inline-block; width: 16px;'}),
              // Follow button / Edit details
              div(
                  [
                    if (!component.isMe)
                      button(
                          [text(component.isFollowing ? 'unfollow' : 'follow')],
                          classes: component.isFollowing ? 'profile-btn text-red-500' : 'profile-btn',
                          attributes: const {'style': 'width: 100px; height: 28px; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; border-radius: 0px !important; cursor: pointer; border: 1px solid black; background: white;'},
                          events: {
                            'click': (e) {
                              final uid = getCurrentUserId();
                              if (uid == null) {
                                GlobalModalBus.show();
                                return;
                              }
                              component.onFollowToggle();
                            }
                          }
                      )
                    else
                      a(
                          [text('edit info')],
                          href: editHref,
                          classes: 'profile-btn',
                          attributes: const {'style': 'width: 100px; height: 28px; display: inline-flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; text-align: center; border: 1px solid #ddd; border-radius: 0px !important; background: white;'}
                      ),
                    div([], attributes: const {'style': 'height: 4px;'}),
                    div(
                        [
                          span(
                            [text('${component.profile.followerCount} followers')],
                            attributes: const {'style': 'text-decoration: underline; margin-right: 8px; cursor: pointer;'},
                            events: {'click': (e) => _openFollowModal('Followers', 'followers')},
                          ),
                          span(
                            [text('${component.profile.followingCount} following')],
                            attributes: const {'style': 'text-decoration: underline; cursor: pointer;'},
                            events: {'click': (e) => _openFollowModal('Following', 'following')},
                          )
                        ],
                        attributes: const {'style': 'font-size: 10px; font-weight: 500; color: #555; display: flex;'}
                    )
                  ],
                  attributes: const {'style': 'display: flex; flex-direction: column; align-items: flex-start; justify-content: center;'}
              )
            ],
            attributes: const {'style': 'display: flex; align-items: center; justify-content: center;'}
        ),
        div([], attributes: const {'style': 'height: 12px;'}),
        h1([text(displayName)], attributes: const {'style': 'font-size: 18px; font-weight: 900; margin: 0; color: black; line-height: 1.2;'}),
        p([text('@$username')], attributes: const {'style': 'font-size: 12px; color: #666; margin: 2px 0 0 0;'}),
        if (bio.isNotEmpty) ...[
          div([], attributes: const {'style': 'height: 8px;'}),
          p([text(bio)], attributes: const {
            'style': 'font-size: 11px; color: #444; font-style: italic; margin-top: 4px; line-height: 1.4; max-width: 280px; text-align: center;'
          })
        ]
      ],
      classes: isMobile ? '' : 'profile-desktop-left',
    );
  }

  Component _buildRightCardSocialsPart(bool isMobile) {
    return div(
      [
        div(
            [
              _buildSocialHeaderMiniTab("socials", 0),
              span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
              _buildSocialHeaderMiniTab("affiliations", 1),
              span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
              _buildSocialHeaderMiniTab("upcoming", 2)
            ],
            classes: 'py-2 bg-gray-100 rounded-md',
            attributes: const {'style': 'display: flex; justify-content: center; margin-bottom: 16px;'}
        ),
        if (_socialSubTabIndex == 0) ...[
          _buildSocialLinkButton("X / Twitter", component.profile.xHandle, "https://x.com/"),
          _buildSocialLinkButton("Instagram", component.profile.instagramHandle, "https://instagram.com/"),
          _buildSocialLinkButton("GitHub", component.profile.githubHandle, "https://github.com/"),
          if ((component.profile.xHandle ?? '').isEmpty &&
              (component.profile.instagramHandle ?? '').isEmpty &&
              (component.profile.githubHandle ?? '').isEmpty)
            div(
                [
                  span([text('contact_mail')], classes: 'material-symbols-outlined text-gray-300', attributes: const {'style': 'font-size: 32px;'}),
                  p([text("No external accounts linked.")], attributes: const {'style': 'font-size: 11px; color: #999; font-style: italic; margin-top: 4px; margin-bottom: 0;'})
                ],
                attributes: const {'style': 'display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 100px; flex: 1;'}
            )
        ] else if (_socialSubTabIndex == 1)
          div(
              [
                p([text("Affiliations Coming Soon")], attributes: const {'style': 'font-size: 12px; color: #999; font-style: italic; margin: 0;'})
              ],
              attributes: const {'style': 'display: flex; align-items: center; justify-content: center; min-height: 100px; flex: 1;'}
          )
        else if (_socialSubTabIndex == 2)
            div(
                [
                  p([text("Upcoming Events Coming Soon")], attributes: const {'style': 'display: flex; align-items: center; justify-content: center; min-height: 100px; flex: 1; margin: 0;'})
                ],
                attributes: const {'style': 'display: flex; align-items: center; justify-content: center; min-height: 100px; flex: 1;'}
            )
          else
            div([]),
        div([], attributes: const {'style': 'flex: 1;'}),
        if (component.isMe)
          div(
              [
                button(
                    [text('logout')],
                    classes: 'btn-logout',
                    attributes: const {'style': 'font-size: 12px; font-weight: bold; text-decoration: underline; background: none; border: none; cursor: pointer; color: black;'},
                    events: {'click': (e) => logoutFromFirebase()}
                )
              ],
              attributes: const {'style': 'display: flex; justify-content: flex-end; margin-top: 12px;'}
          )
      ],
      classes: isMobile ? 'w-full h-full' : 'profile-desktop-right',
      attributes: isMobile ? const {'style': 'display: flex; flex-direction: column;'} : null,
    );
  }

  Component _buildSocialHeaderMiniTab(String title, int idx) {
    final bool isSelected = _socialSubTabIndex == idx;
    return span(
        [text(title)],
        classes: isSelected ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer',
        events: {
          'click': (e) {
            setState(() => _socialSubTabIndex = idx);
          }
        }
    );
  }

  Component _buildSocialLinkButton(String platform, String? handle, String baseUrl) {
    if (handle == null || handle.trim().isEmpty) return div([]);
    return a(
        [
          span([
            text(platform.startsWith('X') ? 'link' : 'alternate_email')
          ], classes: 'material-symbols-outlined text-gray-500', attributes: const {'style': 'font-size: 16px;'}),
          span([text('$platform: ')], attributes: const {'style': 'font-size: 11px; font-weight: bold; color: black; margin-left: 8px;'}),
          span([text('@$handle')], classes: 'handle-text')
        ],
        href: '$baseUrl$handle',
        classes: 'social-link-button',
        attributes: const {
          'target': '_blank'
        }
    );
  }

  @override
  Component build(BuildContext context) {
    return div(
      [
        // Desktop Layout
        div(
            [
              div(
                  [
                    _buildLeftCardDetailsPart(false),
                    div([], classes: 'profile-desktop-divider'),
                    _buildRightCardSocialsPart(false)
                  ],
                  classes: 'white-sticker-8-5'
              )
            ],
            classes: 'envelope-8-5-desktop'
        ),
        // Mobile Layout
        div(
            [
              div(
                  [
                    div([_buildLeftCardDetailsPart(true)], classes: 'white-sticker-mobile-8-5')
                  ],
                  classes: 'envelope-8-5-mobile-item'
              ),
              div(
                  [
                    div([_buildRightCardSocialsPart(true)], classes: 'white-sticker-mobile-8-5')
                  ],
                  classes: 'envelope-8-5-mobile-item'
              )
            ],
            classes: 'envelope-8-5-mobile-container'
        ),
        if (_showModal)
          FollowListModal(
            targetUid: component.profile.uid,
            title: _modalTitle,
            collectionName: _modalCollection,
            onClose: () => setState(() => _showModal = false),
          )
      ],
    );
  }
}

class FollowListModal extends StatefulComponent {
  final String targetUid;
  final String title;
  final String collectionName;
  final VoidCallback onClose;

  const FollowListModal({
    required this.targetUid,
    required this.title,
    required this.collectionName,
    required this.onClose,
    super.key,
  });

  @override
  State<FollowListModal> createState() => _FollowListModalState();
}

class _FollowListModalState extends State<FollowListModal> {
  bool _loading = true;
  List<String> _uids = [];
  Map<String, Map<String, dynamic>> _profiles = {};
  String _searchQuery = '';
  FirebaseSubscription? _listSub;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _listenToList();
    }
  }

  @override
  void dispose() {
    _listSub?.callAsFunction();
    super.dispose();
  }

  void _listenToList() {
    _listSub?.callAsFunction();
    _listSub = fsListenQuery('profiles/${component.targetUid}/${component.collectionName}', '', '', '', '', false, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        final List<String> loadedUids = decoded.map((d) => d['id'].toString()).where((id) => id.isNotEmpty).toList();

        if (mounted) {
          setState(() {
            _uids = loadedUids;
          });
          _fetchProfiles(loadedUids);
        }
      } catch (e) {
        print("Error streaming follow list: $e");
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  Future<void> _fetchProfiles(List<String> uids) async {
    if (uids.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final Map<String, Map<String, dynamic>> temp = {};
    final List<Future<void>> fetches = [];

    for (var uid in uids) {
      fetches.add(
        fsGetDoc('profiles/$uid').then((res) {
          final doc = jsonDecode(res);
          if (doc['exists'] == true) {
            temp[uid] = doc['data'] as Map<String, dynamic>;
          }
        }),
      );
    }

    await Future.wait(fetches);

    if (mounted) {
      setState(() {
        _profiles = temp;
        _loading = false;
      });
    }
  }

  @override
  Component build(BuildContext context) {
    final filteredUids = _uids.where((uid) {
      final p = _profiles[uid];
      if (_searchQuery.trim().isEmpty) return true;
      final name = (p?['displayName'] ?? '').toString().toLowerCase();
      final username = (p?['username'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || username.contains(query);
    }).toList();

    return div(
        classes: 'global-modal-overlay',
        attributes: const {
          'style': 'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.6); z-index: 20000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(4px);'
        },
        [
          div(
              classes: 'manila-envelope',
              attributes: const {
                'style': 'width: 90%; max-width: 400px; max-height: 520px; border-radius: 12px; overflow: hidden; position: relative;'
              },
              [
                div(
                    classes: 'white-sticker p-4 w-full h-full flex flex-col',
                    attributes: const {
                      'style': 'padding: 20px; display: flex; flex-direction: column; width: 100%; height: 100%; box-sizing: border-box; background: white; border-radius: 12px;'
                    },
                    [
                      // Modal Header
                      div(
                          attributes: const {
                            'style': 'display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #eee; padding-bottom: 12px; margin-bottom: 12px;'
                          },
                          [
                            h2([text(component.title)], attributes: const {'style': 'font-size: 16px; font-weight: bold; margin: 0; color: black;'}),
                            button(
                                [text('✕')],
                                attributes: const {
                                  'style': 'border: none; background: transparent; font-size: 18px; font-weight: bold; cursor: pointer; color: #666;'
                                },
                                events: {'click': (e) => component.onClose()}
                            )
                          ]
                      ),
                      // Search bar
                      input(
                          attributes: {
                            'type': 'text',
                            'placeholder': 'Search ${component.title.toLowerCase()}...',
                            'value': _searchQuery,
                            'style': 'width: 100%; padding: 8px 12px; border: 1px solid #ccc; border-radius: 8px; font-size: 13px; margin-bottom: 12px; box-sizing: border-box; outline: none; background: white;'
                          },
                          events: {
                            'input': (e) {
                              setState(() {
                                _searchQuery = getInputValue(e);
                              });
                            }
                          }
                      ),
                      // List body
                      div(
                          classes: 'flex-1 overflow-y-auto',
                          attributes: const {
                            'style': 'flex: 1; overflow-y: auto; display: flex; flex-direction: column; gap: 8px;'
                          },
                          [
                            if (_loading)
                              p([text('Loading...')], classes: 'text-xs text-gray italic text-center py-4')
                            else if (filteredUids.isEmpty)
                              p([text('No ${component.title.toLowerCase()} found.')], classes: 'text-xs text-gray italic text-center py-4')
                            else
                              for (var uid in filteredUids)
                                _buildUserRow(uid)
                          ]
                      )
                    ]
                )
              ]
          )
        ]
    );
  }

  Component _buildUserRow(String uid) {
    final profile = _profiles[uid];
    final displayName = profile?['displayName'] ?? profile?['username'] ?? 'User';
    final username = profile?['username'] ?? uid;
    final photoUrl = profile?['photoUrl'] ?? '';

    return a(
        href: '/$username',
        classes: 'hover:bg-gray-50 transition-colors',
        attributes: const {
          'style': 'display: flex; align-items: center; gap: 12px; padding: 8px; border-bottom: 1px solid #f5f5f5; text-decoration: none;'
        },
        events: {
          'click': (e) {
            component.onClose();
          }
        },
        [
          div(
              [
                if (photoUrl.isNotEmpty)
                  img(src: photoUrl, attributes: const {'style': 'width: 100%; height: 100%; object-fit: cover; display: block;'})
                else
                  span([text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?')], attributes: const {'style': 'font-size: 14px; font-weight: bold; color: #888;'})
              ],
              attributes: const {
                'style': 'width: 36px; height: 36px; border-radius: 50%; background-color: #f0f0f0; overflow: hidden; display: flex; align-items: center; justify-content: center; flex-shrink: 0;'
              }
          ),
          div(
              [
                span([text(displayName)], attributes: const {'style': 'font-size: 13px; font-weight: bold; color: black; line-height: 1.2; text-align: left;'}),
                span([text('@$username')], attributes: const {'style': 'font-size: 11px; color: #666; margin-top: 2px; text-align: left;'})
              ],
              attributes: const {'style': 'display: flex; flex-direction: column; justify-content: center; flex: 1; overflow: hidden;'}
          )
        ]
    );
  }
}