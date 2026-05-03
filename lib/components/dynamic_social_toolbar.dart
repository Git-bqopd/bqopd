import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/reader_tool.dart';
import '../config/reader_tools_config.dart';
import '../services/user_provider.dart';
import '../services/engagement_service.dart';
import 'dynamic_toolbar_button.dart';
import '../widgets/auth_modal.dart';

class DynamicSocialToolbar extends StatefulWidget {
  final String imageId;
  final String? pageId;
  final String? fanzineId;
  final String? fanzineType;
  final int? pageNumber;
  final bool isGame;
  final String? youtubeId;
  final bool isEditingMode;
  final bool isIndiciaPage;
  final VoidCallback? onOpenGrid;
  final Function(BonusRowType) onToggleBonusRow;
  final BonusRowType? activeBonusRow;

  const DynamicSocialToolbar({
    super.key,
    required this.imageId,
    this.pageId,
    this.fanzineId,
    this.fanzineType,
    this.pageNumber,
    this.isGame = false,
    this.youtubeId,
    required this.isEditingMode,
    this.isIndiciaPage = false,
    this.onOpenGrid,
    required this.onToggleBonusRow,
    this.activeBonusRow,
  });

  @override
  State<DynamicSocialToolbar> createState() => _DynamicSocialToolbarState();
}

class _DynamicSocialToolbarState extends State<DynamicSocialToolbar> {
  final EngagementService _engagementService = EngagementService();

  int _likeCount = 0;
  int _commentCount = 0;
  int _viewCount = 0;
  int _tagCount = 0;

  StreamSubscription? _imageSub;
  String? _fanzineShortCode;
  bool _isTwoPage = true; // NEW: Pulled from Fanzine database record

  @override
  void initState() {
    super.initState();
    _listenToStats();
    _fetchFanzineData();
  }

  @override
  void didUpdateWidget(covariant DynamicSocialToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageId != widget.imageId) {
      _imageSub?.cancel();
      _listenToStats();
    }
    if (oldWidget.fanzineId != widget.fanzineId) {
      _fetchFanzineData();
    }
  }

  /// Fetches the readable shortcode and format variables (like twoPage) for the fanzine.
  Future<void> _fetchFanzineData() async {
    if (widget.fanzineId == null || widget.fanzineId!.isEmpty) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('fanzines')
          .doc(widget.fanzineId)
          .get();

      if (doc.exists && mounted) {
        setState(() {
          _fanzineShortCode = doc.data()?['shortCode'];
          _isTwoPage = doc.data()?['twoPage'] ?? true;
        });
      }
    } catch (_) {}
  }

  void _listenToStats() {
    if (widget.imageId.isNotEmpty) {
      _imageSub = FirebaseFirestore.instance
          .collection('images')
          .doc(widget.imageId)
          .snapshots()
          .listen((doc) {
        if (doc.exists && mounted) {
          final data = doc.data() as Map<String, dynamic>;
          final tags = data['tags'] as Map<String, dynamic>? ?? {};

          setState(() {
            _likeCount = data['likeCount'] ?? 0;
            _commentCount = data['commentCount'] ?? 0;
            _viewCount = (data['regListCount'] ?? 0) +
                (data['anonListCount'] ?? 0) +
                (data['regGridCount'] ?? 0) +
                (data['anonGridCount'] ?? 0);
            _tagCount = tags.keys.length;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _imageSub?.cancel();
    super.dispose();
  }

  void _handleToolAction(ReaderTool tool, bool isCurrentlyLiked) async {
    final user = FirebaseAuth.instance.currentUser;
    final isGuest = user == null || user.isAnonymous;

    switch (tool.action) {
      case ToolAction.openBonusRow:
        if (tool.id == 'Settings' && isGuest) {
          showDialog(context: context, builder: (c) => const AuthModal());
          return;
        }
        if (tool.bonusRow != null) {
          widget.onToggleBonusRow(tool.bonusRow!);
        }
        break;

      case ToolAction.toggleLike:
        if (isGuest) {
          showDialog(context: context, builder: (c) => const AuthModal());
          return;
        }
        await _engagementService.toggleLike(
          imageId: widget.imageId,
          fanzineId: widget.fanzineId,
          isCurrentlyLiked: isCurrentlyLiked,
        );
        break;

      case ToolAction.copyShareLink:
        if (widget.fanzineId == null) return;

        // NEW URL SCHEMA: Priority 1: Shortcode based path (bqopd.com/CODE/PAGE)
        // Priority 2: Fallback to old query path using IDs
        String link;
        if (_fanzineShortCode != null) {
          link = 'https://bqopd.com/$_fanzineShortCode/${widget.pageNumber ?? 1}';
        } else {
          link = 'https://bqopd.com/reader/${widget.fanzineId}?p=${widget.pageNumber ?? 1}';
        }

        await Clipboard.setData(ClipboardData(text: link));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Clean link copied: $link')),
          );
        }
        break;

      case ToolAction.switchToGridView:
        if (widget.onOpenGrid != null) {
          widget.onOpenGrid!();
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final visibleTools = ReaderToolsConfig.tools.where((tool) {
      bool isContextuallyVisible = ReaderToolsConfig.isToolVisibleInContext(
        tool: tool,
        userRole: userProvider.userAccount?.role ?? 'user',
        isEditingMode: widget.isEditingMode,
        fanzineType: widget.fanzineType,
        hasYoutube: widget.youtubeId != null && widget.youtubeId!.isNotEmpty,
        isGame: widget.isGame,
        isIndiciaPage: widget.isIndiciaPage,
        canOpenGrid: widget.onOpenGrid != null,
        isTwoPage: _isTwoPage, // Passing the format control downstream
      );

      if (!isContextuallyVisible) return false;

      // Ensure Core Tools bypass the user preferences so they can never be hidden
      final isVisibleByUser = (tool.id == 'Settings' || tool.id == 'Grid' || tool.id == 'Like')
          ? true
          : (userProvider.socialButtonVisibility[tool.id] ?? true);

      return isVisibleByUser;
    }).toList();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      child: Wrap(
        spacing: 8.0,
        runSpacing: 12.0,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: visibleTools.map((tool) {
          if (tool.action == ToolAction.toggleLike) {
            return StreamBuilder<bool>(
              stream: _engagementService.isLikedStream(widget.imageId),
              builder: (context, snapshot) {
                final bool isLiked = snapshot.data ?? false;
                return DynamicToolbarButton(
                  tool: tool,
                  isActive: isLiked,
                  isDarkMode: isDarkMode,
                  count: _likeCount,
                  onPressed: () => _handleToolAction(tool, isLiked),
                );
              },
            );
          }

          bool isActive = (tool.action == ToolAction.openBonusRow)
              ? widget.activeBonusRow == tool.bonusRow
              : false;

          int? count;
          if (tool.id == 'Comment') count = _commentCount;
          if (tool.id == 'Views') count = _viewCount;
          if (tool.id == 'Tags') count = _tagCount;

          return DynamicToolbarButton(
            tool: tool,
            isActive: isActive,
            isDarkMode: isDarkMode,
            count: count,
            onPressed: () => _handleToolAction(tool, false),
          );
        }).toList(),
      ),
    );
  }
}