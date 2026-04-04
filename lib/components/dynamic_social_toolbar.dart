import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/reader_tool.dart';
import '../config/reader_tools_config.dart';
import '../services/user_provider.dart';
import '../services/engagement_service.dart';
import 'dynamic_toolbar_button.dart';

class DynamicSocialToolbar extends StatefulWidget {
  final String imageId;
  final String pageId;
  final String fanzineId;
  final int pageNumber;
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
    required this.pageId,
    required this.fanzineId,
    required this.pageNumber,
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

  bool _isLiked = false;
  int _likeCount = 0;
  int _commentCount = 0;
  int _viewCount = 0;

  StreamSubscription? _likeSub;
  StreamSubscription? _pageSub;
  StreamSubscription? _imageSub;

  @override
  void initState() {
    super.initState();
    _listenToStats();
  }

  void _listenToStats() {
    // 1. Listen for Likes on the Page Document
    if (widget.pageId.isNotEmpty && widget.fanzineId.isNotEmpty) {
      _likeSub = _engagementService.isLikedStream(widget.pageId).listen((liked) {
        if (mounted) setState(() => _isLiked = liked);
      });

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
            // Sum all view variants
            _viewCount = (data['regListCount'] ?? 0) + (data['anonListCount'] ?? 0) + (data['regGridCount'] ?? 0) + (data['anonGridCount'] ?? 0);
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _likeSub?.cancel();
    _pageSub?.cancel();
    _imageSub?.cancel();
    super.dispose();
  }

  void _handleToolAction(ReaderTool tool) async {
    switch (tool.action) {
      case ToolAction.openBonusRow:
        if (tool.bonusRow != null) {
          widget.onToggleBonusRow(tool.bonusRow!);
        }
        break;

      case ToolAction.toggleLike:
        await _engagementService.toggleLike(
          fanzineId: widget.fanzineId,
          pageId: widget.pageId,
          isCurrentlyLiked: _isLiked,
        );
        break;

      case ToolAction.copyShareLink:
        final link = 'https://bqopd.com/fanzine/${widget.fanzineId}?page=${widget.pageNumber}';
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
    // 1. Role Check
    if (tool.role == ToolRole.editor && !widget.isEditingMode) return false;

    // 2. Condition Check
    switch (tool.condition) {
      case ToolCondition.requiresYouTube:
        if (widget.youtubeId == null || widget.youtubeId!.isEmpty) return false;
        break;
      case ToolCondition.requiresGame:
        if (!widget.isGame) return false;
        break;
      case ToolCondition.requiresIndicia:
        if (!widget.isIndiciaPage) return false;
        break;
      case ToolCondition.hideOnDesktopSplit:
        if (widget.onOpenGrid == null) return false;
        break;
      case ToolCondition.requiresTwoPage:
        break;
      case ToolCondition.always:
        break;
    }

    // 3. User Preference Check
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
          bool isActive = false;

          if (tool.action == ToolAction.openBonusRow) {
            isActive = widget.activeBonusRow == tool.bonusRow;
          } else if (tool.action == ToolAction.toggleLike) {
            isActive = _isLiked;
          }

          // Pass the appropriate stat count to the button
          int? count;
          if (tool.id == 'Like') count = _likeCount;
          if (tool.id == 'Comment') count = _commentCount;
          if (tool.id == 'Views') count = _viewCount;

          return DynamicToolbarButton(
            tool: tool,
            isActive: isActive,
            isDarkMode: isDarkMode,
            count: count,
            onPressed: () => _handleToolAction(tool),
          );
        }).toList(),
      ),
    );
  }
}