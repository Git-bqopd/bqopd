import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'not_found_page.dart';

final RegExp _shortcodeRegExp = RegExp(r'^[0-9A-HJKMNP-TV-Z]{7}$');

class ResolverPage extends StatefulWidget {
  final String slug;
  const ResolverPage({super.key, required this.slug});

  @override
  State<ResolverPage> createState() => _ResolverPageState();
}

class _ResolverPageState extends State<ResolverPage> {
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final firestore = FirebaseFirestore.instance;
    final slug = widget.slug;
    DocumentSnapshot<Map<String, dynamic>> snap;
    if (_shortcodeRegExp.hasMatch(slug)) {
      snap = await firestore.doc('codes/$slug').get();
    } else {
      snap = await firestore.doc('aliases/${slug.toLowerCase()}').get();
    }
    if (!snap.exists) {
      setState(() => _notFound = true);
      return;
    }
    final data = snap.data()!;
    final type = data['type'] as String?;
    final targetRef = data['targetRef'] as String?;
    if (type == 'fanzine' && targetRef != null) {
      if (!mounted) return;
      context.go('/fanzine_page');
    } else {
      setState(() => _notFound = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_notFound) {
      return const NotFoundPage();
    }
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
