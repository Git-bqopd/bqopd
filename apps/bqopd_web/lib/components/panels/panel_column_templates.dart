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
          id: 'panel-singleton-scroll-area',
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
///
/// Features a native, unconstrained list scroll feed where scrolling in this column
/// does not trigger or hijack scrolling in Columns 1 and 2.
/// Visually highlights the active target card and switches the target upon clicking.
class MultiPageColumnLayout extends StatelessComponent {
  final String title;
  final List<Map<String, dynamic>> pages;
  final Component Function(Map<String, dynamic> pageData) pageBuilder;
  final VoidCallback onClose;
  final Component? headerWidget;
  final int targetPageIndex;
  final void Function(int pageIndex)? onPageCardTap;

  const MultiPageColumnLayout({
    required this.title,
    required this.pages,
    required this.pageBuilder,
    required this.onClose,
    this.headerWidget,
    this.targetPageIndex = 0,
    this.onPageCardTap,
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
        // Scrollable Feed List
        div(
          id: 'panel-column-scroll-area',
          classes: 'flex-1 overflow-y-auto p-4',
          attributes: const {
            'style':
            'flex: 1; overflow-y: auto; padding: 16px; background-color: #e5e5e5; -webkit-overflow-scrolling: touch;'
          },
          [
            // Optional Top Column Widget (e.g. EntitiesColumnPanelHeader map)
            if (headerWidget != null) headerWidget!,
            for (int i = 0; i < pages.length; i++)
              _buildPageCard(i, pages[i]),
          ],
        )
      ],
    );
  }

  Component _buildPageCard(int index, Map<String, dynamic> page) {
    final bool isTarget = targetPageIndex == index;

    return div(
      id: 'panel-page-$index',
      classes:
      'panel-page-card bg-white rounded-lg border shadow-md p-5 mb-5 ${isTarget ? "target" : "non-target"}',
      attributes: {
        'style':
        'background-color: #ffffff; border-radius: 8px; padding: 20px; margin-bottom: 20px; cursor: pointer; transition: all 0.2s ease; ${isTarget ? "border: 2px solid #6750A4; box-shadow: 0 4px 16px rgba(103, 80, 164, 0.16);" : "border: 1px solid #cbd5e1;"}',
      },
      events: {
        'click': (e) {
          if (!isTarget) {
            onPageCardTap?.call(index);
          }
        },
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
                classes: 'text-xs font-bold uppercase tracking-wider',
                attributes: {
                  'style':
                  'font-size: 11px; font-weight: bold; color: ${isTarget ? "#6750A4" : "#475569"}; letter-spacing: 0.8px; text-transform: uppercase;',
                },
                [Component.text('PAGE ${page['pageNumber']}')],
              ),
              if (isTarget)
                span(
                  classes: 'text-xs font-bold',
                  attributes: const {
                    'style':
                    'font-size: 10px; color: #6750A4; font-weight: bold; letter-spacing: 0.5px; text-transform: uppercase; background-color: #E8DEF8; padding: 2px 8px; border-radius: 10px;',
                  },
                  [Component.text('ACTIVE')],
                ),
            ],
          ),
        // Page Widget Content
        div(
          attributes: const {'style': 'padding: 4px;'},
          [pageBuilder(page)],
        ),
      ],
    );
  }
}
