import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'upload_image_widget.dart'; // Ensure this import statement is correct

class OldProfilePage extends StatefulWidget {
  const OldProfilePage({super.key});

  @override
  State<OldProfilePage> createState() => _OldProfilePageState();
}

class _OldProfilePageState extends State<OldProfilePage> {
  // Current logged in user
  User? currentUser = FirebaseAuth.instance.currentUser;

  // Future for user details
  Future<DocumentSnapshot<Map<String, dynamic>>> getUserDetails() async {
    return await FirebaseFirestore.instance
        .collection("Users")
        .doc(currentUser!.email)
        .get();
  }

  // Future for user images
  Future<List<String>> getUserImages() async {
    final ListResult result = await FirebaseStorage.instance
        .ref('uploads/${currentUser!.email}')
        .listAll();
    final List<String> urls = await Future.wait(result.items.map((ref) => ref.getDownloadURL()).toList());
    return urls;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: getUserDetails(),
        builder: (context, snapshot) {
          // Loading
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          // Error
          else if (snapshot.hasError) {
            return Text("Error: ${snapshot.error}");
          }

          // Data received
          else if (snapshot.hasData) {
            // Extract data
            Map<String, dynamic>? user = snapshot.data!.data();

            return FutureBuilder<List<String>>(
              future: getUserImages(),
              builder: (context, snapshot) {
                // Show loading circle
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                // Display any errors
                else if (snapshot.hasError) {
                  return Text("Error: ${snapshot.error}");
                }

                // Get data
                else if (snapshot.hasData) {
                  final imageUrls = snapshot.data!;
                  return ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      Container(
                        color: Theme.of(context).colorScheme.surface,
                        child: Column(
                          children: [
                            // Back button
                            const BackButton(),

                            // Profile pic
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

                            // User name
                            Text(
                              user!['username'] ?? '@username',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 10),

                            // Email
                            Text(
                              user['email'] ?? 'email',
                              style: TextStyle(color: Colors.grey[600]),
                            ),

                            const SizedBox(height: 25),

                            // Upload Image button
                            ElevatedButton(
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  builder: (context) => UploadImageWidget(),
                                );
                              },
                              child: Text('Upload Image'),
                            ),

                            const SizedBox(height: 25),
                          ],
                        ),
                      ),
                      GridView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 4.0,
                          mainAxisSpacing: 4.0,
                        ),
                        itemCount: imageUrls.isEmpty ? 6 : imageUrls.length, // Show 6 placeholders if empty
                        itemBuilder: (context, index) {
                          if (imageUrls.isEmpty) {
                            // Placeholder images
                            return Container(
                              color: Colors.grey[300],
                              child: Icon(Icons.image, color: Colors.grey[700]),
                            );
                          } else {
                            // Actual uploaded images
                            return Image.network(
                              imageUrls[index],
                              fit: BoxFit.cover,
                            );
                          }
                        },
                      ),
                    ],
                  );
                } else {
                  return const Text('No images found');
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