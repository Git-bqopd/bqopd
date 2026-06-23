import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

/// Highly authentic HTML/CSS-driven Web rendering of the 2000x3200 Publisher text template.
/// Replicates multi-column text flow, custom heading styles, and dynamic image insertion.
class BasicTextTemplate extends StatelessComponent {
  final String textContent;

  const BasicTextTemplate({required this.textContent, super.key});

  @override
  Component build(BuildContext context) {
    final parsedParagraphs = _parseMarkdownBlocks(textContent);

    return div(
      classes: 'basic-text-template-paper',
      attributes: const {
        'style': 'width: 100%; height: 100%; background: #ffffff; border: 8px solid #000000; '
            'box-sizing: border-box; padding: 24px; display: flex; flex-direction: column; '
            'overflow: hidden; font-family: "Arial", sans-serif; position: relative;'
      },
      [
        div(
            classes: 'template-content-columns',
            attributes: const {
              'style': 'column-count: 3; column-gap: 36px; column-rule: 4px solid #000000; '
                  'height: 100%; width: 100%; box-sizing: border-box; text-align: justify; '
                  'overflow: hidden;'
            },
            parsedParagraphs
        )
      ],
    );
  }

  List<Component> _parseMarkdownBlocks(String rawText) {
    final List<Component> elements = [];
    final lines = rawText.split('\n');

    String currentParagraph = "";
    int currentRow = 0; // Track estimated vertical row lines
    bool forceNextColumn = false; // Flag to force the next non-empty content block into the subsequent column

    void commitParagraph() {
      final pText = currentParagraph.trim();
      if (pText.isEmpty) return;

      // Match Regex rules
      final imageRegex = RegExp(r'^\{\{IMAGE(?::\s*(.*?))?\}\}$', caseSensitive: false);
      final templateRegex = RegExp(r'^\{\{TEMPLATE_(\d+):\s*([^|]+)\s*\|\s*(.*?)\}\}$', caseSensitive: false);
      final colBreakRegex = RegExp(r'^(?:\{\{|\[\[)COLUMN_BREAK(?:\}\}|\]\])$', caseSensitive: false);

      final imageMatch = imageRegex.firstMatch(pText);
      final templateMatch = templateRegex.firstMatch(pText);
      final colBreakMatch = colBreakRegex.firstMatch(pText);

      if (colBreakMatch != null || pText == 'column-break' || pText == 'column_break') {
        forceNextColumn = true;
        currentRow = 0; // reset column flow
      } else if (templateMatch != null) {
        final templateNum = templateMatch.group(1) ?? '1';
        final url = templateMatch.group(2)?.trim() ?? '';
        final restContent = templateMatch.group(3)?.trim() ?? '';

        String caption = restContent;
        int? targetRow;
        final rowMatch = RegExp(r'^row=(\d+)\s*\|\s*(.*)$', caseSensitive: false).firstMatch(restContent);
        if (rowMatch != null) {
          targetRow = int.tryParse(rowMatch.group(1) ?? '');
          caption = rowMatch.group(2)!.trim();
        }

        if (templateNum == '1') {
          final int imgRows = 8; // Estimate image height as 8 rows
          final int captionRows = (caption.length / 60).ceil();

          bool hasRowOffset = false;
          if (targetRow != null) {
            final int targetTopRow = targetRow - imgRows;
            if (currentRow < targetTopRow) {
              hasRowOffset = true;
              final int blankRows = targetTopRow - currentRow;
              elements.add(
                  div(
                    attributes: {
                      // Move the column break onto the spacer element so that the spacer
                      // and template element remain in the exact same column flow!
                      'style': 'break-before: column; height: ${blankRows * 24}px; width: 100%;',
                    },
                    [],
                  )
              );
            }
            currentRow = targetRow + captionRows;
          } else {
            currentRow += imgRows + captionRows;
          }

          // Use a standard block-level wrapper div to apply the column break styling.
          // Block-level elements guarantee cross-browser compatibility for column fragmentation,
          // bypassing flexbox multi-column layout rendering bugs entirely.
          // Adding break-after: column natively and strictly forces any trailing text to the next column.
          final String wrapperStyle = 'display: block; width: 100%; break-after: column; ' +
              (hasRowOffset ? '' : 'break-before: column;');

          elements.add(
              div(
                  attributes: {
                    'style': wrapperStyle,
                  },
                  [
                    div(
                        classes: 'template-span-all-container',
                        attributes: const {
                          'style': 'width: 100%; margin: 16px 0; display: flex; flex-direction: column; align-items: stretch; border: 1px solid #e2e8f0; border-radius: 4px; overflow: hidden; background: #ffffff; break-inside: avoid;'
                        },
                        [
                          if (url.isNotEmpty)
                            img(
                                src: url,
                                attributes: const {
                                  'style': 'width: 100%; max-width: 100%; height: auto; display: block; object-fit: contain; max-height: 450px;'
                                }
                            ),
                          if (caption.isNotEmpty)
                            div(
                                attributes: const {
                                  'style': 'padding: 12px; background-color: #f9fafb; border-top: 1px solid #e2e8f0; text-align: center;'
                                },
                                [
                                  p(
                                      [Component.text(caption)],
                                      attributes: const {
                                        'style': 'font-size: 11px; font-style: italic; color: #4b5563; margin: 0; line-height: 1.4;'
                                      }
                                  )
                                ]
                            )
                        ]
                    )
                  ]
              )
          );

          // Signal that the next content element MUST be placed in the next column
          forceNextColumn = true;
          currentRow = 0; // reset column flow for any subsequent elements in next columns!
        } else {
          elements.add(p([Component.text('Unknown Template $templateNum: $caption')]));
        }
      } else if (imageMatch != null) {
        final url = imageMatch.group(1)?.trim();
        final finalUrl = (url != null && url.isNotEmpty) ? url : 'https://placehold.co/600x400/png?text=Image+Asset';

        final String styleStr = 'width: 100%; max-width: 100%; height: auto; margin: 12px 0; '
            'display: block; break-inside: avoid; border: 1px solid #e2e8f0; border-radius: 4px;' +
            (forceNextColumn ? ' break-before: column;' : '');

        elements.add(img(
            src: finalUrl,
            attributes: {
              'style': styleStr
            }
        ));
        currentRow += 8;
        forceNextColumn = false;
      } else if (pText.startsWith('###')) {
        final String styleStr = 'font-family: "Impact", sans-serif; font-size: 16px; margin: 12px 0 6px 0; '
            'text-transform: uppercase; letter-spacing: 0.5px; line-height: 1.2; break-inside: avoid;' +
            (forceNextColumn ? ' break-before: column;' : '');

        elements.add(h3([Component.text(pText.substring(3).trim())], attributes: {
          'style': styleStr
        }));
        currentRow += 2;
        forceNextColumn = false;
      } else if (pText.startsWith('##')) {
        final String styleStr = 'font-family: "Impact", sans-serif; font-size: 20px; margin: 16px 0 8px 0; '
            'text-transform: uppercase; letter-spacing: 0.5px; line-height: 1.2; break-inside: avoid;' +
            (forceNextColumn ? ' break-before: column;' : '');

        elements.add(h2([Component.text(pText.substring(2).trim())], attributes: {
          'style': styleStr
        }));
        currentRow += 2;
        forceNextColumn = false;
      } else if (pText.startsWith('#')) {
        final String styleStr = 'font-family: "Impact", sans-serif; font-size: 24px; margin: 18px 0 10px 0; '
            'text-transform: uppercase; letter-spacing: 0.5px; line-height: 1.2; break-inside: avoid;' +
            (forceNextColumn ? ' break-before: column;' : '');

        elements.add(h1([Component.text(pText.substring(1).trim())], attributes: {
          'style': styleStr
        }));
        currentRow += 2;
        forceNextColumn = false;
      } else if (pText.startsWith('* ') || pText.startsWith('- ')) {
        // Bullet list item
        final String styleStr = 'font-size: 11px; line-height: 1.5; color: #1a1a1a; margin-bottom: 6px; '
            'padding-left: 12px; text-indent: -12px; break-inside: avoid;' +
            (forceNextColumn ? ' break-before: column;' : '');

        elements.add(div([
          span([Component.text('•')], attributes: const {'style': 'font-weight: bold; margin-right: 6px;'}),
          Component.text(pText.substring(2).trim())
        ], attributes: {
          'style': styleStr
        }));
        currentRow += 1;
        forceNextColumn = false;
      } else {
        // Standard body paragraph
        final String styleStr = 'font-size: 11px; line-height: 1.5; color: #1a1a1a; margin-top: 0; '
            'margin-bottom: 12px; text-align: justify;' +
            (forceNextColumn ? ' break-before: column;' : '');

        elements.add(p([Component.text(pText)], attributes: {
          'style': styleStr
        }));
        currentRow += (pText.length / 60).ceil();
        forceNextColumn = false;
      }
      currentParagraph = "";
    }

    for (var line in lines) {
      final cleanLine = line.trim();
      if (cleanLine.isEmpty) {
        commitParagraph();
      } else if (cleanLine.startsWith('#') || cleanLine.startsWith('*') || cleanLine.startsWith('-') || cleanLine.startsWith('{{')) {
        commitParagraph();
        currentParagraph = cleanLine;
        commitParagraph();
      } else {
        if (currentParagraph.isNotEmpty) {
          currentParagraph += " " + cleanLine;
        } else {
          currentParagraph = cleanLine;
        }
      }
    }
    commitParagraph();

    return elements;
  }
}