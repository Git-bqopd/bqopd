import 'dart:convert';
import 'dart:typed_data';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';
import '../../utils/web_shortcode_service.dart';

/// Single image submission workflow.
/// Handles image picker triggers, creator listings with active user lookups, and WebP compile steps.
class MakerUploadForm extends StatefulComponent {
  final String targetUserId;
  final AuthState? authState;
  final VoidCallback onBack;
  final void Function(String shortcode) onUploadComplete;

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
  String _uploadTitle = '';
  String _uploadDescription = '';
  String _uploadIndicia = '';
  String? _uploadError;
  bool _isUploadingImage = false;

  String? _uploadImageBase64;
  String? _uploadImageName;
  String? _uploadPreviewUrl;

  List<Map<String, dynamic>> _uploadCreators = [];
  String _newCreatorHandle = '';
  String _newCreatorRole = '';

  void _pickAndPreviewImage() {
    triggerFilePicker('maker-upload-picker', (base64, fileName, objectUrl) {
      setState(() {
        _uploadImageBase64 = base64;
        _uploadImageName = fileName;
        _uploadPreviewUrl = objectUrl;
        _uploadError = null;
      });
    });
  }

  void _onFileInputChanged() {
    readSelectedFile('maker-upload-picker', (base64, fileName, objectUrl) {
      setState(() {
        _uploadImageBase64 = base64;
        _uploadImageName = fileName;
        _uploadPreviewUrl = objectUrl;
        _uploadError = null;
      });
    });
  }

  Future<void> _addCreator() async {
    final handle = _newCreatorHandle.trim();
    final role = _newCreatorRole.trim();
    if (handle.isEmpty) return;

    final cleanHandle = handle.toLowerCase().replaceAll('@', '');
    String resolvedName = handle;
    String? resolvedUid;

    try {
      final resStr = await fsQuery('profiles', 'username', '==', jsonEncode(cleanHandle), '');
      final List docs = jsonDecode(resStr);
      if (docs.isNotEmpty) {
        final doc = docs.first;
        final data = doc['data'];
        resolvedName = data['displayName'] ?? data['username'] ?? handle;
        resolvedUid = doc['id'];
      }
    } catch (e) {
      print("Error looking up user by handle: $e");
    }

    setState(() {
      _uploadCreators.add({
        'uid': resolvedUid,
        'name': resolvedName,
        'role': role.isNotEmpty ? role : 'Contributor',
      });
      _newCreatorHandle = '';
      _newCreatorRole = '';
    });
  }

  Future<void> _submitSingleImage() async {
    if (_uploadTitle.trim().isEmpty) {
      setState(() => _uploadError = "Title is required.");
      return;
    }
    if (_uploadImageBase64 == null) {
      setState(() => _uploadError = "Please select or capture an image first.");
      return;
    }

    setState(() {
      _isUploadingImage = true;
      _uploadError = null;
    });

    try {
      final Uint8List bytes = base64Decode(_uploadImageBase64!);
      final String path = 'uploads/${component.targetUserId}/folio_assets/img_${DateTime.now().millisecondsSinceEpoch}_$_uploadImageName';
      final String downloadUrl = await stUpload(path, bytes, 'image/jpeg');
      final imageId = 'img_${DateTime.now().millisecondsSinceEpoch}';

      final String? email = component.authState?.user?.email;
      final bool useVanity = email != null && email.trim().toLowerCase() == 'kevin@712liberty.com';

      final shortCode = await WebShortcodeService.assignShortcode(
        contentType: 'image',
        contentId: imageId,
        isVanity: useVanity,
      ) ?? imageId.substring(imageId.length - 7).toUpperCase();

      final imgData = {
        'uid': component.targetUserId,
        'uploaderId': component.targetUserId,
        'fileUrl': downloadUrl,
        'fileName': _uploadImageName,
        'title': _uploadTitle.trim(),
        'description': _uploadDescription.trim(),
        'status': 'approved',
        'tags': {},
        'indicia': _uploadIndicia.trim(),
        'creators': _uploadCreators,
        'timestamp': WebFieldValue.serverTimestamp(),
        'shortCode': shortCode,
        'storagePath': path,
      };
      await fsSetDoc('images/$imageId', jsonEncode(imgData), true);

      final fanzineId = 'folio_${DateTime.now().millisecondsSinceEpoch}';
      final fzShortCode = await WebShortcodeService.assignShortcode(
        contentType: 'fanzine',
        contentId: fanzineId,
        isVanity: useVanity,
      ) ?? fanzineId.substring(fanzineId.length - 7).toUpperCase();

      final fzData = {
        'title': _uploadTitle.trim(),
        'ownerId': component.targetUserId,
        'editorId': component.targetUserId,
        'editors': [],
        'isLive': false,
        'processingStatus': 'complete',
        'creationDate': WebFieldValue.serverTimestamp(),
        'type': 'folio',
        'shortCode': fzShortCode,
        'shortCodeKey': fzShortCode.toUpperCase(),
        'twoPage': false,
      };
      await fsSetDoc('fanzines/$fanzineId', jsonEncode(fzData), true);

      final pageId = 'page_${DateTime.now().millisecondsSinceEpoch}';
      await fsSetDoc('fanzines/$fanzineId/pages/$pageId', jsonEncode({
        'imageId': imageId,
        'imageUrl': downloadUrl,
        'pageNumber': 1,
        'status': 'ready',
        'createdAt': WebFieldValue.serverTimestamp(),
      }), true);

      await fsUpdateDoc('images/$imageId', jsonEncode({
        'usedInFanzines': WebFieldValue.arrayUnion([fanzineId])
      }));

      component.onUploadComplete(fzShortCode);
    } catch (e) {
      setState(() => _uploadError = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isUploadingImage = false);
      }
    }
  }

  Component _buildUploadToolbarButton(String label, String iconName, bool isActive) {
    return button([
      div([
        span(
            [text(iconName)],
            classes: 'material-symbols-outlined',
            attributes: {
              'style': isActive ? "font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24; color: #6750A4;" : "font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24; color: #ccc;"
            }
        )
      ], classes: 'toolbar-icon-wrapper', attributes: const {'style': 'padding: 8px; border-radius: 50%; border: 2px solid black; display: flex; justify-content: center; align-items: center; margin-bottom: 4px; pointer-events: none;'}),
      span([text(label)], classes: 'toolbar-label', attributes: {
        'style': 'color: ${isActive ? '#6750a4' : '#ccc'}; font-weight: ${isActive ? 'bold' : 'normal'}; font-size: 10px;'
      })
    ], classes: 'toolbar-btn ${isActive ? 'active' : ''}');
  }

  @override
  Component build(BuildContext context) {
    return div([
      // Envelope Header details
      div([
        div([
          div([
            h1([text('upload single image')], classes: 'font-bold text-base text-center mb-1', attributes: const {'style': 'color: black; margin: 0; font-size: 16px;'}),
            p([text('Maker Pipeline')], classes: 'text-xs text-center text-gray', attributes: const {'style': 'margin: 0; color: #666; font-size: 11px;'})
          ]),
          img(src: 'assets/logo200.gif', attributes: const {'style': 'width: 70px; height: auto; display: block; margin: 12px 0;'}),
          div([
            button(
                [text(_isUploadingImage ? "publishing..." : "publish")],
                classes: 'btn-primary',
                attributes: _isUploadingImage ? const {'disabled': 'true', 'style': 'padding: 10px; border-radius: 8px; font-weight: bold; width: 100%;'} : const {'style': 'padding: 10px; border-radius: 8px; font-weight: bold; width: 100%; background-color: #6750A4; color: white;'},
                events: {'click': (e) => _submitSingleImage()}
            ),
            button(
                [text("back")],
                classes: 'profile-btn',
                attributes: const {'style': 'width: 100%; padding: 8px; font-size: 11px; font-weight: bold; border: 1px solid #ddd; border-radius: 8px; background: white; color: black; cursor: pointer;'},
                events: {'click': (e) => component.onBack()}
            )
          ], classes: 'flex-col w-full gap-2')
        ], classes: 'white-sticker', attributes: const {'style': 'width: 90%; height: 85%; padding: 20px; display: flex; flex-direction: column; justify-content: space-between; align-items: center; border-radius: 8px;'})
      ], classes: 'manila-envelope w-full mb-4', attributes: const {'style': 'border-radius: 8px; padding: 16px; width: 100%; box-sizing: border-box; display: flex; flex-direction: column; justify-content: center; align-items: center; aspect-ratio: 5 / 8;'}),

      // Form item details
      div([
        div([
          if (_uploadPreviewUrl != null)
            img(src: _uploadPreviewUrl!, attributes: const {'style': 'width: 100%; height: 100%; object-fit: contain; position: absolute; top: 0; left: 0;'})
          else
            div([
              span([text('add_photo_alternate')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 48px; margin-bottom: 8px; color: #aaa;'}),
              span([text('Click to select image')], attributes: const {'style': 'font-size: 12px; font-weight: 500; color: #666;'})
            ], classes: 'flex flex-col items-center justify-center p-4 text-gray-400'),
          input(
              id: 'maker-upload-picker',
              attributes: const {'type': 'file', 'accept': 'image/*', 'style': 'position: absolute; top: 0; left: 0; width: 100%; height: 100%; opacity: 0; cursor: pointer; z-index: 10;'},
              events: {
                'change': (e) => _onFileInputChanged(),
                'click': (e) => (e as dynamic).stopPropagation()
              }
          )
        ], classes: 'aspect-5-8 bg-gray-100 flex-col items-center justify-center relative', attributes: const {'style': 'width: 100%; aspect-ratio: 5 / 8; position: relative; cursor: pointer;'}, events: {'click': (e) => _pickAndPreviewImage()}),

        div([
          _buildUploadToolbarButton('upload', 'edit_document', true),
          _buildUploadToolbarButton('like', 'favorite_border', false),
          _buildUploadToolbarButton('comments', 'chat_bubble_outline', false),
          _buildUploadToolbarButton('tags', 'tag', false),
        ], classes: 'toolbar-container w-full border-t border-b border-gray-100 py-2 my-1'),

        div([
          div([
            span([text("UPLOAD METADATA")], classes: 'text-xs font-bold text-gray')
          ], classes: 'mb-4'),
          input(attributes: const {'type': 'text', 'placeholder': 'Title'}, events: {'input': (e) => _uploadTitle = getInputValue(e)}),
          input(attributes: const {'type': 'text', 'placeholder': 'Caption / Description (optional)'}, events: {'input': (e) => _uploadDescription = getInputValue(e)}),
          input(attributes: const {'type': 'text', 'placeholder': 'Indicia / Copyright (optional)'}, events: {'input': (e) => _uploadIndicia = getInputValue(e)}),

          div([
            span([text('Creators')], attributes: const {'style': 'font-size: 12px; font-weight: bold; color: #333; margin-bottom: 6px;'}),
            if (_uploadCreators.isNotEmpty)
              div([
                for (int i = 0; i < _uploadCreators.length; i++)
                  div([
                    span([text('${_uploadCreators[i]['name']} (${_uploadCreators[i]['role']})')]),
                    span([text('remove_circle')], classes: 'material-symbols-outlined text-red-500 cursor-pointer', events: {'click': (e) => setState(() => _uploadCreators.removeAt(i))})
                  ], classes: 'flex flex-row items-center justify-between bg-gray-50 border border-gray-150 p-1.5 rounded')
              ], classes: 'flex flex-col gap-1 w-full mb-2'),
            div([
              div([
                input(attributes: {'type': 'text', 'placeholder': '@handle', 'value': _newCreatorHandle}, events: {'input': (e) => _newCreatorHandle = getInputValue(e)})
              ], classes: 'flex-1'),
              div([
                input(attributes: {'type': 'text', 'placeholder': 'Role', 'value': _newCreatorRole}, events: {'input': (e) => _newCreatorRole = getInputValue(e)})
              ], classes: 'flex-1'),
              span([text('add_circle')], classes: 'material-symbols-outlined text-green-600 cursor-pointer', events: {'click': (e) => _addCreator()})
            ], classes: 'flex flex-row items-center gap-2 w-full')
          ])
        ], classes: 'p-4 mt-1 panel-container-animate')
      ], classes: 'reader-list-item flex-col w-full bg-white rounded-lg overflow-hidden')
    ]);
  }
}