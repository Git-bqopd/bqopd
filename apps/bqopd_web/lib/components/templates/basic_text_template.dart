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

    void commitParagraph() {
      final pText = currentParagraph.trim();
      if (pText.isEmpty) return;

      // Check if it's an image block: {{IMAGE: url}} or {{IMAGE}}
      final imageRegex = RegExp(r'^\{\{IMAGE(?::\s*(.*?))?\}\}$', caseSensitive: false);
      final match = imageRegex.firstMatch(pText);

      if (match != null) {
        final url = match.group(1)?.trim();
        final finalUrl = (url != null && url.isNotEmpty) ? url : 'https://placehold.co/600x400/png?text=Image+Asset';

        elements.add(img(
            src: finalUrl,
            attributes: const {
              'style': 'width: 100%; max-width: 100%; height: auto; margin: 12px 0; '
                  'display: block; break-inside: avoid; border: 1px solid #e2e8f0; border-radius: 4px;'
            }
        ));
      } else if (pText.startsWith('###')) {
        elements.add(h3([text(pText.substring(3).trim())], attributes: const {
          'style': 'font-family: "Impact", sans-serif; font-size: 16px; margin: 12px 0 6px 0; '
              'text-transform: uppercase; letter-spacing: 0.5px; line-height: 1.2; break-inside: avoid;'
        }));
      } else if (pText.startsWith('##')) {
        elements.add(h2([text(pText.substring(2).trim())], attributes: const {
          'style': 'font-family: "Impact", sans-serif; font-size: 20px; margin: 16px 0 8px 0; '
              'text-transform: uppercase; letter-spacing: 0.5px; line-height: 1.2; break-inside: avoid;'
        }));
      } else if (pText.startsWith('#')) {
        elements.add(h1([text(pText.substring(1).trim())], attributes: const {
          'style': 'font-family: "Impact", sans-serif; font-size: 24px; margin: 18px 0 10px 0; '
              'text-transform: uppercase; letter-spacing: 0.5px; line-height: 1.2; break-inside: avoid;'
        }));
      } else if (pText.startsWith('* ') || pText.startsWith('- ')) {
        // Bullet list item
        elements.add(div([
          span([text('•')], attributes: const {'style': 'font-weight: bold; margin-right: 6px;'}),
          text(pText.substring(2).trim())
        ], attributes: const {
          'style': 'font-size: 11px; line-height: 1.5; color: #1a1a1a; margin-bottom: 6px; '
              'padding-left: 12px; text-indent: -12px; break-inside: avoid;'
        }));
      } else {
        // Standard body paragraph
        elements.add(p([text(pText)], attributes: const {
          'style': 'font-size: 11px; line-height: 1.5; color: #1a1a1a; margin-top: 0; '
              'margin-bottom: 12px; text-align: justify;'
        }));
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