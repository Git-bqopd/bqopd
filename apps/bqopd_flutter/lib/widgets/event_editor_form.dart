import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bqopd_models/bqopd_models.dart';
import 'package:bqopd_core/bqopd_core.dart';

class EventEditorForm extends StatefulWidget {
  final String pageId;
  final PageEvent? existingEvent;
  final VoidCallback onCancel;
  final VoidCallback onSaveComplete;

  const EventEditorForm({
    super.key,
    required this.pageId,
    this.existingEvent,
    required this.onCancel,
    required this.onSaveComplete,
  });

  @override
  State<EventEditorForm> createState() => _EventEditorFormState();
}

class _EventEditorFormState extends State<EventEditorForm> {
  final _formKey = GlobalKey<FormState>();
  final EventService _eventService = EventService();

  late TextEditingController _nameController;
  late TextEditingController _venueController;
  late TextEditingController _addressController;
  late TextEditingController _cityController;
  late TextEditingController _stateController;
  late TextEditingController _zipController;
  late TextEditingController _handleController;

  late DateTime _startDate;
  late DateTime _endDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existingEvent;
    _nameController = TextEditingController(text: e?.eventName ?? '');
    _venueController = TextEditingController(text: e?.venueName ?? '');
    _addressController = TextEditingController(text: e?.address ?? '');
    _cityController = TextEditingController(text: e?.city ?? '');
    _stateController = TextEditingController(text: e?.state ?? '');
    _zipController = TextEditingController(text: e?.zip ?? '');
    _handleController = TextEditingController(text: e?.username ?? '');
    _startDate = e?.startDate ?? DateTime.now();
    _endDate = e?.endDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _venueController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipController.dispose();
    _handleController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) _endDate = _startDate;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final event = PageEvent(
      id: widget.existingEvent?.id ?? '',
      pageId: widget.pageId,
      eventName: _nameController.text,
      startDate: _startDate,
      endDate: _endDate,
      venueName: _venueController.text,
      address: _addressController.text,
      city: _cityController.text,
      state: _stateController.text,
      zip: _zipController.text,
      username: _handleController.text.isNotEmpty ? _handleController.text : null,
    );

    try {
      if (widget.existingEvent == null) {
        await _eventService.addEvent(event);
      } else {
        await _eventService.updateEvent(event);
      }
      widget.onSaveComplete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    if (widget.existingEvent == null) return;
    setState(() => _isSaving = true);
    try {
      await _eventService.deleteEvent(widget.existingEvent!.id);
      widget.onSaveComplete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.existingEvent == null ? 'Add New Event' : 'Edit Event',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              IconButton(onPressed: widget.onCancel, icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Event Name', border: OutlineInputBorder()),
            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ListTile(
                  title: const Text('Starts'),
                  subtitle: Text(DateFormat('MMM dd, yyyy').format(_startDate)),
                  onTap: () => _pickDate(true),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              Expanded(
                child: ListTile(
                  title: const Text('Ends'),
                  subtitle: Text(DateFormat('MMM dd, yyyy').format(_endDate)),
                  onTap: () => _pickDate(false),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _venueController,
            decoration: const InputDecoration(labelText: 'Venue Name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _addressController,
            decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(flex: 2, child: TextFormField(controller: _cityController, decoration: const InputDecoration(labelText: 'City'))),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(controller: _stateController, decoration: const InputDecoration(labelText: 'State'))),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(controller: _zipController, decoration: const InputDecoration(labelText: 'Zip'))),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _handleController,
            decoration: const InputDecoration(labelText: 'Username (@handle)', border: OutlineInputBorder(), prefixText: '@'),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (widget.existingEvent != null)
                TextButton.icon(
                  onPressed: _isSaving ? null : _delete,
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              const Spacer(),
              ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
                child: _isSaving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save Event'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}