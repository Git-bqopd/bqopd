import 'package:flutter/material.dart';

class LikeButton extends StatelessWidget {
  final bool isLiked;
  final void Function()? onTap;
  final int likeCount;
  const LikeButton({
    super.key,
    required this.isLiked,
    required this.onTap,
    required this.likeCount,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          // icon
          Icon(
            isLiked ? Icons.favorite : Icons.favorite_border,
            size: 20,
            color: isLiked ? Colors.red : Colors.grey[800],
          ),

          const SizedBox(width: 5),

          // number
          SizedBox(
            width: 10,
            child: Text(
              likeCount.toString(),
              style: TextStyle(color: Colors.grey[800]),
            ),
          ),
        ],
      ),
    );
  }
}
