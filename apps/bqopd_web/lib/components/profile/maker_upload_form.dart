import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';
import '../../repositories/repositories.dart';

/// Clean BLoC-driven Maker Upload Form for publishing independent/single images.
/// Eliminates direct, low-level GCS storage uploads and Firestore mutations from the UI,
/// routing them through the core [UploadBloc] and [IUploadRepository].
class MakerUploadForm extends StatefulComponent {
  final String targetUserId;
  final AuthState? authState;
  final VoidCallback onBack;
  final ValueChanged<String> onUploadComplete;

  const MakerUploadForm({
    required this.targetUserId,
    this.authState,
    required this.onBack,
    required this.onUploadComplete,
    super.key,
  });

  @override
  State<MakerUploadForm> createState() => _MakerUploadFormState();
}

class _MakerUploadFormState extends State<MakerUploadForm> {
  late final UploadBloc _uploadBloc;
  StreamSubscription<UploadState>? _blocSubscription;
  UploadState _blocState = const UploadState();

  // Local controller states to manage metadata edits prior to starting upload
  String _title = "";
  String _caption = "";
  String _indicia = "";
  String _roleInput = "";
  String _creatorHandleInput = "";

  // Temporary local storage references for selected files
  String? _selectedFileName;
  String? _selectedObjectUrl;
  int _imageWidth = 0;
  int _imageHeight = 0;

  @override
  void initState() {
    super.initState();
    _initUploadBloc();
  }

  void _initUploadBloc() {
    _uploadBloc = UploadBloc(
      repository: createUploadRepository(),
    );

    _blocSubscription = _uploadBloc.stream.listen((state) {
      if (mounted) {
        setState(() {
          _blocState = state;
        });

        // SUCCESS ROUTING TRIGGER: When the BLoC successfully publishes, retrieve the newly created shortcode
        if (state.status == UploadStatus.success) {
          _resolveNewShortcodeAndComplete();
        }
      }
    });
  }

  @override
  void dispose() {
    _blocSubscription?.cancel();
    _uploadBloc.close();
    super.dispose();
  }

  void _triggerFileSelection() {
    triggerFilePicker('single-asset-maker-picker', (base64, fileName, objectUrl) async {
      try {
        final dims = await getImageDimensions(objectUrl);
        final Uint8List bytes = base64Decode(base64);

        if (mounted) {
          setState(() {
            _selectedFileName = fileName;
            _selectedObjectUrl = objectUrl;
            _imageWidth = dims['width'] ?? 0;
            _imageHeight = dims['height'] ?? 0;

            // Default title to file name if empty
            if (_title.isEmpty) {
              _title = fileName.split('.').first;
            }
          });

          // Dispatches selection directly to the core UploadBloc
          _uploadBloc.add(ImagePicked(bytes, fileName));
        }
      } catch (e) {
        print("Error analyzing file parameters: $e");
      }
    });
  }

  void _addCreator() {
    final handle = _creatorHandleInput.trim();
    final role = _roleInput.trim();
    if (handle.isEmpty) return;

    _uploadBloc.add(AddCreatorRequested(handle, role.isNotEmpty ? role : 'Contributor'));
    setState(() {
      _creatorHandleInput = '';
      _roleInput = '';
    });
  }

  void _startPublishFlow() {
    if (_blocState.imageBytes == null) return;

    _uploadBloc.add(SubmitUploadRequested(
      userId: component.targetUserId,
      title: _title.trim(),
      caption: _caption.trim(),
      indicia: _indicia.trim(),
      creators: _blocState.creators,
    ));
  }

  void _resolveNewShortcodeAndComplete() {
    // Queries the latest uploaded image metadata record to retrieve the newly assigned shortcode
    fsQuery('images', 'uploaderId', '==', jsonEncode(component.targetUserId), 'timestamp').then((jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        if (decoded.isNotEmpty) {
          final latestImage = decoded.last;
          final Map<String, dynamic> data = latestImage['data'] as Map<String, dynamic>;
          final String shortcode = data['shortCode'] ?? latestImage['id'] ?? '';
          component.onUploadComplete(shortcode);
        } else {
          component.onUploadComplete('');
        }
      } catch (e) {
        print("Error resolving new shortcode: $e");
        component.onUploadComplete('');
      }
    });
  }

  @override
  Component build(BuildContext context) {
    final status = _blocState.status;
    final isUploading = status == UploadStatus.submitting;
    final errorMessage = _blocState.errorMessage;
    final hasImage = _blocState.imageBytes != null;

    return div(
        [
          // Navigation Header row
          div(
            [
              button(
                  [
                    span([text('arrow_back')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 18px; margin-right: 4px;'}),
                    text('options')
                  ],
                  classes: 'profile-btn mb-0',
                  attributes: const {'style': 'display: inline-flex; align-items: center; border: 1px solid #ddd; background: white; cursor: pointer; padding: 4px 12px; font-weight: bold; font-size: 11px; height: 32px;'},
                  events: {'click': (e) => component.onBack()}
              ),
              h2([text("publish single image")], classes: 'font-bold text-sm text-black', attributes: const {'style': 'margin: 0; margin-left: auto; text-transform: lowercase; font-variant: small-caps;'})
            ],
            attributes: const {'style': 'display: flex; align-items: center; width: 100%; margin-bottom: 20px;'},
          ),

          div(
              [
                // 1. Selector container
                div(
                    [
                      if (_selectedObjectUrl != null)
                        img(
                            src: _selectedObjectUrl!,
                            attributes: const {
                              'style': 'width: 100%; height: 100%; object-fit: contain; display: block;'
                            }
                        )
                      else
                        div(
                            [
                              span([text('add_photo_alternate')], classes: 'material-symbols-outlined text-gray-400', attributes: const {'style': 'font-size: 48px;'}),
                              p([text("Click to select image file from device")], attributes: const {'style': 'font-size: 11px; color: #777; font-weight: bold; margin-top: 8px; margin-bottom: 0;'})
                            ],
                            attributes: const {
                              'style': 'display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; padding: 20px; box-sizing: border-box;'
                            }
                        )
                    ],
                    attributes: {
                      'style': 'width: 100%; aspect-ratio: 16/10; border: 2px dashed #ccc; border-radius: 8px; background-color: #fcfcfc; overflow: hidden; position: relative; cursor: pointer; display: flex; align-items: center; justify-content: center; box-sizing: border-box;',
                    },
                    events: {
                      'click': (e) {
                        if (!isUploading) _triggerFileSelection();
                      }
                    }
                ),

                if (_selectedFileName != null)
                  div(
                      [
                        span([text('file_present')], classes: 'material-symbols-outlined text-gray-500', attributes: const {'style': 'font-size: 16px; margin-right: 4px;'}),
                        span([text("Selected: $_selectedFileName ($_imageWidth × $_imageHeight)")])
                      ],
                      attributes: const {
                        'style': 'display: flex; align-items: center; font-size: 11px; color: #555; margin-top: 6px; padding: 0 4px;'
                      }
                  ),

                div([], attributes: const {'style': 'height: 16px;'}),

                // 2. Details Inputs Form
                div(
                    [
                      span([text("IMAGE TITLE")], classes: 'text-xs font-bold text-gray-600', attributes: const {'style': 'margin-bottom: 4px; display: block;'}),
                      input(
                          attributes: {
                            'type': 'text',
                            'placeholder': 'Give this image a creative title',
                            'value': _title,
                            'style': 'width: 100%; padding: 10px; border: 1px solid #ccc; border-radius: 6px; box-sizing: border-box; font-size: 13px; background: white;',
                            if (isUploading) 'disabled': 'true'
                          },
                          events: {
                            'input': (e) {
                              setState(() {
                                _title = getInputValue(e);
                              });
                            }
                          }
                      )
                    ],
                    attributes: const {'style': 'margin-bottom: 12px;'}
                ),

                div(
                    [
                      span([text("CAPTION / DESCRIPTION")], classes: 'text-xs font-bold text-gray-600', attributes: const {'style': 'margin-bottom: 4px; display: block;'}),
                      input(
                          attributes: {
                            'type': 'text',
                            'placeholder': 'Write a caption for your work (optional)',
                            'value': _caption,
                            'style': 'width: 100%; padding: 10px; border: 1px solid #ccc; border-radius: 6px; box-sizing: border-box; font-size: 13px; background: white;',
                            if (isUploading) 'disabled': 'true'
                          },
                          events: {
                            'input': (e) {
                              setState(() {
                                _caption = getInputValue(e);
                              });
                            }
                          }
                      )
                    ],
                    attributes: const {'style': 'margin-bottom: 12px;'}
                ),

                div(
                    [
                      span([text("INDICIA / HISTORICAL DESCRIPTION")], classes: 'text-xs font-bold text-gray-600', attributes: const {'style': 'margin-bottom: 4px; display: block;'}),
                      textarea(
                          classes: 'border border-gray-300 rounded-md',
                          attributes: {
                            'placeholder': 'Add archival notes, context, or indicia annotations for this print...',
                            'style': 'width: 100%; min-height: 80px; padding: 10px; box-sizing: border-box; font-size: 13px; background: white; margin-bottom: 0;',
                            if (isUploading) 'disabled': 'true'
                          },
                          events: {
                            'input': (e) {
                              setState(() {
                                _indicia = getInputValue(e);
                              });
                            }
                          },
                          [text(_indicia)]
                      )
                    ],
                    attributes: const {'style': 'margin-bottom: 20px;'}
                ),

                // Creators Section
                div(
                    [
                      span([text("CREATORS & CONTRIBUTORS")], classes: 'text-xs font-bold text-gray-600', attributes: const {'style': 'margin-bottom: 6px; display: block;'}),

                      // Existing Creators list
                      if (_blocState.creators.isNotEmpty)
                        div(
                            [
                              for (int i = 0; i < _blocState.creators.length; i++)
                                div(
                                    [
                                      span([text('${_blocState.creators[i]['name']} (${_blocState.creators[i]['role']})')]),
                                      button(
                                          [span([text('remove_circle')], classes: 'material-symbols-outlined text-red-500', attributes: const {'style': 'font-size: 16px;'})],
                                          classes: 'cursor-pointer border-none bg-transparent',
                                          events: {
                                            'click': (e) => _uploadBloc.add(RemoveCreatorRequested(i))
                                          }
                                      )
                                    ],
                                    attributes: const {
                                      'style': 'display: flex; align-items: center; justify-content: space-between; background-color: #f9f9f9; border: 1px solid #eee; border-radius: 6px; padding: 6px 12px; margin-bottom: 6px; font-size: 12px;'
                                    }
                                )
                            ]
                        ),

                      // Creator Composer fields
                      div(
                          [
                            input(
                                attributes: {
                                  'type': 'text',
                                  'placeholder': '@handle',
                                  'value': _creatorHandleInput,
                                  'style': 'flex: 1; padding: 8px 12px; font-size: 12px; margin-bottom: 0; background: white;'
                                },
                                events: {'input': (e) => _creatorHandleInput = getInputValue(e)}
                            ),
                            input(
                                attributes: {
                                  'type': 'text',
                                  'placeholder': 'Role',
                                  'value': _roleInput,
                                  'style': 'flex: 1; padding: 8px 12px; font-size: 12px; margin-bottom: 0; background: white;'
                                },
                                events: {'input': (e) => _roleInput = getInputValue(e)}
                            ),
                            button(
                                [span([text('add_circle')], classes: 'material-symbols-outlined text-green-600', attributes: const {'style': 'font-size: 24px;'})],
                                classes: 'cursor-pointer border-none bg-transparent',
                                events: {
                                  'click': (e) => _addCreator()
                                }
                            )
                          ],
                          attributes: const {
                            'style': 'display: flex; gap: 8px; align-items: center; margin-top: 6px;'
                          }
                      )
                    ],
                    attributes: const {'style': 'margin-bottom: 24px;'}
                ),

                // 3. Status and Trigger Area
                if (errorMessage != null)
                  p([text(errorMessage)], attributes: const {'style': 'font-size: 12px; color: #ef4444; font-weight: bold; margin-bottom: 12px;'}),

                if (isUploading)
                  div(
                      [
                        div([], attributes: const {
                          'style': 'height: 4px; background-color: #6750A4; width: 50%; border-radius: 2px; animation: shimmerKeyframe 1.2s infinite linear;'
                        })
                      ],
                      attributes: const {
                        'style': 'width: 100%; height: 4px; background-color: #eee; border-radius: 2px; overflow: hidden; margin-bottom: 16px;'
                      }
                  ),

                button(
                    [
                      if (isUploading)
                        span([text('progress_activity')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 18px; margin-right: 6px; animation: spin 1s linear infinite;'})
                      else
                        span([text('cloud_upload')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 18px; margin-right: 6px;'}),
                      text(isUploading ? "publishing image..." : "publish to gallery")
                    ],
                    classes: 'btn-primary w-full',
                    attributes: {
                      if (!hasImage || isUploading) 'disabled': 'true',
                      'style': 'height: 44px; display: flex; align-items: center; justify-content: center; font-weight: bold;'
                    },
                    events: {
                      'click': (e) => _startPublishFlow()
                    }
                )
              ],
              classes: 'white-sticker p-6 w-full flex-col',
              attributes: const {
                'style': 'display: flex; flex-direction: column; width: 100%; box-sizing: border-box; border: 1px solid #ddd; border-radius: 12px; background: white;'
              }
          )
        ],
        classes: 'flex-col items-center justify-start w-full',
        attributes: const {'style': 'display: flex; flex-direction: column;'}
    );
  }
}