import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

/// Template layout for singleton tools that occupy the entire column width and height
/// without repeating per page (e.g. Terminal, YouTube, Settings, Analytics).
class SingleWindowColumnLayout extends StatelessComponent {
  final String title;
  final Component child;
  final VoidCallback onClose;

  const SingleWindowColumnLayout({
    required this.title,
    required this.child,
    required this.onClose,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    return div(
      classes: 'w-full h-full flex-col overflow-hidden',
      attributes: const {
        'style':
        'display: flex; flex-direction: column; width: 100%; height: 100%; overflow: hidden; background-color: #e5e5e5;'
      },
      [
        // Column Header
        div(
          classes: 'p-4 bg-white flex-row justify-between items-center',
          attributes: const {
            'style':
            'display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #d1d5db; flex-shrink: 0; padding: 16px; background-color: #ffffff;'
          },
          [
            span(
              [Component.text(title)],
              attributes: const {
                'style':
                'font-weight: bold; font-size: 13px; letter-spacing: 0.8px; text-transform: uppercase; color: #1e293b;'
              },
            ),
            button(
              classes: 'cursor-pointer border-none bg-transparent',
              events: {'click': (e) => onClose()},
              [
                span(
                  classes: 'material-symbols-outlined',
                  [Component.text('close')],
                )
              ],
            )
          ],
        ),
        // Body area (Grey background #e5e5e5)
        div(
          classes: 'flex-1 overflow-y-auto p-4',
          attributes: const {
            'style':
            'flex: 1; overflow-y: auto; padding: 16px; background-color: #e5e5e5;'
          },
          [child],
        )
      ],
    );
  }
}

/// Template layout for per-page panels that iterate through each page in the fanzine
/// (e.g. Comments, Text Reader, OCR Text, Entities, Credits).
/// Accepts an optional [headerWidget] placed at the top of the column feed above the page cards.
class MultiPageColumnLayout extends StatelessComponent {
  final String title;
  final List<Map<String, dynamic>> pages;
  final Component Function(Map<String, dynamic> pageData) pageBuilder;
  final VoidCallback onClose;
  final Component? headerWidget;

  const MultiPageColumnLayout({
    required this.title,
    required this.pages,
    required this.pageBuilder,
    required this.onClose,
    this.headerWidget,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    return div(
      classes: 'w-full h-full flex-col overflow-hidden',
      attributes: const {
        'style':
        'display: flex; flex-direction: column; width: 100%; height: 100%; overflow: hidden; background-color: #e5e5e5;'
      },
      [
        // Column Header
        div(
          classes: 'p-4 bg-white flex-row justify-between items-center',
          attributes: const {
            'style':
            'display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #d1d5db; flex-shrink: 0; padding: 16px; background-color: #ffffff;'
          },
          [
            span(
              [Component.text(title)],
              attributes: const {
                'style':
                'font-weight: bold; font-size: 13px; letter-spacing: 0.8px; text-transform: uppercase; color: #1e293b;'
              },
            ),
            button(
              classes: 'cursor-pointer border-none bg-transparent',
              events: {'click': (e) => onClose()},
              [
                span(
                  classes: 'material-symbols-outlined',
                  [Component.text('close')],
                )
              ],
            )
          ],
        ),
        // Scrollable Feed List (#e5e5e5 backdrop matching Column 1)
        div(
          classes: 'flex-1 overflow-y-auto p-4',
          attributes: const {
            'style':
            'flex: 1; overflow-y: auto; padding: 16px; background-color: #e5e5e5;'
          },
          [
            // Optional Top Column Widget (e.g. EntitiesColumnPanelHeader map)
            if (headerWidget != null) headerWidget!,
            for (var page in pages) ...[
              // Individual Page Card Container (White card floating on grey background)
              div(
                classes:
                'bg-white rounded-lg border border-gray-300 shadow-md p-5 mb-5',
                attributes: const {
                  'style':
                  'background-color: #ffffff; border: 1px solid #cbd5e1; border-radius: 8px; padding: 20px; margin-bottom: 20px; box-shadow: 0 4px 12px rgba(0, 0, 0, 0.08);'
                },
                [
                  // Page Card Header Banner
                  if (page['pageNumber'] != null)
                    div(
                      classes:
                      'flex-row items-center justify-between border-b border-gray-200 pb-2 mb-4',
                      attributes: const {
                        'style':
                        'display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #e2e8f0; padding-bottom: 8px; margin-bottom: 16px;'
                      },
                      [
                        span(
                          classes:
                          'text-xs font-bold text-gray-600 uppercase tracking-wider',
                          attributes: const {
                            'style':
                            'font-size: 11px; font-weight: bold; color: #475569; letter-spacing: 0.8px; text-transform: uppercase;'
                          },
                          [Component.text('PAGE ${page['pageNumber']}')],
                        ),
                      ],
                    ),
                  // Page Widget Content with padding around comments/info
                  div(
                    attributes: const {'style': 'padding: 4px;'},
                    [pageBuilder(page)],
                  ),
                ],
              )
            ]
          ],
        )
      ],
    );
  }
}