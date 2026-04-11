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

  StreamSubscription? _pageSub;
  StreamSubscription? _imageSub;

  @override
  void initState() {
    super.initState();
    _listenToStats();
  }

  @override
  void didUpdateWidget(covariant DynamicSocialToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageId != widget.pageId || oldWidget.imageId != widget.imageId) {
      _pageSub?.cancel();
      _imageSub?.cancel();
      _listenToStats();
    }
  }

  void _listenToStats() {
    // 1. Listen for Like Count on the Page Document
    if (widget.pageId != null && widget.pageId!.isNotEmpty && widget.fanzineId != null && widget.fanzineId!.isNotEmpty) {
      _pageSub = FirebaseFirestore.instance
          .collection('fanzines')
          .doc(widget.fanzineId)
          .collection('pages')
          .doc(widget.pageId)
          .snapshots()
          .listen((doc) {
        if (doc.exists && mounted) {
          setState(() => _likeCount = doc.data()?['likeCount'] ?? 0);
        }
      });
    }

    // 2. Listen for Views and Comments on the Image Document
    if (widget.imageId.isNotEmpty) {
      _imageSub = FirebaseFirestore.instance
          .collection('images')
          .doc(widget.imageId)
          .snapshots()
          .listen((doc) {
        if (doc.exists && mounted) {
          final data = doc.data() as Map<String, dynamic>;
          setState(() {
            _commentCount = data['commentCount'] ?? 0;
            _viewCount = (data['regListCount'] ?? 0) + (data['anonListCount'] ?? 0) + (data['regGridCount'] ?? 0) + (data['anonGridCount'] ?? 0);
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _pageSub?.cancel();
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

        if (widget.fanzineId != null && widget.pageId != null) {
          await _engagementService.toggleLike(
            fanzineId: widget.fanzineId!,
            pageId: widget.pageId!,
            isCurrentlyLiked: isCurrentlyLiked,
          );
        }
        break;

      case ToolAction.copyShareLink:
        if (widget.fanzineId == null) return;
        final link = 'https://bqopd.com/fanzine/${widget.fanzineId}?page=${widget.pageNumber ?? 1}';
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
      case ToolCondition.requiresTwoPage:
        if (widget.fanzineId == null) return false;
        break;
      case ToolCondition.always:
        break;
    }

    if (widget.fanzineId == null && (tool.id == 'Grid' || tool.id == 'Fanzine' || tool.id == 'Indicia' || tool.id == 'OCR' || tool.id == 'Publisher' || tool.id == 'Entities')) {
      return false;
    }

    final isVisibleByUser = userProvider.socialButtonVisibility[tool.id] ?? true;
    if (!isVisibleByUser) return false;

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final visibleTools = ReaderToolsConfig.tools.where((tool) {
      return _isToolVisible(tool, userProvider);
    }).toList();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      child: Wrap(
        spacing: 8.0,
        runSpacing: 12.0,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: visibleTools.map((tool) {
          // Use StreamBuilder specifically for the Like button to ensure it reacts
          // correctly to user changes (auth) and page changes (scroll).
          if (tool.action == ToolAction.toggleLike && widget.pageId != null) {
            return StreamBuilder<bool>(
              stream: _engagementService.isLikedStream(widget.pageId!),
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

          bool isActive = false;
          if (tool.action == ToolAction.openBonusRow) {
            isActive = widget.activeBonusRow == tool.bonusRow;
          }

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