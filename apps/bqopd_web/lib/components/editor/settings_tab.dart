import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_utils.dart';

/// Decoupled Editor Settings sub-tab for updating fanzine metadata and layout rules.
/// Features local text state synchronization to prevent trailing-space trimming bugs on input.
class EditorSettingsTab extends StatefulComponent {
  final Fanzine fanzine;
  final List<FanzinePage> pages;
  final FanzineEditorBloc bloc;
  final bool isSaving;

  const EditorSettingsTab({
    required this.fanzine,
    required this.pages,
    required this.bloc,
    required this.isSaving,
    super.key,
  });

  @override
  State<EditorSettingsTab> createState() => _EditorSettingsTabState();
}

class _EditorSettingsTabState extends State<EditorSettingsTab> {
  String _title = '';
  String _volume = '';
  String _issue = '';
  String _wholeNumber = '';

  @override
  void initState() {
    super.initState();
    _syncLocalFields();
  }

  @override
  void didUpdateComponent(EditorSettingsTab oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.fanzine != component.fanzine) {
      _syncLocalFields();
    }
  }

  void _syncLocalFields() {
    _title = component.fanzine.title;
    _volume = component.fanzine.volume ?? '';
    _issue = component.fanzine.issue ?? '';
    _wholeNumber = component.fanzine.wholeNumber ?? '';
  }

  void _handleSaveAndNavigate() {
    // 1. Locate the first page in the folio page list and assign its thumbnail to 'gridCoverImage'
    String? firstPageImage;
    if (component.pages.isNotEmpty) {
      final sortedPages = List<FanzinePage>.from(component.pages)
        ..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));

      final firstPage = sortedPages.firstWhere(
            (p) => (p.gridUrl != null && p.gridUrl!.isNotEmpty) || (p.imageUrl != null && p.imageUrl!.isNotEmpty),
        orElse: () => sortedPages.first,
      );
      firstPageImage = firstPage.gridUrl ?? firstPage.imageUrl;
    }

    // 2. Dispatch the master save & commit events to the BLoC
    component.bloc.add(UpdateFanzineMetadata(
      _title,
      _volume,
      _issue,
      _wholeNumber,
      gridCoverImage: firstPageImage,
    ));

    // 3. Safely route the user back to their personal profile dashboard
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        Router.of(context).push('/profile');
      }
    });
  }

  @override
  Component build(BuildContext context) {
    final String currentShortcode = component.fanzine.shortCode != null
        ? component.fanzine.shortCode!.toUpperCase().replaceAll('BQOPD', 'bqopd')
        : 'pending...';
    return div(
      [
        // Shortcode indicator
        div(
          [text('shortcode: $currentShortcode')],
          classes: 'text-xs text-gray-500 font-semibold mb-1 text-left',
        ),
        // Fanzine Title Input
        div(
          [
            input(
              attributes: {
                'type': 'text',
                'placeholder': 'new folio name',
                'value': _title,
                'style': 'margin-bottom: 0;'
              },
              events: {
                'input': (e) {
                  setState(() {
                    _title = getInputValue(e);
                  });
                }
              },
            )
          ],
          classes: 'flex-col mb-1',
        ),
        // Volume / Issue / Whole Number Row
        div(
          [
            // Volume
            div(
              [
                input(
                  attributes: {
                    'type': 'text',
                    'placeholder': 'vol.',
                    'value': _volume,
                    'style': 'margin-bottom: 0;'
                  },
                  events: {
                    'input': (e) {
                      setState(() {
                        _volume = getInputValue(e);
                      });
                    }
                  },
                )
              ],
              classes: 'flex-1 flex-col',
            ),
            // Issue
            div(
              [
                input(
                  attributes: {
                    'type': 'text',
                    'placeholder': 'num.',
                    'value': _issue,
                    'style': 'margin-bottom: 0;'
                  },
                  events: {
                    'input': (e) {
                      setState(() {
                        _issue = getInputValue(e);
                      });
                    }
                  },
                )
              ],
              classes: 'flex-1 flex-col',
            ),
            // Whole Number
            div(
              [
                input(
                  attributes: {
                    'type': 'text',
                    'placeholder': 'whole num.',
                    'value': _wholeNumber,
                    'style': 'margin-bottom: 0;'
                  },
                  events: {
                    'input': (e) {
                      setState(() {
                        _wholeNumber = getInputValue(e);
                      });
                    }
                  },
                )
              ],
              classes: 'flex-1 flex-col',
            ),
          ],
          classes: 'flex-row gap-2 mb-1',
          attributes: const {'style': 'display: flex; gap: 8px; width: 100%; box-sizing: border-box;'},
        ),
        // Two-Page Spread Custom Toggle Switch
        div(
          [
            span(
                [
                  text(component.fanzine.twoPage
                      ? 'two page spread (switch: single page view)'
                      : 'single page view (switch: two page spread)')
                ],
                classes: 'text-xs font-medium',
                attributes: const {'style': 'color: #4a4a4a;'}
            ),
            _buildCustomToggleSwitch(component.fanzine.twoPage)
          ],
          classes: 'flex-row items-center justify-between cursor-pointer',
          attributes: const {
            'style': 'padding: 10px 12px; background-color: #f9f9f9; border: 1px solid #eee; border-radius: 8px; margin-bottom: 4px; display: flex; align-items: center; justify-content: space-between;'
          },
          events: {
            'click': (e) {
              component.bloc.add(ToggleTwoPageRequested(!component.fanzine.twoPage));
            }
          },
        ),
        // Save metadata button
        button(
          [text(component.isSaving ? 'saving folio...' : 'save folio')],
          classes: 'btn-primary w-full',
          attributes: component.isSaving ? {'disabled': 'true'} : const {},
          events: {
            'click': (e) => _handleSaveAndNavigate(),
          },
        )
      ],
      classes: 'flex-col text-left p-2',
      attributes: const {
        'style': 'gap: 12px; display: flex;'
      },
    );
  }

  Component _buildCustomToggleSwitch(bool val) {
    return div(
      [],
      attributes: {
        'style': 'width: 44px; height: 24px; border-radius: 12px; background-color: ${val ? '#808080' : '#ccc'}; position: relative; transition: background-color 0.2s; cursor: pointer; display: inline-block;'
      },
    );
  }
}