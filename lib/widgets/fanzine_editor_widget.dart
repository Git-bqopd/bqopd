import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/fanzine.dart';
import '../models/fanzine_page.dart';
import '../blocs/fanzine_editor_bloc.dart';
import 'base_fanzine_workspace.dart';

/// Legacy Editor Widget mapped to the exact same logic as the Curator view.
/// Provided as a fallback/wrapper to maintain backward compatibility.
class FanzineEditorWidget extends StatefulWidget {
  final String fanzineId;
  const FanzineEditorWidget({super.key, required this.fanzineId});

  @override
  State<FanzineEditorWidget> createState() => _FanzineEditorWidgetState();
}

class _FanzineEditorWidgetState extends State<FanzineEditorWidget> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _shortcodeController = TextEditingController();
  String? _lastSyncedTitle;

  @override
  void dispose() {
    _titleController.dispose();
    _shortcodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BaseFanzineWorkspace(
      fanzineId: widget.fanzineId,
      tabs: const [
        Tab(text: "settings", icon: Icon(Icons.settings, size: 20)),
        Tab(text: "order", icon: Icon(Icons.format_list_numbered, size: 20)),
      ],
      tabViews: [
            (context, fanzine, pages) => _buildLegacySettingsTab(context, fanzine),
            (context, fanzine, pages) => _buildLegacyOrderTab(context, pages),
      ],
    );
  }

  Widget _buildLegacySettingsTab(BuildContext context, Fanzine fanzine) {
    final bloc = context.read<FanzineEditorBloc>();

    if (_lastSyncedTitle != fanzine.title) {
      _titleController.text = fanzine.title;
      _lastSyncedTitle = fanzine.title;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _titleController,
            onSubmitted: (val) => bloc.add(UpdateFanzineTitle(val)),
            decoration: const InputDecoration(
                labelText: 'fanzine name',
                isDense: true,
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                helperText: "Press enter to save"),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _shortcodeController,
                    decoration: const InputDecoration(
                      hintText: 'paste image shortcode',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ))),
            const SizedBox(width: 8),
            ElevatedButton(
                onPressed: () {
                  bloc.add(AddPageRequested(_shortcodeController.text));
                  _shortcodeController.clear();
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, foregroundColor: Colors.white),
                child: const Text('add page')),
          ]),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              bloc.add(UpdateFanzineTitle(_titleController.text));
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey,
                foregroundColor: Colors.white),
            child: const Text("save session", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildLegacyOrderTab(BuildContext context, List<FanzinePage> pages) {
    final bloc = context.read<FanzineEditorBloc>();
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PAGE ORDER',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          if (pages.isEmpty)
            const Text('No pages added.',
                style: TextStyle(color: Colors.grey, fontSize: 12))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pages.length,
              itemBuilder: (context, index) {
                final page = pages[index];
                final num = page.pageNumber;

                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.black12, width: 0.5))),
                  child: Row(
                    children: [
                      Text('$num.',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text("Page Image",
                              style: TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis)),
                      IconButton(
                          icon: const Icon(Icons.arrow_upward, size: 14),
                          onPressed: num > 1 ? () => bloc.add(ReorderPageRequested(page, -1, pages)) : null),
                      IconButton(
                          icon: const Icon(Icons.arrow_downward, size: 14),
                          onPressed: num < pages.length ? () => bloc.add(ReorderPageRequested(page, 1, pages)) : null),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}