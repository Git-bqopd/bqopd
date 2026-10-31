import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../../utils/web_utils.dart';
import 'publisher_schedule_view.dart';
import 'micro_spread_board.dart';

/// Renders the Week Dashboard takeover view in Column 3 of `/publisher`.
/// Includes the 72-page Micro-Spread Flatplan Board, Circulation summary,
/// This Week's Fanzines (24p Blueprint Templates), Hypothetical Recipient Simulator,
/// Blueprint Slot Rule Editor, and Create Blueprint Modal.
class PublisherWeekDashboard extends StatelessComponent {
  final PublishingWeek week;
  final List<ScheduledFanzine> scheduledFanzines;
  final List<CirculationRecipient> recipients;
  final List<Map<String, dynamic>> allProfiles;
  final Map<String, String> seriesOptionsMap;
  final String? activeBlueprintId;
  final String selectedPreviewUserKey;
  final String? activeCategoryFilter;

  // Create Fanzine Modal state
  final bool showCreateFanzineModal;
  final String formTitle;
  final String formSeries;
  final String formVolume;
  final String formIssue;
  final String formWholeNumber;
  final bool isCreatingFanzine;
  final String? formError;

  // Callbacks
  final void Function() onCloseWeekDashboard;
  final void Function(PublishingWeek week) onOpenCirculation;
  final void Function(String category) onToggleCategoryFilter;
  final void Function() onClearCategoryFilter;
  final void Function(ScheduledFanzine fanzine, int slotIndex) onSelectBlueprint;
  final void Function(String previewUserKey) onPreviewUserChanged;
  final void Function(
    ScheduledFanzine fanzine,
    int ruleIndex,
    BlueprintSlotRule updatedRule,
  ) onUpdateBlueprintRule;
  final void Function(ScheduledFanzine fanzine, int slotIndex)
      onResetBlueprintRules;
  final void Function() onOpenCreateFanzineModal;
  final void Function() onCloseCreateFanzineModal;
  final void Function(String val) onFormTitleChanged;
  final void Function(String val) onFormSeriesChanged;
  final void Function(String val) onFormVolumeChanged;
  final void Function(String val) onFormIssueChanged;
  final void Function(String val) onFormWholeNumberChanged;
  final void Function() onSubmitNewFanzineForm;
  final void Function(ScheduledFanzine fanzine) onToggleFanzineCancellation;
  final void Function(String fanzineId) onDeleteScheduledFanzine;

  const PublisherWeekDashboard({
    required this.week,
    required this.scheduledFanzines,
    required this.recipients,
    required this.allProfiles,
    required this.seriesOptionsMap,
    required this.activeBlueprintId,
    required this.selectedPreviewUserKey,
    required this.activeCategoryFilter,
    required this.showCreateFanzineModal,
    required this.formTitle,
    required this.formSeries,
    required this.formVolume,
    required this.formIssue,
    required this.formWholeNumber,
    required this.isCreatingFanzine,
    required this.formError,
    required this.onCloseWeekDashboard,
    required this.onOpenCirculation,
    required this.onToggleCategoryFilter,
    required this.onClearCategoryFilter,
    required this.onSelectBlueprint,
    required this.onPreviewUserChanged,
    required this.onUpdateBlueprintRule,
    required this.onResetBlueprintRules,
    required this.onOpenCreateFanzineModal,
    required this.onCloseCreateFanzineModal,
    required this.onFormTitleChanged,
    required this.onFormSeriesChanged,
    required this.onFormVolumeChanged,
    required this.onFormIssueChanged,
    required this.onFormWholeNumberChanged,
    required this.onSubmitNewFanzineForm,
    required this.onToggleFanzineCancellation,
    required this.onDeleteScheduledFanzine,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    final activeFanzines =
        scheduledFanzines.where((f) => !f.isCanceled).toList();

    final zine1 = activeFanzines.isNotEmpty ? activeFanzines[0] : null;
    final zine2 = activeFanzines.length > 1 ? activeFanzines[1] : null;
    final zine3 = activeFanzines.length > 2 ? activeFanzines[2] : null;

    final zine1Pages = generateZineBundlePages(
      1,
      customTitle: zine1?.title,
      rules: zine1?.slotRules,
    );
    final zine2Pages = generateZineBundlePages(
      2,
      customTitle: zine2?.title,
      rules: zine2?.slotRules,
    );
    final zine3Pages = generateZineBundlePages(
      3,
      customTitle: zine3?.title,
      rules: zine3?.slotRules,
    );

    final List<BundlePageDef> allBundlePages = [
      ...zine1Pages,
      ...zine2Pages,
      ...zine3Pages,
    ];

    return div(
      classes: 'flex-col gap-4 w-full',
      attributes: const {
        'style':
            'display: flex; flex-direction: column; gap: 14px; width: 100%; box-sizing: border-box;',
      },
      [
        // Top Navigation & Return Header
        div(
          classes:
              'flex-row items-center justify-between pb-2 border-b border-gray-300',
          attributes: const {
            'style':
                'display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #cbd5e1; padding-bottom: 8px;',
          },
          [
            button(
              classes: 'profile-btn',
              attributes: const {
                'type': 'button',
                'style':
                    'display: inline-flex; align-items: center; gap: 4px; padding: 4px 10px; font-size: 11px; '
                        'font-weight: bold; border: 1px solid #cbd5e1; background: white; border-radius: 14px; cursor: pointer;',
              },
              events: {
                'click': (e) => onCloseWeekDashboard(),
              },
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {'style': 'font-size: 15px; line-height: 1;'},
                  [Component.text('arrow_back')],
                ),
                Component.text('schedule'),
              ],
            ),
            div(
              attributes: const {
                'style': 'display: flex; align-items: center; gap: 8px;',
              },
              [
                span(
                  [
                    Component.text(
                      'WEEK ${week.weekNumber.toString().padLeft(2, '0')}',
                    ),
                  ],
                  attributes: const {
                    'style':
                        'font-size: 12px; font-weight: 900; letter-spacing: 0.5px; color: #6750A4;',
                  },
                ),
                span(
                  [Component.text('· ${week.startDateString}')],
                  attributes: const {
                    'style':
                        'font-size: 11px; color: #475569; font-weight: bold;',
                  },
                ),
                buildPublisherWeekStatusBadge(week),
              ],
            ),
          ],
        ),

        // 2-Column Responsive Dashboard Board
        div(
          classes: 'flex flex-row flex-wrap gap-4 items-start w-full',
          attributes: const {
            'style':
                'display: flex; flex-direction: row; flex-wrap: wrap; gap: 14px; align-items: flex-start; width: 100%; box-sizing: border-box;',
          },
          [
            // COLUMN 1: The 80px Micro-Spread 3-Zine Flatplan Board (Width ~284px)
            MicroSpreadBoard(
              zine1: zine1Pages,
              zine2: zine2Pages,
              zine3: zine3Pages,
              activeFanzines: activeFanzines,
              activeBlueprintId: activeBlueprintId,
              activeCategoryFilter: activeCategoryFilter,
              onToggleCategoryFilter: onToggleCategoryFilter,
              onSelectFanzine: onSelectBlueprint,
            ),

            // COLUMN 2: Circulation Section, Weekly Fanzines Manager, Blueprint Rules & Preview Simulator, Category Budget
            _buildDashboardRightColumn(allBundlePages),
          ],
        ),

        // Create Fanzine Modal Dialog
        if (showCreateFanzineModal) _buildCreateFanzineModal(),
      ],
    );
  }

  Component _buildDashboardRightColumn(List<BundlePageDef> allBundlePages) {
    final int recipientCount = recipients.length;
    ScheduledFanzine? selectedBlueprint;
    int selectedSlotIndex = 1;
    for (int i = 0; i < scheduledFanzines.length; i++) {
      if (scheduledFanzines[i].id == activeBlueprintId) {
        selectedBlueprint = scheduledFanzines[i];
        selectedSlotIndex = i + 1;
        break;
      }
    }
    if (selectedBlueprint == null && scheduledFanzines.isNotEmpty) {
      final firstActiveIdx =
          scheduledFanzines.indexWhere((f) => !f.isCanceled);
      if (firstActiveIdx != -1) {
        selectedBlueprint = scheduledFanzines[firstActiveIdx];
        selectedSlotIndex = firstActiveIdx + 1;
      }
    }

    return div(
      attributes: const {
        'style':
            'display: flex; flex-direction: column; gap: 12px; flex: 1; min-width: 280px; box-sizing: border-box;',
      },
      [
        // 1. CIRCULATION CARD
        div(
          attributes: const {
            'style':
                'background: white; border: 1px solid #cbd5e1; border-radius: 8px; padding: 14px 16px; '
                    'display: flex; flex-direction: column; justify-content: space-between; gap: 10px; '
                    'box-sizing: border-box; box-shadow: 0 1px 3px rgba(0,0,0,0.03);',
          },
          [
            div([
              div(
                attributes: const {
                  'style':
                      'display: flex; align-items: center; justify-content: space-between; margin-bottom: 4px;',
                },
                [
                  div(
                    attributes: const {
                      'style': 'display: flex; align-items: center; gap: 6px;',
                    },
                    [
                      span(
                        classes: 'material-symbols-outlined',
                        attributes: const {
                          'style': 'font-size: 16px; color: #6750A4;',
                        },
                        [Component.text('mark_email_read')],
                      ),
                      span(
                        [Component.text('CIRCULATION')],
                        attributes: const {
                          'style':
                              'font-size: 10px; font-weight: 900; color: #475569; letter-spacing: 0.5px; text-transform: uppercase;',
                        },
                      ),
                    ],
                  ),
                  span(
                    [Component.text('$recipientCount recipients queued')],
                    attributes: const {
                      'style':
                          'font-size: 11px; font-weight: bold; color: #1e293b;',
                    },
                  ),
                ],
              ),
              p(
                [
                  Component.text(
                    'Manage physical recipients for this issue. Each active recipient receives a personalized 72-page print bundle (3 fanzines × 24 pages).',
                  ),
                ],
                attributes: const {
                  'style':
                      'margin: 0; font-size: 11px; color: #64748b; line-height: 1.35;',
                },
              ),
            ]),
            button(
              classes: 'circulation-btn',
              attributes: const {
                'type': 'button',
                'style':
                    'padding: 7px 14px; font-size: 11px; font-weight: bold; '
                        'background: #f3f0fb; color: #6750A4; border: 1px solid #6750A4; '
                        'border-radius: 12px; cursor: pointer; display: inline-flex; '
                        'align-items: center; justify-content: center; gap: 6px; transition: all 0.15s ease;',
              },
              events: {
                'click': (e) => onOpenCirculation(week),
              },
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {'style': 'font-size: 14px; line-height: 1;'},
                  [Component.text('group')],
                ),
                Component.text(
                  recipientCount > 0
                      ? 'manage circulation ($recipientCount)'
                      : 'manage circulation',
                ),
              ],
            ),
          ],
        ),

        // 2. THIS WEEK'S FANZINES CARD (24p BLUEPRINT TEMPLATES & IN-PUBLISHER PREVIEW)
        _buildWeeklyFanzinesCard(),

        // 3. BLUEPRINT HYPOTHETICAL PREVIEW & SLOT RULES EDITOR
        if (selectedBlueprint != null)
          _buildBlueprintSimulatorAndRulesCard(
            selectedBlueprint,
            selectedSlotIndex,
          ),

        // 4. CATEGORY ALLOCATION BUDGET CARD
        _buildCategoryAllocationCard(allBundlePages),
      ],
    );
  }

  Component _buildWeeklyFanzinesCard() {
    final activeCount = scheduledFanzines.where((f) => !f.isCanceled).length;

    return div(
      attributes: const {
        'style':
            'background: white; border: 1px solid #cbd5e1; border-radius: 8px; padding: 14px 16px; '
                'display: flex; flex-direction: column; gap: 10px; box-sizing: border-box; box-shadow: 0 1px 3px rgba(0,0,0,0.03);',
      },
      [
        div(
          attributes: const {
            'style':
                'display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #f1f5f9; padding-bottom: 6px;',
          },
          [
            div(
              attributes: const {
                'style': 'display: flex; align-items: center; gap: 6px;',
              },
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {'style': 'font-size: 16px; color: #6750A4;'},
                  [Component.text('auto_stories')],
                ),
                span(
                  [Component.text("THIS WEEK'S FANZINES ($activeCount of 3)")],
                  attributes: const {
                    'style':
                        'font-size: 10px; font-weight: 900; color: #475569; letter-spacing: 0.5px; text-transform: uppercase;',
                  },
                ),
              ],
            ),
            button(
              classes: 'profile-btn',
              attributes: const {
                'type': 'button',
                'style':
                    'border: 1px solid #6750A4; background: #f3f0fb; color: #6750A4; '
                        'padding: 3px 10px; font-size: 10px; font-weight: bold; border-radius: 12px; cursor: pointer; '
                        'display: inline-flex; align-items: center; gap: 4px;',
              },
              events: {
                'click': (e) => onOpenCreateFanzineModal(),
              },
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {'style': 'font-size: 13px;'},
                  [Component.text('add')],
                ),
                Component.text('create blueprint'),
              ],
            ),
          ],
        ),

        p(
          [
            Component.text(
              '3 fanzine blueprints × 24 pages = 72-page personalized print bundle. Click any blueprint below to preview its hypothetical 24-page mix in Columns 1 & 2.',
            ),
          ],
          attributes: const {
            'style':
                'margin: 0; font-size: 11px; color: #64748b; line-height: 1.35;',
          },
        ),

        // List of Scheduled Fanzines for this Week
        if (scheduledFanzines.isEmpty)
          div(
            attributes: const {
              'style':
                  'background: #f8fafc; border: 1px dashed #cbd5e1; border-radius: 6px; padding: 18px 12px; '
                      'display: flex; flex-direction: column; align-items: center; justify-content: center; text-align: center; gap: 4px;',
            },
            [
              span(
                classes: 'material-symbols-outlined',
                attributes: const {'style': 'font-size: 24px; color: #94a3b8;'},
                [Component.text('menu_book')],
              ),
              span(
                [Component.text('No fanzine blueprints scheduled yet for this week.')],
                attributes: const {
                  'style':
                      'font-size: 11px; color: #64748b; font-weight: bold;',
                },
              ),
              span(
                [
                  Component.text(
                    'Click "create blueprint" to add a 24-page dynamic publication.',
                  ),
                ],
                attributes: const {'style': 'font-size: 10px; color: #94a3b8;'},
              ),
            ],
          )
        else
          div(
            attributes: const {
              'style':
                  'display: flex; flex-direction: column; gap: 8px; width: 100%; box-sizing: border-box;',
            },
            [
              for (int i = 0; i < scheduledFanzines.length; i++)
                _buildScheduledFanzineRow(scheduledFanzines[i], i + 1),
            ],
          ),
      ],
    );
  }

  Component _buildScheduledFanzineRow(ScheduledFanzine fanzine, int slotIndex) {
    final bool isCanceled = fanzine.isCanceled;
    final bool isSelected = fanzine.id == activeBlueprintId;
    final String seriesLabel =
        seriesOptionsMap[fanzine.series] ?? fanzine.series;

    return div(
      attributes: {
        'style':
            'background: ${isCanceled ? "#f8fafc" : (isSelected ? "#faf7ff" : "#ffffff")}; '
                'border: ${isSelected ? "2px solid #6750A4" : (isCanceled ? "1px solid #e2e8f0" : "1px solid #cbd5e1")}; '
                'border-radius: 6px; padding: 10px 12px; display: flex; flex-direction: column; gap: 6px; '
                'opacity: ${isCanceled ? "0.65" : "1.0"}; box-sizing: border-box; width: 100%; '
                'cursor: ${isCanceled ? "default" : "pointer"}; transition: all 0.15s ease;',
      },
      events: {
        if (!isCanceled)
          'click': (e) => onSelectBlueprint(fanzine, slotIndex),
      },
      [
        // Top Row: Title, Slot, and Actions
        div(
          attributes: const {
            'style':
                'display: flex; justify-content: space-between; align-items: flex-start; gap: 8px;',
          },
          [
            div(
              attributes: const {
                'style':
                    'display: flex; align-items: baseline; gap: 6px; overflow: hidden;',
              },
              [
                span(
                  [Component.text('ZINE #$slotIndex')],
                  attributes: const {
                    'style':
                        'font-family: Anton, sans-serif; font-size: 11px; color: #6750A4; letter-spacing: 0.5px;',
                  },
                ),
                span(
                  [Component.text(fanzine.title)],
                  attributes: {
                    'style':
                        'font-size: 12px; font-weight: bold; color: ${isCanceled ? "#64748b" : "#1e293b"}; '
                            '${isCanceled ? "text-decoration: line-through;" : ""} '
                            'white-space: nowrap; overflow: hidden; text-overflow: ellipsis;',
                  },
                ),
              ],
            ),

            // Top action buttons: Preview in Publisher (no longer redirects to /maker!) & Cancel & Delete
            div(
              attributes: const {
                'style':
                    'display: flex; align-items: center; gap: 4px; flex-shrink: 0;',
              },
              [
                if (!isCanceled)
                  button(
                    attributes: {
                      'type': 'button',
                      'title':
                          'Load hypothetical 24-page blueprint into Columns 1 & 2',
                      'style':
                          'padding: 2px 8px; font-size: 9px; font-weight: bold; '
                              'color: ${isSelected ? "white" : "#6750A4"}; '
                              'border: 1px solid #6750A4; '
                              'background: ${isSelected ? "#6750A4" : "#f3f0fb"}; '
                              'border-radius: 4px; cursor: pointer; '
                              'display: inline-flex; align-items: center; gap: 3px;',
                    },
                    events: {
                      'click': (dynamic e) {
                        try {
                          e.stopPropagation();
                        } catch (_) {}
                        onSelectBlueprint(fanzine, slotIndex);
                      },
                    },
                    [
                      span(
                        classes: 'material-symbols-outlined',
                        attributes: const {'style': 'font-size: 12px;'},
                        [
                          Component.text(
                            isSelected ? 'visibility' : 'preview',
                          ),
                        ],
                      ),
                      Component.text(
                        isSelected ? 'previewing' : 'preview blueprint',
                      ),
                    ],
                  ),
                button(
                  attributes: {
                    'type': 'button',
                    'title': isCanceled
                        ? 'Restore to this week'
                        : 'Cancel for this week',
                    'style':
                        'padding: 2px 7px; font-size: 9px; font-weight: bold; border-radius: 4px; cursor: pointer; '
                            'border: 1px solid ${isCanceled ? "#16a34a" : "#ef4444"}; '
                            'background: ${isCanceled ? "#ecfdf5" : "white"}; '
                            'color: ${isCanceled ? "#16a34a" : "#ef4444"};',
                  },
                  events: {
                    'click': (dynamic e) {
                      try {
                        e.stopPropagation();
                      } catch (_) {}
                      onToggleFanzineCancellation(fanzine);
                    },
                  },
                  [Component.text(isCanceled ? 'restore' : 'cancel this week')],
                ),
                button(
                  attributes: const {
                    'type': 'button',
                    'title': 'Remove permanently from schedule',
                    'style':
                        'border: none; background: transparent; cursor: pointer; color: #94a3b8; padding: 2px;',
                  },
                  events: {
                    'click': (dynamic e) {
                      try {
                        e.stopPropagation();
                      } catch (_) {}
                      onDeleteScheduledFanzine(fanzine.id);
                    },
                  },
                  [
                    span(
                      classes: 'material-symbols-outlined',
                      attributes: const {
                        'style': 'font-size: 15px; color: #ef4444;',
                      },
                      [Component.text('delete')],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),

        // Bottom Row: Metadata Badges (vol, num, whole num, series, 24p blueprint)
        div(
          attributes: const {
            'style':
                'display: flex; align-items: center; gap: 6px; flex-wrap: wrap;',
          },
          [
            if (fanzine.volume.isNotEmpty)
              span(
                [Component.text('vol. ${fanzine.volume}')],
                attributes: const {
                  'style':
                      'font-size: 9px; font-family: monospace; font-weight: bold; color: #475569; background: #f1f5f9; padding: 1px 4px; border-radius: 3px;',
                },
              ),
            if (fanzine.issue.isNotEmpty)
              span(
                [Component.text('num. ${fanzine.issue}')],
                attributes: const {
                  'style':
                      'font-size: 9px; font-family: monospace; font-weight: bold; color: #475569; background: #f1f5f9; padding: 1px 4px; border-radius: 3px;',
                },
              ),
            if (fanzine.wholeNumber.isNotEmpty)
              span(
                [Component.text('whole num. ${fanzine.wholeNumber}')],
                attributes: const {
                  'style':
                      'font-size: 9px; font-family: monospace; font-weight: bold; color: #475569; background: #f1f5f9; padding: 1px 4px; border-radius: 3px;',
                },
              ),
            if (seriesLabel.isNotEmpty &&
                seriesLabel != 'no series / independent')
              span(
                [Component.text(seriesLabel)],
                attributes: const {
                  'style':
                      'font-size: 9px; font-weight: bold; color: #6750A4; background: #f3f0fb; padding: 1px 5px; border-radius: 3px; border: 1px solid #e9d5ff;',
                },
              ),
            span(
              [Component.text('${fanzine.pageCount}p blueprint')],
              attributes: const {
                'style':
                    'font-size: 9px; font-weight: bold; color: #16a34a; background: #ecfdf5; padding: 1px 5px; border-radius: 3px; border: 1px solid #bbf7d0;',
              },
            ),
            if (isCanceled)
              span(
                [Component.text('CANCELED')],
                attributes: const {
                  'style':
                      'font-size: 9px; font-weight: 900; color: #ef4444; background: #fef2f2; padding: 1px 5px; border-radius: 3px; border: 1px solid #fecaca; letter-spacing: 0.4px;',
                },
              ),
          ],
        ),
      ],
    );
  }

  Component _buildBlueprintSimulatorAndRulesCard(
    ScheduledFanzine fanzine,
    int slotIndex,
  ) {
    final rules = fanzine.slotRules.isNotEmpty
        ? fanzine.slotRules
        : defaultBlueprintRulesForSlot(slotIndex);

    // Filter interior editable rules (pages 3..23)
    final editableIndices = <int>[];
    for (int i = 0; i < rules.length; i++) {
      if (rules[i].startPage >= 3 && rules[i].endPage <= 23) {
        editableIndices.add(i);
      }
    }

    return div(
      attributes: const {
        'style':
            'background: white; border: 1px solid #6750A4; border-radius: 8px; padding: 14px 16px; '
                'display: flex; flex-direction: column; gap: 12px; box-sizing: border-box; '
                'box-shadow: 0 2px 8px rgba(103, 80, 164, 0.08);',
      },
      [
        // Header
        div(
          attributes: const {
            'style':
                'display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #f1f5f9; padding-bottom: 6px;',
          },
          [
            div(
              attributes: const {
                'style': 'display: flex; align-items: center; gap: 6px;',
              },
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {'style': 'font-size: 16px; color: #6750A4;'},
                  [Component.text('tune')],
                ),
                span(
                  [
                    Component.text(
                      'BLUEPRINT RULES · ZINE #$slotIndex (${fanzine.title})',
                    ),
                  ],
                  attributes: const {
                    'style':
                        'font-size: 10px; font-weight: 900; color: #6750A4; letter-spacing: 0.5px; text-transform: uppercase;',
                  },
                ),
              ],
            ),
            button(
              attributes: const {
                'type': 'button',
                'style':
                    'border: none; background: transparent; font-size: 10px; font-weight: bold; '
                        'color: #64748b; cursor: pointer; text-decoration: underline; padding: 0;',
              },
              events: {
                'click': (e) => onResetBlueprintRules(fanzine, slotIndex),
              },
              [Component.text('reset defaults')],
            ),
          ],
        ),

        // "Preview as Recipient / User" selector
        div(
          attributes: const {
            'style':
                'background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; padding: 10px 12px; '
                    'display: flex; flex-direction: column; gap: 6px;',
          },
          [
            div(
              attributes: const {
                'style':
                    'display: flex; justify-content: space-between; align-items: center;',
              },
              [
                span(
                  [Component.text('PREVIEW HYPOTHETICAL MIX AS RECIPIENT:')],
                  attributes: const {
                    'style':
                        'font-size: 10px; font-weight: 900; color: #1e293b; letter-spacing: 0.4px;',
                  },
                ),
                span(
                  [Component.text('Updates Columns 1 & 2 live')],
                  attributes: const {
                    'style':
                        'font-size: 9px; font-weight: bold; color: #16a34a;',
                  },
                ),
              ],
            ),
            select(
              attributes: const {
                'style':
                    'width: 100%; padding: 6px 8px; border: 1px solid #cbd5e1; border-radius: 6px; '
                        'font-size: 11px; font-weight: bold; color: #1e293b; background: white; cursor: pointer;',
              },
              events: {
                'change': (e) => onPreviewUserChanged(getInputValue(e)),
              },
              [
                option(
                  attributes: {
                    'value': 'persona_terminal',
                    if (selectedPreviewUserKey == 'persona_terminal')
                      'selected': 'true',
                  },
                  [
                    Component.text(
                      '⚡ Persona: Active Terminal Player (Austin, TX · #scifi, #zine)',
                    ),
                  ],
                ),
                option(
                  attributes: {
                    'value': 'persona_standard',
                    if (selectedPreviewUserKey == 'persona_standard')
                      'selected': 'true',
                  },
                  [
                    Component.text(
                      '📬 Persona: Standard Reader — No Terminal (Seattle, WA · #comics)',
                    ),
                  ],
                ),
                if (recipients.isNotEmpty)
                  for (final r in recipients)
                    option(
                      attributes: {
                        'value': 'recipient:${r.id}',
                        if (selectedPreviewUserKey == 'recipient:${r.id}')
                          'selected': 'true',
                      },
                      [
                        Component.text(
                          '📦 Queued Recipient: ${r.displayName} (${r.city.isNotEmpty ? "${r.city}, ${r.state}" : "Local Route"})',
                        ),
                      ],
                    ),
                if (allProfiles.isNotEmpty)
                  for (final p in allProfiles.take(15))
                    option(
                      attributes: {
                        'value': 'profile:${p['uid'] ?? p['id']}',
                        if (selectedPreviewUserKey ==
                            'profile:${p['uid'] ?? p['id']}')
                          'selected': 'true',
                      },
                      [
                        Component.text(
                          '👤 User: ${p['displayName'] ?? p['username'] ?? 'User'} ${p['city'] != null ? "(${p['city']})" : ""}',
                        ),
                      ],
                    ),
              ],
            ),
            span(
              [
                Component.text(
                  'Conditional slots (e.g., Combat Terminal Turn Pages) automatically fall back to Global UGC if the recipient does not play the Terminal game. 2-page Maker spreads auto-backfill any 1-page gap with a Sponsor Ad.',
                ),
              ],
              attributes: const {
                'style': 'font-size: 10px; color: #64748b; line-height: 1.35;',
              },
            ),
          ],
        ),

        // Interior Slot Rules List
        div(
          attributes: const {
            'style':
                'display: flex; flex-direction: column; gap: 6px; width: 100%;',
          },
          [
            span(
              [Component.text('PAGE RANGE SLOT RULES (PAGES 3–23):')],
              attributes: const {
                'style':
                    'font-size: 9px; font-weight: 900; color: #475569; letter-spacing: 0.4px;',
              },
            ),
            for (final idx in editableIndices)
              _buildSlotRuleEditorRow(fanzine, idx, rules[idx]),
          ],
        ),
      ],
    );
  }

  Component _buildSlotRuleEditorRow(
    ScheduledFanzine fanzine,
    int ruleIndex,
    BlueprintSlotRule rule,
  ) {
    final selectableSources = [
      BlueprintSlotSource.globalUgc,
      BlueprintSlotSource.localUgc,
      BlueprintSlotSource.terminalTurn,
      BlueprintSlotSource.sponsorAd,
      BlueprintSlotSource.fillerArt,
    ];

    final color =
        publisherCategoryColors[rule.primarySource.categoryKey] ?? '#6750A4';

    return div(
      attributes: const {
        'style':
            'display: flex; flex-direction: column; gap: 4px; padding: 8px 10px; '
                'background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px;',
      },
      [
        div(
          attributes: const {
            'style':
                'display: flex; align-items: center; justify-content: space-between; gap: 8px;',
          },
          [
            div(
              attributes: const {
                'style': 'display: flex; align-items: center; gap: 6px;',
              },
              [
                span(
                  attributes: {
                    'style':
                        'width: 10px; height: 10px; border-radius: 2px; background: $color; display: inline-block;',
                  },
                  [],
                ),
                span(
                  [
                    Component.text(rule.rangeLabel),
                  ],
                  attributes: const {
                    'style':
                        'font-size: 11px; font-family: monospace; font-weight: 900; color: #0f172a;',
                  },
                ),
              ],
            ),
            select(
              attributes: const {
                'style':
                    'flex: 1; max-width: 210px; padding: 4px 6px; border: 1px solid #cbd5e1; '
                        'border-radius: 4px; font-size: 10px; font-weight: bold; background: white; cursor: pointer;',
              },
              events: {
                'change': (e) {
                  final nextSource =
                      BlueprintSlotSourceX.fromString(getInputValue(e));
                  final updated = BlueprintSlotRule(
                    startPage: rule.startPage,
                    endPage: rule.endPage,
                    primarySource: nextSource,
                    condition: nextSource == BlueprintSlotSource.terminalTurn
                        ? 'plays_terminal'
                        : (nextSource == BlueprintSlotSource.localUgc
                              ? 'has_local_pool'
                              : null),
                    fallbackSource: BlueprintSlotSource.globalUgc,
                  );
                  onUpdateBlueprintRule(fanzine, ruleIndex, updated);
                },
              },
              [
                for (final src in selectableSources)
                  option(
                    attributes: {
                      'value': src.id,
                      if (rule.primarySource == src) 'selected': 'true',
                    },
                    [Component.text(src.label)],
                  ),
              ],
            ),
          ],
        ),
        if (rule.condition != null)
          div(
            attributes: const {
              'style':
                  'display: flex; align-items: center; justify-content: flex-end; gap: 4px;',
            },
            [
              span(
                [
                  Component.text(
                    '↳ Conditional fallback: ${rule.fallbackSource.label}',
                  ),
                ],
                attributes: const {
                  'style':
                      'font-size: 9px; font-weight: bold; color: #EC4899; font-style: italic;',
                },
              ),
            ],
          ),
      ],
    );
  }

  Component _buildCreateFanzineModal() {
    return div(
      classes: 'global-modal-overlay',
      attributes: const {
        'style':
            'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.6); '
                'z-index: 10000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(4px);',
      },
      [
        div(
          classes: 'white-sticker',
          attributes: const {
            'style':
                'width: 90%; max-width: 440px; background: white; border-radius: 10px; padding: 20px; '
                    'box-sizing: border-box; display: flex; flex-direction: column; gap: 12px; max-height: 90vh; overflow-y: auto;',
          },
          [
            div(
              attributes: const {
                'style':
                    'display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #e2e8f0; padding-bottom: 8px;',
              },
              [
                div([
                  h3(
                    [Component.text('Create 24-Page Blueprint Template')],
                    attributes: const {
                      'style':
                          'margin: 0; font-size: 14px; font-weight: bold; color: #1e293b;',
                    },
                  ),
                  span(
                    [
                      Component.text(
                        'Week ${week.weekNumber.toString().padLeft(2, "0")} · Dynamic 24-page blueprint',
                      ),
                    ],
                    attributes: const {
                      'style':
                          'font-size: 11px; color: #64748b; font-weight: 500;',
                    },
                  ),
                ]),
                button(
                  attributes: const {
                    'style':
                        'border: none; background: transparent; cursor: pointer; color: #888; padding: 2px;',
                  },
                  events: {'click': (e) => onCloseCreateFanzineModal()},
                  [
                    span(
                      classes: 'material-symbols-outlined',
                      attributes: const {'style': 'font-size: 18px;'},
                      [Component.text('close')],
                    ),
                  ],
                ),
              ],
            ),

            // Title Field
            div([
              span(
                [Component.text('Blueprint Title *')],
                attributes: const {
                  'style':
                      'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;',
                },
              ),
              input(
                attributes: {
                  'type': 'text',
                  'placeholder': 'e.g. Radius Issue #12',
                  'value': formTitle,
                  'style':
                      'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                },
                events: {
                  'input': (e) => onFormTitleChanged(getInputValue(e)),
                },
              ),
            ]),

            // Series Dropdown Field
            div([
              span(
                [Component.text('part of a series:')],
                attributes: const {
                  'style':
                      'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;',
                },
              ),
              select(
                attributes: const {
                  'style':
                      'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; '
                          'font-size: 12px; background-color: white; outline: none; cursor: pointer; box-sizing: border-box; margin: 0;',
                },
                events: {
                  'change': (e) => onFormSeriesChanged(getInputValue(e)),
                },
                [
                  for (var entry in seriesOptionsMap.entries)
                    option(
                      attributes: {
                        'value': entry.key,
                        if (formSeries == entry.key) 'selected': 'true',
                      },
                      [Component.text(entry.value)],
                    ),
                ],
              ),
            ]),

            // vol., num., whole num. Row
            div(
              attributes: const {
                'style': 'display: flex; gap: 8px; width: 100%;',
              },
              [
                div(
                  attributes: const {'style': 'flex: 1;'},
                  [
                    span(
                      [Component.text('vol.')],
                      attributes: const {
                        'style':
                            'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;',
                      },
                    ),
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'vol.',
                        'value': formVolume,
                        'style':
                            'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                      },
                      events: {
                        'input': (e) => onFormVolumeChanged(getInputValue(e)),
                      },
                    ),
                  ],
                ),
                div(
                  attributes: const {'style': 'flex: 1;'},
                  [
                    span(
                      [Component.text('num.')],
                      attributes: const {
                        'style':
                            'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;',
                      },
                    ),
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'num.',
                        'value': formIssue,
                        'style':
                            'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                      },
                      events: {
                        'input': (e) => onFormIssueChanged(getInputValue(e)),
                      },
                    ),
                  ],
                ),
                div(
                  attributes: const {'style': 'flex: 1;'},
                  [
                    span(
                      [Component.text('whole num.')],
                      attributes: const {
                        'style':
                            'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;',
                      },
                    ),
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'whole num.',
                        'value': formWholeNumber,
                        'style':
                            'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                      },
                      events: {
                        'input': (e) =>
                            onFormWholeNumberChanged(getInputValue(e)),
                      },
                    ),
                  ],
                ),
              ],
            ),

            // Format Info Callout
            div(
              attributes: const {
                'style':
                    'background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; padding: 10px 12px; font-size: 11px; color: #64748b; line-height: 1.4;',
              },
              [
                span(
                  [Component.text('Blueprint Format: ')],
                  attributes: const {
                    'style': 'font-weight: bold; color: #1e293b;',
                  },
                ),
                Component.text(
                  'Creates a 24-page dynamic Blueprint template with customizable UGC, Local Carrier Route, Combat Terminal, and Sponsor Ad slot rules, and loads the hypothetical preview directly in /publisher.',
                ),
              ],
            ),

            if (formError != null)
              span(
                [Component.text(formError!)],
                attributes: const {
                  'style':
                      'font-size: 11px; font-weight: bold; color: #ef4444;',
                },
              ),

            div(
              attributes: const {
                'style':
                    'display: flex; justify-content: flex-end; gap: 8px; margin-top: 8px; border-top: 1px solid #f1f5f9; padding-top: 10px;',
              },
              [
                button(
                  classes: 'profile-btn',
                  attributes: const {
                    'type': 'button',
                    'style':
                        'padding: 6px 14px; font-size: 11px; font-weight: bold; border: 1px solid #ccc; background: white; cursor: pointer; border-radius: 6px;',
                  },
                  events: {'click': (e) => onCloseCreateFanzineModal()},
                  [Component.text('cancel')],
                ),
                button(
                  classes: 'btn-primary nav-pill mb-0',
                  attributes: {
                    'type': 'button',
                    'style':
                        'padding: 6px 16px; font-size: 11px; font-weight: bold; background-color: #6750A4; color: white; border: none; border-radius: 16px; cursor: pointer;',
                    if (isCreatingFanzine) 'disabled': 'true',
                  },
                  events: {'click': (e) => onSubmitNewFanzineForm()},
                  [
                    Component.text(
                      isCreatingFanzine ? 'creating...' : 'create blueprint',
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Component _buildCategoryAllocationCard(List<BundlePageDef> allBundlePages) {
    int countCat(String c) =>
        allBundlePages.where((p) => p.category == c).length;
    String fmtBadge(String c) {
      final n = countCat(c);
      final pct = ((n / 72.0) * 100).round();
      return '${n}p ($pct%)';
    }

    return div(
      attributes: const {
        'style':
            'background: white; border: 1px solid #cbd5e1; border-radius: 8px; padding: 14px 16px; '
                'display: flex; flex-direction: column; gap: 10px; box-sizing: border-box; box-shadow: 0 1px 3px rgba(0,0,0,0.03);',
      },
      [
        div(
          attributes: const {
            'style':
                'display: flex; justify-content: space-between; align-items: center; '
                    'border-bottom: 1px solid #f1f5f9; padding-bottom: 6px;',
          },
          [
            span(
              [Component.text('CATEGORY ALLOCATION (72P BUNDLE)')],
              attributes: const {
                'style':
                    'font-size: 10px; font-weight: 900; color: #475569; letter-spacing: 0.5px; text-transform: uppercase;',
              },
            ),
            if (activeCategoryFilter != null)
              button(
                attributes: const {
                  'type': 'button',
                  'style':
                      'border: none; background: transparent; font-size: 10px; font-weight: bold; '
                          'color: #6750A4; cursor: pointer; text-decoration: underline; padding: 0;',
                },
                events: {
                  'click': (e) => onClearCategoryFilter(),
                },
                [Component.text('reset highlight')],
              ),
          ],
        ),
        div(
          attributes: const {
            'style':
                'display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 6px; width: 100%; box-sizing: border-box;',
          },
          [
            _buildCategoryFilterChip(
              'letters',
              'Global & Local UGC',
              fmtBadge('letters'),
              '#10B981',
              '#ecfdf5',
              '#059669',
            ),
            _buildCategoryFilterChip(
              'terminal',
              'Combat Terminal',
              fmtBadge('terminal'),
              '#EC4899',
              '#fdf2f8',
              '#db2777',
            ),
            _buildCategoryFilterChip(
              'articles',
              'Articles / Essays',
              fmtBadge('articles'),
              '#3B82F6',
              '#eff6ff',
              '#2563eb',
            ),
            _buildCategoryFilterChip(
              'ad',
              'Advertisements',
              fmtBadge('ad'),
              '#F59E0B',
              '#fef3c7',
              '#d97706',
            ),
            _buildCategoryFilterChip(
              'cover',
              'Covers & Indicia',
              fmtBadge('cover'),
              '#6750A4',
              '#f3f0fb',
              '#6750A4',
            ),
            _buildCategoryFilterChip(
              'filler',
              'Fillers & Art',
              fmtBadge('filler'),
              '#94A3B8',
              '#f8fafc',
              '#64748b',
            ),
          ],
        ),
      ],
    );
  }

  Component _buildCategoryFilterChip(
    String cat,
    String label,
    String badge,
    String swatchColor,
    String bgColor,
    String borderColor,
  ) {
    final bool isSelected = activeCategoryFilter == cat;
    return div(
      attributes: {
        'style':
            'cursor: pointer; display: flex; align-items: center; justify-content: space-between; '
                'padding: 6px 8px; border-radius: 6px; border: 1px solid ${isSelected ? "#000000" : borderColor}; '
                'background-color: ${isSelected ? "#f1f5f9" : bgColor}; transition: all 0.15s ease;',
      },
      events: {
        'click': (e) => onToggleCategoryFilter(cat),
      },
      [
        div(
          attributes: const {
            'style': 'display: flex; align-items: center; gap: 6px;',
          },
          [
            span(
              attributes: {
                'style':
                    'width: 12px; height: 10px; border-radius: 2px; background-color: $swatchColor; '
                        'display: inline-block; flex-shrink: 0;',
              },
              [],
            ),
            span(
              [Component.text(label)],
              attributes: const {
                'style': 'font-size: 11px; font-weight: bold; color: #1e293b;',
              },
            ),
          ],
        ),
        span(
          [Component.text(badge)],
          attributes: const {
            'style':
                'font-size: 10px; font-family: monospace; font-weight: 900; color: #0f172a;',
          },
        ),
      ],
    );
  }
}
