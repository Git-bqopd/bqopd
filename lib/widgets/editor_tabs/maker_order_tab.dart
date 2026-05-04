import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/fanzine_editor_bloc.dart';
import '../../models/fanzine.dart';
import '../../models/fanzine_page.dart';

class MakerOrderTab extends StatelessWidget {
  final Fanzine fanzine;
  final List<FanzinePage> pages;

  const MakerOrderTab({super.key, required this.fanzine, required this.pages});

  bool _isPage5x8(FanzinePage page) {
    if (page.templateId != null) return true;
    final w = page.width;
    final h = page.height;
    if (w != null && h != null) {
      final ratio = w / h;
      return ratio >= 0.58 && ratio <= 0.67;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<FanzineEditorBloc>();

    final fullPages = pages.where((p) => _isPage5x8(p)).toList();
    final ordered = fullPages.where((p) => p.pageNumber > 0).toList();
    final unordered = fullPages.where((p) => p.pageNumber == 0).toList();

    return LayoutBuilder(
        builder: (context, constraints) {
          final bool isCompact = constraints.maxWidth < 600;

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('flatplan',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                if (ordered.isEmpty)
                  const Text('no pages in the sequence.',
                      style: TextStyle(color: Colors.grey, fontSize: 12))
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: ordered.length,
                    itemBuilder: (context, index) {
                      final page = ordered[index];
                      final num = page.pageNumber;
                      final bool showLayoutButtons = !(num == 1 && fanzine.hasCover);

                      final layoutRow = Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SegmentedButton<String>(
                              showSelectedIcon: false,
                              emptySelectionAllowed: true,
                              style: SegmentedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                textStyle: const TextStyle(fontSize: 9),
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                selectedBackgroundColor: Colors.grey,
                                selectedForegroundColor: Colors.white,
                              ),
                              segments: const [
                                ButtonSegment(value: 'start', label: Text('start')),
                                ButtonSegment(value: 'end', label: Text('end')),
                              ],
                              selected: page.spreadPosition != null ? {page.spreadPosition!} : <String>{},
                              onSelectionChanged: (sel) {
                                final val = sel.isEmpty ? null : sel.first;
                                bloc.add(UpdatePageLayoutRequested(page, val, page.sidePreference, pages));
                              }
                          ),
                          const SizedBox(width: 4),
                          SegmentedButton<String>(
                              showSelectedIcon: false,
                              emptySelectionAllowed: false,
                              style: SegmentedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                textStyle: const TextStyle(fontSize: 9),
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                selectedBackgroundColor: Colors.grey,
                                selectedForegroundColor: Colors.white,
                              ),
                              segments: const [
                                ButtonSegment(value: 'left', label: Text('left')),
                                ButtonSegment(value: 'either', label: Text('either')),
                                ButtonSegment(value: 'right', label: Text('right')),
                              ],
                              selected: {page.sidePreference},
                              onSelectionChanged: (sel) {
                                bloc.add(UpdatePageLayoutRequested(page, page.spreadPosition, sel.first, pages));
                              }
                          ),
                        ],
                      );

                      final coverRow = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text("cover", style: TextStyle(fontSize: 10, color: Colors.grey)),
                          Transform.scale(
                            scale: 0.7,
                            child: Switch(
                              value: fanzine.hasCover,
                              activeColor: Colors.white,
                              activeTrackColor: Colors.grey,
                              inactiveThumbColor: Colors.grey.shade400,
                              inactiveTrackColor: Colors.grey.shade200,
                              onChanged: (val) => bloc.add(ToggleHasCoverRequested(val)),
                            ),
                          ),
                        ],
                      );

                      Widget layoutButtonsWidget = isCompact
                          ? (showLayoutButtons ? Align(alignment: Alignment.centerLeft, child: FittedBox(fit: BoxFit.scaleDown, child: layoutRow)) : const SizedBox.shrink())
                          : SizedBox(width: 280, child: showLayoutButtons ? FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: layoutRow) : null);

                      Widget controlButtonsWidget = Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isCompact)
                            if (num == 1) coverRow else const SizedBox.shrink()
                          else
                            SizedBox(width: 90, child: num == 1 ? coverRow : null),
                          IconButton(
                              icon: const Icon(Icons.arrow_upward, size: 14, color: Colors.black87),
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              onPressed: num > 1 ? () => bloc.add(ReorderPageRequested(page, -1, pages)) : null),
                          const SizedBox(width: 12),
                          IconButton(
                              icon: const Icon(Icons.arrow_downward, size: 14, color: Colors.black87),
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              onPressed: num < ordered.length ? () => bloc.add(ReorderPageRequested(page, 1, pages)) : null),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.close, size: 14, color: Colors.black54),
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            onPressed: () => bloc.add(TogglePageOrderingRequested(page, false)),
                            tooltip: "unorder",
                          ),
                          if (!isCompact) const SizedBox(width: 8),
                        ],
                      );

                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: Colors.black12, width: 0.5))),
                        child: isCompact
                            ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                SizedBox(width: 24, child: Text('$num.', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                Expanded(child: Text(page.templateId != null ? "template page" : "image page", style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                            if (showLayoutButtons) ...[
                              const SizedBox(height: 8),
                              layoutButtonsWidget,
                            ],
                            const SizedBox(height: 4),
                            controlButtonsWidget,
                          ],
                        )
                            : Row(
                          children: [
                            SizedBox(width: 24, child: Text('$num.', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            Expanded(child: Text(page.templateId != null ? "template page" : "image page", style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                            layoutButtonsWidget,
                            const SizedBox(width: 8),
                            controlButtonsWidget,
                          ],
                        ),
                      );
                    },
                  ),

                if (unordered.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  const Text('unordered full pages',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isCompact ? 3 : 5,
                      childAspectRatio: 0.625,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: unordered.length,
                    itemBuilder: (context, index) {
                      final page = unordered[index];
                      return GestureDetector(
                        onTap: () => bloc.add(TogglePageOrderingRequested(page, true)),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black12),
                            image: page.imageUrl != null ? DecorationImage(image: NetworkImage(page.imageUrl!), fit: BoxFit.cover) : null,
                          ),
                          child: page.imageUrl == null ? const Center(child: Icon(Icons.auto_awesome_motion, size: 16, color: Colors.grey)) : null,
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          );
        }
    );
  }
}