import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bqopd_core/bqopd_core.dart';

class EventService implements IEventService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _collectionName = 'page_events';

  @override
  Future<void> addEvent(PageEvent event) async {
    await _db.collection(_collectionName).add(event.toJson());
  }

  @override
  Future<void> updateEvent(PageEvent event) async {
    if (event.id.isEmpty) {
      throw ArgumentError('Cannot update an event without a valid ID.');
    }
    await _db.collection(_collectionName).doc(event.id).update(event.toJson());
  }

  @override
  Future<void> deleteEvent(String id) async {
    if (id.isEmpty) return;
    await _db.collection(_collectionName).doc(id).delete();
  }

  @override
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