import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class MooScreen extends StatefulWidget {
  const MooScreen({Key? key}) : super(key: key);

  @override
  State<MooScreen> createState() => _MooScreenState();
}

class _MooScreenState extends State<MooScreen> {
  final _textController = TextEditingController();
  final _messages = FirebaseFirestore.instance.collection('terminal_rpg');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal RPG'),
      ),
      body: Column(
        children: [
          // The chat messages will go here
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _messages.orderBy('timestamp').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                // Render chat messages here
                List<Text> messages = snapshot.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return Text('${data['sender']}: ${data['text']}');
                }).toList();

                return SingleChildScrollView(
                  child: Column(
                    children: messages,
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Enter message...',
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Send a message to the database
                    _messages.add({
                      'text': _textController.text,
                      'sender': 'Your Name', // Replace with actual user ID
                      'timestamp': FieldValue.serverTimestamp(),
                    });
                    _textController.clear();
                  },
                  child: const Text('Send'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
}