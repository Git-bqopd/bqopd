import '../models/page_event.dart';

abstract class IEventService {
  Future<void> addEvent(PageEvent event);
  Future<void> updateEvent(PageEvent event);
  Future<void> deleteEvent(String id);
  Stream<List<PageEvent>> getEventsForPage(String pageId);
}