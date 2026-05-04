import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bqopd_models/bqopd_models.dart';
import 'package:bqopd_state/bqopd_state.dart';

class CuratorOrderTab extends StatelessWidget {
  final List<FanzinePage> pages;

  const CuratorOrderTab({super.key, required this.pages});

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<FanzineEditorBloc>();
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PAGE ORDER (CURATOR)',
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

                final String? thumbUrl = page.gridUrl ?? page.listUrl ?? page.imageUrl;
                final bool isPending = thumbUrl == null || thumbUrl.isEmpty;

                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.black12, width: 0.5))),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text('$num.',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 32,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          border: Border.all(color: Colors.black12),
                          image: (thumbUrl != null && thumbUrl.isNotEmpty)
                              ? DecorationImage(image: NetworkImage(thumbUrl), fit: BoxFit.cover)
                              : null,
                        ),
                        child: isPending
                            ? const Center(child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.grey)))
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(isPending ? "Processing Assets..." : "Archival Page",
                              style: TextStyle(fontSize: 11, color: isPending ? Colors.grey : Colors.black),
                              overflow: TextOverflow.ellipsis)),
                      IconButton(
                          icon: const Icon(Icons.arrow_upward, size: 14),
                          onPressed: num > 1 ? () => bloc.add(ReorderPageRequested(page, -1, pages)) : null),
                      IconButton(
                          icon: const Icon(Icons.arrow_downward, size: 14),
                          onPressed: num < pages.length ? () => bloc.add(ReorderPageRequested(page, 1, pages)) : null),
                      IconButton(
                          icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                          tooltip: "Remove from issue",
                          onPressed: () => bloc.add(RemovePageRequested(page, pages))),
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