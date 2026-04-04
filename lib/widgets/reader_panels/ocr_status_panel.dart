import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class OcrStatusPanel extends StatelessWidget {
  final String fanzineId;
  final String pageId;
  final String imageId;

  const OcrStatusPanel({
    super.key,
    required this.fanzineId,
    required this.pageId,
    required this.imageId,
  });

  @override
  Widget build(BuildContext context) {
    if (fanzineId.isEmpty || pageId.isEmpty) {
      return const Text("Pipeline data unavailable (Missing Page ID).", style: TextStyle(color: Colors.red, fontSize: 12));
    }

    return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('fanzines').doc(fanzineId).collection('pages').doc(pageId).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox(height: 50, child: Center(child: CircularProgressIndicator()));
          final data = snap.data!.data() as Map<String, dynamic>?;
          if (data == null) return const Text("Page data missing.");

          final status = data['status'] ?? 'ready';
          final error = data['errorLog'];

          Color statusColor = Colors.grey;
          if (status == 'ocr_complete' || status == 'complete' || status == 'review_needed' || status == 'transcribed') statusColor = Colors.green;
          if (status == 'queued' || status == 'entity_queued') statusColor = Colors.orange;
          if (status == 'error') statusColor = Colors.red;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("OCR STATUS (EGG MODE)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                  if (status == 'review_needed' || status == 'complete')
                    const Icon(Icons.check_circle, color: Colors.green, size: 14),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text(status.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: statusColor)),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                const Text("Error Log:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                Text(error, style: TextStyle(fontSize: 10, color: Colors.red[700], fontFamily: 'Courier')),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh, size: 14, color: Colors.red),
                      label: const Text("Retry Transcription", style: TextStyle(color: Colors.red, fontSize: 11)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                      onPressed: () {
                        FirebaseFirestore.instance.collection('fanzines').doc(fanzineId).collection('pages').doc(pageId).update({
                          'status': 'queued',
                          'errorLog': FieldValue.delete()
                        });
                      }
                  ),
                )
              ],
              const SizedBox(height: 16),
              const Divider(),
              const Text("RAW EXTRACTION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),
              if (imageId.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4)),
                  child: const Text("Image not registered yet. Waiting for initial pipeline run...", style: TextStyle(fontSize: 12, fontFamily: 'Courier', color: Colors.grey)),
                )
              else
                FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('images').doc(imageId).get(),
                    builder: (context, imgSnap) {
                      final raw = (imgSnap.data?.data() as Map?)?['text_raw'] ?? "Pending...";
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4)),
                        child: Text(raw, style: const TextStyle(fontSize: 12, fontFamily: 'Courier')),
                      );
                    }
                )
            ],
          );
        }
    );
  }
}