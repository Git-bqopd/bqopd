import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/view_service.dart';
import 'stats_table.dart';
import 'login_widget.dart';

class FanzineWidget extends StatefulWidget {
  final String? fanzineShortCode;

  const FanzineWidget({super.key, this.fanzineShortCode});

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

  @override
  void initState() { super.initState(); _loadData(); }

  @override
  void didUpdateWidget(covariant FanzineWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fanzineShortCode != widget.fanzineShortCode) _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoadingData = true);
    if (widget.fanzineShortCode != null) await _loadPublicFanzine(widget.fanzineShortCode!);
    else await _loadDashboard();
    if (mounted) setState(() => _isLoadingData = false);
  }

  Future<void> _loadPublicFanzine(String shortCode) async {
    try {
      final query = await FirebaseFirestore.instance.collection('fanzines').where('shortCode', isEqualTo: shortCode).limit(1).get();
      if (query.docs.isEmpty) { _displayUrl = 'bqopd.com/404'; return; }
      _fanzineId = query.docs.first.id;
      _fanzineData = query.docs.first.data();
      if (currentUser == null || currentUser!.isAnonymous) { _displayUrl = 'Login or Register'; _showLoginLink = true; _targetShortCode = null; }
      else {
        _showLoginLink = false;
        final userDoc = await FirebaseFirestore.instance.collection('Users').doc(currentUser!.uid).get();
        final myUsername = userDoc.data()?['username'] ?? 'user';
        _displayUrl = 'bqopd.com/$myUsername';
        _targetShortCode = myUsername;
      }
    } catch (e) { _displayUrl = 'bqopd.com/error'; }
  }

  Future<void> _loadDashboard() async {
    if (currentUser == null || currentUser!.isAnonymous) { _displayUrl = 'Login or Register'; _showLoginLink = true; return; }
    try {
      final userDoc = await FirebaseFirestore.instance.collection('Users').doc(currentUser!.uid).get();
      if (userDoc.exists) {
        final username = userDoc.data()?['username'] as String?;
        _displayUrl = 'bqopd.com/$username';
        _targetShortCode = username;
      }
    } catch (e) { debugPrint("Error loading dashboard: $e"); }
  }

  void _handleLinkTap() {
    if (_showLoginLink) {
      showDialog(context: context, builder: (context) => Dialog(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600), child: LoginWidget(onTap: () { Navigator.pop(context); context.go('/register'); }, onLoginSuccess: () { Navigator.pop(context); _loadData(); }))));
    } else if (_targetShortCode != null) {
      context.goNamed('shortlink', pathParameters: {'code': _targetShortCode!});
    }
  }

  @override
  void dispose() { _pageController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final linkStyle = TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColorDark, fontSize: 16);
    return Container(
      height: 300,
      decoration: const BoxDecoration(color: Color(0xFFF1B255)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _isLoadingData ? const Center(child: CircularProgressIndicator()) : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FittedBox(fit: BoxFit.scaleDown, child: RichText(text: TextSpan(text: _displayUrl, style: linkStyle, recognizer: TapGestureRecognizer()..onTap = _handleLinkTap))),
          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 1, color: Colors.black54),
          const SizedBox(height: 20),
          FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [_buildTab('indicia', 0), _buildTabSeparator(), _buildTab('creators', 1), _buildTabSeparator(), _buildTab('stats', 2)])),
          const SizedBox(height: 10),
          Expanded(child: PageView(controller: _pageController, onPageChanged: (index) => setState(() => _currentPage = index), children: [_buildIndiciaTab(), _buildCreatorsTab(), _buildStatsTab()])),
        ]),
      ),
    );
  }

  Widget _buildIndiciaTab() {
    if (_fanzineData == null) return const Center(child: Text("Indicia pending curation."));
    return SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_fanzineData!['title'] ?? 'Untitled', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      const SizedBox(height: 4),
      Text("Status: ${_fanzineData!['status']}", style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.black54)),
      if (_fanzineData!['creationDate'] != null) Text("Archived: ${(_fanzineData!['creationDate'] as Timestamp).toDate().year}"),
      const SizedBox(height: 8),
      const Text("Detailed volume/issue information coming soon.", style: TextStyle(fontSize: 12, color: Colors.black45)),
    ]));
  }

  Widget _buildCreatorsTab() {
    final mentions = List<String>.from(_fanzineData?['mentionedUsers'] ?? []);
    if (mentions.isEmpty) return const Center(child: Text("No verified entities found yet."));
    return ListView.builder(itemCount: mentions.length, itemBuilder: (context, index) {
      final parts = mentions[index].split(':');
      final uid = parts.last;
      return FutureBuilder<DocumentSnapshot>(future: FirebaseFirestore.instance.collection('Users').doc(uid).get(), builder: (context, snap) {
        if (!snap.hasData) return const SizedBox();
        final data = snap.data!.data() as Map<String, dynamic>?;
        final name = data != null ? "${data['displayName'] ?? ''} @${data['username'] ?? 'user'}".trim() : 'Unknown Entity';
        final username = data?['username'] ?? uid;
        return ListTile(dense: true, leading: const Icon(Icons.verified_user, size: 16, color: Colors.indigo), title: Text(name), onTap: () => context.go('/$username'));
      });
    });
  }

  Widget _buildStatsTab() {
    if (_fanzineId == null) return const Center(child: Text("Engagement stats loading..."));
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          children: [
            // Use StatsTable for the Fanzine context
            StatsTable(contentId: _fanzineId!, viewService: _viewService, isFanzine: true),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text("${_fanzineData?['pageCount'] ?? 0} TOTAL PAGES", style: const TextStyle(fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String text, int index) => GestureDetector(onTap: () => _pageController.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut), child: Text(text, style: TextStyle(fontSize: 16, fontWeight: _currentPage == index ? FontWeight.bold : FontWeight.normal, color: _currentPage == index ? Colors.black : Colors.black54)));
  Widget _buildTabSeparator() => const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text('|', style: TextStyle(fontSize: 16, color: Colors.black54)));
}