import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/view_service.dart';

class StatsTable extends StatelessWidget {
  final String contentId;
  final ViewService viewService;
  final bool isFanzine; // NEW: Distinguish between Image stats and Fanzine stats

  const StatsTable({
    super.key,
    required this.contentId,
    required this.viewService,
    this.isFanzine = false,
  });

  @override
  Widget build(BuildContext context) {
    // If it's a fanzine, we currently rely on the cached totals on the fanzine doc.
    // In the future, this will expand to a per-page breakdown.
    if (isFanzine) {
      return StreamBuilder<DocumentSnapshot>(
        stream: viewService.getFanzineStatsStream(contentId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};

          // Fanzines currently store registered vs guest in flat fields for the summary
          // We will transition these to full logs later, but for now we show the totals.
          return _buildTableUI(
            regList: data['registeredListViewCount'] ?? 0,
            regGrid: (data['totalEngagementViews'] ?? 0) - (data['registeredListViewCount'] ?? 0),
            guestList: 0, // Placeholder until fanzine-level bucket logic is deeper
            guestGrid: 0,
          );
        },
      );
    }

    // If it's an Image, we query the high-fidelity logs.
    return StreamBuilder<QuerySnapshot>(
      stream: viewService.getViewLogsStream(contentId),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));

        int regList = 0; int regGrid = 0; int guestList = 0; int guestGrid = 0;

        for (var doc in snap.data!.docs) {
          final d = doc.data() as Map<String, dynamic>;
          final bool isAnon = d['isAnonymous'] ?? true;
          final String type = d['viewType'] ?? 'list';
          if (isAnon) { if (type == 'list') guestList++; else guestGrid++; }
          else { if (type == 'list') regList++; else regGrid++; }
        }

        return _buildTableUI(regList: regList, regGrid: regGrid, guestList: guestList, guestGrid: guestGrid);
      },
    );
  }

  Widget _buildTableUI({required int regList, required int regGrid, required int guestList, required int guestGrid}) {
    const cellStyle = TextStyle(fontSize: 12);
    const headerStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text("VIEWER BREAKDOWN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.1, color: Colors.grey)),
        const SizedBox(height: 12),
        Table(
          columnWidths: const {0: FlexColumnWidth(1.2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
          border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
          children: [
            TableRow(
              decoration: BoxDecoration(color: Colors.grey[100]),
              children: [
                const SizedBox.shrink(),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.menu_book, size: 14, color: Colors.blueGrey),
                      const SizedBox(width: 4),
                      const Text("Two Page", style: headerStyle),
                    ],
                  ),
                ),
                Padding(padding: const EdgeInsets.all(8.0), child: Center(child: const Text("Single Page", style: headerStyle))),
              ],
            ),
            TableRow(children: [
              _buildCell("Logged In", headerStyle),
              _buildCell("$regGrid", cellStyle),
              _buildCell("$regList", cellStyle),
            ]),
            TableRow(children: [
              _buildCell("Unregistered", headerStyle),
              _buildCell("$guestGrid", cellStyle),
              _buildCell("$guestList", cellStyle),
            ]),
          ],
        ),
      ],
    );
  }

  Widget _buildCell(String text, TextStyle style) => Padding(padding: const EdgeInsets.all(8.0), child: Center(child: Text(text, style: style)));
}