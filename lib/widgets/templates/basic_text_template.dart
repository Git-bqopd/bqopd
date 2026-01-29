import 'package:flutter/material.dart';
import '../../utils/link_parser.dart';

enum BlockType { text, image }

class PageBlock {
  final BlockType type;
  final String content;
  final double height;

  PageBlock({required this.type, required this.content, this.height = 0});
}

class BasicTextTemplate extends StatelessWidget {
  final List<List<PageBlock>> columns;
  final bool showOverlay;

  static const double targetWidth = 2000.0;
  static const double targetHeight = 3200.0;

  static const double outerBorderWidth = 11.0;
  static const double columnWidth = 652.0;
  static const double dividerWidth = 11.0;
  static const double innerPadding = 22.0;
  static const double dividerGap = 99.0;

  static const double textContentWidth = columnWidth - (innerPadding * 2);
  static const double textContentHeight = targetHeight - (outerBorderWidth * 2) - (innerPadding * 2);

  static const TextStyle baseTextStyle = TextStyle(
    fontFamily: 'Arial',
    fontSize: 32,
    color: Colors.black87,
    height: 1.5625,
  );

  static const TextStyle headerTextStyle = TextStyle(
    fontFamily: 'Impact',
    fontSize: 40,
    fontWeight: FontWeight.normal,
    color: Colors.black,
    height: 1.25,
  );

  static const StrutStyle masterGridStrut = StrutStyle(
    fontFamily: 'Arial',
    fontSize: 32,
    height: 1.5625,
    forceStrutHeight: true,
  );

  const BasicTextTemplate({
    super.key,
    required this.columns,
    this.showOverlay = true,
  });

  @override
  Widget build(BuildContext context) {
    final safeCols = List<List<PageBlock>>.from(columns);
    while (safeCols.length < 3) safeCols.add([]);

    return Container(
      width: targetWidth,
      height: targetHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: Colors.black,
          width: outerBorderWidth,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildColumnWidget(context, safeCols[0]),
          _buildDivider(),
          _buildColumnWidget(context, safeCols[1]),
          _buildDivider(),
          _buildColumnWidget(context, safeCols[2]),
        ],
      ),
    );
  }

  Widget _buildColumnWidget(BuildContext context, List<PageBlock> blocks) {
    return Container(
      width: columnWidth,
      padding: const EdgeInsets.all(innerPadding),
      // Ensure clipping is strict to avoid overflow errors
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blocks.map((block) {
          if (block.type == BlockType.image) {
            return Container(
              height: block.height,
              width: double.infinity,
              color: Colors.grey[300],
              child: block.content.isEmpty
                  ? const Center(child: Icon(Icons.image, size: 64, color: Colors.grey))
                  : Image.network(
                block.content,
                fit: BoxFit.cover,
                errorBuilder: (c,e,s) => const Center(child: Icon(Icons.broken_image, size: 64)),
              ),
            );
          } else {
            // Using Flexible/Expanded can sometimes cause issues if inside a scrollable view
            // or if the parent Column isn't constrained properly.
            // Since we know the height matches, we just render it.
            // If overflow persists, wrapping in a SizedBox with the measured height helps.
            return SelectableText.rich(
              LinkParser.renderLinks(
                context,
                block.content,
                baseStyle: baseTextStyle,
                headerStyle: headerTextStyle,
                linkStyle: const TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                  fontSize: 32,
                  height: 1.5625,
                ),
              ),
              textAlign: TextAlign.justify,
              strutStyle: masterGridStrut,
            );
          }
        }).toList(),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: dividerWidth,
      color: Colors.white,
      child: Column(
        children: [
          const SizedBox(height: dividerGap),
          Expanded(child: Container(color: Colors.black)),
          const SizedBox(height: dividerGap),
        ],
      ),
    );
  }

  static List<List<List<PageBlock>>> paginateContent(String fullText) {
    List<List<List<PageBlock>>> pages = [];
    List<List<PageBlock>> currentColumns = [];
    List<PageBlock> currentColumnBlocks = [];
    double currentColumnHeight = 0;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.justify,
      strutStyle: masterGridStrut,
    );

    final RegExp tagExp = RegExp(r'\{\{IMAGE(?::\s*(.*?))?\}\}');
    final List<String> rawTokens = fullText.split(tagExp);
    final List<Match> matches = tagExp.allMatches(fullText).toList();

    List<dynamic> layoutTokens = [];
    for (int i = 0; i < rawTokens.length; i++) {
      if (rawTokens[i].isNotEmpty) layoutTokens.add(rawTokens[i]);
      if (i < matches.length) {
        String? url = matches[i].group(1);
        layoutTokens.add(PageBlock(
            type: BlockType.image,
            content: url ?? "",
            height: 300.0
        ));
      }
    }

    for (var token in layoutTokens) {
      if (token is PageBlock) {
        double imgH = token.height;
        if (currentColumnHeight + imgH <= textContentHeight) {
          currentColumnBlocks.add(token);
          currentColumnHeight += imgH;
        } else {
          currentColumns.add(currentColumnBlocks);
          currentColumnBlocks = [];
          currentColumnHeight = 0;

          if (currentColumns.length == 3) {
            pages.add(currentColumns);
            currentColumns = [];
          }

          currentColumnBlocks.add(token);
          currentColumnHeight += imgH;
        }
      } else if (token is String) {
        List<String> paragraphs = token.split('\n');
        String pendingText = "";

        for (int pIndex = 0; pIndex < paragraphs.length; pIndex++) {
          String paragraph = paragraphs[pIndex];
          String textToAdd = pendingText.isEmpty ? paragraph : "\n$paragraph";
          String testText = pendingText + textToAdd;

          textPainter.text = TextSpan(text: testText, style: baseTextStyle);
          textPainter.layout(maxWidth: textContentWidth);

          // Use a small epsilon for floating point comparison safety
          if (currentColumnHeight + textPainter.height <= textContentHeight + 0.5) {
            pendingText = testText;
          } else {
            if (pendingText.isNotEmpty) {
              currentColumnBlocks.add(PageBlock(type: BlockType.text, content: pendingText));
            }

            currentColumns.add(currentColumnBlocks);
            currentColumnBlocks = [];
            currentColumnHeight = 0;

            if (currentColumns.length == 3) {
              pages.add(currentColumns);
              currentColumns = [];
            }

            pendingText = paragraph;

            textPainter.text = TextSpan(text: pendingText, style: baseTextStyle);
            textPainter.layout(maxWidth: textContentWidth);
          }
        }

        if (pendingText.isNotEmpty) {
          currentColumnBlocks.add(PageBlock(type: BlockType.text, content: pendingText));

          textPainter.text = TextSpan(text: pendingText, style: baseTextStyle);
          textPainter.layout(maxWidth: textContentWidth);
          currentColumnHeight += textPainter.height;
        }
      }
    }

    if (currentColumnBlocks.isNotEmpty) {
      currentColumns.add(currentColumnBlocks);
    }

    if (currentColumns.isNotEmpty) {
      while (currentColumns.length < 3) currentColumns.add([]);
      pages.add(currentColumns);
    }

    return pages;
  }
}