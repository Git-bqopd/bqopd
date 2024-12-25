import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'comment_bubble.dart';
import 'comment_button.dart';
import 'like_button.dart';
import 'package:intl/intl.dart';

class PostTile extends StatefulWidget {
  final String message;
  final String userEmail;
  final Timestamp timestamp;
  final String postId;
  final List<String> likes;

  const PostTile({
    Key? key,
    required this.message,
    required this.userEmail,
    required this.timestamp,
    required this.postId,
    required this.likes,
  }) : super(key: key);

  @override
  State<PostTile> createState() => _PostTileState();
}

class _PostTileState extends State<PostTile> {
  // user
  final currentUser = FirebaseAuth.instance.currentUser!;
  String timestampFormatted = '';

  @override
  void initState() {
    super.initState();

    DateTime dateTime = widget.timestamp.toDate();
    timestampFormatted = DateFormat('dd/MM/yyyy').format(dateTime);
  }

  // toggle like
  void toggleLike() {
    // access the doc in firebase
    DocumentReference postRef =
    FirebaseFirestore.instance.collection('Posts').doc(widget.postId);

    if (widget.likes.contains(currentUser.email)) {
      // if the post is now unliked, remove the current user email from the 'Likes' field
      postRef.update({
        'Likes': FieldValue.arrayRemove([currentUser.email]),
      });
    } else {
      // if the post is now liked, add the current user email to the 'Likes' field
      postRef.update({
        'Likes': FieldValue.arrayUnion([currentUser.email]),
      });
    }
  }

  // add a comment
  void addComment(String commentText) {
    // write the comment to firestore under the comments collection for this post
    if (commentText.isNotEmpty) {
      FirebaseFirestore.instance
          .collection("Posts")
          .doc(widget.postId)
          .collection("Comments")
          .add({
        "CommentText": commentText,
        "CommentedBy": currentUser.email,
        "CommentTime": Timestamp.now(),
      });
    }

    setState(() {});
  }

  // show dialog for adding comment
  final _commentTextController = TextEditingController();
  void showCommentDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add comment"),
          backgroundColor: Theme.of(context).colorScheme.primary,
          content: TextField(
            controller: _commentTextController,
            decoration: const InputDecoration(hintText: "Write a comment"),
          ),
          actions: [
            // post button
            TextButton(
              onPressed: () {
                // add comment
                addComment(_commentTextController.text);

                // clear controller
                _commentTextController.clear();

                // pop dialog box
                Navigator.pop(context);
              },
              child: const Text(
                "Post",
                style: TextStyle(color: Colors.grey),
              ),
            ),

            // cancel button
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        );
      },
    );
  }

  // get total number of comments
  Future<int> getCommentsCount() async {
    QuerySnapshot querySnapshot = await FirebaseFirestore.instance
        .collection("Posts")
        .doc(widget.postId)
        .collection("Comments")
        .get();

    return querySnapshot.docs.length;
  }

  @override
  Widget build(BuildContext context) {
    // get the like status
    bool isLiked = widget.likes.contains(currentUser.email);
    return Container(
      color: Theme.of(context).colorScheme.primary,
      child: Column(
        children: [
          Padding(
            padding:
            const EdgeInsets.only(left: 25, right: 25, top: 25, bottom: 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // message
                Text(
                  widget.message,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),

                // user + timestamp
                Row(
                  children: [
                    Text(
                      widget.userEmail,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary),
                    ),
                    Text(
                      ' • $timestampFormatted',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // comments under the post
                StreamBuilder(
                  stream: FirebaseFirestore.instance
                      .collection("Posts")
                      .doc(widget.postId)
                      .collection("Comments")
                      .orderBy("CommentTime", descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    // get all comments for this post
                    final comments = snapshot.data!.docs;

                    // Map comments to a list of CommentBubble widgets
                    List<Widget> commentBubbles =
                    comments.map<Widget>((comment) {
                      // format the time
                      DateTime dateTime = comment["CommentTime"].toDate();
                      String timestampFormatted =
                      DateFormat('EEE, d/M/y').format(dateTime);

                      return CommentBubble(
                        text: comment["CommentText"],
                        user: comment["CommentedBy"],
                        time: timestampFormatted,
                      );
                    }).toList();

                    // reverse list to show latest comment on the bottom
                    commentBubbles = commentBubbles.reversed.toList();

                    return Column(children: commentBubbles);
                  },
                ),

                const SizedBox(height: 20),

                // buttons -> comment + like
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // comment button
                    FutureBuilder(
                      future: getCommentsCount(),
                      builder: (context, snapshot) {
                        // no data
                        if (!snapshot.hasData || snapshot.data == 0) {
                          return CommentButton(
                            onTap: showCommentDialog,
                            totalCommentCount:
                            0, // Pass 0 if no comments are there
                          );
                        }

                        // living data
                        else {
                          return CommentButton(
                            onTap: showCommentDialog,
                            totalCommentCount:
                            snapshot.data!, // Pass the actual comment count
                          );
                        }
                      },
                    ),

                    const SizedBox(width: 10),

                    // like button
                    LikeButton(
                      isLiked: isLiked,
                      onTap: toggleLike,
                      likeCount: widget.likes.length,
                    ),
                  ],
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
          Divider(
            color: Theme.of(context).colorScheme.background,
            thickness: 1,
          ),
        ],
      ),
    );
  }
}
