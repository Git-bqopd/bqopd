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

  StreamSubscription? _imageSub;

  @override
  void initState() {
    super.initState();
    _listenToStats();
  }

  @override
  void didUpdateWidget(covariant DynamicSocialToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageId != widget.imageId) {
      _imageSub?.cancel();
      _listenToStats();
    }
  }

  void _listenToStats() {
    // SINGLE SOURCE OF TRUTH: Listen only to the Image document for engagement stats
    if (widget.imageId.isNotEmpty) {
      _imageSub = FirebaseFirestore.instance
          .collection('images')
          .doc(widget.imageId)
          .snapshots()
          .listen((doc) {
        if (doc.exists && mounted) {
          final data = doc.data() as Map<String, dynamic>;
          setState(() {
            _likeCount = data['likeCount'] ?? 0; // Canonical Like Count
            _commentCount = data['commentCount'] ?? 0;
            _viewCount = (data['regListCount'] ?? 0) + (data['anonListCount'] ?? 0) + (data['regGridCount'] ?? 0) + (data['anonGridCount'] ?? 0);
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
        // Anchoring like to UGC
        await _engagementService.toggleLike(
          imageId: widget.imageId,
          fanzineId: widget.fanzineId,
          isCurrentlyLiked: isCurrentlyLiked,
        );
        break;

      case ToolAction.copyShareLink:
        if (widget.fanzineId == null) return;
        final link = 'https://bqopd.com/fanzine/${widget.fanzineId}?p=${widget.pageNumber ?? 1}';
        await Clipboard.setData(ClipboardData(text: link));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Link copied to clipboard: $link')),
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

  bool _isToolVisible(ReaderTool tool, UserProvider userProvider) {
    if (tool.role == ToolRole.editor && !widget.isEditingMode) return false;

    switch (tool.condition) {
      case ToolCondition.requiresYouTube:
        if (widget.youtubeId == null || widget.youtubeId!.isEmpty) return false;
        break;
      case ToolCondition.requiresGame:
        if (!widget.isGame) return false;
        break;
      case ToolCondition.requiresIndicia:
        if (!widget.isIndiciaPage || widget.fanzineId == null) return false;
        break;
      case ToolCondition.hideOnDesktopSplit:
        if (widget.onOpenGrid == null) return false;
        break;
      case ToolCondition.requiresOcrPipeline:
      // Hide these tools for Publisher-based folios/calendars
        if (widget.fanzineType == 'folio' || widget.fanzineType == 'calendar') return false;
        break;
      default:
        break;
    }

    final isVisibleByUser = userProvider.socialButtonVisibility[tool.id] ?? true;
    return isVisibleByUser;
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final visibleTools = ReaderToolsConfig.tools.where((tool) => _isToolVisible(tool, userProvider)).toList();

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