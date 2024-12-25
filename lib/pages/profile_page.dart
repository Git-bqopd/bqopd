import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../components/post_tile.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // current logged in user
  User? currentUser = FirebaseAuth.instance.currentUser;

  // future for user details
  Future<DocumentSnapshot<Map<String, dynamic>>> getUserDetails() async {
    return await FirebaseFirestore.instance
        .collection("Users")
        .doc(currentUser!.email)
        .get();
  }

  // stream for user posts
  Stream<QuerySnapshot> getUserPostsStream() {
    return FirebaseFirestore.instance
        .collection('Posts')
        .where('UserEmail', isEqualTo: currentUser!.email)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: getUserDetails(),
        builder: (context, snapshot) {
          // loading..
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          // error
          else if (snapshot.hasError) {
            return Text("Error: ${snapshot.error}");
          }

          // data received
          else if (snapshot.hasData) {
            // extract data
            Map<String, dynamic>? user = snapshot.data!.data();

            return StreamBuilder<QuerySnapshot>(
              stream: getUserPostsStream(),
              builder: (context, snapshot) {
                // show loading circle
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                // display any errors
                else if (snapshot.hasError) {
                  return Text("Error: ${snapshot.error}");
                }

                // get data
                else if (snapshot.hasData) {
                  return ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      Container(
                        color: Theme.of(context).colorScheme.surface,
                        child: Column(
                          children: [
                            // back button
                            const BackButton(),

                            // profile pic
                            Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              padding: const EdgeInsets.all(25),
                              child: const Icon(
                                Icons.person,
                                size: 64,
                              ),
                            ),

                            const SizedBox(height: 25),

                            // user name
                            Text(
                              user!['username'] ?? '@username',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 10),

                            // email
                            Text(
                              user['email'] ?? 'email',
                              style: TextStyle(color: Colors.grey[600]),
                            ),

                            const SizedBox(height: 25),
                          ],
                        ),
                      ),
                      ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: snapshot.data!.docs.length,
                        itemBuilder: (context, index) {
                          DocumentSnapshot post = snapshot.data!.docs[index];

                          String postMessage = post['PostMessage'];
                          String userEmail = post['UserEmail'];
                          Timestamp timestamp = post['TimeStamp'];
                          String postId = post.id;
                          List<String> likes =
                          List<String>.from(post['Likes'] ?? []);

                          return PostTile(
                            message: postMessage,
                            userEmail: userEmail,
                            timestamp: timestamp,
                            postId: postId,
                            likes: likes,
                          );
                        },
                      ),
                    ],
                  );
                } else {
                  return const Text('No data');
                }
              },
            );
          } else {
            return const Text('No data');
          }
        },
      ),
    );
  }
}
