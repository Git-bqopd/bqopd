import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../../utils/web_utils.dart';

/// Renders the Circulation Desk sub-page inside Column 3 of `/publisher`.
class PublisherCirculationView extends StatelessComponent {
  final PublishingWeek week;
  final bool hasActiveWeekDashboard;
  final List<CirculationRecipient> recipients;
  final List<Map<String, dynamic>> allProfiles;
  final String userSearchQuery;
  final bool searchDropdownOpen;

  // Manual Contact Form state
  final bool showAddManualForm;
  final String manualDisplayName;
  final String manualStreet1;
  final String manualStreet2;
  final String manualCity;
  final String manualState;
  final String manualZip;
  final String manualCountry;
  final String manualNotes;
  final String? manualFormError;

  // Edit Address Modal state
  final CirculationRecipient? editingRecipient;
  final String editStreet1;
  final String editStreet2;
  final String editCity;
  final String editState;
  final String editZip;
  final String editCountry;
  final String editNotes;

  // Callbacks
  final void Function() onCloseCirculation;
  final void Function() onToggleManualForm;
  final void Function(String query, bool openDropdown) onSearchQueryChanged;
  final void Function(bool open) onSearchDropdownVisibilityChanged;
  final void Function(Map<String, dynamic> profile)
      onAddUserProfileToCirculation;
  final void Function(String val) onManualDisplayNameChanged;
  final void Function(String val) onManualStreet1Changed;
  final void Function(String val) onManualStreet2Changed;
  final void Function(String val) onManualCityChanged;
  final void Function(String val) onManualStateChanged;
  final void Function(String val) onManualZipChanged;
  final void Function(String val) onManualCountryChanged;
  final void Function(String val) onManualNotesChanged;
  final void Function() onSubmitManualRecipient;
  final void Function(CirculationRecipient recipient) onOpenEditAddress;
  final void Function() onCloseEditAddress;
  final void Function(String val) onEditStreet1Changed;
  final void Function(String val) onEditStreet2Changed;
  final void Function(String val) onEditCityChanged;
  final void Function(String val) onEditStateChanged;
  final void Function(String val) onEditZipChanged;
  final void Function(String val) onEditCountryChanged;
  final void Function(String val) onEditNotesChanged;
  final void Function() onSaveEditedAddress;
  final void Function(String recipientId) onRemoveRecipient;

  const PublisherCirculationView({
    required this.week,
    required this.hasActiveWeekDashboard,
    required this.recipients,
    required this.allProfiles,
    required this.userSearchQuery,
    required this.searchDropdownOpen,
    required this.showAddManualForm,
    required this.manualDisplayName,
    required this.manualStreet1,
    required this.manualStreet2,
    required this.manualCity,
    required this.manualState,
    required this.manualZip,
    required this.manualCountry,
    required this.manualNotes,
    required this.manualFormError,
    required this.editingRecipient,
    required this.editStreet1,
    required this.editStreet2,
    required this.editCity,
    required this.editState,
    required this.editZip,
    required this.editCountry,
    required this.editNotes,
    required this.onCloseCirculation,
    required this.onToggleManualForm,
    required this.onSearchQueryChanged,
    required this.onSearchDropdownVisibilityChanged,
    required this.onAddUserProfileToCirculation,
    required this.onManualDisplayNameChanged,
    required this.onManualStreet1Changed,
    required this.onManualStreet2Changed,
    required this.onManualCityChanged,
    required this.onManualStateChanged,
    required this.onManualZipChanged,
    required this.onManualCountryChanged,
    required this.onManualNotesChanged,
    required this.onSubmitManualRecipient,
    required this.onOpenEditAddress,
    required this.onCloseEditAddress,
    required this.onEditStreet1Changed,
    required this.onEditStreet2Changed,
    required this.onEditCityChanged,
    required this.onEditStateChanged,
    required this.onEditZipChanged,
    required this.onEditCountryChanged,
    required this.onEditNotesChanged,
    required this.onSaveEditedAddress,
    required this.onRemoveRecipient,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    return div(
      classes: 'flex-col gap-4 w-full',
      attributes: const {
        'style':
            'display: flex; flex-direction: column; gap: 16px; width: 100%; box-sizing: border-box;',
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
                'click': (e) => onCloseCirculation(),
              },
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {'style': 'font-size: 15px; line-height: 1;'},
                  [Component.text('arrow_back')],
                ),
                Component.text(
                  hasActiveWeekDashboard ? 'week dashboard' : 'schedule',
                ),
              ],
            ),
            div(
              attributes: const {
                'style': 'display: flex; align-items: baseline; gap: 8px;',
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
                        'font-size: 11px; font-weight: 900; letter-spacing: 0.5px; color: #6750A4;',
                  },
                ),
                span(
                  [Component.text('· ${recipients.length} queued')],
                  attributes: const {
                    'style':
                        'font-size: 10px; color: #64748b; font-weight: 500;',
                  },
                ),
              ],
            ),
          ],
        ),

        // Sub-page Headline Banner
        div(
          attributes: const {
            'style':
                'background: white; border: 1px solid #cbd5e1; border-radius: 8px; padding: 14px 16px; box-sizing: border-box;',
          },
          [
            div(
              attributes: const {
                'style':
                    'display: flex; align-items: center; justify-content: space-between;',
              },
              [
                div(
                  attributes: const {
                    'style': 'display: flex; align-items: center; gap: 8px;',
                  },
                  [
                    span(
                      classes: 'material-symbols-outlined',
                      attributes: const {
                        'style': 'font-size: 18px; color: #6750A4;',
                      },
                      [Component.text('mark_email_read')],
                    ),
                    span(
                      [Component.text('CIRCULATION DESK')],
                      attributes: const {
                        'style':
                            'font-size: 12px; font-weight: 900; letter-spacing: 0.5px; color: #1e293b; text-transform: uppercase;',
                      },
                    ),
                  ],
                ),
                span(
                  [Component.text(week.startDateString)],
                  attributes: const {
                    'style':
                        'font-size: 10px; font-weight: bold; color: #64748b;',
                  },
                ),
              ],
            ),
            p(
              [
                Component.text(
                  'Manage the recipients receiving printed fanzine copies for the week starting ',
                ),
                span(
                  [Component.text(week.startDateString)],
                  attributes: const {
                    'style': 'font-weight: bold; color: #1e293b;',
                  },
                ),
                Component.text('.'),
              ],
              attributes: const {
                'style':
                    'font-size: 11px; color: #64748b; line-height: 1.4; margin: 4px 0 0 0;',
              },
            ),
          ],
        ),

        _buildSearchAndAddBar(),

        if (showAddManualForm) _buildManualContactForm(),

        _buildRecipientsList(),

        if (editingRecipient != null) _buildEditAddressModal(),
      ],
    );
  }

  Component _buildSearchAndAddBar() {
    final filtered = allProfiles.where((p) {
      final q = userSearchQuery.trim().toLowerCase();
      if (q.isEmpty) return false;
      final name = (p['displayName'] ?? '').toString().toLowerCase();
      final user = (p['username'] ?? '').toString().toLowerCase();
      final first = (p['firstName'] ?? '').toString().toLowerCase();
      final last = (p['lastName'] ?? '').toString().toLowerCase();
      return name.contains(q) ||
          user.contains(q) ||
          first.contains(q) ||
          last.contains(q);
    }).toList();

    return div(
      attributes: const {
        'style':
            'background: white; border: 1px solid #cbd5e1; border-radius: 8px; padding: 14px; '
                'display: flex; flex-direction: column; gap: 10px; width: 100%; box-sizing: border-box; position: relative;',
      },
      [
        div(
          attributes: const {
            'style':
                'display: flex; justify-content: space-between; align-items: center;',
          },
          [
            span(
              [Component.text('ADD RECIPIENT TO THIS ISSUE')],
              attributes: const {
                'style':
                    'font-size: 10px; font-weight: bold; color: #475569; letter-spacing: 0.5px; text-transform: uppercase;',
              },
            ),
            button(
              classes: 'profile-btn',
              attributes: {
                'type': 'button',
                'style':
                    'border: 1px solid ${showAddManualForm ? "#6750A4" : "#cbd5e1"}; '
                        'background: ${showAddManualForm ? "#f3f0fb" : "white"}; '
                        'color: ${showAddManualForm ? "#6750A4" : "#475569"}; '
                        'padding: 3px 10px; font-size: 10px; font-weight: bold; border-radius: 12px; cursor: pointer; '
                        'display: inline-flex; align-items: center; gap: 4px;',
              },
              events: {
                'click': (e) => onToggleManualForm(),
              },
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {'style': 'font-size: 13px;'},
                  [Component.text(showAddManualForm ? 'close' : 'person_add')],
                ),
                Component.text(
                  showAddManualForm ? 'cancel manual' : 'contact without profile',
                ),
              ],
            ),
          ],
        ),

        // Live Profile Search Box with Dropdown Autocomplete
        div(
          attributes: const {
            'style': 'position: relative; width: 100%; box-sizing: border-box;',
          },
          [
            input(
              attributes: {
                'type': 'text',
                'placeholder': 'search user by username or real name...',
                'value': userSearchQuery,
                'style':
                    'width: 100%; padding: 8px 12px; border: 1px solid #cbd5e1; border-radius: 6px; '
                        'font-size: 12px; background: white; outline: none; box-sizing: border-box; margin: 0;',
              },
              events: {
                'focus': (e) {
                  if (userSearchQuery.trim().isNotEmpty) {
                    onSearchDropdownVisibilityChanged(true);
                  }
                },
                'input': (e) {
                  final val = getInputValue(e);
                  onSearchQueryChanged(val, val.trim().isNotEmpty);
                },
              },
            ),
            if (userSearchQuery.trim().isNotEmpty)
              button(
                attributes: const {
                  'type': 'button',
                  'style':
                      'position: absolute; right: 8px; top: 50%; transform: translateY(-50%); '
                          'border: none; background: transparent; cursor: pointer; color: #888; padding: 2px;',
                },
                events: {
                  'click': (e) => onSearchQueryChanged('', false),
                },
                [
                  span(
                    classes: 'material-symbols-outlined',
                    attributes: const {'style': 'font-size: 15px;'},
                    [Component.text('close')],
                  ),
                ],
              ),
          ],
        ),

        // Dropdown Overlay Menu for Profile Search Matches
        if (searchDropdownOpen && userSearchQuery.trim().isNotEmpty) ...[
          div(
            attributes: const {
              'style':
                  'position: fixed; top: 0; left: 0; right: 0; bottom: 0; z-index: 99;',
            },
            events: {
              'click': (e) => onSearchDropdownVisibilityChanged(false),
            },
            [],
          ),
          div(
            classes: 'search-results-menu',
            attributes: const {
              'style':
                  'position: absolute; top: 82px; left: 14px; right: 14px; max-height: 220px; '
                      'overflow-y: auto; background: white; border: 1px solid #cbd5e1; border-radius: 6px; '
                      'box-shadow: 0 4px 16px rgba(0,0,0,0.15); z-index: 100; box-sizing: border-box;',
            },
            [
              if (filtered.isEmpty)
                div(
                  [Component.text('no matching user profiles found.')],
                  attributes: const {
                    'style':
                        'padding: 12px; font-size: 11px; color: #888; font-style: italic; text-align: center;',
                  },
                )
              else
                for (final profile in filtered.take(12))
                  _buildProfileSearchResultItem(profile),
            ],
          ),
        ],
      ],
    );
  }

  Component _buildProfileSearchResultItem(Map<String, dynamic> profile) {
    final String uid = profile['uid'] ?? profile['id'] ?? '';
    final bool isAlreadyAdded = recipients.any((r) => r.id == uid);

    final String displayName =
        (profile['displayName'] ?? profile['username'] ?? 'User').toString();
    final String username = (profile['username'] ?? '').toString();
    final String? photoUrl = profile['photoUrl']?.toString();
    final String city = (profile['city'] ?? '').toString().trim();
    final String state = (profile['state'] ?? '').toString().trim();
    final String locSummary = [
      if (city.isNotEmpty) city,
      if (state.isNotEmpty) state,
    ].join(', ');

    return div(
      attributes: {
        'style':
            'display: flex; align-items: center; justify-content: space-between; padding: 8px 12px; '
                'border-bottom: 1px solid #f1f5f9; cursor: ${isAlreadyAdded ? "default" : "pointer"}; '
                'background: ${isAlreadyAdded ? "#f8fafc" : "white"}; transition: background 0.15s;',
      },
      events: {
        'click': (e) {
          if (!isAlreadyAdded) {
            onAddUserProfileToCirculation(profile);
          }
        },
      },
      [
        div(
          attributes: const {
            'style':
                'display: flex; align-items: center; gap: 10px; overflow: hidden;',
          },
          [
            div(
              attributes: const {
                'style':
                    'width: 28px; height: 28px; border-radius: 50%; overflow: hidden; background: #eee; '
                        'display: flex; align-items: center; justify-content: center; flex-shrink: 0;',
              },
              [
                if (photoUrl != null && photoUrl.isNotEmpty)
                  img(
                    src: photoUrl,
                    attributes: const {
                      'style': 'width: 100%; height: 100%; object-fit: cover;',
                    },
                  )
                else
                  span(
                    [
                      Component.text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : '?',
                      ),
                    ],
                    attributes: const {
                      'style':
                          'font-size: 11px; font-weight: bold; color: #666;',
                    },
                  ),
              ],
            ),
            div(
              attributes: const {
                'style':
                    'display: flex; flex-direction: column; text-align: left; overflow: hidden;',
              },
              [
                span(
                  [Component.text(displayName)],
                  attributes: const {
                    'style':
                        'font-size: 12px; font-weight: bold; color: #1e293b; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;',
                  },
                ),
                div(
                  attributes: const {
                    'style': 'display: flex; align-items: center; gap: 6px;',
                  },
                  [
                    if (username.isNotEmpty)
                      span(
                        [Component.text('@$username')],
                        attributes: const {
                          'style':
                              'font-size: 10px; color: #64748b; font-family: monospace;',
                        },
                      ),
                    if (locSummary.isNotEmpty)
                      span(
                        [Component.text('· $locSummary')],
                        attributes: const {
                          'style': 'font-size: 10px; color: #94a3b8;',
                        },
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
        span(
          [Component.text(isAlreadyAdded ? 'added' : '+ add')],
          attributes: {
            'style':
                'font-size: 10px; font-weight: bold; padding: 2px 8px; border-radius: 10px; '
                    'background: ${isAlreadyAdded ? "#e2e8f0" : "#E8DEF8"}; '
                    'color: ${isAlreadyAdded ? "#64748b" : "#6750A4"};',
          },
        ),
      ],
    );
  }

  Component _buildManualContactForm() {
    return div(
      attributes: const {
        'style':
            'background: white; border: 2px dashed #6750A4; border-radius: 8px; padding: 16px; '
                'display: flex; flex-direction: column; gap: 10px; width: 100%; box-sizing: border-box;',
      },
      [
        div(
          attributes: const {
            'style':
                'display: flex; justify-content: space-between; align-items: center;',
          },
          [
            span(
              [Component.text('NEW RECIPIENT (NO APP PROFILE)')],
              attributes: const {
                'style':
                    'font-size: 11px; font-weight: 900; color: #6750A4; letter-spacing: 0.5px; text-transform: uppercase;',
              },
            ),
            span(
              [
                Component.text(
                  'Stores address info without creating a profile',
                ),
              ],
              attributes: const {
                'style':
                    'font-size: 9px; color: #64748b; font-style: italic;',
              },
            ),
          ],
        ),

        // Real Name Input
        div([
          span(
            [Component.text('Real Name / Full Name *')],
            attributes: const {
              'style':
                  'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;',
            },
          ),
          input(
            attributes: {
              'type': 'text',
              'placeholder': 'e.g. Robert A. Heinlein',
              'value': manualDisplayName,
              'style':
                  'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
            },
            events: {
              'input': (e) => onManualDisplayNameChanged(getInputValue(e)),
            },
          ),
        ]),

        // Street Address 1
        div([
          span(
            [Component.text('Street Address Line 1')],
            attributes: const {
              'style':
                  'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;',
            },
          ),
          input(
            attributes: {
              'type': 'text',
              'placeholder': 'e.g. 123 Sci-Fi Way',
              'value': manualStreet1,
              'style':
                  'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
            },
            events: {
              'input': (e) => onManualStreet1Changed(getInputValue(e)),
            },
          ),
        ]),

        // Street Address 2
        div([
          span(
            [Component.text('Address Line 2 (Apt / Suite / Unit)')],
            attributes: const {
              'style':
                  'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;',
            },
          ),
          input(
            attributes: {
              'type': 'text',
              'placeholder': 'Apt 4B',
              'value': manualStreet2,
              'style':
                  'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
            },
            events: {
              'input': (e) => onManualStreet2Changed(getInputValue(e)),
            },
          ),
        ]),

        // City & State Row
        div(
          attributes: const {'style': 'display: flex; gap: 8px; width: 100%;'},
          [
            div(
              attributes: const {'style': 'flex: 2;'},
              [
                span(
                  [Component.text('City')],
                  attributes: const {
                    'style':
                        'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;',
                  },
                ),
                input(
                  attributes: {
                    'type': 'text',
                    'placeholder': 'City',
                    'value': manualCity,
                    'style':
                        'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                  },
                  events: {
                    'input': (e) => onManualCityChanged(getInputValue(e)),
                  },
                ),
              ],
            ),
            div(
              attributes: const {'style': 'flex: 1.2;'},
              [
                span(
                  [Component.text('State / Prov')],
                  attributes: const {
                    'style':
                        'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;',
                  },
                ),
                input(
                  attributes: {
                    'type': 'text',
                    'placeholder': 'State',
                    'value': manualState,
                    'style':
                        'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                  },
                  events: {
                    'input': (e) => onManualStateChanged(getInputValue(e)),
                  },
                ),
              ],
            ),
          ],
        ),

        // ZIP & Country Row
        div(
          attributes: const {'style': 'display: flex; gap: 8px; width: 100%;'},
          [
            div(
              attributes: const {'style': 'flex: 1.5;'},
              [
                span(
                  [Component.text('ZIP / Postal Code')],
                  attributes: const {
                    'style':
                        'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;',
                  },
                ),
                input(
                  attributes: {
                    'type': 'text',
                    'placeholder': 'ZIP Code',
                    'value': manualZip,
                    'style':
                        'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                  },
                  events: {
                    'input': (e) => onManualZipChanged(getInputValue(e)),
                  },
                ),
              ],
            ),
            div(
              attributes: const {'style': 'flex: 1.5;'},
              [
                span(
                  [Component.text('Country')],
                  attributes: const {
                    'style':
                        'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;',
                  },
                ),
                input(
                  attributes: {
                    'type': 'text',
                    'placeholder': 'USA',
                    'value': manualCountry,
                    'style':
                        'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                  },
                  events: {
                    'input': (e) => onManualCountryChanged(getInputValue(e)),
                  },
                ),
              ],
            ),
          ],
        ),

        // Optional Distribution Notes
        div([
          span(
            [Component.text('Circulation Notes (Optional)')],
            attributes: const {
              'style':
                  'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;',
            },
          ),
          input(
            attributes: {
              'type': 'text',
              'placeholder': 'e.g. Mail signed copy, Subscriber #402',
              'value': manualNotes,
              'style':
                  'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
            },
            events: {
              'input': (e) => onManualNotesChanged(getInputValue(e)),
            },
          ),
        ]),

        if (manualFormError != null)
          span(
            [Component.text(manualFormError!)],
            attributes: const {
              'style':
                  'font-size: 11px; font-weight: bold; color: #ef4444;',
            },
          ),

        div(
          attributes: const {
            'style':
                'display: flex; justify-content: flex-end; gap: 8px; margin-top: 4px;',
          },
          [
            button(
              classes: 'profile-btn',
              attributes: const {
                'type': 'button',
                'style':
                    'padding: 6px 14px; font-size: 11px; font-weight: bold; border: 1px solid #ccc; background: white; cursor: pointer; border-radius: 6px;',
              },
              events: {'click': (e) => onToggleManualForm()},
              [Component.text('cancel')],
            ),
            button(
              classes: 'btn-primary nav-pill mb-0',
              attributes: const {
                'type': 'button',
                'style':
                    'padding: 6px 16px; font-size: 11px; font-weight: bold; background-color: #6750A4; color: white; border: none; border-radius: 16px; cursor: pointer; display: inline-flex; align-items: center; gap: 4px;',
              },
              events: {'click': (e) => onSubmitManualRecipient()},
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {'style': 'font-size: 14px;'},
                  [Component.text('check')],
                ),
                Component.text('add to this issue'),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Component _buildRecipientsList() {
    if (recipients.isEmpty) {
      return div(
        attributes: const {
          'style':
              'background: white; border: 1px dashed #cbd5e1; border-radius: 8px; padding: 36px 16px; '
                  'display: flex; flex-direction: column; align-items: center; justify-content: center; '
                  'text-align: center; box-sizing: border-box;',
        },
        [
          span(
            classes: 'material-symbols-outlined',
            attributes: const {
              'style': 'font-size: 36px; color: #94a3b8; margin-bottom: 6px;',
            },
            [Component.text('outgoing_mail')],
          ),
          h3(
            [Component.text('No Recipients Queued Yet')],
            attributes: const {
              'style':
                  'font-size: 13px; font-weight: bold; color: #1e293b; margin: 0 0 4px 0;',
            },
          ),
          p(
            [
              Component.text(
                'Search registered users above or enter contact details for non-profile recipients.',
              ),
            ],
            attributes: const {
              'style':
                  'font-size: 11px; color: #94a3b8; margin: 0; max-width: 320px;',
            },
          ),
        ],
      );
    }

    return div(
      attributes: const {
        'style':
            'display: flex; flex-direction: column; gap: 8px; width: 100%; box-sizing: border-box;',
      },
      [
        div(
          attributes: const {
            'style':
                'display: flex; justify-content: space-between; align-items: center; margin-bottom: 2px;',
          },
          [
            span(
              [Component.text('ISSUE RECIPIENTS (${recipients.length})')],
              attributes: const {
                'style':
                    'font-size: 10px; font-weight: 900; color: #475569; letter-spacing: 0.5px; text-transform: uppercase;',
              },
            ),
            span(
              [Component.text('Print & Mailing Queue')],
              attributes: const {
                'style': 'font-size: 10px; color: #94a3b8; font-style: italic;',
              },
            ),
          ],
        ),
        for (int i = 0; i < recipients.length; i++)
          _buildRecipientCard(recipients[i]),
      ],
    );
  }

  Component _buildRecipientCard(CirculationRecipient recipient) {
    return div(
      attributes: const {
        'style':
            'background: white; border: 1px solid #e2e8f0; border-radius: 8px; padding: 12px 14px; '
                'display: flex; flex-direction: column; gap: 8px; width: 100%; box-sizing: border-box; box-shadow: 0 1px 3px rgba(0,0,0,0.03);',
      },
      [
        // Top Header of Recipient Card
        div(
          attributes: const {
            'style':
                'display: flex; align-items: flex-start; justify-content: space-between; width: 100%; gap: 8px;',
          },
          [
            div(
              attributes: const {
                'style':
                    'display: flex; align-items: center; gap: 10px; overflow: hidden;',
              },
              [
                // Avatar / Badge
                div(
                  attributes: const {
                    'style':
                        'width: 32px; height: 32px; border-radius: 50%; overflow: hidden; background: #f1f5f9; '
                            'border: 1px solid #cbd5e1; display: flex; align-items: center; justify-content: center; flex-shrink: 0;',
                  },
                  [
                    if (recipient.photoUrl != null &&
                        recipient.photoUrl!.isNotEmpty)
                      img(
                        src: recipient.photoUrl!,
                        attributes: const {
                          'style':
                              'width: 100%; height: 100%; object-fit: cover;',
                        },
                      )
                    else if (recipient.hasProfile)
                      span(
                        [
                          Component.text(
                            recipient.displayName.isNotEmpty
                                ? recipient.displayName[0].toUpperCase()
                                : '?',
                          ),
                        ],
                        attributes: const {
                          'style':
                              'font-size: 13px; font-weight: bold; color: #6750A4;',
                        },
                      )
                    else
                      span(
                        classes: 'material-symbols-outlined',
                        attributes: const {
                          'style': 'font-size: 18px; color: #64748b;',
                        },
                        [Component.text('person')],
                      ),
                  ],
                ),

                // Name and Profile Handle / Manual Badge
                div(
                  attributes: const {
                    'style':
                        'display: flex; flex-direction: column; text-align: left; overflow: hidden;',
                  },
                  [
                    span(
                      [Component.text(recipient.displayName)],
                      attributes: const {
                        'style':
                            'font-size: 13px; font-weight: bold; color: #1e293b; line-height: 1.2; '
                                'white-space: nowrap; overflow: hidden; text-overflow: ellipsis;',
                      },
                    ),
                    div(
                      attributes: const {
                        'style':
                            'display: flex; align-items: center; gap: 6px; margin-top: 2px;',
                      },
                      [
                        if (recipient.hasProfile && recipient.username != null)
                          a(
                            [Component.text('@${recipient.username}')],
                            href: '/@${recipient.username}',
                            classes: 'hover:underline',
                            attributes: const {
                              'style':
                                  'font-size: 10px; font-weight: bold; color: #6750A4; text-decoration: none; font-family: monospace;',
                            },
                          )
                        else
                          span(
                            [Component.text('EXTERNAL (NO PROFILE)')],
                            attributes: const {
                              'style':
                                  'font-size: 8px; font-weight: bold; background: #f1f5f9; color: #475569; '
                                      'padding: 1px 5px; border-radius: 4px; border: 1px solid #cbd5e1; letter-spacing: 0.3px;',
                            },
                          ),
                        if (recipient.notes != null)
                          span(
                            [Component.text('· ${recipient.notes}')],
                            attributes: const {
                              'style':
                                  'font-size: 10px; color: #94a3b8; font-style: italic;',
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),

            // Top action buttons: Edit Address & Remove
            div(
              attributes: const {
                'style':
                    'display: flex; align-items: center; gap: 4px; flex-shrink: 0;',
              },
              [
                button(
                  classes: 'profile-btn',
                  attributes: const {
                    'type': 'button',
                    'title': 'Edit mailing address',
                    'style':
                        'padding: 3px 8px; font-size: 10px; font-weight: bold; color: #475569; '
                            'border: 1px solid #cbd5e1; background: white; border-radius: 4px; cursor: pointer; '
                            'display: inline-flex; align-items: center; gap: 2px;',
                  },
                  events: {'click': (e) => onOpenEditAddress(recipient)},
                  [
                    span(
                      classes: 'material-symbols-outlined',
                      attributes: const {'style': 'font-size: 12px;'},
                      [Component.text('edit')],
                    ),
                    Component.text('address'),
                  ],
                ),
                button(
                  attributes: const {
                    'type': 'button',
                    'title': 'Remove recipient from this issue',
                    'style':
                        'border: none; background: transparent; cursor: pointer; color: #94a3b8; padding: 2px 4px; '
                            'display: inline-flex; align-items: center; transition: color 0.15s;',
                  },
                  events: {'click': (e) => onRemoveRecipient(recipient.id)},
                  [
                    span(
                      classes: 'material-symbols-outlined',
                      attributes: const {
                        'style': 'font-size: 16px; color: #ef4444;',
                      },
                      [Component.text('close')],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),

        // Mailing Address Box
        div(
          attributes: const {
            'style':
                'background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; padding: 8px 10px; '
                    'display: flex; align-items: flex-start; gap: 8px;',
          },
          [
            span(
              classes: 'material-symbols-outlined',
              attributes: {
                'style':
                    'font-size: 15px; line-height: 1.2; '
                        'color: ${recipient.hasAddress ? "#16a34a" : "#ca8a04"};',
              },
              [
                Component.text(
                  recipient.hasAddress ? 'location_on' : 'warning',
                ),
              ],
            ),
            div(
              attributes: const {
                'style':
                    'display: flex; flex-direction: column; gap: 1px; flex: 1;',
              },
              [
                if (recipient.hasAddress)
                  p(
                    [Component.text(recipient.formattedAddress)],
                    attributes: const {
                      'style':
                          'font-family: Georgia, serif; font-size: 11px; line-height: 1.35; '
                              'color: #334155; margin: 0; white-space: pre-line;',
                    },
                  )
                else
                  span(
                    [
                      Component.text(
                        'No mailing address entered for this recipient.',
                      ),
                    ],
                    attributes: const {
                      'style':
                          'font-size: 10px; color: #ca8a04; font-style: italic; font-weight: 500;',
                    },
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Component _buildEditAddressModal() {
    final target = editingRecipient;
    if (target == null) return div([]);

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
                    [Component.text('Edit Mailing Address')],
                    attributes: const {
                      'style':
                          'margin: 0; font-size: 14px; font-weight: bold; color: #1e293b;',
                    },
                  ),
                  span(
                    [Component.text('Recipient: ${target.displayName}')],
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
                  events: {'click': (e) => onCloseEditAddress()},
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

            // Street 1
            div([
              span(
                [Component.text('Street Address Line 1')],
                attributes: const {
                  'style':
                      'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;',
                },
              ),
              input(
                attributes: {
                  'type': 'text',
                  'placeholder': '123 Main St',
                  'value': editStreet1,
                  'style':
                      'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                },
                events: {
                  'input': (e) => onEditStreet1Changed(getInputValue(e)),
                },
              ),
            ]),

            // Street 2
            div([
              span(
                [Component.text('Address Line 2 (Apt / Suite / Unit)')],
                attributes: const {
                  'style':
                      'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;',
                },
              ),
              input(
                attributes: {
                  'type': 'text',
                  'placeholder': 'Apt 4B',
                  'value': editStreet2,
                  'style':
                      'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                },
                events: {
                  'input': (e) => onEditStreet2Changed(getInputValue(e)),
                },
              ),
            ]),

            // City & State Row
            div(
              attributes: const {'style': 'display: flex; gap: 8px; width: 100%;'},
              [
                div(
                  attributes: const {'style': 'flex: 2;'},
                  [
                    span(
                      [Component.text('City')],
                      attributes: const {
                        'style':
                            'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;',
                      },
                    ),
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'City',
                        'value': editCity,
                        'style':
                            'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                      },
                      events: {
                        'input': (e) => onEditCityChanged(getInputValue(e)),
                      },
                    ),
                  ],
                ),
                div(
                  attributes: const {'style': 'flex: 1.2;'},
                  [
                    span(
                      [Component.text('State')],
                      attributes: const {
                        'style':
                            'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;',
                      },
                    ),
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'State',
                        'value': editState,
                        'style':
                            'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                      },
                      events: {
                        'input': (e) => onEditStateChanged(getInputValue(e)),
                      },
                    ),
                  ],
                ),
              ],
            ),

            // ZIP & Country Row
            div(
              attributes: const {'style': 'display: flex; gap: 8px; width: 100%;'},
              [
                div(
                  attributes: const {'style': 'flex: 1.5;'},
                  [
                    span(
                      [Component.text('ZIP / Postal Code')],
                      attributes: const {
                        'style':
                            'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;',
                      },
                    ),
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'ZIP Code',
                        'value': editZip,
                        'style':
                            'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                      },
                      events: {
                        'input': (e) => onEditZipChanged(getInputValue(e)),
                      },
                    ),
                  ],
                ),
                div(
                  attributes: const {'style': 'flex: 1.5;'},
                  [
                    span(
                      [Component.text('Country')],
                      attributes: const {
                        'style':
                            'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;',
                      },
                    ),
                    input(
                      attributes: {
                        'type': 'text',
                        'placeholder': 'Country',
                        'value': editCountry,
                        'style':
                            'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                      },
                      events: {
                        'input': (e) => onEditCountryChanged(getInputValue(e)),
                      },
                    ),
                  ],
                ),
              ],
            ),

            // Notes
            div([
              span(
                [Component.text('Circulation Notes')],
                attributes: const {
                  'style':
                      'font-size: 10px; font-weight: bold; color: #475569; display: block; margin-bottom: 2px;',
                },
              ),
              input(
                attributes: {
                  'type': 'text',
                  'placeholder': 'Special mailing instructions or notes...',
                  'value': editNotes,
                  'style':
                      'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 12px; background: white; box-sizing: border-box; margin: 0;',
                },
                events: {
                  'input': (e) => onEditNotesChanged(getInputValue(e)),
                },
              ),
            ]),

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
                  events: {'click': (e) => onCloseEditAddress()},
                  [Component.text('cancel')],
                ),
                button(
                  classes: 'btn-primary nav-pill mb-0',
                  attributes: const {
                    'type': 'button',
                    'style':
                        'padding: 6px 16px; font-size: 11px; font-weight: bold; background-color: #6750A4; color: white; border: none; border-radius: 16px; cursor: pointer;',
                  },
                  events: {'click': (e) => onSaveEditedAddress()},
                  [Component.text('save address')],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
