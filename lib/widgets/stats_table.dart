import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/view_service.dart';

/// A standardized table displaying view analytics for unique content (Images).
/// Reads directly from the Image's pre-aggregated view counts.
class StatsTable extends StatelessWidget {
  final String contentId;
  final ViewService viewService;
  final bool isFanzine;

  const StatsTable({
    super.key,
    required this.contentId,
    required this.viewService,
    this.isFanzine = false,
  });

  @override
  Widget build(BuildContext context) {
    // --- FANZINE MODE ---
    if (isFanzine) {
      return StreamBuilder<QuerySnapshot>(
        stream: viewService.getFanzinePagesStream(contentId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final pages = snapshot.data!.docs;
          if (pages.isEmpty) return const Center(child: Text("No pages found."));

          return _buildTableContainer(
            title: "IMAGE ANALYTICS (GLOBAL LIFETIME)",
            includeLabelColumn: true,
            labelHeader: "Page",
            rows: pages.asMap().entries.map((entry) {
              final pageData = entry.value.data() as Map<String, dynamic>;
              final String imageId = pageData['imageId'] ?? '';
              final int pageNum = pageData['pageNumber'] ?? (entry.key + 1);

              return _StatRowWrapper(
                label: "$pageNum",
                imageId: imageId,
              );
            }).toList(),
          );
        },
      );
    }

    // --- IMAGE MODE ---
    return Center(
      child: _buildTableContainer(
        title: "VIEWER BREAKDOWN",
        includeLabelColumn: false,
        labelHeader: "",
        rows: [
          _StatRowWrapper(
            label: "",
            imageId: contentId,
          ),
        ],
      ),
    );
  }

  Widget _buildTableContainer({
    required String title,
    required bool includeLabelColumn,
    required String labelHeader,
    required List<Widget> rows,
  }) {
    const double colWidth = 60.0;
    const double labelWidth = 50.0;
    const hStyle = TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF546E7A));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isFanzine ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.1, color: Colors.grey)),
        const SizedBox(height: 12),
        Container(
          constraints: BoxConstraints(
            maxWidth: (includeLabelColumn ? labelWidth : 0) + (colWidth * 4) + 2,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  if (includeLabelColumn) const SizedBox(width: labelWidth),
                  _buildSpanningHeader("Grid (Glance)", icon: Icons.grid_view, width: colWidth * 2),
                  _buildSpanningHeader("List (Read)", icon: Icons.view_list, width: colWidth * 2),
                ],
              ),
              Table(
                columnWidths: {
                  0: includeLabelColumn ? const FixedColumnWidth(labelWidth) : const FixedColumnWidth(0),
                  1: const FixedColumnWidth(colWidth),
                  2: const FixedColumnWidth(colWidth),
                  3: const FixedColumnWidth(colWidth),
                  4: const FixedColumnWidth(colWidth),
                },
                border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: Colors.grey[50]),
                    children: [
                      if (includeLabelColumn) _buildCell(labelHeader, hStyle) else const SizedBox.shrink(),
                      _buildCell("User", hStyle),
                      _buildCell("Anon", hStyle),
                      _buildCell("User", hStyle),
                      _buildCell("Anon", hStyle),
                    ],
                  ),
                ],
              ),
              ...rows,
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSpanningHeader(String text, {required double width, IconData? icon}) {
    return Container(
      width: width,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300, width: 0.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) Icon(icon, size: 10, color: const Color(0xFF546E7A)),
          if (icon != null) const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF546E7A))),
        ],
      ),
    );
  }

  static Widget _buildCell(String text, TextStyle style) {
    return Container(
      height: 32,
      alignment: Alignment.center,
      child: Text(text, style: style, textAlign: TextAlign.center),
    );
  }
}

class _StatRowWrapper extends StatelessWidget {
  final String label;
  final String imageId;

  const _StatRowWrapper({
    required this.label,
    required this.imageId,
  });

  @override
  Widget build(BuildContext context) {
    const double colWidth = 60.0;
    const double labelWidth = 50.0;

    // Fast fail if image isn't fully processed yet
    if (imageId.isEmpty) {
      return _buildTableRow(label, labelWidth, colWidth, 0, 0, 0, 0);
    }

    return StreamBuilder<DocumentSnapshot>(
      // Pull directly from the aggregated counts on the image document
      stream: FirebaseFirestore.instance.collection('images').doc(imageId).snapshots(),
      builder: (context, snap) {
        int regList = 0; int regGrid = 0; int anonList = 0; int anonGrid = 0;

        if (snap.hasData && snap.data!.exists) {
          final data = snap.data!.data() as Map<String, dynamic>;
          regList = data['regListCount'] ?? 0;
          regGrid = data['regGridCount'] ?? 0;
          anonList = data['anonListCount'] ?? 0;
          anonGrid = data['anonGridCount'] ?? 0;
        }

        return _buildTableRow(label, labelWidth, colWidth, regGrid, anonGrid, regList, anonList);
      },
    );
  }

  Widget _buildTableRow(String lbl, double lblWidth, double colWidth, int regGrid, int anonGrid, int regList, int anonList) {
    return Table(
      columnWidths: {
        0: lbl.isNotEmpty ? FixedColumnWidth(lblWidth) : const FixedColumnWidth(0),
        1: FixedColumnWidth(colWidth),
        2: FixedColumnWidth(colWidth),
        3: FixedColumnWidth(colWidth),
        4: FixedColumnWidth(colWidth),
      },
      border: TableBorder(
        verticalInside: BorderSide(color: Colors.grey.shade300, width: 0.5),
        bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
        left: BorderSide(color: Colors.grey.shade300, width: 0.5),
        right: BorderSide(color: Colors.grey.shade300, width: 0.5),
      ),
      children: [
        TableRow(
          children: [
            if (lbl.isNotEmpty)
              StatsTable._buildCell(lbl, const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))
            else
              const SizedBox.shrink(),
            StatsTable._buildCell("$regGrid", const TextStyle(fontSize: 12)),
            StatsTable._buildCell("$anonGrid", const TextStyle(fontSize: 12)),
            StatsTable._buildCell("$regList", const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
            StatsTable._buildCell("$anonList", const TextStyle(fontSize: 12)),
          ],
        ),
      ],
    );
  }
}