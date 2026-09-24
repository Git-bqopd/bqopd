import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

/// Confirmation dialog modal for curator destructive actions.
class CuratorConfirmModal extends StatelessComponent {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool isDestructive;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const CuratorConfirmModal({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel = 'cancel',
    this.isDestructive = false,
    required this.onConfirm,
    required this.onCancel,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    return div(
      classes: 'global-modal-overlay',
      attributes: const {
        'style':
        'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0, 0, 0, 0.65); z-index: 10000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(4px);'
      },
      [
        div(
          classes: 'white-sticker shadow-lg',
          attributes: const {
            'style':
            'width: 90%; max-width: 420px; background: white; border-radius: 12px; padding: 24px; box-sizing: border-box; display: flex; flex-direction: column; gap: 16px;'
          },
          [
            h3(
              [Component.text(title)],
              attributes: const {
                'style':
                'margin: 0; font-size: 16px; font-weight: bold; color: #111; letter-spacing: -0.2px;'
              },
            ),
            p(
              [Component.text(message)],
              attributes: const {
                'style':
                'margin: 0; font-size: 13px; line-height: 1.5; color: #555;'
              },
            ),
            div(
              attributes: const {
                'style':
                'display: flex; justify-content: flex-end; gap: 10px; margin-top: 8px;'
              },
              [
                button(
                  [Component.text(cancelLabel)],
                  classes: 'profile-btn',
                  attributes: const {
                    'type': 'button',
                    'style':
                    'padding: 8px 16px; font-size: 11px; font-weight: bold; border: 1px solid #ccc; background: white; color: #444; border-radius: 6px; cursor: pointer;'
                  },
                  events: {
                    'click': (e) => onCancel(),
                  },
                ),
                button(
                  [Component.text(confirmLabel)],
                  attributes: {
                    'type': 'button',
                    'style':
                    'padding: 8px 18px; font-size: 11px; font-weight: bold; border: none; border-radius: 6px; cursor: pointer; color: white; background-color: ${isDestructive ? "#ef4444" : "#6750A4"};'
                  },
                  events: {
                    'click': (e) => onConfirm(),
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}