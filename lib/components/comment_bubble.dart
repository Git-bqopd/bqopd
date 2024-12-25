import 'package:flutter/material.dart';

class CommentBubble extends StatelessWidget {
  final String text;
  final String user;
  final String time;

  const CommentBubble({
    super.key,
    required this.text,
    required this.user,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // comment
          Text(text),

          const SizedBox(height: 5),

          // user, time
          Row(
            children: [
              Text(
                time,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                    fontSize: 12),
              ),
              Text(
                ' • ',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                    fontSize: 12),
              ),
              Text(
                user,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                    fontSize: 12),
              ),
            ],
          )
        ],
      ),
    );
  }
}
