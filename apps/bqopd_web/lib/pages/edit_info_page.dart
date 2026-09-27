import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import '../utils/web_utils.dart';
import '../components/segmented_button.dart';

/// Full-featured Web Profile & Account Editor Page for Jaspr.
/// Supports updating public profile metadata, social media handles,
/// photo avatar URLs, and private contact/address information.
/// Allows curators and creators to toggle whether their mailing address is public or private.
class EditInfoPage extends StatefulComponent {
  final AuthState? authState;
  final AuthBloc authBloc;
  final IUserRepository userRepository;
  final String? targetUserId;

  const EditInfoPage({
    required this.authState,
    required this.authBloc,
    required this.userRepository,
    this.targetUserId,
    super.key,
  });

  @override
  State<EditInfoPage> createState() => _EditInfoPageState();
}

class _EditInfoPageState extends State<EditInfoPage> {
  bool _loading = true;
  bool _saving = false;
  bool _isAuthorized = true;
  String? _statusMessage;
  bool _isError = false;

  // Public Profile Fields
  String _displayName = '';
  String _username = '';
  String _initialUsername = '';
  String _bio = '';
  String _photoUrl = '';
  String _xHandle = '';
  String _instagramHandle = '';
  String _githubHandle = '';
  bool _isManaged = false;

  // Managed Profile Managers State
  List<String> _managers = [];
  bool _managerDropdownOpen = false;
  String _managerSearchQuery = '';
  List<Map<String, dynamic>> _allProfiles = [];
  FirebaseSubscription? _profilesUnsub;

  // User Contact & Address Fields
  String _firstName = '';
  String _lastName = '';
  String _street1 = '';
  String _street2 = '';
  String _city = '';
  String _state = '';
  String _zipCode = '';
  String _country = '';

  // Address Visibility Setting (defaults to 'private')
  // Options: 'address' (full), 'city' (city & state), 'state' (state only), 'private' (none)
  String _addressVisibility = 'private';

  StreamSubscription? _profileSub;
  StreamSubscription? _accountSub;
  StreamSubscription? _viewerAccountSub;
  UserAccount? _viewerAccount;

  String get _editingUid =>
      component.targetUserId ?? component.authState?.user?.uid ?? getCurrentUserId() ?? '';

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loadData();
      _listenToProfiles();
    }
  }

  @override
  void didUpdateComponent(EditInfoPage oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.targetUserId != component.targetUserId ||
        oldComponent.authState?.user?.uid != component.authState?.user?.uid) {
      _loadData();
      if (kIsWeb) _listenToProfiles();
    }
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _accountSub?.cancel();
    _viewerAccountSub?.cancel();
    _profilesUnsub?.callAsFunction();
    super.dispose();
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
        print("Error streaming profiles in EditInfoPage: $e");
      }
    });
  }

  void _loadData() {
    final uid = _editingUid;
    final currentAuthUid = component.authState?.user?.uid ?? getCurrentUserId();

    if (uid.isEmpty || currentAuthUid == null) {
      setState(() {
        _loading = false;
        _isAuthorized = false;
        _statusMessage = 'Authentication required to edit profile info.';
        _isError = true;
      });
      return;
    }

    setState(() => _loading = true);
    _profileSub?.cancel();
    _accountSub?.cancel();
    _viewerAccountSub?.cancel();

    // Listen to the viewer account to inspect platform roles (admin / moderator)
    _viewerAccountSub = component.userRepository.watchUserAccount(currentAuthUid).listen((acc) {
      if (acc != null && mounted) {
        setState(() => _viewerAccount = acc);
      }
    });

    // Query profiles and users documents to fetch address visibility preference
    fsGetDoc('profiles/$uid').then((res) {
      try {
        final doc = jsonDecode(res);
        if (doc['exists'] == true && mounted) {
          final data = doc['data'] as Map<String, dynamic>;
          if (data.containsKey('addressVisibility')) {
            setState(() {
              _addressVisibility = data['addressVisibility']?.toString() ?? 'private';
            });
          } else if (data.containsKey('isAddressPublic')) {
            setState(() {
              _addressVisibility = data['isAddressPublic'] == true ? 'address' : 'private';
            });
          }
        }
      } catch (_) {}
    });

    fsGetDoc('Users/$uid').then((res) {
      try {
        final doc = jsonDecode(res);
        if (doc['exists'] == true && mounted) {
          final data = doc['data'] as Map<String, dynamic>;
          if (data.containsKey('addressVisibility')) {
            setState(() {
              _addressVisibility = data['addressVisibility']?.toString() ?? 'private';
            });
          } else if (data.containsKey('isAddressPublic')) {
            setState(() {
              _addressVisibility = data['isAddressPublic'] == true ? 'address' : 'private';
            });
          }
        }
      } catch (_) {}
    });

    _profileSub = component.userRepository.watchUser(uid).listen((profile) {
      if (profile != null && mounted) {
        final bool isSelf = currentAuthUid == uid;
        final bool isManager = profile.isManaged && profile.managers.contains(currentAuthUid);
        final bool isStaff = _viewerAccount?.role == 'admin' ||
            _viewerAccount?.role == 'moderator' ||
            (_viewerAccount?.roles.contains('admin') ?? false) ||
            (_viewerAccount?.roles.contains('moderator') ?? false);

        final bool hasPermission = isSelf || isManager || isStaff;

        setState(() {
          _displayName = profile.displayName;
          _username = profile.username;
          _initialUsername = profile.username;
          _bio = profile.bio;
          _photoUrl = profile.photoUrl;
          _xHandle = profile.xHandle ?? '';
          _instagramHandle = profile.instagramHandle ?? '';
          _githubHandle = profile.githubHandle ?? '';
          _isManaged = profile.isManaged;
          _managers = List<String>.from(profile.managers);
          _isAuthorized = hasPermission;
          _loading = false;
        });

        // Upgrade legacy /edit-info paths to canonical vanity /@handle/edit-info
        if (hasPermission && kIsWeb && profile.username.isNotEmpty) {
          final currentPath = getCurrentPath();
          if (currentPath.startsWith('/edit-info')) {
            try {
              Router.of(context).replace('/@${profile.username}/edit-info');
            } catch (_) {}
          }
        }
      }
    });

    _accountSub = component.userRepository.watchUserAccount(uid).listen((account) {
      if (account != null && mounted) {
        setState(() {
          _firstName = account.firstName;
          _lastName = account.lastName;
          _street1 = account.street1 ?? '';
          _street2 = account.street2 ?? '';
          _city = account.city ?? '';
          _state = account.state ?? '';
          _zipCode = account.zipCode ?? '';
          _country = account.country ?? '';
          if (account.preferences.containsKey('addressVisibility')) {
            _addressVisibility = account.preferences['addressVisibility']?.toString() ?? 'private';
          } else if (account.preferences.containsKey('isAddressPublic')) {
            _addressVisibility = account.preferences['isAddressPublic'] == true ? 'address' : 'private';
          }
        });
      }
    });
  }

  String _cleanHandle(String raw) {
    return raw.trim().toLowerCase().replaceAll('@', '').replaceAll(RegExp(r'[^a-z0-9_-]'), '');
  }

  Future<void> _saveProfile() async {
    final uid = _editingUid;
    if (uid.isEmpty || _saving || !_isAuthorized) return;

    setState(() {
      _saving = true;
      _statusMessage = 'Saving profile info...';
      _isError = false;
    });

    try {
      final finalUsername = _cleanHandle(_username);

      // 1. Update public profile fields with selected geographic precision
      final publicData = <String, dynamic>{
        'displayName': _displayName.trim(),
        'bio': _bio.trim(),
        'photoUrl': _photoUrl.trim(),
        'xHandle': _cleanHandle(_xHandle),
        'instagramHandle': _cleanHandle(_instagramHandle),
        'githubHandle': _cleanHandle(_githubHandle),
        'addressVisibility': _addressVisibility,
        'isAddressPublic': _addressVisibility != 'private',
        'updatedAt': WebFieldValue.serverTimestamp(),
      };

      if (_isManaged) {
        publicData['managers'] = _managers;
      }

      switch (_addressVisibility) {
        case 'address':
          publicData['street1'] = _street1.trim();
          publicData['street2'] = _street2.trim();
          publicData['city'] = _city.trim();
          publicData['state'] = _state.trim();
          publicData['zipCode'] = _zipCode.trim();
          publicData['country'] = _country.trim();
          break;
        case 'city':
          publicData['street1'] = '';
          publicData['street2'] = '';
          publicData['city'] = _city.trim();
          publicData['state'] = _state.trim();
          publicData['zipCode'] = '';
          publicData['country'] = _country.trim();
          break;
        case 'state':
          publicData['street1'] = '';
          publicData['street2'] = '';
          publicData['city'] = '';
          publicData['state'] = _state.trim();
          publicData['zipCode'] = '';
          publicData['country'] = _country.trim();
          break;
        case 'private':
        default:
          publicData['street1'] = '';
          publicData['street2'] = '';
          publicData['city'] = '';
          publicData['state'] = '';
          publicData['zipCode'] = '';
          publicData['country'] = '';
          break;
      }

      if (finalUsername.isNotEmpty) {
        publicData['username'] = finalUsername;
      }
      await fsSetDoc('profiles/$uid', jsonEncode(publicData), true);

      // 2. Update private user account details (always preserves full address)
      final privateData = <String, dynamic>{
        'firstName': _firstName.trim(),
        'lastName': _lastName.trim(),
        'street1': _street1.trim(),
        'street2': _street2.trim(),
        'city': _city.trim(),
        'state': _state.trim(),
        'zipCode': _zipCode.trim(),
        'country': _country.trim(),
        'addressVisibility': _addressVisibility,
        'isAddressPublic': _addressVisibility != 'private',
        'preferences.addressVisibility': _addressVisibility,
        'preferences.isAddressPublic': _addressVisibility != 'private',
        'updatedAt': WebFieldValue.serverTimestamp(),
      };
      await fsSetDoc('Users/$uid', jsonEncode(privateData), true);

      // 3. Update username and shortcode mappings if handle was changed
      if (finalUsername.isNotEmpty && finalUsername != _initialUsername) {
        final checkRes = await fsGetDoc('usernames/$finalUsername');
        final checkDoc = jsonDecode(checkRes);
        if (checkDoc['exists'] == true && checkDoc['data']['uid'] != uid) {
          throw Exception('Username @$finalUsername is already taken by another user.');
        }
        await fsSetDoc('usernames/$finalUsername', jsonEncode({
          'uid': uid,
          'isManaged': _isManaged,
          'createdAt': WebFieldValue.serverTimestamp(),
        }), true);
        await fsSetDoc('shortcodes/${finalUsername.toUpperCase()}', jsonEncode({
          'type': 'user',
          'contentId': uid,
          'displayCode': finalUsername,
          'createdAt': WebFieldValue.serverTimestamp(),
        }), true);
      }

      if (mounted) {
        setState(() {
          _saving = false;
          _statusMessage = 'Profile updated successfully!';
          _isError = false;
          _initialUsername = finalUsername;
        });

        // Navigate back to the canonical profile page using the @username format
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            final targetPath = finalUsername.isNotEmpty ? '/@$finalUsername' : '/profile';
            Router.of(context).push(targetPath);
          }
        });
      }
    } catch (e) {
      print('[EDIT INFO ERROR] Save failed: $e');
      if (mounted) {
        setState(() {
          _saving = false;
          _statusMessage = 'Failed to save: ${e.toString().replaceAll('Exception:', '').trim()}';
          _isError = true;
        });
      }
    }
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(
        classes: 'flex-col items-center justify-center w-full',
        attributes: const {'style': 'min-height: 100vh; background-color: #e5e5e5;'},
        [p([Component.text('Loading profile details...')])],
      );
    }

    // Access Denied Shield for Unauthorized Viewers
    if (!_isAuthorized) {
      return div(
        classes: 'flex-col items-center justify-center w-full py-16 px-4',
        attributes: const {
          'style': 'min-height: 100vh; background-color: #e5e5e5; box-sizing: border-box;'
        },
        [
          div(
            classes: 'manila-envelope shadow-md',
            attributes: const {
              'style': 'max-width: 440px; border-radius: 12px; overflow: hidden; padding: 24px;'
            },
            [
              div(
                classes: 'white-sticker p-8 text-center flex-col items-center gap-4',
                attributes: const {
                  'style': 'padding: 32px 24px; display: flex; flex-direction: column; align-items: center; width: 100%; box-sizing: border-box; background: white; border-radius: 8px;'
                },
                [
                  span(
                    [Component.text('lock')],
                    classes: 'material-symbols-outlined',
                    attributes: const {'style': 'font-size: 48px; color: #ef4444; margin-bottom: 8px;'},
                  ),
                  h2([Component.text('Access Denied')], classes: 'font-bold text-base text-black mb-2'),
                  p(
                    [Component.text('You do not have permission to manage or edit this profile.')],
                    classes: 'text-xs text-gray mb-4',
                    attributes: const {'style': 'margin: 0 0 16px 0; text-align: center; color: #666;'},
                  ),
                  a(
                    [Component.text(_username.isNotEmpty ? 'Return to @$_username' : 'Return Home')],
                    href: _username.isNotEmpty ? '/@$_username' : '/',
                    classes: 'btn-primary nav-pill mb-0',
                    attributes: const {
                      'style': 'display: inline-flex; align-items: center; justify-content: center; padding: 8px 20px; font-size: 12px; font-weight: bold; background-color: #6750A4; color: white; text-decoration: none; border-radius: 50px;'
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      );
    }

    return div(
      classes: 'flex-col items-center justify-start w-full py-8 px-4',
      attributes: const {
        'style': 'min-height: 100vh; background-color: #e5e5e5; box-sizing: border-box;'
      },
      [
        div(
          classes: 'unified-profile-column',
          [
            div(
              classes: 'manila-envelope-flexible rounded-lg p-6 shadow-md',
              attributes: const {'style': 'width: 100%; border-radius: 12px;'},
              [
                div(
                  classes: 'white-sticker-flexible w-full p-6 bg-white rounded-lg shadow-sm',
                  attributes: const {'style': 'width: 100%; padding: 24px; box-sizing: border-box; background: white; border-radius: 8px;'},
                  [
                    // --- SECTION 1: PUBLIC PROFILE DETAILS ---
                    h2([Component.text('PUBLIC PROFILE')], classes: 'text-xs font-bold text-gray uppercase tracking-wider mb-3 mt-0'),
                    div(classes: 'flex-col gap-3 w-full mb-6', [
                      div([
                        span([Component.text('Display Name')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                        input(
                          attributes: {'type': 'text', 'placeholder': 'Jane Doe', 'value': _displayName, 'style': 'margin-bottom: 0; background: white;'},
                          events: {'input': (e) => setState(() => _displayName = getInputValue(e))},
                        )
                      ]),
                      div([
                        span([Component.text('Username / Handle')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                        input(
                          attributes: {'type': 'text', 'placeholder': 'janedoe', 'value': _username, 'style': 'margin-bottom: 0; background: white;'},
                          events: {'input': (e) => setState(() => _username = getInputValue(e))},
                        )
                      ]),
                      div([
                        span([Component.text('Biography')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                        textarea(
                            classes: 'border border-gray-300 rounded-md',
                            attributes: {
                              'placeholder': 'Tell the community about yourself...',
                              'style': 'width: 100%; min-height: 70px; font-size: 13px; background: white; margin-bottom: 0;',
                            },
                            events: {'input': (e) => setState(() => _bio = getInputValue(e))},
                            [Component.text(_bio)]
                        )
                      ]),
                      div([
                        span([Component.text('Profile Photo URL')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                        input(
                          attributes: {'type': 'text', 'placeholder': 'https://example.com/avatar.jpg', 'value': _photoUrl, 'style': 'margin-bottom: 0; background: white;'},
                          events: {'input': (e) => setState(() => _photoUrl = getInputValue(e))},
                        )
                      ]),
                    ]),
                    div([], attributes: const {'style': 'height: 1px; background: #eee; margin: 16px 0;'}),

                    // --- SECTION 2: PROFILE MANAGERS (MANAGED PROFILES ONLY) ---
                    if (_isManaged) ...[
                      _buildManagersSection(),
                      div([], attributes: const {'style': 'height: 1px; background: #eee; margin: 16px 0;'}),
                    ],

                    // --- SECTION 3: SOCIAL MEDIA HANDLES ---
                    h2([Component.text('EXTERNAL SOCIALS')], classes: 'text-xs font-bold text-gray uppercase tracking-wider mb-3 mt-0'),
                    div(classes: 'flex-col gap-3 w-full mb-6', [
                      div([
                        span([Component.text('X / Twitter Handle')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                        input(
                          attributes: {'type': 'text', 'placeholder': '@handle', 'value': _xHandle, 'style': 'margin-bottom: 0; background: white;'},
                          events: {'input': (e) => setState(() => _xHandle = getInputValue(e))},
                        )
                      ]),
                      div([
                        span([Component.text('Instagram Handle')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                        input(
                          attributes: {'type': 'text', 'placeholder': '@handle', 'value': _instagramHandle, 'style': 'margin-bottom: 0; background: white;'},
                          events: {'input': (e) => setState(() => _instagramHandle = getInputValue(e))},
                        )
                      ]),
                      div([
                        span([Component.text('GitHub Handle')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                        input(
                          attributes: {'type': 'text', 'placeholder': 'username', 'value': _githubHandle, 'style': 'margin-bottom: 0; background: white;'},
                          events: {'input': (e) => setState(() => _githubHandle = getInputValue(e))},
                        )
                      ]),
                    ]),
                    div([], attributes: const {'style': 'height: 1px; background: #eee; margin: 16px 0;'}),

                    // --- SECTION 3: PERSONAL & MAILING DETAILS ---
                    div(
                      classes: 'flex-row justify-between items-center mb-3 mt-0',
                      attributes: const {
                        'style': 'display: flex; flex-direction: row; justify-content: space-between; align-items: center; width: 100%; flex-wrap: wrap; gap: 8px;'
                      },
                      [
                        h2(
                          [
                            Component.text(
                                  () {
                                switch (_addressVisibility) {
                                  case 'address':
                                    return 'PERSONAL & MAILING DETAILS - FULL ADDRESS PUBLIC';
                                  case 'city':
                                    return 'PERSONAL & MAILING DETAILS - CITY & STATE PUBLIC';
                                  case 'state':
                                    return 'PERSONAL & MAILING DETAILS - STATE PUBLIC';
                                  case 'private':
                                  default:
                                    return 'PERSONAL & MAILING DETAILS - NOT DISPLAYED PUBLICLY';
                                }
                              }(),
                            )
                          ],
                          classes: 'text-xs font-bold text-gray uppercase tracking-wider mb-0 mt-0',
                          attributes: const {'style': 'margin: 0; font-size: 11px;'},
                        ),
                        // 4-Option Segmented Button: [address | city | state | private] defaulting to private
                        SegmentedButton<String>(
                          segments: const ['address', 'city', 'state', 'private'],
                          selected: _addressVisibility,
                          labelBuilder: (val) => val,
                          showSelectedCheckmark: true,
                          onSelectionChanged: (val) {
                            setState(() {
                              _addressVisibility = val;
                            });
                          },
                        ),
                      ],
                    ),
                    div(classes: 'flex-col gap-3 w-full mb-6', [
                      div(classes: 'flex-row gap-2', attributes: const {'style': 'display: flex; gap: 8px; width: 100%;'}, [
                        div(classes: 'flex-1', [
                          span([Component.text('First Name')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                          input(
                            attributes: {'type': 'text', 'placeholder': 'First Name', 'value': _firstName, 'style': 'margin-bottom: 0; background: white;'},
                            events: {'input': (e) => setState(() => _firstName = getInputValue(e))},
                          )
                        ]),
                        div(classes: 'flex-1', [
                          span([Component.text('Last Name')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                          input(
                            attributes: {'type': 'text', 'placeholder': 'Last Name', 'value': _lastName, 'style': 'margin-bottom: 0; background: white;'},
                            events: {'input': (e) => setState(() => _lastName = getInputValue(e))},
                          )
                        ]),
                      ]),
                      div([
                        span([Component.text('Street Address Line 1')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                        input(
                          attributes: {'type': 'text', 'placeholder': '123 Main St', 'value': _street1, 'style': 'margin-bottom: 0; background: white;'},
                          events: {'input': (e) => setState(() => _street1 = getInputValue(e))},
                        )
                      ]),
                      div([
                        span([Component.text('Street Address Line 2')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                        input(
                          attributes: {'type': 'text', 'placeholder': 'Apt / Suite / Unit', 'value': _street2, 'style': 'margin-bottom: 0; background: white;'},
                          events: {'input': (e) => setState(() => _street2 = getInputValue(e))},
                        )
                      ]),
                      div(classes: 'flex-row gap-2', attributes: const {'style': 'display: flex; gap: 8px; width: 100%;'}, [
                        div(classes: 'flex-1', [
                          span([Component.text('City')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                          input(
                            attributes: {'type': 'text', 'placeholder': 'City', 'value': _city, 'style': 'margin-bottom: 0; background: white;'},
                            events: {'input': (e) => setState(() => _city = getInputValue(e))},
                          )
                        ]),
                        div(classes: 'flex-1', [
                          span([Component.text('State / Province')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                          input(
                            attributes: {'type': 'text', 'placeholder': 'State', 'value': _state, 'style': 'margin-bottom: 0; background: white;'},
                            events: {'input': (e) => setState(() => _state = getInputValue(e))},
                          )
                        ]),
                      ]),
                      div(classes: 'flex-row gap-2', attributes: const {'style': 'display: flex; gap: 8px; width: 100%;'}, [
                        div(classes: 'flex-1', [
                          span([Component.text('ZIP / Postal Code')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                          input(
                            attributes: {'type': 'text', 'placeholder': 'ZIP Code', 'value': _zipCode, 'style': 'margin-bottom: 0; background: white;'},
                            events: {'input': (e) => setState(() => _zipCode = getInputValue(e))},
                          )
                        ]),
                        div(classes: 'flex-1', [
                          span([Component.text('Country')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                          input(
                            attributes: {'type': 'text', 'placeholder': 'Country', 'value': _country, 'style': 'margin-bottom: 0; background: white;'},
                            events: {'input': (e) => setState(() => _country = getInputValue(e))},
                          )
                        ]),
                      ]),
                    ]),

                    // Status Message Feedback Bar
                    if (_statusMessage != null)
                      p(
                        [Component.text(_statusMessage!)],
                        classes: _isError ? 'text-xs font-bold text-red-500 mb-3' : 'text-xs font-bold text-green-600 mb-3',
                        attributes: {
                          'style': 'color: ${_isError ? "#ef4444" : "#16a34a"}; margin-bottom: 12px; font-weight: bold; text-align: center;'
                        },
                      ),

                    // Action Button Bar
                    div(
                      classes: 'flex-row justify-end gap-3 mt-4',
                      attributes: const {'style': 'display: flex; justify-content: flex-end; gap: 12px; margin-top: 16px;'},
                      [
                        button(
                          [Component.text('cancel')],
                          classes: 'profile-btn',
                          attributes: const {
                            'type': 'button',
                            'style': 'padding: 10px 20px; font-size: 12px; font-weight: bold; border: 1px solid #ccc; background: white; cursor: pointer;'
                          },
                          events: {
                            'click': (e) {
                              if (_username.isNotEmpty) {
                                Router.of(context).push('/@$_username');
                              } else {
                                Router.of(context).push('/profile');
                              }
                            }
                          },
                        ),
                        button(
                          [Component.text(_saving ? 'saving...' : 'save changes')],
                          classes: 'btn-primary nav-pill mb-0',
                          attributes: {
                            'type': 'button',
                            'style': 'padding: 10px 24px; font-size: 12px; font-weight: bold; background-color: #6750A4; border: none; border-radius: 50px; color: white; cursor: pointer;',
                            if (_saving) 'disabled': 'true',
                          },
                          events: {
                            'click': (e) => _saveProfile(),
                          },
                        )
                      ],
                    )
                  ],
                )
              ],
            )
          ],
        )
      ],
    );
  }

  Component _buildManagersSection() {
    final List<Map<String, dynamic>> filtered = _allProfiles.where((p) {
      final q = _managerSearchQuery.trim().toLowerCase();
      if (q.isEmpty) return true;
      final name = (p['displayName'] ?? '').toString().toLowerCase();
      final user = (p['username'] ?? '').toString().toLowerCase();
      return name.contains(q) || user.contains(q);
    }).toList();

    return div(
      classes: 'flex-col',
      attributes: const {
        'style': 'position: relative; width: 100%; box-sizing: border-box;'
      },
      [
        div(
          attributes: const {
            'style': 'display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 6px;'
          },
          [
            h2(
              [Component.text('PROFILE MANAGERS')],
              classes: 'text-xs font-bold text-gray uppercase tracking-wider mb-0 mt-0',
              attributes: const {'style': 'margin: 0;'},
            ),
            span(
              [Component.text('${_managers.length} assigned')],
              attributes: const {'style': 'font-size: 10px; color: #888;'},
            ),
          ],
        ),
        p(
          [Component.text('Users authorized to edit this managed profile, update historical metadata, and curate associated assets.')],
          classes: 'text-xs text-gray-500 mb-3',
          attributes: const {'style': 'margin: 0 0 10px 0; font-size: 11px; color: #666;'},
        ),
        // Selected Manager Chips Container
        if (_managers.isNotEmpty)
          div(
            attributes: const {
              'style': 'display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 10px; width: 100%; box-sizing: border-box;'
            },
            [
              for (var uid in _managers) _buildManagerChip(uid),
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
                'placeholder': 'search user or @handle to add manager...',
                'value': _managerSearchQuery,
                'style': 'width: 100%; padding: 8px 12px; border: 1px solid #ccc; border-radius: 6px; box-sizing: border-box; font-size: 12px; background: white; outline: none; margin-bottom: 0;',
              },
              events: {
                'focus': (e) => setState(() => _managerDropdownOpen = true),
                'input': (e) {
                  setState(() {
                    _managerSearchQuery = getInputValue(e);
                    _managerDropdownOpen = true;
                  });
                },
              },
            ),
            if (_managerDropdownOpen)
              button(
                [span([Component.text('close')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px;'})],
                attributes: const {
                  'type': 'button',
                  'style': 'position: absolute; right: 8px; top: 50%; transform: translateY(-50%); border: none; background: transparent; cursor: pointer; color: #888; padding: 2px;'
                },
                events: {'click': (e) => setState(() => _managerDropdownOpen = false)},
              ),
          ],
        ),
        // Backdrop to dismiss dropdown on click outside
        if (_managerDropdownOpen)
          div(
            attributes: const {
              'style': 'position: fixed; top: 0; left: 0; right: 0; bottom: 0; z-index: 99;'
            },
            events: {'click': (e) => setState(() => _managerDropdownOpen = false)},
            [],
          ),
        // Dropdown Results Menu
        if (_managerDropdownOpen)
          div(
            attributes: const {
              'style': 'position: absolute; top: calc(100% + 4px); left: 0; right: 0; max-height: 220px; overflow-y: auto; background: white; border: 1px solid #ccc; border-radius: 6px; box-shadow: 0 4px 12px rgba(0,0,0,0.15); z-index: 100; box-sizing: border-box;'
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
                for (var profile in filtered) _buildProfileOptionRow(profile),
            ],
          ),
      ],
    );
  }

  Component _buildManagerChip(String uid) {
    final profile = _allProfiles.firstWhere(
          (p) => (p['uid'] == uid || p['id'] == uid),
      orElse: () => {'displayName': uid, 'username': ''},
    );
    final String displayName = (profile['displayName'] ?? '').toString().isNotEmpty
        ? profile['displayName']
        : (profile['username'] ?? uid);
    final String? photoUrl = profile['photoUrl'];
    final bool canRemove = _managers.length > 1;

    return div(
      attributes: const {
        'style': 'display: inline-flex; align-items: center; gap: 6px; background: #E8DEF8; color: #1D192B; border: 1px solid #D0BCFF; border-radius: 16px; padding: 2px 8px 2px 4px; font-size: 11px; font-weight: 500;'
      },
      [
        div(
          attributes: const {
            'style': 'width: 20px; height: 20px; border-radius: 50%; overflow: hidden; background: #fff; display: flex; align-items: center; justify-content: center; flex-shrink: 0;'
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
        if (canRemove)
          button(
            [span([Component.text('close')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px;'})],
            attributes: const {
              'type': 'button',
              'title': 'Remove manager',
              'style': 'border: none; background: transparent; cursor: pointer; color: #1D192B; padding: 0; display: inline-flex; align-items: center;'
            },
            events: {
              'click': (e) {
                setState(() {
                  _managers.remove(uid);
                });
              }
            },
          ),
      ],
    );
  }

  Component _buildProfileOptionRow(Map<String, dynamic> profile) {
    final String uid = profile['uid'] ?? profile['id'] ?? '';
    final String displayName = profile['displayName'] ?? profile['username'] ?? 'User';
    final String username = profile['username'] ?? '';
    final String? photoUrl = profile['photoUrl'];
    final bool isSelected = _managers.contains(uid);

    return div(
      attributes: {
        'style':
        'display: flex; align-items: center; justify-content: space-between; padding: 8px 12px; cursor: pointer; border-bottom: 1px solid #f0f0f0; transition: background 0.15s; '
            'background: ${isSelected ? "rgba(103, 80, 164, 0.08)" : "white"};'
      },
      events: {
        'click': (e) {
          setState(() {
            if (isSelected) {
              if (_managers.length > 1) {
                _managers.remove(uid);
              }
            } else {
              _managers.add(uid);
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
                'style': 'width: 26px; height: 26px; border-radius: 50%; overflow: hidden; background: #eee; display: flex; align-items: center; justify-content: center; flex-shrink: 0;'
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
        span(
          classes: 'material-symbols-outlined',
          attributes: {
            'style': 'font-size: 18px; color: ${isSelected ? "#6750A4" : "#ccc"};'
          },
          [Component.text(isSelected ? 'check_box' : 'check_box_outline_blank')],
        ),
      ],
    );
  }
}