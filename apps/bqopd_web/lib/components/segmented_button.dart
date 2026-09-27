import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

/// A reusable Segmented Button component adhering strictly to Material Design 3 (M3) specifications.
/// Matches https://m3.material.io/components/segmented-buttons/overview
/// Features pill container borders, internal dividers, selected checkmark icons, and M3 color tokens.
class SegmentedButton<T> extends StatelessComponent {
  /// The list of items representing each segment in the group.
  final List<T> segments;

  /// The currently active/selected value.
  final T selected;

  /// Callback triggered when a segment is tapped.
  final ValueChanged<T> onSelectionChanged;

  /// Builder function to map your generic type to a readable display string.
  final String Function(T) labelBuilder;

  /// Optional builder to map a segment value to a custom Material Symbol name string.
  final String? Function(T)? iconBuilder;

  /// Whether to display the checkmark icon on the selected segment (default true in M3 single-select).
  final bool showSelectedCheckmark;

  const SegmentedButton({
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    required this.labelBuilder,
    this.iconBuilder,
    this.showSelectedCheckmark = true,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    return div(
      classes: 'm3-segmented-button-container',
      attributes: const {
        'style':
        'display: inline-flex; align-items: stretch; height: 38px; border: 1px solid var(--m3-outline, #79747E); border-radius: 100px; overflow: hidden; background-color: var(--m3-surface, #ffffff); box-sizing: border-box;'
      },
      [
        for (int i = 0; i < segments.length; i++) ...[
          _buildSegment(segments[i]),
          if (i < segments.length - 1)
            div(
              classes: 'm3-segment-divider',
              attributes: const {
                'style':
                'width: 1px; height: 100%; background-color: var(--m3-outline, #79747E); opacity: 0.35; flex-shrink: 0;'
              },
              [],
            ),
        ]
      ],
    );
  }

  Component _buildSegment(T segment) {
    final bool isSelected = segment == selected;
    final String? customIcon = iconBuilder != null ? iconBuilder!(segment) : null;
    final String? iconName = isSelected
        ? (customIcon ?? (showSelectedCheckmark ? 'check' : null))
        : customIcon;

    return button(
      classes: 'm3-segment-button ${isSelected ? 'active' : ''}',
      attributes: {
        'type': 'button',
        'style':
        'border: none; padding: 0 16px; height: 100%; font-size: 13px; font-weight: 500; font-family: inherit; cursor: pointer; transition: background-color 0.2s cubic-bezier(0.4, 0, 0.2, 1), color 0.2s; '
            'display: inline-flex; align-items: center; justify-content: center; gap: 6px; user-select: none; '
            'background-color: ${isSelected ? "var(--m3-secondary-container, #E8DEF8)" : "transparent"}; '
            'color: ${isSelected ? "var(--m3-on-secondary-container, #1D192B)" : "#49454F"};'
      },
      events: {
        'click': (e) => onSelectionChanged(segment),
      },
      [
        if (iconName != null)
          span(
            classes: 'material-symbols-outlined',
            attributes: {
              'style':
              'font-size: 18px; line-height: 1; color: ${isSelected ? "var(--m3-on-secondary-container, #1D192B)" : "inherit"};'
            },
            [Component.text(iconName)],
          ),
        Component.text(labelBuilder(segment).toLowerCase()),
      ],
    );
  }
}