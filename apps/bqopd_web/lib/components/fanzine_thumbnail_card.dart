import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

/// Formats dates dynamically based on precision mode and estimated guess toggle.
String formatThumbnailDate(String? dateStr, String? mode, bool isGuess) {
  if (dateStr == null || dateStr.trim().isEmpty) return '';
  try {
    final parts = dateStr.split('-');
    if (parts.isEmpty) return '';
    final year = parts[0];
    final monthInt = parts.length > 1 ? int.tryParse(parts[1]) : null;
    final dayInt = parts.length > 2 ? int.tryParse(parts[2]) : null;

    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    String result = '';
    if (mode == 'day') {
      if (monthInt != null && monthInt >= 1 && monthInt <= 12) {
        final monthName = months[monthInt - 1];
        final day = dayInt != null ? '$dayInt, ' : '';
        result = '$monthName $day$year';
      } else {
        result = dateStr;
      }
    } else if (mode == 'month') {
      if (monthInt != null && monthInt >= 1 && monthInt <= 12) {
        final monthName = months[monthInt - 1];
        result = '$monthName, $year';
      } else {
        result = year;
      }
    } else {
      result = year;
    }

    if (isGuess) {
      result += '?';
    }
    return result;
  } catch (_) {
    return dateStr + (isGuess ? '?' : '');
  }
}

/// A reusable, lightweight 5:8 thumbnail card with square corners and no drop shadows.
/// Row 1: The 5:8 thumbnail container with #F1B255 letterbox/pillarbox margins (squared edges).
/// Row 2: Left-aligned title and right-aligned three-dot menu (transparent background).
/// Three-dot menu: Shows the source type ('fanzine' or 'image') with a horizontal divider,
/// followed by contextual actions (e.g. 'show indicia', 'use as full page' checkbox, and 'delete').
/// Row 3: Optional indicia text row when toggled via the three-dot menu (page-wide or local).
class FanzineThumbnailCard extends StatefulComponent {
  final Map<String, dynamic> fanzineData;
  final String? targetHref;
  final String? customCoverUrl;
  final String? cardType; // 'fanzine' or 'image'
  final bool? showTopBadges;
  final bool? showIndicia;
  final ValueChanged<bool>? onToggleShowIndicia;
  final void Function(String id, String title)? onDelete;
  final VoidCallback? onUseAsFullPage;
  final bool? isFullPage;
  final ValueChanged<bool>? onToggleFullPage;
  final void Function()? onMenuTap;
  final VoidCallback? onCardTap;

  const FanzineThumbnailCard({
    required this.fanzineData,
    this.targetHref,
    this.customCoverUrl,
    this.cardType,
    this.showTopBadges,
    this.showIndicia,
    this.onToggleShowIndicia,
    this.onDelete,
    this.onUseAsFullPage,
    this.isFullPage,
    this.onToggleFullPage,
    this.onMenuTap,
    this.onCardTap,
    super.key,
  });

  @override
  State<FanzineThumbnailCard> createState() => _FanzineThumbnailCardState();
}

class _FanzineThumbnailCardState extends State<FanzineThumbnailCard> {
  bool _isMenuOpen = false;
  bool _localShowIndicia = false;
  bool _localIsFullPage = false;

  bool get _effectiveShowIndicia => component.showIndicia ?? _localShowIndicia;
  bool get _effectiveIsFullPage => component.isFullPage ?? _localIsFullPage;

  @override
  void initState() {
    super.initState();
    _localShowIndicia = component.showIndicia ?? false;
    _localIsFullPage = component.isFullPage ?? (component.fanzineData['is5x8'] == true);
  }

  @override
  void didUpdateComponent(FanzineThumbnailCard oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (component.showIndicia != null && component.showIndicia != oldComponent.showIndicia) {
      _localShowIndicia = component.showIndicia!;
    }
    if (component.isFullPage != null && component.isFullPage != oldComponent.isFullPage) {
      _localIsFullPage = component.isFullPage!;
    } else if (component.fanzineData['is5x8'] != oldComponent.fanzineData['is5x8']) {
      _localIsFullPage = component.fanzineData['is5x8'] == true;
    }
  }

  @override
  Component build(BuildContext context) {
    final String fanzineId = component.fanzineData['id']?.toString() ?? '';
    final String title = component.fanzineData['title']?.toString() ??
        component.fanzineData['fileName']?.toString() ??
        (component.cardType == 'image' ? 'untitled image' : 'Untitled Fanzine');
    final String? resolvedHref = component.targetHref;
    final String indicia = component.fanzineData['masterIndicia']?.toString() ??
        component.fanzineData['indicia']?.toString() ??
        '';
    String coverUrl = component.customCoverUrl ??
        component.fanzineData['gridCoverImage']?.toString() ??
        component.fanzineData['gridUrl']?.toString() ??
        component.fanzineData['coverUrl']?.toString() ??
        component.fanzineData['imageUrl']?.toString() ??
        component.fanzineData['fileUrl']?.toString() ??
        '';

    if (coverUrl.isEmpty && component.fanzineData['sourceFile'] != null) {
      coverUrl = 'https://placehold.co/450x720/png?text=Archival+Ingest';
    }

    final String typeTitle = component.cardType?.toLowerCase() ??
        (component.fanzineData['type'] == 'image' ? 'image' : 'fanzine');

    final bool hasIndiciaOption = component.onToggleShowIndicia != null;
    final bool hasFullPageOption = component.onToggleFullPage != null || component.onUseAsFullPage != null;
    final bool hasDeleteOption = component.onDelete != null;

    final thumbnailBox = div(
      attributes: const {
        'style':
        'aspect-ratio: 5 / 8; background-color: #F1B255; width: 100%; display: flex; align-items: center; justify-content: center; overflow: hidden; border-radius: 0px;',
      },
      [
        if (coverUrl.isNotEmpty)
          img(
            src: coverUrl,
            attributes: const {
              'style':
              'width: 100%; height: 100%; object-fit: contain; display: block; border-radius: 0px;',
            },
          )
        else
          span(
            [
              Component.text(
                component.cardType == 'image' ? 'image' : 'menu_book',
              )
            ],
            classes: 'material-symbols-outlined',
            attributes: const {
              'style': 'font-size: 40px; color: rgba(0, 0, 0, 0.25);',
            },
          ),
      ],
    );

    final Component row1Widget;
    if (resolvedHref != null && resolvedHref != '#' && resolvedHref.isNotEmpty) {
      row1Widget = a(
        href: resolvedHref,
        attributes: const {
          'style':
          'display: block; width: 100%; text-decoration: none; cursor: pointer; border-radius: 0px; overflow: hidden; border: 1px solid #ddd; box-shadow: none;',
        },
        [thumbnailBox],
      );
    } else {
      row1Widget = div(
        attributes: {
          'style':
          'display: block; width: 100%; border-radius: 0px; overflow: hidden; border: 1px solid #ddd; box-shadow: none; ${component.onCardTap != null ? "cursor: pointer;" : ""}',
        },
        events: {
          if (component.onCardTap != null)
            'click': (dynamic e) {
              try {
                e.preventDefault();
                e.stopPropagation();
              } catch (_) {}
              component.onCardTap!();
            }
        },
        [thumbnailBox],
      );
    }

    final Component titleWidget;
    if (resolvedHref != null && resolvedHref != '#' && resolvedHref.isNotEmpty) {
      titleWidget = a(
        href: resolvedHref,
        classes: 'hover:underline',
        attributes: const {
          'style':
          'font-size: 13px; font-weight: bold; color: black; text-decoration: none; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; flex: 1; text-align: left; margin-right: 8px;',
        },
        [Component.text(title)],
      );
    } else {
      titleWidget = span(
        attributes: const {
          'style':
          'font-size: 13px; font-weight: bold; color: black; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; flex: 1; text-align: left; margin-right: 8px;',
        },
        [Component.text(title)],
      );
    }

    return div(
      classes: 'transition-all',
      attributes: const {
        'style':
        'display: flex; flex-direction: column; width: 100%; box-sizing: border-box; position: relative; background: transparent; border-radius: 0px; box-shadow: none;',
      },
      [
        row1Widget,

        div(
          attributes: const {
            'style':
            'display: flex; flex-direction: row; justify-content: space-between; align-items: center; width: 100%; padding: 8px 4px 4px 4px; box-sizing: border-box; background: transparent;',
          },
          [
            titleWidget,

            div(
              attributes: const {
                'style':
                'position: relative; display: flex; align-items: center; flex-shrink: 0;',
              },
              [
                button(
                  attributes: const {
                    'type': 'button',
                    'style':
                    'background: transparent; border: none; cursor: pointer; padding: 4px; display: inline-flex; align-items: center; justify-content: center; border-radius: 0px; color: #4b5563;',
                  },
                  events: {
                    'click': (dynamic e) {
                      try {
                        e.preventDefault();
                        e.stopPropagation();
                      } catch (_) {}
                      if (component.onMenuTap != null) {
                        component.onMenuTap!();
                      } else {
                        setState(() => _isMenuOpen = !_isMenuOpen);
                      }
                    }
                  },
                  [
                    span(
                      classes: 'material-symbols-outlined',
                      attributes: const {'style': 'font-size: 20px;'},
                      [Component.text('more_vert')],
                    ),
                  ],
                ),
                if (_isMenuOpen) ...[
                  div(
                    attributes: const {
                      'style':
                      'position: fixed; top: 0; left: 0; right: 0; bottom: 0; z-index: 99;',
                    },
                    events: {
                      'click': (dynamic e) {
                        try {
                          e.preventDefault();
                          e.stopPropagation();
                        } catch (_) {}
                        setState(() => _isMenuOpen = false);
                      }
                    },
                    [],
                  ),
                  div(
                    classes: 'three-dot-dropdown-menu',
                    attributes: const {
                      'style':
                      'position: absolute; right: 0; bottom: calc(100% + 4px); background: white; border: 1px solid #e5e7eb; border-radius: 6px; box-shadow: 0 4px 12px rgba(0,0,0,0.15); z-index: 100; min-width: 160px; overflow: hidden;',
                    },
                    [
                      div(
                        attributes: const {
                          'style':
                          'padding: 8px 12px 6px 12px; font-size: 11px; font-weight: bold; color: #6b7280; text-transform: lowercase; letter-spacing: 0.5px; user-select: none;',
                        },
                        [Component.text(typeTitle)],
                      ),
                      div(
                        attributes: const {
                          'style':
                          'height: 1px; background-color: #f3f4f6; margin: 0 0 2px 0;',
                        },
                        [],
                      ),

                      if (hasIndiciaOption)
                        label(
                          attributes: const {
                            'style':
                            'display: flex; align-items: center; gap: 8px; padding: 8px 12px; cursor: pointer; user-select: none; font-size: 12px; color: #374151; font-weight: 500; transition: background 0.15s;',
                          },
                          events: {
                            'click': (dynamic e) {
                              try {
                                e.stopPropagation();
                              } catch (_) {}
                            }
                          },
                          [
                            input(
                              type: InputType.checkbox,
                              attributes: {
                                'style':
                                'cursor: pointer; width: 14px; height: 14px; margin: 0;',
                                if (_effectiveShowIndicia) 'checked': 'true',
                              },
                              events: {
                                'change': (dynamic e) {
                                  try {
                                    e.stopPropagation();
                                  } catch (_) {}
                                  final nextVal = !_effectiveShowIndicia;
                                  if (component.onToggleShowIndicia != null) {
                                    component.onToggleShowIndicia!(nextVal);
                                  } else {
                                    setState(() => _localShowIndicia = nextVal);
                                  }
                                }
                              },
                            ),
                            span([Component.text('show indicia')]),
                          ],
                        ),

                      if (hasFullPageOption)
                        label(
                          attributes: const {
                            'style':
                            'display: flex; align-items: center; gap: 8px; padding: 8px 12px; cursor: pointer; user-select: none; font-size: 12px; color: #374151; font-weight: 500; transition: background 0.15s;',
                          },
                          events: {
                            'click': (dynamic e) {
                              try {
                                e.stopPropagation();
                              } catch (_) {}
                            }
                          },
                          [
                            input(
                              type: InputType.checkbox,
                              attributes: {
                                'style':
                                'cursor: pointer; width: 14px; height: 14px; margin: 0;',
                                if (_effectiveIsFullPage) 'checked': 'true',
                              },
                              events: {
                                'change': (dynamic e) {
                                  try {
                                    e.stopPropagation();
                                  } catch (_) {}
                                  final nextVal = !_effectiveIsFullPage;
                                  setState(() {
                                    _localIsFullPage = nextVal;
                                    _isMenuOpen = false;
                                  });
                                  if (component.onToggleFullPage != null) {
                                    component.onToggleFullPage!(nextVal);
                                  } else if (component.onUseAsFullPage != null && nextVal) {
                                    component.onUseAsFullPage!();
                                  }
                                }
                              },
                            ),
                            span([Component.text('use as full page')]),
                          ],
                        ),

                      if (hasDeleteOption) ...[
                        if (hasIndiciaOption || hasFullPageOption)
                          div(
                            attributes: const {
                              'style':
                              'height: 1px; background-color: #f3f4f6; margin: 2px 0;',
                            },
                            [],
                          ),
                        button(
                          attributes: const {
                            'type': 'button',
                            'style':
                            'background: transparent; border: none; cursor: pointer; padding: 8px 12px; display: flex; align-items: center; width: 100%; text-align: left; gap: 6px; transition: background 0.15s;',
                          },
                          events: {
                            'click': (dynamic e) {
                              try {
                                e.preventDefault();
                                e.stopPropagation();
                              } catch (_) {}
                              setState(() => _isMenuOpen = false);
                              component.onDelete!(fanzineId, title);
                            }
                          },
                          [
                            span(
                              classes: 'material-symbols-outlined',
                              attributes: const {
                                'style': 'font-size: 16px; color: #ef4444;'
                              },
                              [Component.text('delete')],
                            ),
                            span(
                              attributes: const {
                                'style':
                                'font-size: 12px; color: #ef4444; font-weight: bold;'
                              },
                              [Component.text('delete')],
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),

        if (_effectiveShowIndicia)
          div(
            attributes: const {
              'style':
              'display: flex; flex-direction: column; width: 100%; padding: 4px; box-sizing: border-box; background: transparent;',
            },
            [
              p(
                [
                  Component.text(
                    indicia.isNotEmpty
                        ? indicia
                        : 'No indicia available for this issue.',
                  )
                ],
                attributes: const {
                  'style':
                  'margin: 0; font-size: 11px; line-height: 1.4; color: #4b5563; font-family: Georgia, serif; text-align: justify; word-break: break-word; white-space: pre-wrap;',
                },
              ),
            ],
          ),
      ],
    );
  }
}