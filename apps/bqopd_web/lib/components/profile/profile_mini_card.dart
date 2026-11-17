import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

/// A reusable mini card component representing a user profile, place entity,
/// or combined profile-with-mailing-address entity (up to 3 rows of text:
/// Row 1: Display Name / Street, Row 2: Street / City-State-ZIP, Row 3: City-State-ZIP).
class ProfileMiniCard extends StatelessComponent {
  final String title;
  final String? subtitle;
  final String? subtitleLine2;
  final String? photoUrl;
  final bool isAddress;
  final bool isLinked;
  final VoidCallback? onTap;

  const ProfileMiniCard({
    required this.title,
    this.subtitle,
    this.subtitleLine2,
    this.photoUrl,
    this.isAddress = false,
    this.isLinked = true,
    this.onTap,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    return div(
      attributes: {
        'style':
        'background-color: #ffffff; border: 1px solid #cbd5e1; border-radius: 8px; padding: 12px; display: flex; align-items: center; justify-content: space-between; ${isLinked ? "cursor: pointer; transition: all 0.2s ease;" : ""}'
      },
      events: isLinked && onTap != null ? {'click': (e) => onTap!()} : {},
      [
        div(
          attributes: const {
            'style':
            'display: flex; align-items: center; gap: 12px; overflow: hidden;'
          },
          [
            // Avatar / Icon
            if (isAddress)
              div(
                attributes: const {
                  'style':
                  'width: 36px; height: 36px; border-radius: 50%; background-color: #e0e7ff; display: flex; align-items: center; justify-content: center; flex-shrink: 0;'
                },
                [
                  span(
                    classes: 'material-symbols-outlined text-indigo-600',
                    attributes: const {'style': 'font-size: 18px;'},
                    [Component.text('pin_drop')],
                  )
                ],
              )
            else if (photoUrl != null && photoUrl!.isNotEmpty)
              img(
                src: photoUrl!,
                attributes: const {
                  'style':
                  'width: 36px; height: 36px; border-radius: 50%; object-fit: cover; flex-shrink: 0;'
                },
              )
            else
              div(
                attributes: const {
                  'style':
                  'width: 36px; height: 36px; border-radius: 50%; background-color: #cbd5e1; color: #334155; display: flex; align-items: center; justify-content: center; font-weight: bold; font-size: 14px; flex-shrink: 0;'
                },
                [
                  Component.text(
                    title.isNotEmpty ? title[0].toUpperCase() : '?',
                  )
                ],
              ),
            // Stacked Text Rows (Row 1: title, Row 2: subtitle, Row 3: subtitleLine2)
            div(
              attributes: const {
                'style':
                'display: flex; flex-direction: column; overflow: hidden; text-align: left;'
              },
              [
                span(
                  attributes: const {
                    'style':
                    'font-weight: 600; font-size: 14px; color: #1e293b; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; line-height: 1.25;'
                  },
                  [Component.text(title)],
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  span(
                    attributes: const {
                      'style':
                      'font-size: 12px; color: #64748b; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; line-height: 1.3; margin-top: 2px;'
                    },
                    [Component.text(subtitle!)],
                  ),
                if (subtitleLine2 != null && subtitleLine2!.isNotEmpty)
                  span(
                    attributes: const {
                      'style':
                      'font-size: 12px; color: #64748b; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; line-height: 1.3; margin-top: 1px;'
                    },
                    [Component.text(subtitleLine2!)],
                  ),
              ],
            ),
          ],
        ),
        if (isLinked)
          span(
            classes: 'material-symbols-outlined',
            attributes: const {
              'style': 'font-size: 18px; color: #94a3b8; flex-shrink: 0;'
            },
            [Component.text(isAddress ? 'open_in_new' : 'chevron_right')],
          ),
      ],
    );
  }
}