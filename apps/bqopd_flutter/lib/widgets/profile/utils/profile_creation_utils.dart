import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';

class ProfileCreationUtils {
  static Future<void> createFolio(BuildContext context, String userId, {bool isSingleImage = false}) async {
    try {
      final db = FirebaseFirestore.instance;
      final folioRef = db.collection('fanzines').doc();
      final shortCode = folioRef.id.substring(0, 7);

      await folioRef.set({
        'title': isSingleImage ? 'Single Image' : 'New Folio',
        'ownerId': userId,
        'editorId': userId,
        'editors': [],
        'isLive': false,
        'processingStatus': 'complete',
        'creationDate': FieldValue.serverTimestamp(),
        'type': 'folio',
        'shortCode': shortCode,
        'shortCodeKey': shortCode.toUpperCase(),
        'twoPage': true,
      });

      if (context.mounted) {
        context.push('/editor/${folioRef.id}');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  static Future<void> createArchivalFanzine(BuildContext context, String userId) async {
    try {
      final db = FirebaseFirestore.instance;
      final fzRef = db.collection('fanzines').doc();
      final shortCode = fzRef.id.substring(0, 7);

      await fzRef.set({
        'title': 'Archival Work',
        'ownerId': userId,
        'editorId': userId,
        'editors': [],
        'isLive': false,
        'processingStatus': 'idle',
        'creationDate': FieldValue.serverTimestamp(),
        'type': 'ingested',
        'shortCode': shortCode,
        'shortCodeKey': shortCode.toUpperCase(),
        'twoPage': true,
      });

      if (context.mounted) {
        context.push('/editor/${fzRef.id}');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  static Future<void> createCalendarFanzine(BuildContext context, String userId) async {
    try {
      final db = FirebaseFirestore.instance;
      final fanzineRef = db.collection('fanzines').doc();
      final shortCode = fanzineRef.id.substring(0, 7);

      await fanzineRef.set({
        'title': 'Convention Calendar 2026',
        'ownerId': userId,
        'editorId': userId,
        'editors': [],
        'isLive': false,
        'processingStatus': 'draft_calendar',
        'creationDate': FieldValue.serverTimestamp(),
        'type': 'calendar',
        'shortCode': shortCode,
        'shortCodeKey': shortCode.toUpperCase(),
        'twoPage': true,
      });

      await fanzineRef.collection('pages').add({'pageNumber': 1, 'templateId': 'calendar_left', 'status': 'ready'});
      await fanzineRef.collection('pages').add({'pageNumber': 2, 'templateId': 'calendar_right', 'status': 'ready'});

      if (context.mounted) {
        context.push('/editor/${fanzineRef.id}');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  static Future<void> createArticleFanzine(BuildContext context, String userId) async {
    try {
      final db = FirebaseFirestore.instance;
      final fzRef = db.collection('fanzines').doc();
      final shortCode = fzRef.id.substring(0, 7);

      await fzRef.set({
        'title': 'New Article',
        'ownerId': userId,
        'editorId': userId,
        'editors': [],
        'isLive': false,
        'processingStatus': 'complete',
        'creationDate': FieldValue.serverTimestamp(),
        'type': 'article',
        'shortCode': shortCode,
        'shortCodeKey': shortCode.toUpperCase(),
        'twoPage': true,
      });

      final imgRef = db.collection('images').doc();
      await imgRef.set({
        'uploaderId': userId,
        'type': 'template',
        'templateId': 'basic_text',
        'text_corrected': '# New Article\n\nStart typing...',
        'text_raw': '# New Article\n\nStart typing...',
        'title': 'Article Content',
        'timestamp': FieldValue.serverTimestamp(),
        'isGenerated': true,
        'folioContext': fzRef.id,
        'usedInFanzines': [fzRef.id],
      });

      await fzRef.collection('pages').add({
        'pageNumber': 1,
        'templateId': 'basic_text',
        'imageId': imgRef.id,
        'status': 'ready',
      });

      if (context.mounted) {
        context.push('/editor/${fzRef.id}');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  static Future<void> handlePdfUpload(BuildContext context, String userId, Function(bool) setUploadingState) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['pdf'], withData: true);

      if (result != null) {
        setUploadingState(true);
        PlatformFile file = result.files.first;
        Uint8List? fileBytes = file.bytes;

        if (fileBytes != null) {
          final storageRef = FirebaseStorage.instance.ref().child('uploads/raw_pdfs/${file.name}');
          final metadata = SettableMetadata(
              contentType: 'application/pdf',
              customMetadata: {
                'uploaderId': userId,
                'originalName': file.name
              });

          await storageRef.putData(fileBytes, metadata);

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploaded "${file.name}". Curator processing started.')));
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload Error: $e')));
      }
    } finally {
      setUploadingState(false);
    }
  }
}