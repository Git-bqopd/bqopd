import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../blocs/fanzine_editor_bloc.dart';
import '../../models/fanzine.dart';
import '../../services/user_provider.dart';
import '../../repositories/fanzine_repository.dart';

class CuratorSettingsTab extends StatefulWidget {
  final String fanzineId;
  final Fanzine fanzine;

  const CuratorSettingsTab({super.key, required this.fanzineId, required this.fanzine});

  @override
  State<CuratorSettingsTab> createState() => _CuratorSettingsTabState();
}

class _CuratorSettingsTabState extends State<CuratorSettingsTab> {
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
  void didUpdateWidget(covariant CuratorSettingsTab oldWidget) {
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

  void _saveMeta() {
    context.read<FanzineEditorBloc>().add(UpdateFanzineMetadata(
      _titleController.text,
      _volumeController.text,
      _issueController.text,
      _wholeNumberController.text,
    ));
  }

  void _showAddSeriesDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Create New Series", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Series Name (e.g. The Comet)"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                context.read<FanzineRepository>().createSeries(controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text("CREATE"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fzRepo = context.read<FanzineRepository>();
    final editorBloc = context.read<FanzineEditorBloc>();
    final fanzine = widget.fanzine;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- SERIES SELECTION ---
          const Text("SERIES ASSIGNMENT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot>(
            stream: fzRepo.watchSeries(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              final String? currentSeriesValue = docs.any((d) => d.id == fanzine.seriesId)
                  ? fanzine.seriesId
                  : null;

              return Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: currentSeriesValue,
                      decoration: const InputDecoration(
                        labelText: "part of a series",
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text("None (Standalone)")),
                        ...docs.map((d) => DropdownMenuItem(value: d.id, child: Text(d['name'])))
                      ],
                      onChanged: (val) {
                        String seriesName = "";
                        if (val != null) {
                          seriesName = docs.firstWhere((d) => d.id == val)['name'];
                        }
                        editorBloc.add(UpdateFanzineSeries(val, seriesName));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: Colors.indigo),
                    onPressed: _showAddSeriesDialog,
                    tooltip: "Add New Series",
                  ),
                  if (fanzine.seriesId != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => fzRepo.deleteSeries(fanzine.seriesId!),
                      tooltip: "Delete Selected Series",
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          TextField(
            controller: _titleController,
            onSubmitted: (val) => _saveMeta(),
            decoration: const InputDecoration(
                labelText: 'fanzine name',
                isDense: true,
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                floatingLabelStyle: TextStyle(color: Colors.black87)),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _volumeController,
                  onSubmitted: (_) => _saveMeta(),
                  decoration: const InputDecoration(labelText: 'Volume', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _issueController,
                  onSubmitted: (_) => _saveMeta(),
                  decoration: const InputDecoration(labelText: 'Issue', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _wholeNumberController,
                  onSubmitted: (_) => _saveMeta(),
                  decoration: const InputDecoration(labelText: 'Whole Number', isDense: true, border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // --- granular published date & display options ---
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.black12),
            ),
            child: Row(
              children: [
                // 1. DATE PICKER SECTION
                Expanded(
                  flex: 3,
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: fanzine.publishedDate ?? DateTime.now(),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null && context.mounted) {
                        editorBloc.add(UpdateFanzineDate(picked));
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("published date", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.calendar_month, size: 16, color: Colors.black54),
                            const SizedBox(width: 6),
                            Text(
                              fanzine.publishedDate != null
                                  ? DateFormat('MMMM d, yyyy').format(fanzine.publishedDate!)
                                  : "set date",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. DISPLAY FORMAT SEGMENTED BUTTON
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      const Text("display precision", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 4),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          textStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                        segments: const [
                          ButtonSegment(value: 'day', label: Text('day')),
                          ButtonSegment(value: 'month', label: Text('month')),
                          ButtonSegment(value: 'year', label: Text('year')),
                        ],
                        selected: {fanzine.datePrecision},
                        onSelectionChanged: (val) => editorBloc.add(UpdateFanzineDateOptions(datePrecision: val.first)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // 3. GUESS CHECKBOX
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      const Text("guess?", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey)),
                      Transform.scale(
                        scale: 0.9,
                        child: Checkbox(
                          value: fanzine.dateIsGuess,
                          onChanged: (val) => editorBloc.add(UpdateFanzineDateOptions(dateIsGuess: val)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          const Text("SHORTCODE",
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          SelectableText(
            fanzine.shortCode ?? 'pending...',
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo, letterSpacing: 1.1),
          ),
          const SizedBox(height: 20),
          const Text("COLLABORATORS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Owner: ${fanzine.ownerId == context.read<UserProvider>().currentUserId ? 'You' : fanzine.ownerId}", style: const TextStyle(fontSize: 12)),
                if (fanzine.editors.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text("Editors: ${fanzine.editors.length}", style: const TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Enable two page spread view', style: TextStyle(fontSize: 12)),
            Switch(
                value: fanzine.twoPage,
                activeColor: Colors.grey,
                onChanged: (val) => editorBloc.add(ToggleTwoPageRequested(val))),
          ]),
          const Divider(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Live on site (available via shortcode)', style: TextStyle(fontSize: 12)),
            Switch(
                value: fanzine.isLive,
                activeColor: Colors.green,
                onChanged: (val) => editorBloc.add(ToggleIsLiveRequested(val))),
          ]),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              _saveMeta();
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey,
                foregroundColor: Colors.white),
            child: const Text("save curator session", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}