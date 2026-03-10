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
  int _currentPage = 0; // 0=Indicia, 1=Creators, 2=Stats

  String _displayUrl = 'bqopd.com/...';
  String? _targetShortCode;
  bool _isLoadingData = true;
  bool _showLoginLink = false;
  Map<String, dynamic>? _fanzineData;
  String? _fanzineId;

  // Design Tokens
  static const Color kPrimaryColor = Color(0xFFF1B255);
  static const Color kBgLight = Color(0xFFF8F7F6);
  static const double kInternalContentWidth = 200.0; // The "mobile" width constraint

  // --- DUMMY DATA FOR UI ITERATION ---
  final String _dummyIndicia =
      "© 2026 BQOPD Collective. All rights reserved.\n\n"
      "Published digitally on the bqopd platform. No part of this publication "
      "may be reproduced, distributed, or transmitted in any form or by any means, "
      "including photocopying, recording, or other electronic or mechanical methods, "
      "without the prior written permission of the publisher, except in the case of "
      "brief quotations embodied in critical reviews and certain other noncommercial "
      "uses permitted by copyright law.\n\n"
      "Characters and likenesses remain the property of their respective trademark holders.";

  final List<Map<String, dynamic>> _dummyCreators = [
    {"name": "Jack Kirby", "uid": "dummy_1", "role": "Penciller"},
    {"name": "Stan Lee", "uid": "dummy_2", "role": "Writer / Editor"},
    {"name": "Artie Simek", "uid": null, "role": "Letterer"}, // Example of non-platform user
    {"name": "Marie Severin", "uid": null, "role": "Colorist"},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
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
      if (query.docs.isEmpty) {
        _displayUrl = 'bqopd.com/404';
        return;
      }
      _fanzineId = query.docs.first.id;
      _fanzineData = query.docs.first.data();
      if (currentUser == null || currentUser!.isAnonymous) {
        _displayUrl = 'Login / Register';
        _showLoginLink = true;
        _targetShortCode = null;
      } else {
        _showLoginLink = false;
        final userDoc = await FirebaseFirestore.instance.collection('Users').doc(currentUser!.uid).get();
        final myUsername = userDoc.data()?['username'] ?? 'user';
        _displayUrl = 'bqopd.com/$myUsername';
        _targetShortCode = myUsername;
      }
    } catch (e) {
      _displayUrl = 'bqopd.com/error';
    }
  }

  Future<void> _loadDashboard() async {
    if (currentUser == null || currentUser!.isAnonymous) {
      _displayUrl = 'Login / Register';
      _showLoginLink = true;
      return;
    }
    try {
      final userDoc = await FirebaseFirestore.instance.collection('Users').doc(currentUser!.uid).get();
      if (userDoc.exists) {
        final username = userDoc.data()?['username'] as String?;
        _displayUrl = 'bqopd.com/$username';
        _targetShortCode = username;
      }
    } catch (e) {
      debugPrint("Error loading dashboard: $e");
    }
  }

  void _handleLinkTap() {
    if (_showLoginLink) {
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- TOP PILL (URL) ---
            Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(color: Colors.black.withOpacity(0.05)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                margin: const EdgeInsets.only(bottom: 10),
                child: RichText(
                  text: TextSpan(
                    text: _displayUrl.toLowerCase(),
                    style: const TextStyle(
                      fontFamily: 'Impact', // Or fallback to heavyweight
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                      letterSpacing: 0.5,
                    ),
                    recognizer: TapGestureRecognizer()..onTap = _handleLinkTap,
                  ),
                ),
              ),
            ),

            // --- MAIN CARD ---
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black.withOpacity(0.05)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // --- NAVIGATION ROW ---
                    Container(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          _buildNavText("indicia", 0),
                          _buildNavDivider(),
                          _buildNavText("creators", 1),
                          _buildNavDivider(),
                          _buildNavText("stats", 2),
                        ],
                      ),
                    ),

                    // --- PERFORATED LINE ---
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: _DashedSeparator(height: 1, color: Color(0xFFD1D1D1)),
                    ),

                    // --- CONTENT AREA ---
                    Expanded(
                      child: _isLoadingData
                          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                          : PageView(
                        controller: _pageController,
                        onPageChanged: (index) => setState(() => _currentPage = index),
                        children: [
                          // Tab 0: Indicia (Constrained to 200px)
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: kInternalContentWidth),
                              child: _buildIndiciaTab(),
                            ),
                          ),
                          // Tab 1: Creators (Constrained to 200px)
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: kInternalContentWidth),
                              child: _buildCreatorsTab(),
                            ),
                          ),
                          // Tab 2: Stats (Unconstrained width, centered, scrolls if needed)
                          Center(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SingleChildScrollView(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                  child: _buildStatsTab(),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- SUB-WIDGETS FOR TABS ---

  Widget _buildIndiciaTab() {
    if (_fanzineData == null && _isLoadingData) return const Center(child: Text("Pending...", style: TextStyle(fontSize: 10)));

    final indiciaText = _fanzineData?['masterIndicia'] as String? ?? _dummyIndicia;
    final title = _fanzineData?['title'] ?? 'Untitled';
    final status = _fanzineData?['status'] ?? 'Draft';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              title.toString().toUpperCase(),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, height: 1.2, color: Colors.black, fontFamily: 'Arial')
          ),
          const SizedBox(height: 4),
          Text(
              "STATUS: ${status.toString().toUpperCase()}",
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.black54, fontFamily: 'Arial')
          ),
          const SizedBox(height: 12),
          Text(
            indiciaText,
            style: const TextStyle(fontSize: 10, height: 1.5, color: Colors.black87, fontFamily: 'Georgia'),
            textAlign: TextAlign.justify,
          ),
        ],
      ),
    );
  }

  Widget _buildCreatorsTab() {
    // 1. Prioritize masterCreators from DB
    // 2. Fall back to _dummyCreators for testing UI
    final rawCreators = _fanzineData?['masterCreators'] as List<dynamic>?;
    final creators = rawCreators != null
        ? rawCreators.map((e) => e as Map<String, dynamic>).toList()
        : _dummyCreators;

    if (creators.isEmpty) {
      return const Center(child: Text("No creators listed.", style: TextStyle(fontSize: 10, color: Colors.grey)));
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      itemCount: creators.length,
      separatorBuilder: (c, i) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final creator = creators[index];
        final String role = (creator['role'] ?? 'Creator').toString().toUpperCase();
        final String fallbackName = (creator['name'] ?? 'Unknown').toString().toUpperCase();
        final String? uid = creator['uid'];

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Role Column
            SizedBox(
                width: 45,
                child: Text(
                  role,
                  style: const TextStyle(fontSize: 8, color: Colors.black54, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6.0),
              child: Text("|", style: TextStyle(fontSize: 10, color: Colors.black12)),
            ),

            // User Info Column
            Expanded(
              child: _buildCreatorInfo(uid, fallbackName),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCreatorInfo(String? uid, String fallbackName) {
    if (uid == null || uid.isEmpty) {
      // Non-platform user (Guest Contributor)
      return Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.05),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black.withOpacity(0.1)),
              ),
              child: Center(child: Text(fallbackName.isNotEmpty ? fallbackName[0] : '?', style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fallbackName, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text("Guest Contributor", style: TextStyle(fontSize: 8, color: Colors.black.withOpacity(0.4), fontStyle: FontStyle.italic)),
                ],
              ),
            )
          ]
      );
    }

    // Platform user (Fetch data from Users collection)
    return FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('Users').doc(uid).get(),
        builder: (context, snap) {
          String name = fallbackName;
          String handle = "fetching...";
          String? photoUrl;
          bool userExists = false;

          if (snap.hasData && snap.data!.exists) {
            userExists = true;
            final data = snap.data!.data() as Map<String, dynamic>;
            name = (data['displayName'] ?? data['username'] ?? fallbackName).toString().toUpperCase();
            handle = "@${data['username'] ?? 'user'}".toLowerCase();
            photoUrl = data['photoUrl'];
          } else if (snap.connectionState == ConnectionState.done) {
            handle = "@unknown";
          }

          return Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.05),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black.withOpacity(0.1)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: photoUrl != null
                      ? ColorFiltered(
                      colorFilter: const ColorFilter.matrix(<double>[
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0,      0,      0,      1, 0,
                      ]),
                      child: Image.network(photoUrl, fit: BoxFit.cover)
                  )
                      : Center(child: Text(name.isNotEmpty ? name[0] : '?', style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (userExists && handle != "@unknown") {
                        // route expects code without '@'
                        context.goNamed('shortlink', pathParameters: {'code': handle.substring(1)});
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(handle, style: TextStyle(fontSize: 8, color: Colors.black.withOpacity(0.4))),
                      ],
                    ),
                  ),
                ),
              ]
          );
        }
    );
  }

  Widget _buildStatsTab() {
    if (_fanzineId == null) return const Center(child: Text("Loading...", style: TextStyle(fontSize: 10)));

    // We wrap the StatsTable but customize it to look like the HTML grid
    // Since StatsTable is complex, we will stick to a simplified representation matching the HTML
    // using the existing StatsTable data logic but applying our constraints.
    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: StatsTable(
        contentId: _fanzineId!,
        viewService: _viewService,
        isFanzine: true,
        // Passing a flag or creating a custom styled version would be ideal,
        // but StatsTable is a separate widget. For now, it will render inside
        // our 200px constraint, which forces it to look compact like the design.
      ),
    );
  }

  // --- NAVIGATION HELPERS ---

  Widget _buildNavText(String text, int index) {
    final bool isActive = _currentPage == index;
    return GestureDetector(
      onTap: () => _pageController.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontFamily: isActive ? 'Impact' : 'Arial',
              fontWeight: isActive ? FontWeight.w900 : FontWeight.normal,
              color: isActive ? Colors.black : const Color(0xFF999999),
            ),
          ),
          if (isActive)
            Container(
              margin: const EdgeInsets.only(top: 2),
              width: 4,
              height: 4,
              decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }

  Widget _buildNavDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.0),
      child: Text("|", style: TextStyle(fontSize: 10, color: Color(0xFFD1D1D1))),
    );
  }
}

// --- UTILS ---

class _DashedSeparator extends StatelessWidget {
  final double height;
  final Color color;

  const _DashedSeparator({this.height = 1, this.color = Colors.black});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 4.0;
        final dashHeight = height;
        final dashCount = (boxWidth / (2 * dashWidth)).floor();
        return Flex(
          children: List.generate(dashCount, (_) {
            return SizedBox(
              width: dashWidth,
              height: dashHeight,
              child: DecoratedBox(decoration: BoxDecoration(color: color)),
            );
          }),
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
        );
      },
    );
  }
}