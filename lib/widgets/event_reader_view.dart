import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../models/page_event.dart';

class EventReaderView extends StatelessWidget {
  final List<PageEvent> events;

  const EventReaderView({super.key, required this.events});

  String _formatDateRange(DateTime start, DateTime end) {
    final DateFormat monthDay = DateFormat('MMM dd');
    final DateFormat fullDate = DateFormat('MMM dd, yyyy');

    if (start.year == end.year && start.month == end.month && start.day == end.day) {
      return fullDate.format(start);
    }

    if (start.year == end.year) {
      return '${monthDay.format(start)} - ${fullDate.format(end)}';
    }

    return '${fullDate.format(start)} - ${fullDate.format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text('No events listed for this page.'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Page Events',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        ...events.map((event) => _EventReaderCard(
          event: event,
          dateRange: _formatDateRange(event.startDate, event.endDate),
        )),
      ],
    );
  }
}

class _EventReaderCard extends StatelessWidget {
  final PageEvent event;
  final String dateRange;

  const _EventReaderCard({required this.event, required this.dateRange});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.eventName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateRange,
                      style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              if (event.username != null && event.username!.isNotEmpty)
                GestureDetector(
                  onTap: () => context.push('/${event.username}'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '@${event.username}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (event.venueName.isNotEmpty || event.address.isNotEmpty) ...[
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (event.venueName.isNotEmpty)
                        Text(
                          event.venueName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      if (event.address.isNotEmpty)
                        Text(
                          '${event.address}, ${event.city} ${event.state} ${event.zip}',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}