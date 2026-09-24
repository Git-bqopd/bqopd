import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_utils.dart';

/// Isolated Settings tab for managing metadata, title, volume/issue numbers, and spread mode.
class SettingsTab extends StatefulComponent {
  final Fanzine fanzine;
  final List<FanzinePage> pages;
  final FanzineEditorBloc bloc;
  final bool isSaving;

  const SettingsTab({
    required this.fanzine,
    required this.pages,
    required this.bloc,
    required this.isSaving,
    super.key,
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
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
  void didUpdateComponent(SettingsTab oldComponent) {
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
    String? firstPageImage;
    if (component.pages.isNotEmpty) {
      final sortedPages = List<FanzinePage>.from(component.pages)
        ..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
      final firstPage = sortedPages.firstWhere(
            (p) =>
        (p.gridUrl != null && p.gridUrl!.isNotEmpty) ||
            (p.imageUrl != null && p.imageUrl!.isNotEmpty),
        orElse: () => sortedPages.first,
      );
      firstPageImage = firstPage.gridUrl ?? firstPage.imageUrl;
    }

    component.bloc.add(UpdateFanzineMetadata(
      _title,
      _volume,
      _issue,
      _wholeNumber,
      gridCoverImage: firstPageImage,
    ));

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
      classes: 'flex-col text-left p-2',
      attributes: const {'style': 'gap: 12px; display: flex; width: 100%; box-sizing: border-box;'},
      [
        // Shortcode Indicator
        div(
          [Component.text('shortcode: $currentShortcode')],
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
                'style': 'margin-bottom: 0; width: 100%; box-sizing: border-box;'
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
            div(
              [
                input(
                  attributes: {
                    'type': 'text',
                    'placeholder': 'vol.',
                    'value': _volume,
                    'style': 'margin-bottom: 0; width: 100%; box-sizing: border-box;'
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
            div(
              [
                input(
                  attributes: {
                    'type': 'text',
                    'placeholder': 'num.',
                    'value': _issue,
                    'style': 'margin-bottom: 0; width: 100%; box-sizing: border-box;'
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
            div(
              [
                input(
                  attributes: {
                    'type': 'text',
                    'placeholder': 'whole num.',
                    'value': _wholeNumber,
                    'style': 'margin-bottom: 0; width: 100%; box-sizing: border-box;'
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

        // Two-Page Spread Option Toggle
        div(
          [
            span(
              [
                Component.text(component.fanzine.twoPage
                    ? 'two page spread (switch: single page view)'
                    : 'single page view (switch: two page spread)')
              ],
              classes: 'text-xs font-medium',
              attributes: const {'style': 'color: #4a4a4a;'},
            ),
            _buildCustomToggleSwitch(component.fanzine.twoPage)
          ],
          classes: 'flex-row items-center justify-between cursor-pointer',
          attributes: const {
            'style':
            'padding: 10px 12px; background-color: #f9f9f9; border: 1px solid #eee; border-radius: 8px; margin-bottom: 4px; display: flex; align-items: center; justify-content: space-between;'
          },
          events: {
            'click': (e) {
              component.bloc.add(ToggleTwoPageRequested(!component.fanzine.twoPage));
            }
          },
        ),

        // Save Button
        button(
          [Component.text(component.isSaving ? 'saving folio...' : 'save folio')],
          classes: 'btn-primary w-full',
          attributes: component.isSaving ? {'disabled': 'true'} : const {},
          events: {
            'click': (e) => _handleSaveAndNavigate(),
          },
        )
      ],
    );
  }

  Component _buildCustomToggleSwitch(bool val) {
    return div(
      [
        div(
          [],
          attributes: {
            'style':
            'width: 18px; height: 18px; border-radius: 50%; background-color: white; position: absolute; top: 3px; left: ${val ? "23px" : "3px"}; transition: left 0.2s; box-shadow: 0 1px 3px rgba(0,0,0,0.35);'
          },
        )
      ],
      attributes: {
        'style':
        'width: 44px; height: 24px; border-radius: 12px; background-color: ${val ? "#6750A4" : "#ccc"}; position: relative; transition: background-color 0.2s; cursor: pointer; display: inline-block;'
      },
    );
  }
}

typedef EditorSettingsTab = SettingsTab;