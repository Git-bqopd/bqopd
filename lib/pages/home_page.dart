import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../components/my_drawer.dart';
import '../components/post_button.dart';
import '../components/post_tile.dart';
import '../components/textfield.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // current logged in user
  User? user = FirebaseAuth.instance.currentUser;

  // logout
  void logout() {
    FirebaseAuth.instance.signOut();
  }

  // text editing controllers
  final TextEditingController newPostController = TextEditingController();

  void cancelPost() {
    newPostController.clear();
  }

  // post message
  void postMessage() {
    // only post if there is something to post in the textfield
    if (newPostController.text.isNotEmpty) {
      // store in firebase in all posts
      FirebaseFirestore.instance.collection("Posts").add({
        'UserEmail': user!.email!,
        'PostMessage': newPostController.text,
        'TimeStamp': Timestamp.now(),
        'Likes': [],
      });
    }
    newPostController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      endDrawer: MyDrawer(logout: logout),
      body: CustomScrollView(
        physics: const ClampingScrollPhysics(),
        slivers: [
          // APP BAR
          SliverAppBar(
            title: const Text("T H E   W A L L"),
            centerTitle: true,
            backgroundColor: Theme.of(context).colorScheme.surface,
            foregroundColor: Theme.of(context).colorScheme.inversePrimary,
            elevation: 0,
            floating: true,
            expandedHeight: 160,
            flexibleSpace: FlexibleSpaceBar(
              background: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(25.0),
                    child: Row(
                      children: [
                        // textfield
                        Expanded(
                          child: MyTextField(
                            controller: newPostController,
                            hintText: 'Say something..',
                            obscureText: false,
                          ),
                        ),

                        // post button
                        PostButton(onTap: postMessage),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // POSTS
          StreamBuilder(
            stream: FirebaseFirestore.instance
                .collection('Posts')
                .orderBy('TimeStamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              // show loading circle
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverToBoxAdapter(
                    child: Center(child: CircularProgressIndicator()));
              }

              // get all posts
              final posts = snapshot.data!.docs;

              // no data
              if (snapshot.data == null || posts.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(25.0),
                      child: Text("No Posts.. Post something!"),
                    ),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  childCount: posts.length,
                      (context, index) {
                    // get each post
                    final post = posts[index];

                    // get data from post
                    String message = post['PostMessage'];
                    String userEmail = post['UserEmail'];
                    Timestamp timestamp = post['TimeStamp'];
                    String postId = post.id;
                    List<String> likes = List<String>.from(post['Likes'] ?? []);

                    // post tile UI
                    return PostTile(
                      message: message,
                      userEmail: userEmail,
                      timestamp: timestamp,
                      postId: postId,
                      likes: likes,
                      key: ValueKey(postId),
                    );
                  },
                ),
              );

            },
          )
        ],
      ),
    );
  }
}
