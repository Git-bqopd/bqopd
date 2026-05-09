import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/view_service.dart';
import 'stats_table.dart';
import 'login_widget.dart';

class FanzineWidget extends StatefulWidget {
  final String? fanzineShortCode;
  final bool isStickerOnly;
  final VoidCallback? onLoginRequested;

  const FanzineWidget({
    super.key,
    this.fanzineShortCode,
    this.isStickerOnly = false,
    this.onLoginRequested,
  });

  @override
  State<FanzineWidget> createState() => _FanzineWidgetState();
}

class _FanzineWidgetState extends State<FanzineWidget> {
  User? get currentUser => FirebaseAuth.instance.currentUser;
  final ViewService _viewService = ViewService();
  final PageController _pageController = PageController();
  int _currentPage = 0;

  String _displayUrl = 'bqopd.com/...';
  String? _targetShortCode;
  bool _isLoadingData = true;
  bool _showLoginLink = false;
  Map<String, dynamic>? _fanzineData;
  String? _fanzineId;

  static const Color kPrimaryColor = Color(0xFFF1B255);
  static const double kInternalContentWidth = 200.0;

  @override
  void initState() {
    super.initState();
    _loadData();
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (mounted) {
        _loadData();
      }
    });
  }

  @override
  void didUpdateWidget(covariant FanzineWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fanzineShortCode != widget.fanzineShortCode) _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoadingData = true);
    if (widget.fanzineShortCode != null) {
      await _loadPublicFanzine(widget.fanzineShortCode!);
    } else {
      await _loadDashboard();
    }
    if (mounted) setState(() => _isLoadingData = false);
  }

  Future<void> _loadPublicFanzine(String shortCode) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('fanzines')
          .where('shortCode', isEqualTo: shortCode)
          .limit(1)
          .get();

      if (!mounted) return;

      if (query.docs.isEmpty) {
        setState(() {
          _displayUrl = 'bqopd.com/404';
          _showLoginLink = false;
        });
        return;
      }

      _fanzineId = query.docs.first.id;
      _fanzineData = query.docs.first.data();

      if (currentUser == null || currentUser!.isAnonymous) {
        setState(() {
          _displayUrl = 'Login / Register';
          _showLoginLink = true;
          _targetShortCode = null;
        });
      } else {
        // FIXED: Look up my profile in the 'profiles' collection, not 'Users'
        final profileDoc = await FirebaseFirestore.instance.collection('profiles').doc(currentUser!.uid).get();
        if (mounted) {
          final myUsername = profileDoc.data()?['username'] ?? 'user';
          setState(() {
            _showLoginLink = false;
            _displayUrl = 'bqopd.com/$myUsername';
            _targetShortCode = myUsername;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _displayUrl = 'bqopd.com/error');
    }
  }

  Future<void> _loadDashboard() async {
    if (currentUser == null || currentUser!.isAnonymous) {
      if (mounted) {
        setState(() {
          _displayUrl = 'Login / Register';
          _showLoginLink = true;
        });
      }
      return;
    }
    try {
      // FIXED: Use 'profiles' collection for the URL display
      final profileDoc = await FirebaseFirestore.instance.collection('profiles').doc(currentUser!.uid).get();
      if (profileDoc.exists && mounted) {
        final username = profileDoc.data()?['username'] as String?;
        setState(() {
          _displayUrl = 'bqopd.com/$username';
          _targetShortCode = username;
          _showLoginLink = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading dashboard: $e");
    }
  }

  void _handleLinkTap() {
    if (_showLoginLink) {
      if (widget.onLoginRequested != null) {
        widget.onLoginRequested!();
      } else {
        showDialog(
          context: context,
          builder: (context) => Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
              child: LoginWidget(
                  onTap: () { Navigator.pop(context); context.go('/register'); },
                  onLoginSuccess: () { Navigator.pop(context); _loadData(); }
              ),
            ),
          ),
        );
      }
    } else if (_targetShortCode != null) {
      context.goNamed('shortlink', pathParameters: {'code': _targetShortCode!});
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 5 / 8,
      child: Container(
        color: kPrimaryColor,
        padding: const EdgeInsets.all(10.0),
        child: widget.isStickerOnly
            ? _buildStickerOnlyView()
            : _buildFullInteractiveView(),
      ),
    );
  }

  Widget _buildStickerOnlyView() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2, offset: const Offset(0, 1))
          ],
        ),
        child: Image.asset('assets/logo200.gif', width: 100, fit: BoxFit.contain),
      ),
    );
  }

  Widget _buildFullInteractiveView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: GestureDetector(
            onTap: _handleLinkTap,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2, offset: const Offset(0, 1))
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                margin: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _displayUrl.toLowerCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),

        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2, offset: const Offset(0, 1))
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildNavText("indicia", 0),
                      _buildNavDivider(),
                      _buildNavText("creators", 1),
                      _buildNavDivider(),
                      _buildNavText("stats", 2),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: _DashedSeparator(height: 1, color: Color(0xFFD1D1D1)),
                ),
                Expanded(
                  child: _isLoadingData
                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                      : PageView(
                    controller: _pageController,
                    onPageChanged: (index) => setState(() => _currentPage = index),
                    children: [
                      Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: kInternalContentWidth), child: _buildIndiciaTab())),
                      Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: kInternalContentWidth), child: _buildCreatorsTab())),
                      Center(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: _buildStatsTab())))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIndiciaTab() {
    final indiciaText = _fanzineData?['masterIndicia'] as String? ?? "© 2026 BQOPD Collective.";
    return SingleChildScrollView(padding: const EdgeInsets.all(12.0), child: Text(indiciaText, style: const TextStyle(fontSize: 10, height: 1.5, color: Colors.black87, fontFamily: 'Georgia'), textAlign: TextAlign.justify));
  }

  Widget _buildCreatorsTab() {
    final creators = (_fanzineData?['masterCreators'] as List?)?.map((e) => e as Map<String, dynamic>).toList() ?? [];
    if (creators.isEmpty) return const Center(child: Text("No creators listed.", style: TextStyle(fontSize: 10, color: Colors.grey)));
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      itemCount: creators.length,
      separatorBuilder: (c, i) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final creator = creators[index];
        return Row(
          children: [
            SizedBox(width: 45, child: Text((creator['role'] ?? 'Creator').toString().toUpperCase(), style: const TextStyle(fontSize: 8, color: Colors.black54, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 6.0), child: Text("|", style: TextStyle(fontSize: 10, color: Colors.black12))),
            Expanded(child: _buildCreatorInfo(creator['uid'], (creator['name'] ?? 'Unknown'))),
          ],
        );
      },
    );
  }

  Widget _buildCreatorInfo(String? uid, String fallbackName) {
    if (uid == null || uid.isEmpty) {
      return Row(children: [
        Container(width: 28, height: 28, decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.05), shape: BoxShape.circle), child: Center(child: Text(fallbackName.isNotEmpty ? fallbackName[0].toUpperCase() : '?', style: const TextStyle(fontSize: 10, color: Colors.black54)))),
        const SizedBox(width: 8),
        Expanded(child: Text(fallbackName.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis)),
      ]);
    }
    return FutureBuilder<DocumentSnapshot>(
      // FIXED: Fetch from 'profiles' for correct display name/photo
        future: FirebaseFirestore.instance.collection('profiles').doc(uid).get(),
        builder: (context, snap) {
          final data = snap.data?.data() as Map<String, dynamic>?;
          final name = (data?['displayName'] ?? data?['username'] ?? fallbackName).toString().toUpperCase();
          final photoUrl = data?['photoUrl'];
          return Row(children: [
            CircleAvatar(radius: 14, backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null, child: photoUrl == null ? Text(name[0]) : null),
            const SizedBox(width: 8),
            Expanded(child: Text(name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis)),
          ]);
        }
    );
  }

  Widget _buildStatsTab() {
    if (_fanzineId == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(top: 16.0), child: StatsTable(contentId: _fanzineId!, viewService: _viewService, isFanzine: true));
  }

  Widget _buildNavText(String text, int index) {
    final bool isActive = _currentPage == index;
    return GestureDetector(
      onTap: () => _pageController.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: isActive ? FontWeight.bold : FontWeight.normal, color: isActive ? Colors.black : Colors.grey)),
    );
  }

  Widget _buildNavDivider() => const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("|", style: TextStyle(fontSize: 10, color: Color(0xFFD1D1D1))));
}

class _DashedSeparator extends StatelessWidget {
  final double height;
  final Color color;
  const _DashedSeparator({this.height = 1, this.color = Colors.black});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final dashCount = (constraints.constrainWidth() / 8).floor();
      return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(dashCount, (_) => SizedBox(width: 4, height: height, child: DecoratedBox(decoration: BoxDecoration(color: color)))));
    });
  }
}