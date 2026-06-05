import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';
import '../segmented_button.dart';

/// Decoupled default fanzine series metadata choices.
const Map<String, String> _defaultSeriesOptions = {
  '': 'no series / independent',
  'the-fantasy-fan': 'the fantasy fan',
  'the-comet-cosmology': 'the comet / cosmology',
  'phantagraph': 'phantagraph',
  'science-fiction-digest': 'science-fiction-digest / fantasy magazine',
  'the-planet': 'the planet',
  'the-time-traveller': 'the time traveller',
  'futuria-fantasia': 'futuria fantasia',
};

/// Curator-only decoupled Settings sub-tab.
/// Completely independent from the Editor Settings tab to allow custom meta and pipeline parameters.
class CuratorSettingsTab extends StatefulComponent {
  final Fanzine fanzine;
  final List<FanzinePage> pages;
  final FanzineEditorBloc bloc;
  final bool isSaving;

  const CuratorSettingsTab({
    required this.fanzine,
    required this.pages,
    required this.bloc,
    required this.isSaving,
    super.key,
  });

  @override
  State<CuratorSettingsTab> createState() => _CuratorSettingsTabState();
}

class _CuratorSettingsTabState extends State<CuratorSettingsTab> {
  String _title = '';
  String _volume = '';
  String _issue = '';
  String _wholeNumber = '';
  String _series = '';
  String _publishedDate = '';
  String _publishedDateMode = 'year';
  bool _publishedDateGuess = false;

  // Series List Manager State
  bool _showSeriesManager = false;
  Map<String, String> _seriesOptionsMap = {};
  FirebaseSubscription? _seriesUnsub;
  bool _isUsingDefaults = true;

  String _newSeriesKey = '';
  String _newSeriesName = '';
  String? _editingSeriesKey;
  String _editingSeriesName = '';
  String _editingSeriesNewKey = '';

  @override
  void initState() {
    super.initState();
    _syncLocalFields();
    if (kIsWeb) {
      _listenToSeries();
    } else {
      _seriesOptionsMap = Map.from(_defaultSeriesOptions);
    }
  }

  @override
  void didUpdateComponent(CuratorSettingsTab oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.fanzine != component.fanzine) {
      _syncLocalFields();
    }
  }

  @override
  void dispose() {
    _seriesUnsub?.callAsFunction();
    super.dispose();
  }

  void _syncLocalFields() {
    _title = component.fanzine.title;
    _volume = component.fanzine.volume ?? '';
    _issue = component.fanzine.issue ?? '';
    _wholeNumber = component.fanzine.wholeNumber ?? '';
    _series = component.fanzine.series ?? '';
    _publishedDate = component.fanzine.publishedDate ?? '';
    _publishedDateMode = component.fanzine.publishedDateMode ?? 'year';
    _publishedDateGuess = component.fanzine.publishedDateGuess;
  }

  void _listenToSeries() {
    _seriesUnsub?.callAsFunction();
    _seriesUnsub = fsListenQuery('artifacts/bqopd/public/data/series', '', '', '', '', false, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        if (decoded.isEmpty) {
          if (mounted) {
            setState(() {
              _seriesOptionsMap = Map.from(_defaultSeriesOptions);
              _isUsingDefaults = true;
            });
          }
        } else {
          final Map<String, String> loaded = {
            '': 'no series / independent',
          };
          for (var item in decoded) {
            final id = item['id'] as String;
            final data = item['data'] as Map<String, dynamic>;
            loaded[id] = data['name'] ?? id;
          }
          if (mounted) {
            setState(() {
              _seriesOptionsMap = loaded;
              _isUsingDefaults = false;
            });
          }
        }
      } catch (e) {
        print("Error listening to series collection: $e");
        if (mounted) {
          setState(() {
            _seriesOptionsMap = Map.from(_defaultSeriesOptions);
            _isUsingDefaults = true;
          });
        }
      }
    });
  }

  Future<void> _addSeries() async {
    final key = _newSeriesKey.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '-');
    final name = _newSeriesName.trim();
    if (key.isEmpty || name.isEmpty) return;

    try {
      if (kIsWeb) {
        if (_isUsingDefaults) {
          // Seed all default options into Firestore first
          for (var entry in _defaultSeriesOptions.entries) {
            if (entry.key.isNotEmpty) {
              await fsSetDoc(
                'artifacts/bqopd/public/data/series/${entry.key}',
                jsonEncode({'name': entry.value}),
                true,
              );
            }
          }
        }

        // Add the newly created custom series option
        await fsSetDoc(
          'artifacts/bqopd/public/data/series/$key',
          jsonEncode({'name': name}),
          true,
        );

        setState(() {
          _newSeriesKey = '';
          _newSeriesName = '';
        });
      }
    } catch (e) {
      print("Error adding series: $e");
    }
  }

  Future<void> _updateSeries(String oldKey, String newKey, String name) async {
    final cleanNewKey = newKey.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '-');
    final cleanName = name.trim();
    if (oldKey.isEmpty || cleanNewKey.isEmpty || cleanName.isEmpty) return;

    try {
      if (kIsWeb) {
        if (_isUsingDefaults) {
          // Seed all default options, substituting the edited key/name inline
          for (var entry in _defaultSeriesOptions.entries) {
            if (entry.key.isNotEmpty) {
              final String finalKey = (entry.key == oldKey) ? cleanNewKey : entry.key;
              final String finalName = (entry.key == oldKey) ? cleanName : entry.value;
              await fsSetDoc(
                'artifacts/bqopd/public/data/series/$finalKey',
                jsonEncode({'name': finalName}),
                true,
              );
            }
          }
        } else {
          // If the key has changed, delete the old Firestore doc and create the new one
          if (oldKey != cleanNewKey) {
            await fsDeleteDoc('artifacts/bqopd/public/data/series/$oldKey');
          }
          await fsSetDoc(
            'artifacts/bqopd/public/data/series/$cleanNewKey',
            jsonEncode({'name': cleanName}),
            true,
          );
        }

        // Keep active dropdown select references in sync
        if (_series == oldKey) {
          setState(() {
            _series = cleanNewKey;
          });
        }
        if (component.fanzine.series == oldKey) {
          component.bloc.add(UpdateFanzineMetadata(
            _title,
            _volume,
            _issue,
            _wholeNumber,
            series: cleanNewKey,
          ));
        }

        setState(() {
          _editingSeriesKey = null;
          _editingSeriesName = '';
          _editingSeriesNewKey = '';
        });
      }
    } catch (e) {
      print("Error updating series: $e");
    }
  }

  Future<void> _deleteSeries(String key) async {
    if (key.isEmpty) return;
    try {
      if (kIsWeb) {
        if (_isUsingDefaults) {
          // Seed all default options EXCEPT the deleted one
          for (var entry in _defaultSeriesOptions.entries) {
            if (entry.key.isNotEmpty && entry.key != key) {
              await fsSetDoc(
                'artifacts/bqopd/public/data/series/${entry.key}',
                jsonEncode({'name': entry.value}),
                true,
              );
            }
          }
        } else {
          // Delete directly from Firestore
          await fsDeleteDoc('artifacts/bqopd/public/data/series/$key');
        }

        if (_series == key) {
          setState(() {
            _series = '';
          });
        }
      }
    } catch (e) {
      print("Error deleting series: $e");
    }
  }

  void _handleSaveAndNavigate() {
    // Locate the first page in the fanzine page list to assign its thumbnail to 'gridCoverImage'
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

    // Dispatch save and commit metadata to the BLoC
    component.bloc.add(UpdateFanzineMetadata(
      _title,
      _volume,
      _issue,
      _wholeNumber,
      gridCoverImage: firstPageImage,
      series: _series.isEmpty ? '' : _series,
      publishedDate: _publishedDate.isEmpty ? '' : _publishedDate,
      publishedDateMode: _publishedDateMode,
      publishedDateGuess: _publishedDateGuess,
    ));

    // Route user back to profile
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
        // Shortcode Indicator
        div(
          [text('shortcode: $currentShortcode')],
          classes: 'text-xs text-gray-500 font-semibold mb-1 text-left',
        ),
        // Dropdown container for Series selection
        div(
            [
              div(
                  attributes: const {
                    'style': 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;'
                  },
                  [
                    span([text('part of a series:')], attributes: const {
                      'style': 'font-size: 11px; font-weight: bold; color: #555;'
                    }),
                    span(
                        [text(_showSeriesManager ? 'close manager' : 'manage list')],
                        attributes: const {
                          'style': 'font-size: 11px; font-weight: bold; color: #6750A4; text-decoration: underline; cursor: pointer;'
                        },
                        events: {
                          'click': (e) {
                            setState(() {
                              _showSeriesManager = !_showSeriesManager;
                            });
                          }
                        }
                    )
                  ]
              ),
              select(
                  attributes: const {
                    'style': 'width: 100%; padding: 12px; margin-bottom: 12px; border: 1px solid #ccc; border-radius: 12px; box-sizing: border-box; font-size: 14px; background-color: white; outline: none; -webkit-appearance: none; appearance: none; cursor: pointer;'
                  },
                  events: {
                    'change': (e) {
                      setState(() {
                        _series = getInputValue(e);
                      });
                    }
                  },
                  [
                    for (var entry in _seriesOptionsMap.entries)
                      option(
                          attributes: {
                            'value': entry.key,
                            if (_series == entry.key) 'selected': 'true',
                          },
                          [text(entry.value)]
                      )
                  ]
              )
            ],
            classes: 'flex-col',
            attributes: const {'style': 'margin-bottom: 4px;'}
        ),

        // Expanded Inline Series Manager UI
        if (_showSeriesManager)
          div(
              attributes: const {
                'style': 'background: #f9f9f9; border: 1px solid #eee; border-radius: 12px; padding: 12px; margin-bottom: 12px;'
              },
              [
                span([text('manage series list')], attributes: const {
                  'style': 'font-size: 11px; font-weight: bold; color: #333; text-transform: uppercase; letter-spacing: 0.5px; display: block; margin-bottom: 8px;'
                }),
                div(
                    attributes: const {
                      'style': 'display: flex; flex-direction: column; gap: 6px; max-height: 200px; overflow-y: auto; margin-bottom: 12px;'
                    },
                    [
                      for (var entry in _seriesOptionsMap.entries)
                        if (entry.key.isNotEmpty)
                          div(
                              attributes: const {
                                'style': 'display: flex; align-items: center; justify-content: space-between; padding: 6px 8px; background: white; border: 1px solid #e5e7eb; border-radius: 8px;'
                              },
                              [
                                if (_editingSeriesKey == entry.key)
                                  div(
                                      attributes: const {'style': 'display: flex; flex-direction: column; gap: 6px; flex: 1; margin-right: 8px;'},
                                      [
                                        input(
                                            attributes: {
                                              'type': 'text',
                                              'placeholder': 'series name',
                                              'value': _editingSeriesName,
                                              'style': 'margin-bottom: 0; padding: 6px 10px; font-size: 12px; border-radius: 6px; border: 1px solid #ccc;'
                                            },
                                            events: {
                                              'input': (e) {
                                                _editingSeriesName = getInputValue(e);
                                              }
                                            }
                                        ),
                                        input(
                                            attributes: {
                                              'type': 'text',
                                              'placeholder': 'id-slug',
                                              'value': _editingSeriesNewKey,
                                              'style': 'margin-bottom: 0; padding: 6px 10px; font-size: 11px; font-family: monospace; border-radius: 6px; border: 1px solid #ccc;'
                                            },
                                            events: {
                                              'input': (e) {
                                                _editingSeriesNewKey = getInputValue(e).trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '-');
                                              }
                                            }
                                        ),
                                      ]
                                  )
                                else
                                  div(
                                      attributes: const {'style': 'display: flex; flex-direction: column; gap: 1px;'},
                                      [
                                        span([text(entry.value)], attributes: const {
                                          'style': 'font-size: 12px; font-weight: bold; color: black;'
                                        }),
                                        span([text('id: ${entry.key}')], attributes: const {
                                          'style': 'font-size: 9px; color: #888; font-family: monospace;'
                                        }),
                                      ]
                                  ),
                                div(
                                    attributes: const {'style': 'display: flex; gap: 4px; align-items: center;'},
                                    [
                                      if (_editingSeriesKey == entry.key) ...[
                                        button(
                                            [span([text('done')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px;'})],
                                            attributes: const {
                                              'type': 'button',
                                              'style': 'border: none; background: transparent; color: #16a34a; cursor: pointer; padding: 4px;'
                                            },
                                            events: {
                                              'click': (e) => _updateSeries(entry.key, _editingSeriesNewKey, _editingSeriesName)
                                            }
                                        ),
                                        button(
                                            [span([text('close')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px;'})],
                                            attributes: const {
                                              'type': 'button',
                                              'style': 'border: none; background: transparent; color: #ef4444; cursor: pointer; padding: 4px;'
                                            },
                                            events: {
                                              'click': (e) {
                                                setState(() {
                                                  _editingSeriesKey = null;
                                                  _editingSeriesName = '';
                                                  _editingSeriesNewKey = '';
                                                });
                                              }
                                            }
                                        )
                                      ] else ...[
                                        button(
                                            [span([text('edit_note')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px;'})],
                                            attributes: const {
                                              'type': 'button',
                                              'style': 'border: none; background: transparent; color: #6750A4; cursor: pointer; padding: 4px;'
                                            },
                                            events: {
                                              'click': (e) {
                                                setState(() {
                                                  _editingSeriesKey = entry.key;
                                                  _editingSeriesName = entry.value;
                                                  _editingSeriesNewKey = entry.key;
                                                });
                                              }
                                            }
                                        ),
                                        button(
                                            [span([text('delete')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px;'})],
                                            attributes: const {
                                              'type': 'button',
                                              'style': 'border: none; background: transparent; color: #ef4444; cursor: pointer; padding: 4px;'
                                            },
                                            events: {
                                              'click': (e) {
                                                if (e is dynamic) {
                                                  try {
                                                    e.preventDefault();
                                                    e.stopPropagation();
                                                  } catch (_) {}
                                                }
                                                _deleteSeries(entry.key);
                                              }
                                            }
                                        )
                                      ]
                                    ]
                                )
                              ]
                          )
                    ]
                ),
                div(
                    attributes: const {
                      'style': 'border-top: 1px solid #e5e7eb; padding-top: 10px; display: flex; flex-direction: column; gap: 8px;'
                    },
                    [
                      span([text('add new series')], attributes: const {
                        'style': 'font-size: 10px; font-weight: bold; color: #555;'
                      }),
                      div(
                          attributes: const {
                            'style': 'display: flex; gap: 8px; align-items: center;'
                          },
                          [
                            input(
                                attributes: {
                                  'type': 'text',
                                  'placeholder': 'series name',
                                  'value': _newSeriesName,
                                  'style': 'margin-bottom: 0; padding: 8px 12px; font-size: 12px; flex: 1; border-radius: 8px; border: 1px solid #ccc;'
                                },
                                events: {
                                  'input': (e) {
                                    final nameVal = getInputValue(e);
                                    setState(() {
                                      _newSeriesName = nameVal;
                                      _newSeriesKey = nameVal.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s-]'), '').replaceAll(RegExp(r'\s+'), '-');
                                    });
                                  }
                                }
                            ),
                            input(
                                attributes: {
                                  'type': 'text',
                                  'placeholder': 'id-slug',
                                  'value': _newSeriesKey,
                                  'style': 'margin-bottom: 0; padding: 8px 12px; font-size: 11px; width: 100px; border-radius: 8px; font-family: monospace; border: 1px solid #ccc;'
                                },
                                events: {
                                  'input': (e) {
                                    setState(() {
                                      _newSeriesKey = getInputValue(e);
                                    });
                                  }
                                }
                            ),
                            button(
                                [span([text('add')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 18px;'})],
                                attributes: const {
                                  'type': 'button',
                                  'style': 'height: 34px; display: inline-flex; align-items: center; justify-content: center; padding: 0 12px; border: none; border-radius: 8px; background-color: #6750A4; color: white; cursor: pointer; font-weight: bold;'
                                },
                                events: {
                                  'click': (e) => _addSeries()
                                }
                            )
                          ]
                      )
                    ]
                )
              ]
          ),

        // Fanzine Title Input Field
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
        // Volume / Issue / Whole Number Input Row
        div(
          [
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
        // Published Date Row
        div(
            [
              span([text('published date:')], attributes: const {
                'style': 'font-size: 11px; font-weight: bold; color: #555; display: block; margin-bottom: 4px; text-align: left;'
              }),
              div(
                  [
                    // Left element: Date Input
                    div(
                        [
                          input(
                            attributes: {
                              'type': 'date',
                              'value': _publishedDate,
                              'style': 'width: 100%; padding: 10px; border: 1px solid #ccc; border-radius: 12px; box-sizing: border-box; font-size: 14px; background-color: white; outline: none; cursor: pointer; height: 36px;'
                            },
                            events: {
                              'change': (e) {
                                setState(() {
                                  _publishedDate = getInputValue(e);
                                });
                              }
                            },
                          )
                        ],
                        attributes: const {'style': 'flex: 1.5; min-width: 150px;'}
                    ),
                    // Middle element: Date Display Mode Segmented Button (day, month, year)
                    div(
                        [
                          SegmentedButton<String>(
                            segments: const ['day', 'month', 'year'],
                            selected: _publishedDateMode,
                            labelBuilder: (val) => val,
                            onSelectionChanged: (val) {
                              setState(() {
                                _publishedDateMode = val;
                              });
                            },
                          )
                        ],
                        attributes: const {'style': 'flex: 2; min-width: 200px; display: flex; align-items: center;'}
                    ),
                    // Right element: Guess Checkbox
                    div(
                        [
                          input(
                            type: InputType.checkbox,
                            attributes: {
                              'id': 'curator-guess-checkbox',
                              if (_publishedDateGuess) 'checked': 'true',
                              'style': 'cursor: pointer; width: 16px; height: 16px; margin: 0 6px 0 0; outline: none;'
                            },
                            events: {
                              'change': (e) {
                                setState(() {
                                  _publishedDateGuess = !_publishedDateGuess;
                                });
                              }
                            },
                          ),
                          label(
                              attributes: {
                                'for': 'curator-guess-checkbox',
                                'style': 'font-size: 11px; font-weight: bold; color: #555; cursor: pointer; user-select: none;'
                              },
                              [text('guess?')]
                          )
                        ],
                        attributes: const {'style': 'display: inline-flex; align-items: center; margin-left: auto; white-space: nowrap; height: 36px;'}
                    )
                  ],
                  attributes: const {
                    'style': 'display: flex; flex-direction: row; flex-wrap: wrap; gap: 12px; align-items: center; width: 100%;'
                  }
              )
            ],
            classes: 'flex-col',
            attributes: const {'style': 'margin-bottom: 12px;'}
        ),
        // Two-Page Spread Layout Option Toggle
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
        // Visibility Option Toggle
        div(
          [
            span(
                [
                  text(component.fanzine.isLive
                      ? 'visible'
                      : 'hidden')
                ],
                classes: 'text-xs font-medium',
                attributes: const {'style': 'color: #4a4a4a;'}
            ),
            _buildCustomToggleSwitch(component.fanzine.isLive)
          ],
          classes: 'flex-row items-center justify-between cursor-pointer',
          attributes: const {
            'style': 'padding: 10px 12px; background-color: #f9f9f9; border: 1px solid #eee; border-radius: 8px; margin-bottom: 4px; display: flex; align-items: center; justify-content: space-between;'
          },
          events: {
            'click': (e) {
              component.bloc.add(ToggleIsLiveRequested(!component.fanzine.isLive));
            }
          },
        ),
        // Save Button
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
      [
        div(
          [],
          attributes: {
            'style': 'width: 18px; height: 18px; border-radius: 50%; background-color: white; position: absolute; top: 3px; left: ${val ? "23px" : "3px"}; transition: left 0.2s; box-shadow: 0 1px 3px rgba(0,0,0,0.35);'
          },
        )
      ],
      attributes: {
        'style': 'width: 44px; height: 24px; border-radius: 12px; background-color: ${val ? "#6750A4" : "#ccc"}; position: relative; transition: background-color 0.2s; cursor: pointer; display: inline-block;'
      },
    );
  }
}