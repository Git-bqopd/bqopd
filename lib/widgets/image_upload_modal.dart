import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../blocs/upload/upload_bloc.dart';

class ImageUploadModal extends StatefulWidget {
  final String userId;
  const ImageUploadModal({super.key, required this.userId});

  @override
  State<ImageUploadModal> createState() => _ImageUploadModalState();
}

class _ImageUploadModalState extends State<ImageUploadModal> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _indiciaController = TextEditingController();
  final TextEditingController _newCreatorHandleController = TextEditingController();
  final TextEditingController _newCreatorRoleController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _titleController.dispose();
    _captionController.dispose();
    _indiciaController.dispose();
    _newCreatorHandleController.dispose();
    _newCreatorRoleController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    // Capture the BLoC before the async gap to avoid synchronous context issues
    final uploadBloc = context.read<UploadBloc>();

    final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      final bytes = await file.readAsBytes();
      // Use standard mounted check
      if (mounted) {
        uploadBloc.add(ImagePicked(bytes, file.name));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<UploadBloc, UploadState>(
      listener: (context, state) {
        if (state.status == UploadStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Upload Successful!")));
          Navigator.pop(context);
        } else if (state.status == UploadStatus.failure) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: ${state.errorMessage}"), backgroundColor: Colors.red));
        }
      },
      builder: (context, state) {
        final bloc = context.read<UploadBloc>();
        final bool isSubmitting = state.status == UploadStatus.submitting;

        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("Upload Work", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),

                  GestureDetector(
                    onTap: isSubmitting ? null : _pickImage,
                    child: Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: state.imageBytes != null
                          ? Image.memory(state.imageBytes!, fit: BoxFit.contain)
                          : const Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey),
                    ),
                  ),

                  const SizedBox(height: 16),
                  TextField(controller: _titleController, decoration: const InputDecoration(labelText: "Title", border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: _captionController, maxLines: 2, decoration: const InputDecoration(labelText: "Caption", border: OutlineInputBorder())),

                  const Divider(height: 32),
                  const Text("Creators", style: TextStyle(fontWeight: FontWeight.bold)),
                  ...state.creators.asMap().entries.map((entry) => ListTile(
                    dense: true,
                    title: Text("${entry.value['name']} (${entry.value['role']})"),
                    trailing: IconButton(icon: const Icon(Icons.remove_circle), onPressed: () => bloc.add(RemoveCreatorRequested(entry.key))),
                  )),

                  Row(
                    children: [
                      Expanded(child: TextField(controller: _newCreatorHandleController, decoration: const InputDecoration(hintText: "@handle"))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: _newCreatorRoleController, decoration: const InputDecoration(hintText: "Role"))),
                      IconButton(icon: const Icon(Icons.add_circle), onPressed: () {
                        bloc.add(AddCreatorRequested(_newCreatorHandleController.text, _newCreatorRoleController.text));
                        _newCreatorHandleController.clear();
                        _newCreatorRoleController.clear();
                      })
                    ],
                  ),

                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: isSubmitting || state.imageBytes == null
                        ? null
                        : () => bloc.add(SubmitUploadRequested(
                      userId: widget.userId,
                      title: _titleController.text,
                      caption: _captionController.text,
                      indicia: _indiciaController.text,
                      creators: state.creators,
                    )),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF1B255), padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("PUBLISH TO GALLERY"),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}