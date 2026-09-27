import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';

/// Squared presentation profile card with no drop shadows on the envelope and white sticker cards.
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
  Map<String, String> _managerUsernames = {};
  List<String> _publicAddressLines = [];

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loadManagerProfiles();
      _loadPublicAddress();
    }
  }

  @override
  void didUpdateComponent(ProfileCard oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.profile.managers != component.profile.managers ||
        oldComponent.profile.isManaged != component.profile.isManaged) {
      if (kIsWeb) {
        _loadManagerProfiles();
      }
    }
    if (oldComponent.profile.uid != component.profile.uid) {
      if (kIsWeb) {
        _loadPublicAddress();
      }
    }
  }

  Future<void> _loadPublicAddress() async {
    final uid = component.profile.uid;
    if (uid.isEmpty) return;
    try {
      final res = await fsGetDoc('profiles/$uid');
      final doc = jsonDecode(res);
      if (doc['exists'] == true && doc['data'] is Map) {
        final data = doc['data'] as Map<String, dynamic>;
        final visibility = data['addressVisibility']?.toString() ??
            (data['isAddressPublic'] == true ? 'address' : 'private');

        if (visibility == 'private') {
          if (mounted && _publicAddressLines.isNotEmpty) {
            setState(() => _publicAddressLines = []);
          }
          return;
        }

        final street1 = (data['street1'] ?? '').toString().trim();
        final street2 = (data['street2'] ?? '').toString().trim();
        final city = (data['city'] ?? '').toString().trim();
        final state = (data['state'] ?? '').toString().trim();
        final zip = (data['zipCode'] ?? '').toString().trim();
        final country = (data['country'] ?? '').toString().trim();

        final lines = <String>[];
        if (visibility == 'address') {
          final streetParts = [
            if (street1.isNotEmpty) street1,
            if (street2.isNotEmpty) street2,
          ];
          if (streetParts.isNotEmpty) {
            lines.add(streetParts.join(', '));
          }

          final cityStateZip = [
            if (city.isNotEmpty) city,
            if (state.isNotEmpty) state,
          ].join(', ') + (zip.isNotEmpty ? ' $zip' : '');
          if (cityStateZip.trim().isNotEmpty) {
            lines.add(cityStateZip.trim());
          }

          if (country.isNotEmpty &&
              country.toLowerCase() != 'us' &&
              country.toLowerCase() != 'usa' &&
              country.toLowerCase() != 'united states') {
            lines.add(country);
          }
        } else if (visibility == 'city') {
          final parts = <String>[];
          if (city.isNotEmpty && state.isNotEmpty) {
            parts.add('$city, $state');
          } else if (city.isNotEmpty) {
            parts.add(city);
          } else if (state.isNotEmpty) {
            parts.add(state);
          }
          if (country.isNotEmpty &&
              country.toLowerCase() != 'us' &&
              country.toLowerCase() != 'usa' &&
              country.toLowerCase() != 'united states') {
            parts.add(country);
          }
          if (parts.isNotEmpty) lines.add(parts.join(', '));
        } else if (visibility == 'state') {
          final parts = <String>[];
          if (state.isNotEmpty) parts.add(state);
          if (country.isNotEmpty &&
              country.toLowerCase() != 'us' &&
              country.toLowerCase() != 'usa' &&
              country.toLowerCase() != 'united states') {
            parts.add(country);
          }
          if (parts.isNotEmpty) lines.add(parts.join(', '));
        }

        if (mounted) {
          setState(() {
            _publicAddressLines = lines;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadManagerProfiles() async {
    if (!component.profile.isManaged || component.profile.managers.isEmpty) {
      if (_managerUsernames.isNotEmpty && mounted) {
        setState(() => _managerUsernames = {});
      }
      return;
    }
    final Map<String, String> resolved = {};
    final List<Future<void>> fetches = [];
    for (final uid in component.profile.managers) {
      fetches.add(
        fsGetDoc('profiles/$uid').then((res) {
          try {
            final doc = jsonDecode(res);
            if (doc['exists'] == true && doc['data'] is Map) {
              final data = doc['data'] as Map<String, dynamic>;
              final uname = (data['username'] ?? '').toString().trim();
              if (uname.isNotEmpty) {
                resolved[uid] = uname;
              }
            }
          } catch (_) {}
        }),
      );
    }
    await Future.wait(fetches);
    if (mounted) {
      setState(() {
        _managerUsernames = resolved;
      });
    }
  }

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

    // CANONICAL VANITY ROUTE: /@handle/edit-info
    final String editHref = username.isNotEmpty
        ? '/@$username/edit-info'
        : '/edit-info?userId=${component.profile.uid}';

    // Verify if viewer manages this entity
    final currentUid = getCurrentUserId();
    final bool canManage = component.profile.isManaged &&
        currentUid != null &&
        component.profile.managers.contains(currentUid);

    return div(
      [
        // Top section: Avatar (col 1) + Name, Handle & Actions (col 2)
        div(
          [
            // Avatar Circle
            div(
              [
                if (photoUrl.isNotEmpty)
                  img(
                    src: photoUrl,
                    attributes: const {
                      'style': 'width: 100%; height: 100%; object-fit: cover; display: block;'
                    },
                  )
                else
                  span(
                    [
                      Component.text(
                        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                      )
                    ],
                    attributes: const {
                      'style': 'font-size: 28px; font-weight: bold; color: #9ca3af;'
                    },
                  )
              ],
              attributes: const {
                'style': 'width: 72px; height: 72px; min-width: 72px; min-height: 72px; border-radius: 50%; background-color: #f3f4f6; overflow: hidden; border: 2px solid #ccc; display: flex; justify-content: center; align-items: center; flex-shrink: 0;'
              },
            ),
            span([], attributes: const {'style': 'display: inline-block; width: 16px;'}),
            // Next column: Row 1 = Display Name & @handle, Row 2 = Public Address, Row 3 = Followers / Following / Button
            div(
              [
                // Row 1: Display Name & @handle inline
                div(
                  [
                    h1(
                      [Component.text(displayName)],
                      attributes: const {
                        'style': 'font-size: 18px; font-weight: 900; margin: 0; color: black; line-height: 1.2; text-align: left;'
                      },
                    ),
                    span(
                      [Component.text('@$username')],
                      attributes: const {
                        'style': 'font-size: 12px; color: #666; margin: 0; text-align: left;'
                      },
                    ),
                  ],
                  attributes: const {
                    'style': 'display: flex; flex-direction: row; align-items: baseline; gap: 6px; flex-wrap: wrap;'
                  },
                ),
                // Row 2: Public Address lines (envelope format, no map pin icon, omitting 'United States')
                if (_publicAddressLines.isNotEmpty)
                  div(
                    [
                      for (final line in _publicAddressLines)
                        div(
                          [Component.text(line)],
                          attributes: const {
                            'style': 'font-size: 11px; color: #555; text-align: left; line-height: 1.35;'
                          },
                        ),
                    ],
                    attributes: const {
                      'style': 'display: flex; flex-direction: column; margin-top: 3px;'
                    },
                  ),
                // Row 3: Followers, Following, and Follow / Edit Info button
                div(
                  [
                    span(
                      [Component.text('${component.profile.followerCount} followers')],
                      attributes: const {
                        'style': 'text-decoration: underline; cursor: pointer;'
                      },
                      events: {'click': (e) => _openFollowModal('Followers', 'followers')},
                    ),
                    span(
                      [Component.text('${component.profile.followingCount} following')],
                      attributes: const {
                        'style': 'text-decoration: underline; cursor: pointer;'
                      },
                      events: {'click': (e) => _openFollowModal('Following', 'following')},
                    ),
                    if (component.profile.isManaged || !component.isMe)
                      button(
                        [Component.text(component.isFollowing ? 'unfollow' : 'follow')],
                        classes: component.isFollowing ? 'profile-btn text-red-500' : 'profile-btn',
                        attributes: const {
                          'style': 'height: 24px; padding: 0 10px; display: inline-flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; border-radius: 0px !important; cursor: pointer; border: 1px solid black; background: white;'
                        },
                        events: {
                          'click': (e) {
                            final uid = getCurrentUserId();
                            if (uid == null) {
                              GlobalModalBus.show();
                              return;
                            }
                            component.onFollowToggle();
                          }
                        },
                      )
                    else
                      a(
                        [Component.text('edit info')],
                        href: editHref,
                        classes: 'profile-btn',
                        attributes: const {
                          'style': 'height: 24px; padding: 0 10px; display: inline-flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; text-align: center; border: 1px solid #ddd; border-radius: 0px !important; background: white; text-decoration: none;'
                        },
                      ),
                  ],
                  attributes: const {
                    'style': 'display: flex; flex-direction: row; align-items: center; gap: 8px; margin-top: 6px; font-size: 10px; font-weight: 500; color: #555; flex-wrap: wrap;'
                  },
                )
              ],
              attributes: const {
                'style': 'display: flex; flex-direction: column; align-items: flex-start; justify-content: center;'
              },
            )
          ],
          attributes: const {'style': 'display: flex; align-items: center; justify-content: center;'},
        ),
        // Row under profile info: "profile managed by:" banner
        if (component.profile.isManaged && component.profile.managers.isNotEmpty) ...[
          div([], attributes: const {'style': 'height: 12px;'}),
          _buildManagedByBanner(canManage, editHref),
        ],
        // Row under banner: Biography
        if (bio.isNotEmpty) ...[
          div([], attributes: const {'style': 'height: 10px;'}),
          p(
            [Component.text(bio)],
            attributes: const {
              'style': 'font-size: 11px; color: #444; font-style: italic; margin: 0; line-height: 1.4; max-width: 280px; text-align: center;'
            },
          )
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
            span(
              [Component.text('|')],
              classes: 'text-xs text-gray',
              attributes: const {'style': 'display: inline-block; margin: 0 8px;'},
            ),
            _buildSocialHeaderMiniTab("affiliations", 1),
            span(
              [Component.text('|')],
              classes: 'text-xs text-gray',
              attributes: const {'style': 'display: inline-block; margin: 0 8px;'},
            ),
            _buildSocialHeaderMiniTab("upcoming", 2)
          ],
          classes: 'py-2 bg-gray-100 rounded-md',
          attributes: const {
            'style': 'display: flex; justify-content: center; margin-bottom: 16px;'
          },
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
                span(
                  [Component.text('contact_mail')],
                  classes: 'material-symbols-outlined text-gray-300',
                  attributes: const {'style': 'font-size: 32px;'},
                ),
                p(
                  [Component.text("No external accounts linked.")],
                  attributes: const {
                    'style': 'font-size: 11px; color: #999; font-style: italic; margin-top: 4px; margin-bottom: 0;'
                  },
                )
              ],
              attributes: const {
                'style': 'display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 100px; flex: 1;'
              },
            )
        ] else if (_socialSubTabIndex == 1)
          div(
            [
              p(
                [Component.text("Affiliations Coming Soon")],
                attributes: const {
                  'style': 'font-size: 12px; color: #999; font-style: italic; margin: 0;'
                },
              )
            ],
            attributes: const {
              'style': 'display: flex; align-items: center; justify-content: center; min-height: 100px; flex: 1;'
            },
          )
        else if (_socialSubTabIndex == 2)
            div(
              [
                p(
                  [Component.text("Upcoming Events Coming Soon")],
                  attributes: const {
                    'style': 'display: flex; align-items: center; justify-content: center; min-height: 100px; flex: 1; margin: 0;'
                  },
                )
              ],
              attributes: const {
                'style': 'display: flex; align-items: center; justify-content: center; min-height: 100px; flex: 1;'
              },
            )
          else
            div([]),
        div([], attributes: const {'style': 'flex: 1;'}),
        if (component.isMe)
          div(
            [
              button(
                [Component.text('logout')],
                classes: 'btn-logout',
                attributes: const {
                  'style': 'font-size: 12px; font-weight: bold; text-decoration: underline; background: none; border: none; cursor: pointer; color: black;'
                },
                events: {'click': (e) => logoutFromFirebase()},
              )
            ],
            attributes: const {
              'style': 'display: flex; justify-content: flex-end; margin-top: 12px;'
            },
          )
      ],
      classes: isMobile ? 'w-full h-full' : 'profile-desktop-right',
      attributes: isMobile ? const {'style': 'display: flex; flex-direction: column;'} : null,
    );
  }

  Component _buildSocialHeaderMiniTab(String title, int idx) {
    final bool isSelected = _socialSubTabIndex == idx;
    return span(
      [Component.text(title)],
      classes: isSelected
          ? 'text-xs font-bold text-black border-b border-black cursor-pointer'
          : 'text-xs text-gray cursor-pointer',
      events: {
        'click': (e) {
          setState(() => _socialSubTabIndex = idx);
        }
      },
    );
  }

  Component _buildSocialLinkButton(String platform, String? handle, String baseUrl) {
    if (handle == null || handle.trim().isEmpty) return div([]);
    return a(
      [
        span(
          [
            Component.text(platform.startsWith('X') ? 'link' : 'alternate_email')
          ],
          classes: 'material-symbols-outlined text-gray-500',
          attributes: const {'style': 'font-size: 16px;'},
        ),
        span(
          [Component.text('$platform: ')],
          attributes: const {
            'style': 'font-size: 11px; font-weight: bold; color: black; margin-left: 8px;'
          },
        ),
        span([Component.text('@$handle')], classes: 'handle-text')
      ],
      href: '$baseUrl$handle',
      classes: 'social-link-button',
      attributes: const {'target': '_blank'},
    );
  }

  Component _buildManagedByBanner(bool canManage, String editHref) {
    return div(
      classes: 'py-2 bg-gray-100 rounded-md',
      attributes: const {
        'style':
        'width: 100%; max-width: 280px; display: flex; flex-direction: row; align-items: center; justify-content: center; flex-wrap: wrap; gap: 4px; box-sizing: border-box; border: none;',
      },
      [
        if (canManage) ...[
          a(
            [Component.text('edit info')],
            href: editHref,
            classes: 'text-xs text-gray hover:text-black',
            attributes: const {
              'style': 'font-size: 11px; font-weight: normal; text-decoration: underline;',
            },
          ),
          span(
            [Component.text('|')],
            classes: 'text-xs text-gray',
            attributes: const {'style': 'font-size: 11px; font-weight: normal; margin: 0 2px;'},
          ),
        ],
        span(
          [Component.text('profile managed by:')],
          classes: 'text-xs text-gray',
          attributes: const {
            'style': 'font-size: 11px; font-weight: normal;',
          },
        ),
        for (int i = 0; i < component.profile.managers.length; i++) ...[
              () {
            final uid = component.profile.managers[i];
            final username = _managerUsernames[uid];
            final displayText = username != null && username.isNotEmpty
                ? '@$username'
                : (uid.length > 8 ? '@${uid.substring(0, 8)}...' : '@$uid');
            final href = username != null && username.isNotEmpty ? '/@$username' : null;

            if (href != null) {
              return a(
                [Component.text(displayText)],
                href: href,
                classes: 'text-xs text-gray hover:text-black',
                attributes: const {
                  'style': 'font-size: 11px; font-weight: normal; text-decoration: underline;',
                },
              );
            } else {
              return span(
                [Component.text(displayText)],
                classes: 'text-xs text-gray',
                attributes: const {
                  'style': 'font-size: 11px; font-weight: normal;',
                },
              );
            }
          }(),
          if (i < component.profile.managers.length - 1)
            span(
              [Component.text(',')],
              classes: 'text-xs text-gray',
              attributes: const {'style': 'font-size: 11px; font-weight: normal; margin-right: 2px;'},
            ),
        ],
      ],
    );
  }

  @override
  Component build(BuildContext context) {
    return div(
      [
        // Desktop envelope view (squared, no drop shadows)
        div(
          classes: 'envelope-8-5-desktop',
          [
            div(
              classes: 'white-sticker-8-5',
              [
                _buildLeftCardDetailsPart(false),
                div([], classes: 'profile-desktop-divider'),
                _buildRightCardSocialsPart(false),
              ],
            ),
          ],
        ),
        // Mobile envelope view (stacked, squared, no drop shadows)
        div(
          classes: 'envelope-8-5-mobile-container',
          [
            div(
              classes: 'envelope-8-5-mobile-item',
              [
                div(
                  classes: 'white-sticker-mobile-8-5',
                  [
                    _buildLeftCardDetailsPart(true),
                  ],
                ),
              ],
            ),
            div(
              classes: 'envelope-8-5-mobile-item',
              [
                div(
                  classes: 'white-sticker-mobile-8-5',
                  [
                    _buildRightCardSocialsPart(true),
                  ],
                ),
              ],
            ),
          ],
        ),
        if (_showModal)
          _FollowersFollowingModal(
            title: _modalTitle,
            collectionName: _modalCollection,
            targetUid: component.profile.uid,
            onClose: () => setState(() => _showModal = false),
          ),
      ],
    );
  }
}

class _FollowersFollowingModal extends StatefulComponent {
  final String title;
  final String collectionName;
  final String targetUid;
  final VoidCallback onClose;

  const _FollowersFollowingModal({
    required this.title,
    required this.collectionName,
    required this.targetUid,
    required this.onClose,
  });

  @override
  State<_FollowersFollowingModal> createState() => _FollowersFollowingModalState();
}

class _FollowersFollowingModalState extends State<_FollowersFollowingModal> {
  bool _loading = true;
  List<String> _uids = [];
  Map<String, Map<String, dynamic>> _profiles = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loadList();
    } else {
      _loading = false;
    }
  }

  Future<void> _loadList() async {
    try {
      final res = await fsQuery(
        'profiles/${component.targetUid}/${component.collectionName}',
        '', '', '', '',
      );
      final List decoded = jsonDecode(res);
      final List<String> uids = [];
      for (var d in decoded) {
        final String uid = (d['id'] ?? d['data']?['uid'] ?? '').toString();
        if (uid.isNotEmpty) uids.add(uid);
      }

      final Map<String, Map<String, dynamic>> profMap = {};
      final List<Future<void>> fetches = [];
      for (final u in uids) {
        fetches.add(
          fsGetDoc('profiles/$u').then((docRes) {
            try {
              final doc = jsonDecode(docRes);
              if (doc['exists'] == true && doc['data'] is Map) {
                profMap[u] = Map<String, dynamic>.from(doc['data']);
              }
            } catch (_) {}
          }),
        );
      }
      await Future.wait(fetches);

      if (mounted) {
        setState(() {
          _uids = uids;
          _profiles = profMap;
          _loading = false;
        });
      }
    } catch (e) {
      print('Error loading follow list: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
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
            'style': 'width: 90%; max-width: 400px; max-height: 520px; border-radius: 0px; box-shadow: none; overflow: hidden; position: relative;'
          },
          [
            div(
              classes: 'white-sticker p-4 w-full h-full flex flex-col',
              attributes: const {
                'style': 'padding: 20px; display: flex; flex-direction: column; width: 100%; height: 100%; box-sizing: border-box; background: white; border-radius: 0px; box-shadow: none;'
              },
              [
                // Modal Header
                div(
                  attributes: const {
                    'style': 'display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #eee; padding-bottom: 12px; margin-bottom: 12px;'
                  },
                  [
                    h2(
                      [Component.text(component.title)],
                      attributes: const {
                        'style': 'font-size: 16px; font-weight: bold; margin: 0; color: black;'
                      },
                    ),
                    button(
                      [Component.text('close')],
                      attributes: const {
                        'style': 'border: none; background: transparent; font-size: 12px; font-weight: bold; cursor: pointer; color: #666;'
                      },
                      events: {'click': (e) => component.onClose()},
                    )
                  ],
                ),
                // Search bar
                input(
                  attributes: {
                    'type': 'text',
                    'placeholder': 'Search ${component.title.toLowerCase()}...',
                    'value': _searchQuery,
                    'style': 'width: 100%; padding: 8px 12px; border: 1px solid #ccc; border-radius: 0px; font-size: 13px; margin-bottom: 12px; box-sizing: border-box; outline: none; background: white;'
                  },
                  events: {
                    'input': (e) {
                      setState(() {
                        _searchQuery = getInputValue(e);
                      });
                    }
                  },
                ),
                // List body
                div(
                  classes: 'flex-1 overflow-y-auto',
                  attributes: const {
                    'style': 'flex: 1; overflow-y: auto; display: flex; flex-direction: column; gap: 8px;'
                  },
                  [
                    if (_loading)
                      p(
                        [Component.text('Loading...')],
                        classes: 'text-xs text-gray italic text-center py-4',
                      )
                    else if (filteredUids.isEmpty)
                      p(
                        [Component.text('No ${component.title.toLowerCase()} found.')],
                        classes: 'text-xs text-gray italic text-center py-4',
                      )
                    else
                      for (var uid in filteredUids)
                        _buildUserRow(uid)
                  ],
                )
              ],
            )
          ],
        )
      ],
    );
  }

  Component _buildUserRow(String uid) {
    final profile = _profiles[uid];
    final displayName = profile?['displayName'] ?? profile?['username'] ?? 'User';
    final username = profile?['username'] ?? uid;
    final photoUrl = profile?['photoUrl'] ?? '';

    return a(
      href: '/@$username',
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
              img(
                src: photoUrl,
                attributes: const {
                  'style': 'width: 100%; height: 100%; object-fit: cover; display: block;'
                },
              )
            else
              span(
                [
                  Component.text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                  )
                ],
                attributes: const {
                  'style': 'font-size: 14px; font-weight: bold; color: #888;'
                },
              )
          ],
          attributes: const {
            'style': 'width: 36px; height: 36px; border-radius: 50%; background-color: #f0f0f0; overflow: hidden; display: flex; align-items: center; justify-content: center; flex-shrink: 0;'
          },
        ),
        div(
          [
            span(
              [Component.text(displayName)],
              attributes: const {
                'style': 'font-size: 13px; font-weight: bold; color: black; line-height: 1.2; text-align: left;'
              },
            ),
            span(
              [Component.text('@$username')],
              attributes: const {
                'style': 'font-size: 11px; color: #666; margin-top: 2px; text-align: left;'
              },
            )
          ],
          attributes: const {
            'style': 'display: flex; flex-direction: column; justify-content: center; flex: 1; overflow: hidden;'
          },
        )
      ],
    );
  }
}