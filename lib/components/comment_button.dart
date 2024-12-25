import 'package:flutter/material.dart';

class CommentButton extends StatelessWidget {
  final void Function()? onTap;
  final int totalCommentCount;

  const CommentButton({
    super.key,
    required this.onTap,
    required this.totalCommentCount,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          // icon
          Icon(
            Icons.comment,
            size: 20,
            color: Colors.grey[800],
          ),

          const SizedBox(width: 5),

          // number
          SizedBox(
            width: 10,
            child: Text(
              totalCommentCount.toString(),
              style: TextStyle(color: Colors.grey[800]),
            ),
          ),
        ],
      ),
    );
  }
}
