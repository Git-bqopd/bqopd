import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

/// Curator-isolated custom modal for confirming destructive operations.
/// 100% decoupled from Editor dialog states.
class CuratorConfirmModal extends StatelessComponent {
  final String title;
  final String message;
  final String confirmLabel;
  final bool isDestructive;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const CuratorConfirmModal({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.isDestructive = false,
    required this.onCancel,
    required this.onConfirm,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    return div(
      classes: 'global-modal-overlay',
      attributes: const {
        'style': 'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.65); z-index: 30000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(4px);'
      },
      [
        div(
          attributes: const {
            'style': 'background-color: white; border-radius: 12px; width: 100%; max-width: 400px; padding: 24px; display: flex; flex-direction: column; gap: 16px; box-shadow: 0 10px 25px rgba(0,0,0,0.2); text-align: left; margin: 16px; box-sizing: border-box;'
          },
          [
            // Title
            h3(
              [text(title)],
              attributes: const {
                'style': 'font-size: 18px; font-weight: bold; margin: 0; color: #1a1a1a;'
              },
            ),

            // Message Description
            p(
              [text(message)],
              attributes: const {
                'style': 'font-size: 13.5px; color: #555555; line-height: 1.5; margin: 0;'
              },
            ),

            // Actions
            div(
              attributes: const {
                'style': 'display: flex; gap: 12px; justify-content: flex-end; margin-top: 8px;'
              },
              [
                // Cancel Action Button
                button(
                  [text("cancel")],
                  attributes: const {
                    'style': 'background-color: #f3f4f6; color: #374151; border: none; border-radius: 8px; padding: 8px 16px; font-size: 12px; font-weight: bold; cursor: pointer; transition: background 0.15s;'
                  },
                  events: {
                    'click': (e) => onCancel(),
                  },
                ),

                // Confirm Action Button
                button(
                  [text(confirmLabel.toLowerCase())],
                  attributes: {
                    'style': 'background-color: ${isDestructive ? "#ef4444" : "#6750A4"}; color: white; border: none; border-radius: 8px; padding: 8px 16px; font-size: 12px; font-weight: bold; cursor: pointer; transition: background 0.15s;'
                  },
                  events: {
                    'click': (e) => onConfirm(),
                  },
                ),
              ],
            ),
          ],
        )
      ],
    );
  }
}