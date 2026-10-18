import 'dart:math' as math;

import '../models/page_display_list.dart';
import 'font_metrics.dart';

/// Enumerates the supported block elements in the publisher markdown syntax.
enum LayoutBlockType {
  text,
  h1,
  h2,
  h3,
  bullet,
  image,
  templateBlock,
  columnBreak,
}

/// Internal intermediate representation of a tokenized markdown layout block.
class LayoutBlock {
  final LayoutBlockType type;
  final String content;
  final String raw;
  final String url;
  final int? templateNum;
  final int? targetRow;

  const LayoutBlock({
    required this.type,
    this.content = '',
    this.raw = '',
    this.url = '',
    this.templateNum,
    this.targetRow,
  });
}

/// Pure Dart layout and typesetting engine for 2000x3200 multi-column publisher pages.
/// Operates on the strict 42px baseline grid, balances columns across pages,
/// and produces a deterministic [PageDisplayList] for visual rasterization.
class PublisherLayoutEngine {
  /// Physical canvas width in pixels (standard 5:8 publishing plate).
  static const double kPageWidth = 2000.0;

  /// Physical canvas height in pixels.
  static const double kPageHeight = 3200.0;

  /// Top coordinate of the 42px baseline grid.
  static const double kGridTop = 33.0;

  /// Baseline row height in pixels.
  static const double kRowHeight = 42.0;

  /// Maximum vertical Y coordinate before triggering a column or page break.
  static const double kMaxY = 3120.0;

  /// Horizontal X offset for each of the three standard columns.
  static const List<double> kColumnsX = [33.0, 696.0, 1359.0];

  /// Standard column width in pixels.
  static const double kColumnWidth = 608.0;

  /// Total usable vertical pixels available per column (3120 - 33 = 3087).
  static const double kUsableColumnHeight = 3087.0;

  /// Snaps a vertical [y] coordinate to the nearest subsequent baseline grid row.
  static double snapToGrid(double y) {
    if (y <= kGridTop) return kGridTop;
    final int rows = ((y - kGridTop) / kRowHeight).ceil();
    return kGridTop + (rows * kRowHeight);
  }

  /// Generates the standard physical page chrome (outer 11px border frame
  /// and two internal vertical column dividers at x=663 and x=1326).
  /// Returns a fresh growable List containing const DrawCommand objects.
  static List<DrawCommand> createDefaultPageChrome() {
    return [
      // Outer border frame (11px stroke width outline)
      const DrawRectCommand(
        x: 5.0,
        y: 5.0,
        width: 1989.0, // (2000 - 6) - 5
        height: 3189.0, // (3200 - 6) - 5
        borderColor: '#000000',
        borderWidth: 11.0,
      ),
      // Column divider line between Column 1 and Column 2
      const DrawRectCommand(
        x: 663.0,
        y: 99.0,
        width: 11.0,
        height: 3002.0, // 3101 - 99
        fillColor: '#000000',
      ),
      // Column divider line between Column 2 and Column 3
      const DrawRectCommand(
        x: 1326.0,
        y: 99.0,
        width: 11.0,
        height: 3002.0, // 3101 - 99
        fillColor: '#000000',
      ),
    ];
  }

  /// Parses continuous raw markdown into structured [LayoutBlock] tokens.
  /// Identifies headings, bullets, images, composite templates, and column breaks.
  static List<LayoutBlock> parseMarkdownToBlocks(String rawText) {
    final List<LayoutBlock> blocks = [];
    String currentParagraph = '';

    final imageRegex = RegExp(r'^\{\{IMAGE(?::\s*(.*?))?\}\}$', caseSensitive: false);
    final templateRegex = RegExp(r'^\{\{TEMPLATE_(\d+):\s*([^|]+)\s*\|\s*(.*?)\}\}$', caseSensitive: false);
    final colBreakRegex = RegExp(r'^(?:\{\{|\[\[)COLUMN_BREAK(?:\}\}|\]\])$', caseSensitive: false);
    final rowParamRegex = RegExp(r'^row=(\d+)\s*\|\s*(.*)$', caseSensitive: false);

    void commitParagraph() {
      final pText = currentParagraph.trim();
      if (pText.isEmpty) return;

      final mImg = imageRegex.firstMatch(pText);
      final mTmpl = templateRegex.firstMatch(pText);
      final mCb = colBreakRegex.firstMatch(pText);

      if (mImg != null) {
        final url = mImg.group(1)?.trim() ?? '';
        blocks.add(LayoutBlock(
          type: LayoutBlockType.image,
          url: url,
          raw: pText,
        ));
      } else if (mTmpl != null) {
        final tNum = int.tryParse(mTmpl.group(1) ?? '1') ?? 1;
        final tUrl = mTmpl.group(2)?.trim() ?? '';
        final rest = mTmpl.group(3)?.trim() ?? '';

        int? targetRow;
        String captionText = rest;
        final rowMatch = rowParamRegex.firstMatch(rest);
        if (rowMatch != null) {
          targetRow = int.tryParse(rowMatch.group(1) ?? '');
          captionText = rowMatch.group(2)?.trim() ?? '';
        }

        blocks.add(const LayoutBlock(type: LayoutBlockType.columnBreak));
        blocks.add(LayoutBlock(
          type: LayoutBlockType.templateBlock,
          templateNum: tNum,
          url: tUrl,
          content: captionText,
          targetRow: targetRow,
          raw: pText,
        ));
        blocks.add(const LayoutBlock(type: LayoutBlockType.columnBreak));
      } else if (mCb != null ||
          pText.toLowerCase() == 'column-break' ||
          pText.toLowerCase() == 'column_break') {
        blocks.add(const LayoutBlock(type: LayoutBlockType.columnBreak));
      } else if (pText.startsWith('### ')) {
        blocks.add(LayoutBlock(
          type: LayoutBlockType.h3,
          content: pText.substring(4).trim(),
          raw: pText,
        ));
      } else if (pText.startsWith('## ')) {
        blocks.add(LayoutBlock(
          type: LayoutBlockType.h2,
          content: pText.substring(3).trim(),
          raw: pText,
        ));
      } else if (pText.startsWith('# ')) {
        blocks.add(LayoutBlock(
          type: LayoutBlockType.h1,
          content: pText.substring(2).trim(),
          raw: pText,
        ));
      } else if (pText.startsWith('* ') || pText.startsWith('- ')) {
        blocks.add(LayoutBlock(
          type: LayoutBlockType.bullet,
          content: pText.substring(2).trim(),
          raw: pText,
        ));
      } else {
        blocks.add(LayoutBlock(
          type: LayoutBlockType.text,
          content: pText,
          raw: pText,
        ));
      }

      currentParagraph = '';
    }

    final lines = rawText.split('\n');
    for (final line in lines) {
      final cleanLine = line.trim();
      if (cleanLine.isEmpty) {
        commitParagraph();
      } else if (cleanLine.startsWith('# ') ||
          cleanLine.startsWith('## ') ||
          cleanLine.startsWith('### ') ||
          cleanLine.startsWith('* ') ||
          cleanLine.startsWith('- ') ||
          cleanLine.startsWith('{{') ||
          cleanLine.startsWith('[[')) {
        commitParagraph();
        currentParagraph = cleanLine;
        commitParagraph();
      } else {
        if (currentParagraph.isNotEmpty) {
          currentParagraph += ' $cleanLine';
        } else {
          currentParagraph = cleanLine;
        }
      }
    }

    commitParagraph();
    return blocks;
  }

  /// Fast measurement evaluating the exact number of pages resulting from [rawMarkdown]
  /// using the pure Dart typographical tables without allocating canvases or images.
  static int measurePageCount(String rawMarkdown) {
    if (rawMarkdown.trim().isEmpty) return 0;
    final displayList = compileToDisplayList(
      fanzineId: 'measure',
      rawMarkdown: rawMarkdown,
      includeChrome: false,
    );
    return displayList.pageCount;
  }

  /// Typesets continuous [rawMarkdown] across 2000x3200 3-column physical sheets.
  /// Enforces line wrapping, baseline grid alignment, and produces a [PageDisplayList].
  static PageDisplayList compileToDisplayList({
    required String fanzineId,
    required String rawMarkdown,
    String templateId = 'basic_text',
    int startPageNumber = 1,
    bool includeChrome = true,
    Map<String, dynamic> metadata = const {},
  }) {
    if (rawMarkdown.trim().isEmpty) {
      return PageDisplayList(
        fanzineId: fanzineId,
        templateId: templateId,
        pages: const [],
        metadata: metadata,
      );
    }

    final List<LayoutBlock> blocks = parseMarkdownToBlocks(rawMarkdown);
    final List<PageLayoutSheet> resultPages = [];

    List<DrawCommand> activeCommands = includeChrome
        ? createDefaultPageChrome()
        : <DrawCommand>[];
    int colIndex = 0;
    double currentY = kGridTop;
    final List<String> currentPageTextParts = [];
    int pageSequenceIndex = 0;

    void finalizeCurrentPage() {
      final pageNum = startPageNumber + pageSequenceIndex;
      final pageExtractedText = currentPageTextParts.join('\n\n').trim();

      resultPages.add(PageLayoutSheet(
        pageNumber: pageNum,
        width: kPageWidth.toInt(),
        height: kPageHeight.toInt(),
        commands: List<DrawCommand>.from(activeCommands),
        extractedText: pageExtractedText,
        metadata: {
          'columnCount': 3,
          'baselineRowHeight': kRowHeight,
        },
      ));

      pageSequenceIndex++;
      activeCommands = includeChrome
          ? createDefaultPageChrome()
          : <DrawCommand>[];
      colIndex = 0;
      currentY = kGridTop;
      currentPageTextParts.clear();
    }

    void advanceToNextColumn() {
      colIndex++;
      currentY = kGridTop;
      if (colIndex >= 3) {
        finalizeCurrentPage();
      }
    }

    for (final block in blocks) {
      // 1. Column Break Token
      if (block.type == LayoutBlockType.columnBreak) {
        if (currentY > kGridTop) {
          advanceToNextColumn();
        }
        continue;
      }

      // 2. Standalone Inline Image Block
      if (block.type == LayoutBlockType.image) {
        final targetUrl = block.url;
        const double drawHeight = 400.0;
        const double minMarginBottom = 14.0;
        final int rowsNeeded = ((drawHeight + minMarginBottom) / kRowHeight).ceil();
        final double totalImageBlockHeight = rowsNeeded * kRowHeight;

        if (currentY + totalImageBlockHeight > kMaxY) {
          advanceToNextColumn();
        }

        final double x = kColumnsX[colIndex];
        final double y = currentY;

        activeCommands.add(DrawImageCommand(
          url: targetUrl,
          x: x,
          y: y,
          width: kColumnWidth,
          height: drawHeight,
          fit: 'contain',
        ));

        currentY += totalImageBlockHeight;
        currentPageTextParts.add('{{IMAGE: $targetUrl}}');
        continue;
      }

      // 3. Composite Image & Caption Template Block (Template 1)
      if (block.type == LayoutBlockType.templateBlock && block.templateNum == 1) {
        final targetUrl = block.url;
        final caption = block.content;
        final targetRow = block.targetRow;

        const double imgHeight = 400.0;
        const double captionFontSize = 24.0;
        const double textLeadingStep = captionFontSize * 1.4; // 33.6px

        final linesToDraw = FontMetrics.wrapWords(
          caption,
          kColumnWidth,
          fontFamily: 'Arimo',
          fontSize: captionFontSize,
        );

        final double totalTextHeight = linesToDraw.length * textLeadingStep + 12.0;
        double x = kColumnsX[colIndex];

        if (targetRow != null) {
          double targetYBottom = kGridTop + (targetRow * kRowHeight);
          double targetYTop = targetYBottom - imgHeight;

          if (currentY > targetYTop || targetYBottom + totalTextHeight > kMaxY) {
            advanceToNextColumn();
            x = kColumnsX[colIndex];
            targetYBottom = kGridTop + (targetRow * kRowHeight);
            targetYTop = targetYBottom - imgHeight;
          }

          activeCommands.add(DrawImageCommand(
            url: targetUrl,
            x: x,
            y: targetYTop,
            width: kColumnWidth,
            height: imgHeight,
            fit: 'contain',
          ));

          double captionY = targetYTop + imgHeight + 16.0;
          for (final line in linesToDraw) {
            activeCommands.add(DrawTextCommand(
              text: line,
              x: x,
              y: captionY,
              fontFamily: 'Arimo',
              fontSize: captionFontSize,
              color: '#1a1a1a',
              textAlign: 'left',
            ));
            captionY += textLeadingStep;
          }

          currentY = snapToGrid(captionY + 14.0);
        } else {
          final double compositeHeight = imgHeight + totalTextHeight + 20.0;
          final int rowsNeeded = ((compositeHeight + 14.0) / kRowHeight).ceil();
          final double totalBlockHeight = rowsNeeded * kRowHeight;

          if (currentY + totalBlockHeight > kMaxY) {
            advanceToNextColumn();
            x = kColumnsX[colIndex];
          }

          activeCommands.add(DrawImageCommand(
            url: targetUrl,
            x: x,
            y: currentY,
            width: kColumnWidth,
            height: imgHeight,
            fit: 'contain',
          ));

          double captionY = currentY + imgHeight + 16.0;
          for (final line in linesToDraw) {
            activeCommands.add(DrawTextCommand(
              text: line,
              x: x,
              y: captionY,
              fontFamily: 'Arimo',
              fontSize: captionFontSize,
              color: '#1a1a1a',
              textAlign: 'left',
            ));
            captionY += textLeadingStep;
          }

          currentY += totalBlockHeight;
        }

        currentPageTextParts.add('{{TEMPLATE_1: $targetUrl | $caption}}');
        continue;
      }

      // 4. Text, Headings, and Bullet List Blocks
      double fontSize = 28.0;
      String fontFamily = 'Arimo';
      bool isBold = false;
      double step = kRowHeight;

      if (block.type == LayoutBlockType.h1) {
        fontSize = 42.0;
        fontFamily = 'Anton';
        isBold = false;
        step = 56.0;
      } else if (block.type == LayoutBlockType.h2) {
        fontSize = 36.0;
        fontFamily = 'Anton';
        isBold = false;
        step = 48.0;
      } else if (block.type == LayoutBlockType.h3) {
        fontSize = 28.0;
        fontFamily = 'Anton';
        isBold = false;
        step = kRowHeight;
      } else {
        fontSize = 28.0;
        fontFamily = 'Arimo';
        isBold = false;
        step = kRowHeight;
      }

      final isBullet = block.type == LayoutBlockType.bullet;
      final textToWrap = isBullet ? '    ${block.content}' : block.content;

      final linesToDraw = FontMetrics.wrapWords(
        textToWrap,
        kColumnWidth,
        fontFamily: fontFamily,
        fontSize: fontSize,
        isBold: isBold,
      );

      final List<String> currentParagraphRenderedLines = [];

      for (int i = 0; i < linesToDraw.length; i++) {
        final line = linesToDraw[i];

        if (currentY + fontSize > kMaxY) {
          if (currentParagraphRenderedLines.isNotEmpty) {
            currentPageTextParts.add(currentParagraphRenderedLines.join(' '));
            currentParagraphRenderedLines.clear();
          }
          advanceToNextColumn();
        }

        final double x = kColumnsX[colIndex];
        final bool isLastLine = i == linesToDraw.length - 1;

        if (!isLastLine && block.type == LayoutBlockType.text && linesToDraw.length > 1) {
          final words = line.split(' ').where((w) => w.isNotEmpty).toList();
          if (words.length > 1) {
            double wordsWidth = 0.0;
            for (final w in words) {
              wordsWidth += FontMetrics.measureString(
                w,
                fontFamily: fontFamily,
                fontSize: fontSize,
                isBold: isBold,
              );
            }
            final double spaceDiff = kColumnWidth - wordsWidth;
            final double wordSpacing = math.max(0.0, spaceDiff / (words.length - 1));

            activeCommands.add(DrawTextCommand(
              text: line,
              x: x,
              y: currentY,
              fontFamily: fontFamily,
              fontSize: fontSize,
              isBold: isBold,
              color: '#1a1a1a',
              textAlign: 'justify',
              wordSpacing: wordSpacing,
            ));
          } else {
            activeCommands.add(DrawTextCommand(
              text: line,
              x: x,
              y: currentY,
              fontFamily: fontFamily,
              fontSize: fontSize,
              isBold: isBold,
              color: '#1a1a1a',
              textAlign: 'left',
            ));
          }
        } else {
          activeCommands.add(DrawTextCommand(
            text: line,
            x: x,
            y: currentY,
            fontFamily: fontFamily,
            fontSize: fontSize,
            isBold: isBold,
            color: '#1a1a1a',
            textAlign: 'left',
          ));
        }

        currentY += step;
        currentParagraphRenderedLines.add(line);
      }

      currentY = snapToGrid(currentY + 14.0);

      if (currentParagraphRenderedLines.isNotEmpty) {
        if (block.type == LayoutBlockType.h1) {
          currentPageTextParts.add('# ${currentParagraphRenderedLines.join(" ")}');
        } else if (block.type == LayoutBlockType.h2) {
          currentPageTextParts.add('## ${currentParagraphRenderedLines.join(" ")}');
        } else if (block.type == LayoutBlockType.h3) {
          currentPageTextParts.add('### ${currentParagraphRenderedLines.join(" ")}');
        } else if (block.type == LayoutBlockType.bullet) {
          currentPageTextParts.add('* ${currentParagraphRenderedLines.join(" ")}');
        } else {
          currentPageTextParts.add(currentParagraphRenderedLines.join(' '));
        }
      }
    }

    if (currentY > kGridTop || colIndex > 0) {
      finalizeCurrentPage();
    }

    return PageDisplayList(
      fanzineId: fanzineId,
      templateId: templateId,
      pages: resultPages,
      metadata: metadata,
    );
  }
}