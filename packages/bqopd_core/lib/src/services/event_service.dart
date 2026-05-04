import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bqopd_models/bqopd_models.dart';

class EventService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _collectionName = 'page_events';

  /// Adds a new event to the Firestore collection
  Future<void> addEvent(PageEvent event) async {
    await _db.collection(_collectionName).add(event.toJson());
  }

  /// Updates an existing event using its ID
  Future<void> updateEvent(PageEvent event) async {
    if (event.id.isEmpty) {
      throw ArgumentError('Cannot update an event without a valid ID.');
    }
    await _db.collection(_collectionName).doc(event.id).update(event.toJson());
  }

  /// Deletes an event by ID
  Future<void> deleteEvent(String id) async {
    if (id.isEmpty) return;
    await _db.collection(_collectionName).doc(id).delete();
  }

  /// Returns a real-time stream of events associated with a specific pageId,
  /// ordered by the event's start date.
  Stream<List<PageEvent>> getEventsForPage(String pageId) {
    return _db
        .collection(_collectionName)
        .where('pageId', isEqualTo: pageId)
        .orderBy('startDate')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => PageEvent.fromJson(doc.data(), doc.id)).toList();
    });
  }
}