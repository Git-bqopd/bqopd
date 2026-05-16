import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'dart:convert';
import '../utils/web_firebase_interop.dart';
import 'stats_table.dart';

class FanzineHeader extends StatefulComponent {
  final String? fanzineId;
  final String? shortCode;
  final Map<String, dynamic>? fanzineData;
  final Map<String, Map<String, dynamic>> creatorProfiles;
  final Map<String, Map<String, dynamic>> imageStats;
  final List<Map<String, dynamic>> pageStructure;
  final bool isStickerOnly;

  const FanzineHeader({
    this.fanzineId,
    this.shortCode,
    this.fanzineData,
    this.creatorProfiles = const {},
    this.imageStats = const {},
    this.pageStructure = const [],
    this.isStickerOnly = false,
    super.key,
  });

  @override
  State<FanzineHeader> createState() => _FanzineHeaderState();
}

class _FanzineHeaderState extends State<FanzineHeader> {
  int _activeTab = 0; // 0: indicia, 1: creators, 2: stats
  String _displayUrl = 'bqopd.com/...';

  @override
  void initState() {
    super.initState();
    _resolveDisplayUrl();
  }

  Future<void> _resolveDisplayUrl() async {
    final uid = getCurrentUserId();
    if (uid == null) {
      if (mounted) setState(() => _displayUrl = 'login / register');
    } else {
      final res = await fsGetDoc('profiles/$uid');
      final data = jsonDecode(res);
      if (data['exists'] && mounted) {
        setState(() => _displayUrl = 'bqopd.com/${data['data']['username']}');
      }
    }
  }

  @override
  Component build(BuildContext context) {
    // Both views share the common navigation link at the top
    final navLink = button(
      classes: 'nav-pill',
      events: {
        'click': (e) {
          final uid = getCurrentUserId();
          if (uid == null) {
            Router.of(context).push('/login');
          } else {
            Router.of(context).push('/profile');
          }
        }
      },
      [text(_displayUrl)],
    );

    if (component.isStickerOnly) {
      // EXPLICIT COMPACT LOGO MODE
      return div(classes: 'flex-col items-center w-full h-full p-2', [
        navLink,
        div(
            classes: 'flex-1 flex-col justify-center items-center w-full',
            [
              div(
                  classes: 'white-sticker',
                  [
                    img(
                      src: 'assets/logo200.gif',
                      attributes: {'style': 'width: 100px; height: auto; display: block;'},
                    )
                  ]
              )
            ]
        )
      ]);
    }

    final indiciaText = component.fanzineData?['masterIndicia'] ?? "© 2026 BQOPD Collective.";
    final creators = component.fanzineData?['masterCreators'] as List? ?? [];

    // STICKER VIEW (Responsive Toggle)
    final stickerView = div(
        classes: 'fh-sticker-view flex-col items-center w-full h-full p-2',
        [
          navLink,
          div(
              classes: 'flex-1 flex-col justify-center items-center w-full',
              [
                div(
                    classes: 'white-sticker',
                    [
                      img(
                        src: 'assets/logo200.gif',
                        attributes: {'style': 'width: 100px; height: auto; display: block;'},
                      )
                    ]
                )
              ]
          )
        ]
    );

    // FULL VIEW (Responsive Toggle)
    final fullView = div(classes: 'fh-full-view flex-col items-center w-full h-full p-2', [
      navLink,
      div(classes: 'white-sticker-compact w-full mt-2', [
        div(classes: 'flex-row justify-center items-center py-2 bg-gray-100', [
          _buildTab('indicia', 0),
          span(classes: 'px-4 text-gray text-xs', [text('|')]),
          _buildTab('creators', 1),
          span(classes: 'px-4 text-gray text-xs', [text('|')]),
          _buildTab('stats', 2),
        ]),
        div(classes: 'flex-col flex-1 p-4 overflow-y-auto', [
          div(classes: _activeTab == 0 ? '' : 'hidden', [
            p(
              classes: 'text-xs text-justify',
              attributes: {'style': 'font-family: Georgia; line-height: 1.5;'},
              [text(indiciaText)],
            )
          ]),
          div(classes: _activeTab == 1 ? '' : 'hidden', [
            _buildCreatorsTab(creators),
          ]),
          div(classes: _activeTab == 2 ? '' : 'hidden', [
            if (component.fanzineId != null)
              StatsTable(
                contentId: component.fanzineId!,
                isFanzine: true,
                preloadedPages: component.pageStructure,
                preloadedStats: component.imageStats,
              )
          ])
        ])
      ])
    ]);

    return div(classes: 'w-full h-full', [
      stickerView,
      fullView,
    ]);
  }

  Component _buildTab(String label, int index) {
    final isActive = _activeTab == index;
    return span(
      classes: 'text-xs cursor-pointer ${isActive ? 'font-bold' : 'text-gray'}',
      events: {'click': (e) => setState(() => _activeTab = index)},
      [text(label)],
    );
  }

  Component _buildCreatorsTab(List creators) {
    if (creators.isEmpty) return p(classes: 'text-xs text-center text-gray', [text('No creators listed.')]);

    return div(classes: 'creator-list', [
      div(attributes: {'style': 'display: inline-flex; flex-direction: column; align-items: flex-start;'}, [
        for (var c in creators)
          div(
            classes: 'creator-row',
            attributes: {'style': 'width: auto;'},
            [
              span(classes: 'creator-role', [text('${c['role']}')]),
              span(classes: 'creator-divider', [text('|')]),
              div(classes: 'creator-identity', [
                UserTile(
                  profile: component.creatorProfiles[c['uid']],
                  fallbackName: c['name'] ?? 'Unknown',
                ),
              ]),
            ],
          )
      ])
    ]);
  }
}

class UserTile extends StatelessComponent {
  final Map<String, dynamic>? profile;
  final String fallbackName;

  const UserTile({this.profile, required this.fallbackName, super.key});

  @override
  Component build(BuildContext context) {
    final String displayName = profile?['displayName'] ?? fallbackName;
    final String? username = profile?['username'];
    final String? photoUrl = profile?['photoUrl'];

    return div(classes: 'user-tile', [
      div(classes: 'user-avatar-container', [
        if (photoUrl != null && photoUrl.isNotEmpty)
          img(classes: 'user-avatar', src: photoUrl)
        else
          div(classes: 'user-avatar-placeholder', [text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?')])
      ]),
      div(classes: 'user-info', [
        div(classes: 'user-display-name', [text(displayName)]),
        if (username != null) div(classes: 'user-handle', [text('@$username')])
      ])
    ]);
  }
}