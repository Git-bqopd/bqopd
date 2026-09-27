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

  // Curators & Collections Multiselect State
  List<String> _curators = [];
  List<String> _collections = [];

  // Dropdown & Search Filter States
  bool _curatorDropdownOpen = false;
  String _curatorSearchQuery = '';

  bool _collectionDropdownOpen = false;
  String _collectionSearchQuery = '';

  // Real-time Profiles Stream State
  List<Map<String, dynamic>> _allProfiles = [];
  FirebaseSubscription? _profilesUnsub;

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
      _listenToProfiles();
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
    _profilesUnsub?.callAsFunction();
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
    _curators = List<String>.from(component.fanzine.curators);
    _collections = List<String>.from(component.fanzine.collections);
  }

  void _listenToProfiles() {
    _profilesUnsub?.callAsFunction();
    _profilesUnsub = fsListenQuery('profiles', '', '', '', '', false, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        final List<Map<String, dynamic>> list = [];
        for (var d in decoded) {
          final rawData = d['data'];
          final Map<String, dynamic> data =
          rawData is Map ? Map<String, dynamic>.from(rawData) : {};
          final String docId = d['id'] ?? data['uid'] ?? '';
          data['id'] = docId;
          data['uid'] = docId;
          list.add(data);
        }
        list.sort((a, b) {
          final String nameA =
          (a['displayName'] ?? a['username'] ?? '').toString().toLowerCase();
          final String nameB =
          (b['displayName'] ?? b['username'] ?? '').toString().toLowerCase();
          return nameA.compareTo(nameB);
        });
        if (mounted) {
          setState(() {
            _allProfiles = list;
          });
        }
      } catch (e) {
        print("Error streaming profiles in CuratorSettingsTab: $e");
      }
    });
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
          if (oldKey != cleanNewKey) {
            await fsDeleteDoc('artifacts/bqopd/public/data/series/$oldKey');
          }
          await fsSetDoc(
            'artifacts/bqopd/public/data/series/$cleanNewKey',
            jsonEncode({'name': cleanName}),
            true,
          );
        }
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

  Future<void> _handleSaveAndNavigate() async {
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
      curators: _curators,
      collections: _collections,
    ));

    // Resolve current user handle to navigate cleanly to /@handle/curator/curator
    final uid = getCurrentUserId();
    String? username;
    if (uid != null) {
      final myProfile = _allProfiles.firstWhere(
            (p) => p['uid'] == uid || p['id'] == uid,
        orElse: () => {},
      );
      if (myProfile['username'] != null && myProfile['username'].toString().isNotEmpty) {
        username = myProfile['username'].toString();
      }
      if (username == null) {
        try {
          final res = await fsGetDoc('profiles/$uid');
          final decoded = jsonDecode(res);
          if (decoded['exists'] == true) {
            username = decoded['data']?['username']?.toString();
          }
        } catch (_) {}
      }

      // Ensure sticky preferences remember curator mode
      try {
        final prefsData = {
          'mainTab': 'curator',
          'settingsSubTab': '',
        };
        saveLocalPreference('profile_sticky_prefs_$uid', jsonEncode(prefsData));
      } catch (_) {}
    }

    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) {
      if (username != null && username.isNotEmpty) {
        Router.of(context).push('/@$username/curator/curator');
      } else {
        Router.of(context).push('/profile');
      }
    }
  }

  Component _buildCuratorsSection() {
    final List<Map<String, dynamic>> filtered = _allProfiles.where((p) {
      final q = _curatorSearchQuery.trim().toLowerCase();
      if (q.isEmpty) return true;
      final name = (p['displayName'] ?? '').toString().toLowerCase();
      final user = (p['username'] ?? '').toString().toLowerCase();
      return name.contains(q) || user.contains(q);
    }).toList();

    return div(
      classes: 'flex-col',
      attributes: const {
        'style': 'margin-bottom: 14px; position: relative; width: 100%; box-sizing: border-box;'
      },
      [
        div(
          attributes: const {
            'style': 'display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 6px;'
          },
          [
            span(
              [Component.text('curators:')],
              attributes: const {
                'style': 'font-size: 11px; font-weight: bold; color: #555;'
              },
            ),
            span(
              [Component.text('${_curators.length} assigned')],
              attributes: const {
                'style': 'font-size: 10px; color: #888;'
              },
            ),
          ],
        ),
        // Selected Curators Chips Container
        if (_curators.isNotEmpty)
          div(
            attributes: const {
              'style':
              'display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 8px; width: 100%; box-sizing: border-box;'
            },
            [
              for (var uid in _curators) _buildCuratorChip(uid),
            ],
          ),
        // Dropdown Search Input Trigger
        div(
          attributes: const {
            'style': 'position: relative; width: 100%; box-sizing: border-box;'
          },
          [
            input(
              attributes: {
                'type': 'text',
                'placeholder': 'search user or @handle to add curator...',
                'value': _curatorSearchQuery,
                'style':
                'width: 100%; padding: 8px 12px; border: 1px solid #ccc; border-radius: 6px; box-sizing: border-box; font-size: 12px; background: white; outline: none;',
              },
              events: {
                'focus': (e) => setState(() => _curatorDropdownOpen = true),
                'input': (e) {
                  setState(() {
                    _curatorSearchQuery = getInputValue(e);
                    _curatorDropdownOpen = true;
                  });
                },
              },
            ),
            if (_curatorDropdownOpen)
              button(
                [span([Component.text('close')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px;'})],
                attributes: const {
                  'type': 'button',
                  'style':
                  'position: absolute; right: 8px; top: 50%; transform: translateY(-50%); border: none; background: transparent; cursor: pointer; color: #888; padding: 2px;'
                },
                events: {'click': (e) => setState(() => _curatorDropdownOpen = false)},
              ),
          ],
        ),
        // Transparent Backdrop to Dismiss Dropdown on Click-Outside
        if (_curatorDropdownOpen)
          div(
            attributes: const {
              'style':
              'position: fixed; top: 0; left: 0; right: 0; bottom: 0; z-index: 99;'
            },
            events: {'click': (e) => setState(() => _curatorDropdownOpen = false)},
            [],
          ),
        // Dropdown Results Menu
        if (_curatorDropdownOpen)
          div(
            attributes: const {
              'style':
              'position: absolute; top: calc(100% + 4px); left: 0; right: 0; max-height: 220px; overflow-y: auto; background: white; border: 1px solid #ccc; border-radius: 6px; box-shadow: 0 4px 12px rgba(0,0,0,0.15); z-index: 100; box-sizing: border-box;'
            },
            [
              if (filtered.isEmpty)
                div(
                  [Component.text('no matching users found.')],
                  attributes: const {
                    'style': 'padding: 12px; font-size: 11px; color: #888; font-style: italic; text-align: center;'
                  },
                )
              else
                for (var profile in filtered) _buildProfileOptionRow(profile, isCurator: true)
            ],
          ),
      ],
    );
  }

  Component _buildCollectionSection() {
    final List<Map<String, dynamic>> filtered = _allProfiles.where((p) {
      final q = _collectionSearchQuery.trim().toLowerCase();
      if (q.isEmpty) return true;
      final name = (p['displayName'] ?? '').toString().toLowerCase();
      final user = (p['username'] ?? '').toString().toLowerCase();
      return name.contains(q) || user.contains(q);
    }).toList();

    return div(
      classes: 'flex-col',
      attributes: const {
        'style': 'margin-bottom: 14px; position: relative; width: 100%; box-sizing: border-box;'
      },
      [
        div(
          attributes: const {
            'style': 'display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 6px;'
          },
          [
            span(
              [Component.text('collection / physical copy:')],
              attributes: const {
                'style': 'font-size: 11px; font-weight: bold; color: #555;'
              },
            ),
            span(
              [Component.text('${_collections.length} selected')],
              attributes: const {
                'style': 'font-size: 10px; color: #888;'
              },
            ),
          ],
        ),
        // Selected Collection Chips Container
        if (_collections.isNotEmpty)
          div(
            attributes: const {
              'style':
              'display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 8px; width: 100%; box-sizing: border-box;'
            },
            [
              for (var uid in _collections) _buildCollectionChip(uid),
            ],
          ),
        // Dropdown Search Input Trigger
        div(
          attributes: const {
            'style': 'position: relative; width: 100%; box-sizing: border-box;'
          },
          [
            input(
              attributes: {
                'type': 'text',
                'placeholder': 'search users or managed profiles to add to collection...',
                'value': _collectionSearchQuery,
                'style':
                'width: 100%; padding: 8px 12px; border: 1px solid #ccc; border-radius: 6px; box-sizing: border-box; font-size: 12px; background: white; outline: none;',
              },
              events: {
                'focus': (e) => setState(() => _collectionDropdownOpen = true),
                'input': (e) {
                  setState(() {
                    _collectionSearchQuery = getInputValue(e);
                    _collectionDropdownOpen = true;
                  });
                },
              },
            ),
            if (_collectionDropdownOpen)
              button(
                [span([Component.text('close')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px;'})],
                attributes: const {
                  'type': 'button',
                  'style':
                  'position: absolute; right: 8px; top: 50%; transform: translateY(-50%); border: none; background: transparent; cursor: pointer; color: #888; padding: 2px;'
                },
                events: {'click': (e) => setState(() => _collectionDropdownOpen = false)},
              ),
          ],
        ),
        // Transparent Backdrop to Dismiss Dropdown on Click-Outside
        if (_collectionDropdownOpen)
          div(
            attributes: const {
              'style':
              'position: fixed; top: 0; left: 0; right: 0; bottom: 0; z-index: 99;'
            },
            events: {'click': (e) => setState(() => _collectionDropdownOpen = false)},
            [],
          ),
        // Dropdown Results Menu
        if (_collectionDropdownOpen)
          div(
            attributes: const {
              'style':
              'position: absolute; top: calc(100% + 4px); left: 0; right: 0; max-height: 220px; overflow-y: auto; background: white; border: 1px solid #ccc; border-radius: 6px; box-shadow: 0 4px 12px rgba(0,0,0,0.15); z-index: 100; box-sizing: border-box;'
            },
            [
              if (filtered.isEmpty)
                div(
                  [Component.text('no matching profiles found.')],
                  attributes: const {
                    'style': 'padding: 12px; font-size: 11px; color: #888; font-style: italic; text-align: center;'
                  },
                )
              else
                for (var profile in filtered) _buildProfileOptionRow(profile, isCurator: false)
            ],
          ),
      ],
    );
  }

  Component _buildCuratorChip(String uid) {
    final profile = _allProfiles.firstWhere(
          (p) => (p['uid'] == uid || p['id'] == uid),
      orElse: () => {'displayName': uid, 'username': ''},
    );
    final String displayName = (profile['displayName'] ?? '').toString().isNotEmpty
        ? profile['displayName']
        : (profile['username'] ?? uid);
    final String? photoUrl = profile['photoUrl'];

    return div(
      attributes: const {
        'style':
        'display: inline-flex; align-items: center; gap: 6px; background: #E8DEF8; color: #1D192B; border: 1px solid #D0BCFF; border-radius: 16px; padding: 2px 8px 2px 4px; font-size: 11px; font-weight: 500;'
      },
      [
        div(
          attributes: const {
            'style':
            'width: 20px; height: 20px; border-radius: 50%; overflow: hidden; background: #fff; display: flex; align-items: center; justify-content: center; flex-shrink: 0;'
          },
          [
            if (photoUrl != null && photoUrl.isNotEmpty)
              img(src: photoUrl, attributes: const {'style': 'width: 100%; height: 100%; object-fit: cover;'})
            else
              span([Component.text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?')],
                  attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #6750A4;'}),
          ],
        ),
        span([Component.text(displayName)]),
        button(
          [span([Component.text('close')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px;'})],
          attributes: const {
            'type': 'button',
            'style': 'border: none; background: transparent; cursor: pointer; color: #1D192B; padding: 0; display: inline-flex; align-items: center;'
          },
          events: {
            'click': (e) {
              setState(() {
                _curators.remove(uid);
              });
            }
          },
        ),
      ],
    );
  }

  Component _buildCollectionChip(String uid) {
    final profile = _allProfiles.firstWhere(
          (p) => (p['uid'] == uid || p['id'] == uid),
      orElse: () => {'displayName': uid, 'username': ''},
    );
    final String displayName = (profile['displayName'] ?? '').toString().isNotEmpty
        ? profile['displayName']
        : (profile['username'] ?? uid);
    final bool isManaged = profile['isManaged'] == true;
    final String? photoUrl = profile['photoUrl'];

    return div(
      attributes: const {
        'style':
        'display: inline-flex; align-items: center; gap: 6px; background: #f3f4f6; color: #1f2937; border: 1px solid #d1d5db; border-radius: 16px; padding: 2px 8px 2px 4px; font-size: 11px; font-weight: 500;'
      },
      [
        div(
          attributes: const {
            'style':
            'width: 20px; height: 20px; border-radius: 50%; overflow: hidden; background: #fff; display: flex; align-items: center; justify-content: center; flex-shrink: 0;'
          },
          [
            if (photoUrl != null && photoUrl.isNotEmpty)
              img(src: photoUrl, attributes: const {'style': 'width: 100%; height: 100%; object-fit: cover;'})
            else
              span([Component.text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?')],
                  attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #555;'}),
          ],
        ),
        span([Component.text(displayName)]),
        if (isManaged)
          span(
            [Component.text('managed')],
            attributes: const {
              'style':
              'font-size: 8px; font-weight: bold; background: #e0e7ff; color: #3730a3; padding: 1px 4px; border-radius: 4px; text-transform: uppercase;'
            },
          ),
        button(
          [span([Component.text('close')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px;'})],
          attributes: const {
            'type': 'button',
            'style': 'border: none; background: transparent; cursor: pointer; color: #4b5563; padding: 0; display: inline-flex; align-items: center;'
          },
          events: {
            'click': (e) {
              setState(() {
                _collections.remove(uid);
              });
            }
          },
        ),
      ],
    );
  }

  Component _buildProfileOptionRow(Map<String, dynamic> profile, {required bool isCurator}) {
    final String uid = profile['uid'] ?? profile['id'] ?? '';
    final String displayName = profile['displayName'] ?? profile['username'] ?? 'User';
    final String username = profile['username'] ?? '';
    final String? photoUrl = profile['photoUrl'];
    final bool isManaged = profile['isManaged'] == true;
    final bool isSelected = isCurator ? _curators.contains(uid) : _collections.contains(uid);

    return div(
      attributes: {
        'style':
        'display: flex; align-items: center; justify-content: space-between; padding: 8px 12px; cursor: pointer; border-bottom: 1px solid #f0f0f0; transition: background 0.15s; '
            'background: ${isSelected ? "rgba(103, 80, 164, 0.08)" : "white"};'
      },
      events: {
        'click': (e) {
          setState(() {
            if (isCurator) {
              if (isSelected) {
                _curators.remove(uid);
              } else {
                _curators.add(uid);
              }
            } else {
              if (isSelected) {
                _collections.remove(uid);
              } else {
                _collections.add(uid);
              }
            }
          });
        }
      },
      [
        div(
          attributes: const {'style': 'display: flex; align-items: center; gap: 8px; overflow: hidden;'},
          [
            div(
              attributes: const {
                'style':
                'width: 26px; height: 26px; border-radius: 50%; overflow: hidden; background: #eee; display: flex; align-items: center; justify-content: center; flex-shrink: 0;'
              },
              [
                if (photoUrl != null && photoUrl.isNotEmpty)
                  img(src: photoUrl, attributes: const {'style': 'width: 100%; height: 100%; object-fit: cover;'})
                else
                  span([Component.text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?')],
                      attributes: const {'style': 'font-size: 11px; font-weight: bold; color: #666;'}),
              ],
            ),
            div(
              attributes: const {'style': 'display: flex; flex-direction: column; text-align: left; overflow: hidden;'},
              [
                span([Component.text(displayName)],
                    attributes: const {'style': 'font-size: 12px; font-weight: bold; color: black; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'}),
                if (username.isNotEmpty)
                  span([Component.text('@$username')],
                      attributes: const {'style': 'font-size: 10px; color: #666; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'}),
              ],
            ),
          ],
        ),
        div(
          attributes: const {'style': 'display: flex; align-items: center; gap: 6px; flex-shrink: 0;'},
          [
            if (isManaged)
              span(
                [Component.text('managed')],
                attributes: const {
                  'style':
                  'font-size: 8px; font-weight: bold; background: #e0e7ff; color: #3730a3; padding: 1px 4px; border-radius: 4px; text-transform: uppercase;'
                },
              ),
            span(
              classes: 'material-symbols-outlined',
              attributes: {
                'style':
                'font-size: 18px; color: ${isSelected ? "#6750A4" : "#ccc"};'
              },
              [Component.text(isSelected ? 'check_box' : 'check_box_outline_blank')],
            ),
          ],
        ),
      ],
    );
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
          [Component.text('shortcode: $currentShortcode')],
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
                span([Component.text('part of a series:')], attributes: const {
                  'style': 'font-size: 11px; font-weight: bold; color: #555;'
                }),
                span(
                  [Component.text(_showSeriesManager ? 'close manager' : 'manage list')],
                  attributes: const {
                    'style': 'font-size: 11px; font-weight: bold; color: #6750A4; text-decoration: underline; cursor: pointer;'
                  },
                  events: {
                    'click': (e) {
                      setState(() {
                        _showSeriesManager = !_showSeriesManager;
                      });
                    }
                  },
                )
              ],
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
                    [Component.text(entry.value)],
                  )
              ],
            )
          ],
          classes: 'flex-col',
          attributes: const {'style': 'margin-bottom: 4px;'},
        ),

        // Expanded Inline Series Manager UI
        if (_showSeriesManager)
          div(
            attributes: const {
              'style': 'background: #f9f9f9; border: 1px solid #eee; border-radius: 12px; padding: 12px; margin-bottom: 12px;'
            },
            [
              span([Component.text('manage series list')], attributes: const {
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
                                  },
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
                                  },
                                ),
                              ],
                            )
                          else
                            div(
                              attributes: const {'style': 'display: flex; flex-direction: column; gap: 1px;'},
                              [
                                span([Component.text(entry.value)], attributes: const {
                                  'style': 'font-size: 12px; font-weight: bold; color: black;'
                                }),
                                span([Component.text('id: ${entry.key}')], attributes: const {
                                  'style': 'font-size: 9px; color: #888; font-family: monospace;'
                                }),
                              ],
                            ),
                          div(
                            attributes: const {'style': 'display: flex; gap: 4px; align-items: center;'},
                            [
                              if (_editingSeriesKey == entry.key) ...[
                                button(
                                  [span([Component.text('done')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px;'})],
                                  attributes: const {
                                    'type': 'button',
                                    'style': 'border: none; background: transparent; color: #16a34a; cursor: pointer; padding: 4px;'
                                  },
                                  events: {
                                    'click': (e) => _updateSeries(entry.key, _editingSeriesNewKey, _editingSeriesName)
                                  },
                                ),
                                button(
                                  [span([Component.text('close')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px;'})],
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
                                  },
                                )
                              ] else ...[
                                button(
                                  [span([Component.text('edit_note')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px;'})],
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
                                  },
                                ),
                                button(
                                  [span([Component.text('delete')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px;'})],
                                  attributes: const {
                                    'type': 'button',
                                    'style': 'border: none; background: transparent; color: #ef4444; cursor: pointer; padding: 4px;'
                                  },
                                  events: {
                                    'click': (dynamic e) {
                                      try {
                                        e.preventDefault();
                                        e.stopPropagation();
                                      } catch (_) {}
                                      _deleteSeries(entry.key);
                                    }
                                  },
                                )
                              ]
                            ],
                          )
                        ],
                      )
                ],
              ),
              div(
                attributes: const {
                  'style': 'border-top: 1px solid #e5e7eb; padding-top: 10px; display: flex; flex-direction: column; gap: 8px;'
                },
                [
                  span([Component.text('add new series')], attributes: const {
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
                        },
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
                        },
                      ),
                      button(
                        [span([Component.text('add')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 18px;'})],
                        attributes: const {
                          'type': 'button',
                          'style': 'height: 34px; display: inline-flex; align-items: center; justify-content: center; padding: 0 12px; border: none; border-radius: 8px; background-color: #6750A4; color: white; cursor: pointer; font-weight: bold;'
                        },
                        events: {
                          'click': (e) => _addSeries()
                        },
                      )
                    ],
                  )
                ],
              )
            ],
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

        // Published Date Row (Aligned cleanly with M3 38px specifications)
        div(
          [
            span([Component.text('published date:')], attributes: const {
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
                        'style': 'width: 100%; padding: 8px 12px; border: 1px solid var(--m3-outline, #79747E); border-radius: 8px; box-sizing: border-box; font-size: 13px; background-color: white; outline: none; cursor: pointer; height: 38px;'
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
                  attributes: const {'style': 'flex: 1; min-width: 140px;'},
                ),
                // Middle element: Date Display Mode M3 Segmented Button (day, month, year)
                div(
                  [
                    SegmentedButton<String>(
                      segments: const ['day', 'month', 'year'],
                      selected: _publishedDateMode,
                      labelBuilder: (val) => val,
                      showSelectedCheckmark: true,
                      onSelectionChanged: (val) {
                        setState(() {
                          _publishedDateMode = val;
                        });
                      },
                    )
                  ],
                  attributes: const {'style': 'display: inline-flex; align-items: center;'},
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
                        'style': 'font-size: 12px; font-weight: 500; color: #49454F; cursor: pointer; user-select: none;'
                      },
                      [Component.text('guess?')],
                    )
                  ],
                  attributes: const {'style': 'display: inline-flex; align-items: center; margin-left: auto; white-space: nowrap; height: 38px;'},
                )
              ],
              attributes: const {
                'style': 'display: flex; flex-direction: row; flex-wrap: wrap; gap: 12px; align-items: center; width: 100%;'
              },
            )
          ],
          classes: 'flex-col',
          attributes: const {'style': 'margin-bottom: 12px;'},
        ),

        // Curators Multiselect Dropdown Section
        _buildCuratorsSection(),

        // Collection Multiselect Dropdown Section
        _buildCollectionSection(),

        // Two-Page Spread Layout Option Toggle
        div(
          [
            span(
              [
                Component.text(component.fanzine.twoPage
                    ? 'two page spread (switch: single page view)'
                    : 'single page view (switch: two page spread)')
              ],
              classes: 'text-xs font-medium',
              attributes: const {'style': 'color: #4a4a4a;'},
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
                Component.text(component.fanzine.isLive
                    ? 'visible'
                    : 'hidden')
              ],
              classes: 'text-xs font-medium',
              attributes: const {'style': 'color: #4a4a4a;'},
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
          [Component.text(component.isSaving ? 'saving folio...' : 'save folio')],
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
            'style':
            'width: 18px; height: 18px; border-radius: 50%; background-color: white; position: absolute; top: 3px; left: ${val ? "23px" : "3px"}; transition: left 0.2s; box-shadow: 0 1px 3px rgba(0,0,0,0.35);'
          },
        )
      ],
      attributes: {
        'style':
        'width: 44px; height: 24px; border-radius: 12px; background-color: ${val ? "#6750A4" : "#ccc"}; position: relative; transition: background-color 0.2s; cursor: pointer; display: inline-block;'
      },
    );
  }
}