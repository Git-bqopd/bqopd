import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/icon_utils.dart';
import '../social_toolbar.dart';

/// Presentation mode toggle for inspecting mobile inline drawer targets
/// versus desktop third column panel destinations.
enum MatrixLayoutMode {
  bonusRow,
  bonusColumn,
}

/// Interactive visual inspection and configuration matrix for social buttons.
/// Accurately renders each tool scope (FanzineReaderPage, FanzineCurator, FanzineEditor)
/// matching the exact live app toolbar visibility and panel destination rules.
class SettingsSocialButtonsPage extends StatefulComponent {
  final String targetUserId;
  final UserAccount? viewerAccount;

  const SettingsSocialButtonsPage({
    required this.targetUserId,
    this.viewerAccount,
    super.key,
  });

  @override
  State<SettingsSocialButtonsPage> createState() => _SettingsSocialButtonsPageState();
}

class _SettingsSocialButtonsPageState extends State<SettingsSocialButtonsPage> {
  BonusRowType? _previewReaderBonusRow;
  BonusRowType? _previewCuratorBonusRow;
  BonusRowType? _previewEditorBonusRow;

  // Layout mode switcher: inspect Mobile Drawer vs Desktop Column
  MatrixLayoutMode _layoutMode = MatrixLayoutMode.bonusRow;

  // Context simulation toggles for preview inspection
  bool _previewHasYoutube = false;
  bool _previewIsGame = false;
  bool _previewIsIndicia = false;
  bool _previewCanOpenGrid = true;

  // Strict canonical order of columns across the dashboard matrix
  static const List<String> _orderedColumnKeys = [
    'position',
    'reader',
    'maker',
    'curator',
    'guests',
  ];

  static const Map<String, String> _matrixColumnLabels = {
    'position': 'position',
    'reader': 'fanzine reader',
    'maker': 'maker / editor',
    'curator': 'curator pipeline',
    'guests': 'public guests',
  };

  // Active matrix feature/context column filters
  final Set<String> _activeMatrixColumns = {
    'position',
    'reader',
    'maker',
    'curator',
    'guests',
  };

  List<ReaderTool> _tools = [];

  @override
  void initState() {
    super.initState();
    _tools = List<ReaderTool>.from(ReaderToolsConfig.tools);
  }

  /// Returns active columns strictly sorted according to the canonical column order.
  List<String> get _visibleColumns =>
      _orderedColumnKeys.where((k) => _activeMatrixColumns.contains(k)).toList();

  /// Converts a camelCase enum identifier (e.g. `textReader`, `analyticsDashboard`)
  /// into a clean, human-readable lowercase label (`text reader`, `analytics dashboard`).
  String _formatEnumName(String raw) {
    return raw
        .replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
    )
        .toLowerCase();
  }

  /// Resolves the live panel or action triggered when clicking a tool within a given column.
  /// Dynamically evaluates either `tool.getBonusRowForScope` (mobile) or `tool.getBonusColumnForScope` (desktop).
  Component _buildCellContent(ReaderTool tool, String colKey) {
    // 1. Resolve effective scope for this column
    final ToolScope? scope = switch (colKey) {
      'reader' || 'guests' => ToolScope.reader,
      'maker' => ToolScope.editor,
      'curator' => ToolScope.curator,
      _ => null,
    };

    if (scope == null || !tool.scopes.contains(scope)) {
      return span(
        [text('—')],
        attributes: const {
          'style': 'font-size: 13px; color: #d1d5db; line-height: 1; user-select: none;',
        },
      );
    }

    // 2. Handle Public Guests authentication-gated checkpoints
    if (colKey == 'guests') {
      if (tool.id == 'Like' || tool.id == 'Settings' || tool.id == 'Terminal') {
        return _buildPillBadge('prompt login', '#fef3c7', '#92400e', '#fde68a');
      }
    }

    // 3. Direct Action buttons (no panel)
    if (tool.action == ToolAction.switchToGridView) {
      return _buildPillBadge('grid view', '#eff6ff', '#1e40af', '#bfdbfe');
    }
    if (tool.action == ToolAction.copyShareLink) {
      return _buildPillBadge('copy link', '#eff6ff', '#1e40af', '#bfdbfe');
    }
    if (tool.action == ToolAction.toggleLike) {
      return _buildPillBadge('toggle like', '#fdf2f8', '#9d174d', '#fbcfe8');
    }

    // 4. Panel Opening: dynamically interrogate the scope and layout mode
    final BonusRowType? targetPanel = (_layoutMode == MatrixLayoutMode.bonusColumn)
        ? tool.getBonusColumnForScope(scope)
        : tool.getBonusRowForScope(scope);

    if (targetPanel != null) {
      String displayLabel = _formatEnumName(targetPanel.name);

      // Distinguish view vs edit modes if the panel differs conceptually between reader and editor/curator
      if (targetPanel == BonusRowType.entities) {
        displayLabel = (scope == ToolScope.curator) ? 'entities (edit)' : 'entities (view)';
      } else if (targetPanel == BonusRowType.indicia) {
        displayLabel = (scope == ToolScope.reader) ? 'indicia (view)' : 'indicia (edit)';
      }

      return _buildPillBadge(displayLabel, '#f3f4f6', '#374151', '#e5e7eb');
    }

    return span(
      [text('—')],
      attributes: const {
        'style': 'font-size: 13px; color: #d1d5db; line-height: 1; user-select: none;',
      },
    );
  }

  Component _buildPillBadge(String label, String bgColor, String textColor, String borderColor) {
    return span(
      [text(label)],
      attributes: {
        'style': 'font-size: 10px; font-weight: 600; color: $textColor; background-color: $bgColor; border: 1px solid $borderColor; padding: 2px 7px; border-radius: 4px; text-transform: lowercase; white-space: nowrap; line-height: 1.2; letter-spacing: 0.2px; text-align: center; max-width: 100px; overflow: hidden; text-overflow: ellipsis;',
      },
    );
  }

  Component _buildColumnChip(String colKey, String label) {
    final bool isSelected = _activeMatrixColumns.contains(colKey);
    return button(
      classes: isSelected ? 'm3-chip active' : 'm3-chip',
      attributes: {
        'type': 'button',
        'style': 'height: 28px; padding: 0 12px; font-size: 11px; font-weight: bold; border-radius: 100px; cursor: pointer; text-transform: lowercase; border: ${isSelected ? "none" : "1px solid #79747E"}; background-color: ${isSelected ? "#E8DEF8" : "#ffffff"}; color: ${isSelected ? "#1D192B" : "#49454F"}; display: inline-flex; align-items: center; gap: 4px;',
      },
      events: {
        'click': (e) {
          setState(() {
            if (isSelected) {
              _activeMatrixColumns.remove(colKey);
            } else {
              _activeMatrixColumns.add(colKey);
            }
          });
        }
      },
      [
        if (isSelected)
          span(
            classes: 'material-symbols-outlined',
            attributes: const {'style': 'font-size: 14px; color: #1D192B;'},
            [text('check')],
          ),
        text(label),
      ],
    );
  }

  Component _buildContextToggleChip(String label, bool isSelected, VoidCallback onToggle) {
    return button(
      classes: isSelected ? 'm3-chip active' : 'm3-chip',
      attributes: {
        'type': 'button',
        'style': 'height: 24px; padding: 0 10px; font-size: 10px; font-weight: bold; border-radius: 100px; cursor: pointer; text-transform: lowercase; border: ${isSelected ? "none" : "1px solid #ccc"}; background-color: ${isSelected ? "#E8DEF8" : "#ffffff"}; color: ${isSelected ? "#1D192B" : "#666"}; display: inline-flex; align-items: center; gap: 4px;',
      },
      events: {'click': (e) => onToggle()},
      [
        if (isSelected)
          span(
            classes: 'material-symbols-outlined',
            attributes: const {'style': 'font-size: 12px; color: #1D192B;'},
            [text('check')],
          ),
        text(label),
      ],
    );
  }

  Component _buildSocialButtonCardRow(ReaderTool tool, int index) {
    final iconPath = tool.defaultIcon;
    final bool isSvgAsset = iconPath.endsWith('.svg') || iconPath.startsWith('assets/');

    return div(
      classes: 'social-button-card-row',
      attributes: const {
        'style': 'display: flex; flex-direction: row; align-items: center; gap: 12px; padding: 8px 12px; background-color: #ffffff; border: 1px solid #e5e7eb; border-radius: 8px; min-height: 48px; box-sizing: border-box; width: 100%; transition: background-color 0.15s ease;',
      },
      [
        // Icon circular badge
        div(
          attributes: const {
            'style': 'display: flex; align-items: center; justify-content: center; width: 34px; height: 34px; border-radius: 50%; border: 1.5px solid #000; flex-shrink: 0; background-color: #ffffff;'
          },
          [
            if (isSvgAsset)
              img(
                src: iconPath,
                attributes: const {
                  'style': 'width: 18px; height: 18px; object-fit: contain; display: block;'
                },
              )
            else
              span(
                classes: 'material-symbols-outlined',
                attributes: const {
                  'style': 'font-size: 18px; color: #000; line-height: 1;'
                },
                [text(cleanIconName(iconPath))],
              )
          ],
        ),

        // Title and description
        div(
          attributes: const {
            'style': 'display: flex; flex-direction: column; justify-content: center; flex: 1; overflow: hidden;'
          },
          [
            div(
              [text(tool.label.toLowerCase())],
              attributes: const {
                'style': 'font-size: 13px; font-weight: bold; color: #000; line-height: 1.2; text-transform: lowercase;'
              },
            ),
            div(
              [text(tool.description)],
              attributes: const {
                'style': 'font-size: 11px; color: #6b7280; line-height: 1.3; margin-top: 2px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'
              },
            )
          ],
        ),

        // Feature and context columns strictly in canonical order
        for (var colKey in _visibleColumns)
          div(
            attributes: const {
              'style': 'width: 110px; display: flex; justify-content: center; align-items: center; flex-shrink: 0;'
            },
            [
              if (colKey == 'position')
                _buildPositionCell(index)
              else
                _buildCellContent(tool, colKey),
            ],
          )
      ],
    );
  }

  Component _buildPositionCell(int index) {
    return span(
      [text('${index + 1}')],
      attributes: const {
        'style': 'font-size: 13px; font-weight: bold; color: #49454F; font-family: monospace;',
      },
    );
  }

  @override
  Component build(BuildContext context) {
    return div(
      [
        // TOP SECTION: Live Toolbar Previews for FanzineReaderPage, FanzineCurator, and FanzineEditor
        div(
          classes: 'flex-col gap-4 w-full mb-6 pb-6 border-b border-gray-200',
          attributes: const {
            'style': 'display: flex; flex-direction: column; gap: 16px; width: 100%; border-bottom: 2px solid #e5e7eb; padding-bottom: 24px;'
          },
          [
            // Context simulation toolbar row
            div(
              classes: 'flex-row flex-wrap justify-between items-center',
              attributes: const {'style': 'display: flex; flex-wrap: wrap; justify-content: space-between; align-items: center; gap: 8px; width: 100%;'},
              [
                span(
                  [text("LIVE APP TOOLBAR SIMULATION")],
                  attributes: const {
                    'style': 'font-size: 11px; font-weight: bold; color: #374151; letter-spacing: 0.5px;'
                  },
                ),
                div(
                  attributes: const {'style': 'display: flex; flex-wrap: wrap; gap: 6px; align-items: center;'},
                  [
                    span([text("simulate:")], attributes: const {'style': 'font-size: 10px; color: #888; font-weight: bold; margin-right: 2px;'}),
                    _buildContextToggleChip("grid open", _previewCanOpenGrid, () {
                      setState(() => _previewCanOpenGrid = !_previewCanOpenGrid);
                    }),
                    _buildContextToggleChip("youtube", _previewHasYoutube, () {
                      setState(() => _previewHasYoutube = !_previewHasYoutube);
                    }),
                    _buildContextToggleChip("terminal", _previewIsGame, () {
                      setState(() => _previewIsGame = !_previewIsGame);
                    }),
                    _buildContextToggleChip("indicia", _previewIsIndicia, () {
                      setState(() => _previewIsIndicia = !_previewIsIndicia);
                    }),
                  ],
                ),
              ],
            ),

            // 1. FanzineReaderPage Preview (ToolScope.reader)
            div(
              classes: 'flex-col gap-2 w-full',
              attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px; width: 100%;'},
              [
                div(
                  attributes: const {'style': 'display: flex; justify-content: space-between; align-items: center;'},
                  [
                    span(
                      [text("FanzineReaderPage (Public Reader)")],
                      attributes: const {
                        'style': 'font-size: 11px; font-weight: bold; color: #6b7280; text-transform: uppercase; letter-spacing: 0.5px;'
                      },
                    ),
                    span(
                      [text("ToolScope.reader | ingested")],
                      attributes: const {
                        'style': 'font-size: 10px; color: #9ca3af; font-family: monospace;'
                      },
                    ),
                  ],
                ),
                div(
                  classes: 'bg-gray-50 border border-gray-200 rounded-lg p-2',
                  attributes: const {'style': 'background-color: #f9fafb; border: 1px solid #e5e7eb; border-radius: 8px; padding: 8px; width: 100%; box-sizing: border-box;'},
                  [
                    SocialToolbar(
                      imageId: 'preview_reader',
                      activeScope: ToolScope.reader,
                      fanzineType: 'ingested',
                      isEditingMode: false,
                      onOpenGrid: _previewCanOpenGrid ? () {} : null,
                      youtubeId: _previewHasYoutube ? 'demo' : null,
                      isGame: _previewIsGame,
                      isIndiciaPage: _previewIsIndicia,
                      activeBonusRow: _previewReaderBonusRow,
                      onToggleBonusRow: (row) {
                        setState(() {
                          _previewReaderBonusRow = (_previewReaderBonusRow == row) ? null : row;
                        });
                      },
                      likedImageIds: const {},
                    )
                  ],
                )
              ],
            ),

            // 2. FanzineCurator Preview (ToolScope.curator)
            div(
              classes: 'flex-col gap-2 w-full',
              attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px; width: 100%;'},
              [
                div(
                  attributes: const {'style': 'display: flex; justify-content: space-between; align-items: center;'},
                  [
                    span(
                      [text("FanzineCurator (Curator Workspace)")],
                      attributes: const {
                        'style': 'font-size: 11px; font-weight: bold; color: #6b7280; text-transform: uppercase; letter-spacing: 0.5px;'
                      },
                    ),
                    span(
                      [text("ToolScope.curator | ingested")],
                      attributes: const {
                        'style': 'font-size: 10px; color: #9ca3af; font-family: monospace;'
                      },
                    ),
                  ],
                ),
                div(
                  classes: 'bg-gray-50 border border-gray-200 rounded-lg p-2',
                  attributes: const {'style': 'background-color: #f9fafb; border: 1px solid #e5e7eb; border-radius: 8px; padding: 8px; width: 100%; box-sizing: border-box;'},
                  [
                    SocialToolbar(
                      imageId: 'preview_curator',
                      activeScope: ToolScope.curator,
                      fanzineType: 'ingested',
                      isEditingMode: true,
                      onOpenGrid: _previewCanOpenGrid ? () {} : null,
                      youtubeId: _previewHasYoutube ? 'demo' : null,
                      isGame: _previewIsGame,
                      isIndiciaPage: _previewIsIndicia,
                      activeBonusRow: _previewCuratorBonusRow,
                      onToggleBonusRow: (row) {
                        setState(() {
                          _previewCuratorBonusRow = (_previewCuratorBonusRow == row) ? null : row;
                        });
                      },
                      likedImageIds: const {},
                    )
                  ],
                )
              ],
            ),

            // 3. FanzineEditor Preview (ToolScope.editor)
            div(
              classes: 'flex-col gap-2 w-full',
              attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px; width: 100%;'},
              [
                div(
                  attributes: const {'style': 'display: flex; justify-content: space-between; align-items: center;'},
                  [
                    span(
                      [text("FanzineEditor (Maker / Folio Workspace)")],
                      attributes: const {
                        'style': 'font-size: 11px; font-weight: bold; color: #6b7280; text-transform: uppercase; letter-spacing: 0.5px;'
                      },
                    ),
                    span(
                      [text("ToolScope.editor | folio")],
                      attributes: const {
                        'style': 'font-size: 10px; color: #9ca3af; font-family: monospace;'
                      },
                    ),
                  ],
                ),
                div(
                  classes: 'bg-gray-50 border border-gray-200 rounded-lg p-2',
                  attributes: const {'style': 'background-color: #f9fafb; border: 1px solid #e5e7eb; border-radius: 8px; padding: 8px; width: 100%; box-sizing: border-box;'},
                  [
                    SocialToolbar(
                      imageId: 'preview_editor',
                      activeScope: ToolScope.editor,
                      fanzineType: 'folio',
                      isEditingMode: true,
                      onOpenGrid: _previewCanOpenGrid ? () {} : null,
                      youtubeId: _previewHasYoutube ? 'demo' : null,
                      isGame: _previewIsGame,
                      isIndiciaPage: _previewIsIndicia,
                      activeBonusRow: _previewEditorBonusRow,
                      onToggleBonusRow: (row) {
                        setState(() {
                          _previewEditorBonusRow = (_previewEditorBonusRow == row) ? null : row;
                        });
                      },
                      likedImageIds: const {},
                    )
                  ],
                )
              ],
            ),
          ],
        ),

        div(
          classes: 'flex-row justify-between items-center w-full mb-4 pb-4 border-b border-gray-100',
          attributes: const {
            'style': 'display: flex; justify-content: space-between; align-items: center; width: 100%; margin-bottom: 16px; border-bottom: 1px solid #eee; padding-bottom: 12px; flex-wrap: wrap; gap: 12px;'
          },
          [
            div([
              span(
                [text("TARGET VIEWPORT PANEL")],
                attributes: const {
                  'style': 'font-size: 11px; font-weight: bold; color: #6b7280; text-transform: uppercase; letter-spacing: 0.5px; display: block;'
                },
              ),
              span(
                  [text("inspect mobile bonus row drawer vs desktop 3rd column targets")],
                  attributes: const {'style': 'font-size: 10px; color: #9ca3af;'}
              )
            ]),
            div(
              attributes: const {
                'style': 'display: flex; border: 1px solid #ccc; border-radius: 100px; overflow: hidden; background: white;'
              },
              [
                button(
                  [
                    span(
                      classes: 'material-symbols-outlined',
                      attributes: const {'style': 'font-size: 13px; margin-right: 4px; vertical-align: middle;'},
                      [text('smartphone')],
                    ),
                    text("bonus row (mobile)")
                  ],
                  attributes: {
                    'type': 'button',
                    'style': 'border: none; padding: 6px 14px; font-size: 11px; font-weight: bold; cursor: pointer; display: inline-flex; align-items: center; '
                        'background-color: ${_layoutMode == MatrixLayoutMode.bonusRow ? "#E8DEF8" : "transparent"}; '
                        'color: ${_layoutMode == MatrixLayoutMode.bonusRow ? "#1D192B" : "#49454F"};'
                  },
                  events: {
                    'click': (e) => setState(() => _layoutMode = MatrixLayoutMode.bonusRow)
                  },
                ),
                div(attributes: const {'style': 'width: 1px; background: #ccc;'}, []),
                button(
                  [
                    span(
                      classes: 'material-symbols-outlined',
                      attributes: const {'style': 'font-size: 13px; margin-right: 4px; vertical-align: middle;'},
                      [text('desktop_windows')],
                    ),
                    text("bonus column (desktop)")
                  ],
                  attributes: {
                    'type': 'button',
                    'style': 'border: none; padding: 6px 14px; font-size: 11px; font-weight: bold; cursor: pointer; display: inline-flex; align-items: center; '
                        'background-color: ${_layoutMode == MatrixLayoutMode.bonusColumn ? "#E8DEF8" : "transparent"}; '
                        'color: ${_layoutMode == MatrixLayoutMode.bonusColumn ? "#1D192B" : "#49454F"};'
                  },
                  events: {
                    'click': (e) => setState(() => _layoutMode = MatrixLayoutMode.bonusColumn)
                  },
                ),
              ],
            )
          ],
        ),

        // MATRIX TOGGLES
        div(
          classes: 'flex-col gap-2 w-full mb-4',
          attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px; width: 100%; margin-bottom: 16px;'},
          [
            span(
              [text("FEATURE / CONTEXT COLUMNS")],
              attributes: const {
                'style': 'font-size: 11px; font-weight: bold; color: #6b7280; text-transform: uppercase; letter-spacing: 0.5px;'
              },
            ),
            div(
              classes: 'flex-row flex-wrap gap-2 items-center',
              attributes: const {'style': 'display: flex; flex-wrap: wrap; gap: 8px; align-items: center;'},
              [
                for (var colKey in _orderedColumnKeys)
                  _buildColumnChip(colKey, _matrixColumnLabels[colKey]!)
              ],
            ),
          ],
        ),

        // MATRIX HEADER
        if (_visibleColumns.isNotEmpty)
          div(
            attributes: const {
              'style': 'display: flex; flex-direction: row; align-items: center; padding: 0 12px 8px 12px; border-bottom: 2px solid #e5e7eb; width: 100%; box-sizing: border-box;'
            },
            [
              div([text("BUTTON / PANEL")], attributes: const {'style': 'flex: 1; font-size: 11px; font-weight: bold; color: #6b7280; text-transform: uppercase;'}),
              for (var colKey in _visibleColumns)
                div(
                  [text(_matrixColumnLabels[colKey] ?? colKey)],
                  attributes: const {
                    'style': 'width: 110px; text-align: center; font-size: 10px; font-weight: bold; color: #6b7280; text-transform: uppercase; flex-shrink: 0; padding: 0 4px;'
                  },
                )
            ],
          ),

        // MATRIX ROWS
        div(
          classes: 'flex-col gap-2 w-full',
          attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px; width: 100%;'},
          [
            for (int i = 0; i < _tools.length; i++)
              _buildSocialButtonCardRow(_tools[i], i),
          ],
        )
      ],
      classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-4',
      attributes: const {'style': 'display: flex; flex-direction: column; gap: 16px; padding: 24px; background: white; box-sizing: border-box;'},
    );
  }
}