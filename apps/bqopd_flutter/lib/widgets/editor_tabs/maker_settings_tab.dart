import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:bqopd_models/bqopd_models.dart';
import 'package:bqopd_core/bqopd_core.dart';
import 'package:bqopd_state/bqopd_state.dart';

class MakerSettingsTab extends StatefulWidget {
  final String fanzineId;
  final Fanzine fanzine;

  const MakerSettingsTab({super.key, required this.fanzineId, required this.fanzine});

  @override
  State<MakerSettingsTab> createState() => _MakerSettingsTabState();
}

class _MakerSettingsTabState extends State<MakerSettingsTab> {
  late TextEditingController _titleController;
  late TextEditingController _volumeController;
  late TextEditingController _issueController;
  late TextEditingController _wholeNumberController;
  String? _lastSyncedTitle;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  @override
  void didUpdateWidget(covariant MakerSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastSyncedTitle != widget.fanzine.title) {
      _initializeControllers();
    }
  }

  void _initializeControllers() {
    _titleController = TextEditingController(text: widget.fanzine.title);
    _volumeController = TextEditingController(text: widget.fanzine.volume ?? '');
    _issueController = TextEditingController(text: widget.fanzine.issue ?? '');
    _wholeNumberController = TextEditingController(text: widget.fanzine.wholeNumber ?? '');
    _lastSyncedTitle = widget.fanzine.title;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _volumeController.dispose();
    _issueController.dispose();
    _wholeNumberController.dispose();
    super.dispose();
  }

  void _saveMeta(BuildContext tabContext) {
    tabContext.read<FanzineEditorBloc>().add(UpdateFanzineMetadata(
      _titleController.text,
      _volumeController.text,
      _issueController.text,
      _wholeNumberController.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final fanzine = widget.fanzine;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _titleController,
            onSubmitted: (_) => _saveMeta(context),
            decoration: const InputDecoration(
              labelText: 'fanzine name',
              isDense: true,
              border: OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
              floatingLabelStyle: TextStyle(color: Colors.black87),
            ),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _volumeController,
                  onSubmitted: (_) => _saveMeta(context),
                  decoration: const InputDecoration(labelText: 'Volume', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _issueController,
                  onSubmitted: (_) => _saveMeta(context),
                  decoration: const InputDecoration(labelText: 'Issue', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _wholeNumberController,
                  onSubmitted: (_) => _saveMeta(context),
                  decoration: const InputDecoration(labelText: 'Whole Number', isDense: true, border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              _saveMeta(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("settings updated.")));

              // Custom Maker Save Routing
              if (context.canPop()) {
                context.pop();
              } else {
                final userProvider = Provider.of<UserProvider>(context, listen: false);
                final username = userProvider.userProfile?.username;
                if (username != null) {
                  context.go('/$username', extra: {'tab': 'maker', 'drafts': true});
                } else {
                  context.go('/');
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, foregroundColor: Colors.white),
            child: const Text("save folio", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}