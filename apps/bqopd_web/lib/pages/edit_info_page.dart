import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import '../utils/web_utils.dart';

/// Full-featured Web Profile & Account Editor Page for Jaspr.
/// Supports updating public profile metadata, social media handles,
/// photo avatar URLs, and private contact/address information.
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

  // User Private Account Fields
  String _firstName = '';
  String _lastName = '';
  String _email = '';
  String _street1 = '';
  String _street2 = '';
  String _city = '';
  String _state = '';
  String _zipCode = '';
  String _country = '';

  StreamSubscription? _profileSub;
  StreamSubscription? _accountSub;

  String get _editingUid =>
      component.targetUserId ?? component.authState?.user?.uid ?? getCurrentUserId() ?? '';

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loadData();
    }
  }

  @override
  void didUpdateComponent(EditInfoPage oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.targetUserId != component.targetUserId ||
        oldComponent.authState?.user?.uid != component.authState?.user?.uid) {
      _loadData();
    }
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _accountSub?.cancel();
    super.dispose();
  }

  void _loadData() {
    final uid = _editingUid;
    if (uid.isEmpty) {
      setState(() {
        _loading = false;
        _statusMessage = 'Authentication required to edit profile info.';
        _isError = true;
      });
      return;
    }

    setState(() => _loading = true);

    _profileSub?.cancel();
    _accountSub?.cancel();

    _profileSub = component.userRepository.watchUser(uid).listen((profile) {
      if (profile != null && mounted) {
        setState(() {
          _displayName = profile.displayName;
          _username = profile.username;
          _initialUsername = profile.username;
          _bio = profile.bio;
          _photoUrl = profile.photoUrl;
          _xHandle = profile.xHandle ?? '';
          _instagramHandle = profile.instagramHandle ?? '';
          _githubHandle = profile.githubHandle ?? '';
          _loading = false;
        });
      }
    });

    _accountSub = component.userRepository.watchUserAccount(uid).listen((account) {
      if (account != null && mounted) {
        setState(() {
          _email = account.email;
          _firstName = account.firstName;
          _lastName = account.lastName;
          _street1 = account.street1 ?? '';
          _street2 = account.street2 ?? '';
          _city = account.city ?? '';
          _state = account.state ?? '';
          _zipCode = account.zipCode ?? '';
          _country = account.country ?? '';
        });
      }
    });
  }

  String _cleanHandle(String raw) {
    return raw.trim().toLowerCase().replaceAll('@', '').replaceAll(RegExp(r'[^a-z0-9_-]'), '');
  }

  Future<void> _saveProfile() async {
    final uid = _editingUid;
    if (uid.isEmpty || _saving) return;

    setState(() {
      _saving = true;
      _statusMessage = 'Saving profile info...';
      _isError = false;
    });

    try {
      final finalUsername = _cleanHandle(_username);

      // 1. Update public profile fields
      final publicData = <String, dynamic>{
        'displayName': _displayName.trim(),
        'bio': _bio.trim(),
        'photoUrl': _photoUrl.trim(),
        'xHandle': _cleanHandle(_xHandle),
        'instagramHandle': _cleanHandle(_instagramHandle),
        'githubHandle': _cleanHandle(_githubHandle),
        'updatedAt': WebFieldValue.serverTimestamp(),
      };

      if (finalUsername.isNotEmpty) {
        publicData['username'] = finalUsername;
      }

      await fsSetDoc('profiles/$uid', jsonEncode(publicData), true);

      // 2. Update private user account details
      final privateData = <String, dynamic>{
        'firstName': _firstName.trim(),
        'lastName': _lastName.trim(),
        'street1': _street1.trim(),
        'street2': _street2.trim(),
        'city': _city.trim(),
        'state': _state.trim(),
        'zipCode': _zipCode.trim(),
        'country': _country.trim(),
        'updatedAt': WebFieldValue.serverTimestamp(),
      };

      await fsSetDoc('Users/$uid', jsonEncode(privateData), true);

      // 3. Update username mapping if handle was changed
      if (finalUsername.isNotEmpty && finalUsername != _initialUsername) {
        final checkRes = await fsGetDoc('usernames/$finalUsername');
        final checkDoc = jsonDecode(checkRes);
        if (checkDoc['exists'] == true && checkDoc['data']['uid'] != uid) {
          throw Exception('Username @$finalUsername is already taken by another user.');
        }

        await fsSetDoc('usernames/$finalUsername', jsonEncode({
          'uid': uid,
          'isManaged': false,
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

        // Navigate back to profile page after confirmation
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            final targetPath = finalUsername.isNotEmpty ? '/$finalUsername' : '/profile';
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
        [p([text('Loading profile details...')])],
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
                // Sticker Body
                div(
                  classes: 'white-sticker-flexible w-full p-6 bg-white rounded-lg shadow-sm',
                  attributes: const {'style': 'width: 100%; padding: 24px; box-sizing: border-box; background: white; border-radius: 8px;'},
                  [
                    // --- SECTION 1: PUBLIC PROFILE DETAILS ---
                    h2([text('PUBLIC PROFILE')], classes: 'text-xs font-bold text-gray uppercase tracking-wider mb-3 mt-0'),

                    div(classes: 'flex-col gap-3 w-full mb-6', [
                      div([
                        span([text('Display Name')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                        input(
                          attributes: {'type': 'text', 'placeholder': 'Jane Doe', 'value': _displayName, 'style': 'margin-bottom: 0; background: white;'},
                          events: {'input': (e) => setState(() => _displayName = getInputValue(e))},
                        )
                      ]),

                      div([
                        span([text('Username / Handle')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                        input(
                          attributes: {'type': 'text', 'placeholder': 'janedoe', 'value': _username, 'style': 'margin-bottom: 0; background: white;'},
                          events: {'input': (e) => setState(() => _username = getInputValue(e))},
                        )
                      ]),

                      div([
                        span([text('Biography')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                        textarea(
                            classes: 'border border-gray-300 rounded-md',
                            attributes: {
                              'placeholder': 'Tell the community about yourself...',
                              'style': 'width: 100%; min-height: 70px; font-size: 13px; background: white; margin-bottom: 0;',
                            },
                            events: {'input': (e) => setState(() => _bio = getInputValue(e))},
                            [text(_bio)]
                        )
                      ]),

                      div([
                        span([text('Profile Photo URL')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                        input(
                          attributes: {'type': 'text', 'placeholder': 'https://example.com/avatar.jpg', 'value': _photoUrl, 'style': 'margin-bottom: 0; background: white;'},
                          events: {'input': (e) => setState(() => _photoUrl = getInputValue(e))},
                        )
                      ]),
                    ]),

                    div([], attributes: const {'style': 'height: 1px; background: #eee; margin: 16px 0;'}),

                    // --- SECTION 2: SOCIAL MEDIA HANDLES ---
                    h2([text('EXTERNAL SOCIALS')], classes: 'text-xs font-bold text-gray uppercase tracking-wider mb-3 mt-0'),

                    div(classes: 'flex-col gap-3 w-full mb-6', [
                      div([
                        span([text('X / Twitter Handle')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                        input(
                          attributes: {'type': 'text', 'placeholder': '@handle', 'value': _xHandle, 'style': 'margin-bottom: 0; background: white;'},
                          events: {'input': (e) => setState(() => _xHandle = getInputValue(e))},
                        )
                      ]),

                      div([
                        span([text('Instagram Handle')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                        input(
                          attributes: {'type': 'text', 'placeholder': '@handle', 'value': _instagramHandle, 'style': 'margin-bottom: 0; background: white;'},
                          events: {'input': (e) => setState(() => _instagramHandle = getInputValue(e))},
                        )
                      ]),

                      div([
                        span([text('GitHub Handle')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                        input(
                          attributes: {'type': 'text', 'placeholder': 'username', 'value': _githubHandle, 'style': 'margin-bottom: 0; background: white;'},
                          events: {'input': (e) => setState(() => _githubHandle = getInputValue(e))},
                        )
                      ]),
                    ]),

                    div([], attributes: const {'style': 'height: 1px; background: #eee; margin: 16px 0;'}),

                    // --- SECTION 3: PERSONAL & CONTACT INFORMATION ---
                    h2([text('PERSONAL & MAILING DETAILS - NOT DISPLAYED PUBLICLY')], classes: 'text-xs font-bold text-gray uppercase tracking-wider mb-3 mt-0'),

                    div(classes: 'flex-col gap-3 w-full mb-6', [
                      div(classes: 'flex-row gap-2', attributes: const {'style': 'display: flex; gap: 8px; width: 100%;'}, [
                        div(classes: 'flex-1', [
                          span([text('First Name')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                          input(
                            attributes: {'type': 'text', 'placeholder': 'First Name', 'value': _firstName, 'style': 'margin-bottom: 0; background: white;'},
                            events: {'input': (e) => setState(() => _firstName = getInputValue(e))},
                          )
                        ]),
                        div(classes: 'flex-1', [
                          span([text('Last Name')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                          input(
                            attributes: {'type': 'text', 'placeholder': 'Last Name', 'value': _lastName, 'style': 'margin-bottom: 0; background: white;'},
                            events: {'input': (e) => setState(() => _lastName = getInputValue(e))},
                          )
                        ]),
                      ]),

                      div([
                        span([text('Street Address Line 1')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                        input(
                          attributes: {'type': 'text', 'placeholder': '123 Main St', 'value': _street1, 'style': 'margin-bottom: 0; background: white;'},
                          events: {'input': (e) => setState(() => _street1 = getInputValue(e))},
                        )
                      ]),

                      div([
                        span([text('Street Address Line 2')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                        input(
                          attributes: {'type': 'text', 'placeholder': 'Apt / Suite / Unit', 'value': _street2, 'style': 'margin-bottom: 0; background: white;'},
                          events: {'input': (e) => setState(() => _street2 = getInputValue(e))},
                        )
                      ]),

                      div(classes: 'flex-row gap-2', attributes: const {'style': 'display: flex; gap: 8px; width: 100%;'}, [
                        div(classes: 'flex-1', [
                          span([text('City')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                          input(
                            attributes: {'type': 'text', 'placeholder': 'City', 'value': _city, 'style': 'margin-bottom: 0; background: white;'},
                            events: {'input': (e) => setState(() => _city = getInputValue(e))},
                          )
                        ]),
                        div(classes: 'flex-1', [
                          span([text('State / Province')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                          input(
                            attributes: {'type': 'text', 'placeholder': 'State', 'value': _state, 'style': 'margin-bottom: 0; background: white;'},
                            events: {'input': (e) => setState(() => _state = getInputValue(e))},
                          )
                        ]),
                      ]),

                      div(classes: 'flex-row gap-2', attributes: const {'style': 'display: flex; gap: 8px; width: 100%;'}, [
                        div(classes: 'flex-1', [
                          span([text('ZIP / Postal Code')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
                          input(
                            attributes: {'type': 'text', 'placeholder': 'ZIP Code', 'value': _zipCode, 'style': 'margin-bottom: 0; background: white;'},
                            events: {'input': (e) => setState(() => _zipCode = getInputValue(e))},
                          )
                        ]),
                        div(classes: 'flex-1', [
                          span([text('Country')], classes: 'text-xs font-bold text-gray-600 block mb-1'),
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
                        [text(_statusMessage!)],
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
                          [text('cancel')],
                          classes: 'profile-btn',
                          attributes: const {
                            'type': 'button',
                            'style': 'padding: 10px 20px; font-size: 12px; font-weight: bold; border: 1px solid #ccc; background: white; cursor: pointer;'
                          },
                          events: {
                            'click': (e) {
                              if (_username.isNotEmpty) {
                                Router.of(context).push('/$_username');
                              } else {
                                Router.of(context).push('/profile');
                              }
                            }
                          },
                        ),
                        button(
                          [text(_saving ? 'saving...' : 'save changes')],
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
}