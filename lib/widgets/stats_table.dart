import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/view_service.dart';

/// A standardized table displaying view analytics for unique content (Images).
/// Reads directly from the Image's 'views' subcollection (Ledger).
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
                viewService: viewService,
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
            viewService: viewService,
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
  final ViewService viewService;

  const _StatRowWrapper({
    required this.label,
    required this.imageId,
    required this.viewService,
  });

  @override
  Widget build(BuildContext context) {
    const double colWidth = 60.0;
    const double labelWidth = 50.0;

    return StreamBuilder<QuerySnapshot>(
      stream: viewService.getViewLogsStream(imageId),
      builder: (context, snap) {
        int regList = 0; int regGrid = 0; int anonList = 0; int anonGrid = 0;

        if (snap.hasData) {
          for (var doc in snap.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final bool isAnon = data['isAnonymous'] ?? true;
            final String type = data['viewType'] ?? 'list';

            if (isAnon) {
              if (type == 'list') anonList++; else anonGrid++;
            } else {
              if (type == 'list') regList++; else regGrid++;
            }
          }
        }

        return Table(
          columnWidths: {
            0: label.isNotEmpty ? const FixedColumnWidth(labelWidth) : const FixedColumnWidth(0),
            1: const FixedColumnWidth(colWidth),
            2: const FixedColumnWidth(colWidth),
            3: const FixedColumnWidth(colWidth),
            4: const FixedColumnWidth(colWidth),
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
                if (label.isNotEmpty)
                  StatsTable._buildCell(label, const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))
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
      },
    );
  }
}