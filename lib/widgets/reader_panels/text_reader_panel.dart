import 'package:flutter/material.dart';
import '../../utils/link_parser.dart';

class TextReaderPanel extends StatelessWidget {
  final String text;
  final ValueNotifier<double> fontSizeNotifier;

  const TextReaderPanel({
    super.key,
    required this.text,
    required this.fontSizeNotifier,
  });

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text("No text available for this page.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min, // Avoid infinite height crash
      children: [
        _FontSizeSlider(fontSizeNotifier: fontSizeNotifier),
        ValueListenableBuilder<double>(
          valueListenable: fontSizeNotifier,
          builder: (context, size, _) {
            return SelectableText.rich(
              LinkParser.renderLinks(
                context,
                text,
                baseStyle: TextStyle(fontSize: size, fontFamily: 'Georgia'),
              ),
              textAlign: TextAlign.justify,
            );
          },
        ),
      ],
    );
  }
}

class _FontSizeSlider extends StatelessWidget {
  final ValueNotifier<double> fontSizeNotifier;

  const _FontSizeSlider({required this.fontSizeNotifier});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          const Icon(Icons.format_size, size: 14, color: Colors.grey),
          Expanded(
            child: ValueListenableBuilder<double>(
              valueListenable: fontSizeNotifier,
              builder: (context, size, _) {
                return SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: Colors.black54,
                    inactiveTrackColor: Colors.black12,
                    thumbColor: Colors.black,
                  ),
                  child: Slider(
                    value: size,
                    min: 12.0,
                    max: 48.0,
                    divisions: 36,
                    onChanged: (val) => fontSizeNotifier.value = val,
                  ),
                );
              },
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: fontSizeNotifier,
            builder: (context, size, _) => Text(
              "${size.toInt()}px",
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}