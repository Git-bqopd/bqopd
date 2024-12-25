import 'package:flutter/material.dart';

class UserTile extends StatelessWidget {
  final String userName;
  final String userEmail;
  const UserTile({
    super.key,
    required this.userName,
    required this.userEmail,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: Colors.grey[800]),
        Padding(
          padding: const EdgeInsets.all(25.0),
          child: Row(
            children: [
              Icon(
                Icons.person,
                color: Theme.of(context).colorScheme.inversePrimary,
              ),
              const SizedBox(width: 25),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    userEmail,
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
