import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

/// Represents parsed, structured page content assigned to physical columns.
class ColumnData {
  final List<Component> elements = [];
  bool isSpecialLayout = false;

  void add(Component element) {
    elements.add(element);
  }
}

/// A highly-flexible flow parser and layout renderer for 3-column page templates.
/// It dynamically translates linear text mixed with standard and layout-breaking tokens
/// into structured column-based responsive web designs.
class FanzinePageLayout extends StatelessComponent {
  final String rawText;
  final String currentImageId;

  const FanzinePageLayout({
    required this.rawText,
    required this.currentImageId,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    // Parse the linear text stream into up to 3 structured physical columns
    final List<ColumnData> parsedColumns = _parseColumns(rawText);

    return div(
      classes: 'fanzine-page-grid grid grid-cols-3 gap-6 h-full w-full min-h-[600px] bg-white p-6 border border-gray-300 rounded-lg shadow-sm overflow-hidden box-border',
      [
        for (int i = 0; i < 3; i++)
          _buildColumn(i < parsedColumns.length ? parsedColumns[i] : ColumnData())
      ],
    );
  }

  /// Evaluates linear text, splitting it dynamically when a structural template is hit.
  List<ColumnData> _parseColumns(String text) {
    // We initialize our layout slots (columns 1, 2, and 3)
    final List<ColumnData> columns = [ColumnData(), ColumnData(), ColumnData()];
    int currentColumnIndex = 0;

    // Matches layout-breaking template patterns: e.g., {{1|image|Caption Text}}
    // Also matches inline standard asset IDs: e.g., {{DJ5bqopd}}
    final RegExp tagRegex = RegExp(r'\{\{([^}]+)\}\}');

    int lastMatchEnd = 0;
    final Iterable<RegExpMatch> matches = tagRegex.allMatches(text);

    for (final match in matches) {
      // 1. Flush any plain text before the token into the current column
      final plainText = text.substring(lastMatchEnd, match.start).trim();
      if (plainText.isNotEmpty) {
        _addFlowableText(columns, currentColumnIndex, plainText);
      }

      final tokenContent = match.group(1) ?? '';

      // 2. Identify if the token is a Layout-Breaking Template (starts with '1|image|')
      if (tokenContent.startsWith('1|image|')) {
        final parts = tokenContent.split('|');
        final caption = parts.length > 2 ? parts[2] : '';

        // Force column transition!
        // If our current column already has text content, move to the next column
        if (currentColumnIndex < 3 && columns[currentColumnIndex].elements.isNotEmpty) {
          currentColumnIndex++;
        }

        // Check boundary limits (ensure we stay within the 3-column physical layout constraints)
        if (currentColumnIndex < 3) {
          final targetColumn = columns[currentColumnIndex];
          targetColumn.isSpecialLayout = true;

          // Build the centered exclusive block inside this column
          targetColumn.add(
              div(
                  classes: 'flex flex-col justify-center items-center text-center h-full w-full py-6 px-4 box-border',
                  attributes: const {'style': 'min-height: 100%; justify-content: center;'},
                  [
                    img(
                      classes: 'max-h-[60%] object-contain rounded shadow mb-4 border border-gray-200 transition-transform duration-200 hover:scale-[1.02]',
                      src: '/api/image/$currentImageId', // Fallback URL matching your assets
                      alt: caption,
                    ),
                    if (caption.isNotEmpty)
                      p(
                          classes: 'text-sm font-semibold text-gray-700 tracking-wide mt-2',
                          [Component.text(caption)]
                      ),
                  ]
              )
          );

          // Once mapped, lock this column by stepping into the NEXT column slot for subsequent text flow
          currentColumnIndex++;
        }
      }
      // 3. Otherwise, treat it as a Standard Inline Asset Tag (e.g., {{DJ5bqopd}}), which flows inline
      else {
        if (currentColumnIndex < 3) {
          columns[currentColumnIndex].add(
              div(
                  classes: 'my-4 text-center',
                  [
                    img(
                      classes: 'w-full max-h-[150px] object-cover rounded border border-gray-100 shadow-sm',
                      src: '/api/image/$tokenContent',
                      alt: 'Inline reference asset',
                    ),
                    span(classes: 'text-xs text-gray-400 mt-1 block', [Component.text('Ref: $tokenContent')])
                  ]
              )
          );
        }
      }

      lastMatchEnd = match.end;
    }

    // 4. Flush any remaining text after the final token into the active column
    if (lastMatchEnd < text.length) {
      final remainingText = text.substring(lastMatchEnd).trim();
      if (remainingText.isNotEmpty) {
        _addFlowableText(columns, currentColumnIndex, remainingText);
      }
    }

    return columns;
  }

  /// Gracefully chunks text by paragraph and adds it to the current column, spilling over if columns overflow
  void _addFlowableText(List<ColumnData> columns, int index, String text) {
    final activeIndex = index < 3 ? index : 2; // Clamp overflow to column 3
    final target = columns[activeIndex];

    // Split text into individual paragraphs for clean vertical typography flow
    final paragraphs = text.split('\n\n');
    for (final para in paragraphs) {
      if (para.trim().isNotEmpty) {
        target.add(
            p(
                classes: 'text-sm text-gray-800 leading-relaxed text-justify mb-4 font-normal',
                attributes: const {'style': 'font-feature-settings: "kern" 1, "liga" 1;'},
                [Component.text(para.trim())]
            )
        );
      }
    }
  }

  /// Builds a physical column grid slot with Tailwind CSS, altering styles based on template types.
  Component _buildColumn(ColumnData column) {
    if (column.isSpecialLayout) {
      // Highlight container design for exclusive block templates
      return div(
          classes: 'h-full bg-gray-50 rounded-lg border border-dashed border-gray-300 transition-colors duration-200 hover:bg-gray-100 flex flex-col justify-center overflow-hidden',
          column.elements
      );
    } else {
      // Classic vertical editorial flow styles
      return div(
          classes: 'h-full flex flex-col text-flow-column overflow-y-auto pr-1 select-text scrollbar-thin',
          column.elements.isNotEmpty
              ? column.elements
              : [div(classes: 'text-gray-300 italic text-xs py-4 text-center', [Component.text('Empty slot')])]
      );
    }
  }
}