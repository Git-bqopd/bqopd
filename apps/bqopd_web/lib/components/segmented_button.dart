import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

/// A reusable, highly-interactive Segmented Button component for the Jaspr web app.
/// Styled using standard CSS matching Material 3 patterns.
class SegmentedButton<T> extends StatelessComponent {
  /// The list of items representing each segment in the group.
  final List<T> segments;

  /// The currently active/selected value.
  final T selected;

  /// Callback triggered when a segment is tapped.
  final ValueChanged<T> onSelectionChanged;

  /// Builder function to map your raw generic type to a readable display string.
  final String Function(T) labelBuilder;

  /// Optional builder to map a segment value to a Material Symbol name string (e.g. 'check').
  final String? Function(T)? iconBuilder;

  const SegmentedButton({
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    required this.labelBuilder,
    this.iconBuilder,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    return div(
      classes: 'm3-segmented-button-container',
      attributes: {
        'style': 'display: inline-flex; align-items: center; border: 1px solid var(--m3-outline); border-radius: 100px; overflow: hidden; background: var(--m3-surface);'
      },
      [
        for (int i = 0; i < segments.length; i++) ...[
          _buildSegment(segments[i]),
          if (i < segments.length - 1)
          // Vertical separation border between segments
            div(
              classes: 'segment-separator',
              attributes: {
                'style': 'width: 1px; height: 16px; background-color: var(--m3-outline); opacity: 0.25;'
              },
              [],
            ),
        ]
      ],
    );
  }

  Component _buildSegment(T segment) {
    final bool isSelected = segment == selected;
    final String? iconName = iconBuilder != null ? iconBuilder!(segment) : null;

    return button(
      classes: 'segment-button ${isSelected ? 'active' : ''}',
      attributes: {
        'type': 'button', // Safe guard against default form submissions
        'style': 'border: none; padding: 6px 14px; font-size: 11px; font-weight: 600; cursor: pointer; transition: all 0.15s ease-in-out; '
            'display: inline-flex; align-items: center; justify-content: center; gap: 4px; '
            'background-color: ${isSelected ? 'var(--m3-secondary-container)' : 'transparent'}; '
            'color: ${isSelected ? 'var(--m3-on-secondary-container)' : '#49454F'};'
      },
      events: {
        'click': (e) => onSelectionChanged(segment),
      },
      [
        if (iconName != null)
          span(
            classes: 'material-symbols-outlined',
            attributes: {
              'style': 'font-size: 14px; '
                  'font-variation-settings: "FILL" ${isSelected ? 1 : 0};'
            },
            [text(iconName)],
          ),
        text(labelBuilder(segment).toLowerCase()),
      ],
    );
  }
}