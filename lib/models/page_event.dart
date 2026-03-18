import 'package:cloud_firestore/cloud_firestore.dart';

/// Data model for community-submitted events.
class PageEvent {
  final String id;
  final String pageId;
  final String eventName;
  final String venueName;
  final String address;
  final String city;
  final String state;
  final String zip;
  final String username;
  final DateTime startDate;
  final DateTime endDate;
  final String category;
  final String description;
  final String imageUrl;

  PageEvent({
    required this.id,
    String? pageId,
    String? eventName,
    String? venueName,
    String? address,
    String? city,
    String? state,
    String? zip,
    String? username,
    DateTime? startDate,
    DateTime? endDate,
    String? category,
    String? description,
    String? imageUrl,
  })  : pageId = pageId ?? '',
        eventName = eventName ?? '',
        venueName = venueName ?? '',
        address = address ?? '',
        city = city ?? '',
        state = state ?? '',
        zip = zip ?? '',
        username = username ?? '',
        startDate = startDate ?? DateTime.now(),
        endDate = endDate ?? DateTime.now(),
        category = category ?? 'Convention',
        description = description ?? '',
        imageUrl = imageUrl ?? '';

  /// Factory constructor to create a PageEvent from a Firestore map and ID.
  factory PageEvent.fromMap(Map<String, dynamic> data, String id) {
    return PageEvent(
      id: id,
      pageId: data['pageId'],
      eventName: data['eventName'],
      venueName: data['venueName'],
      address: data['address'],
      city: data['city'],
      state: data['state'],
      zip: data['zip'],
      username: data['username'],
      startDate: (data['startDate'] as Timestamp?)?.toDate(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
      category: data['category'],
      description: data['description'],
      imageUrl: data['imageUrl'],
    );
  }

  /// Handles the 2-argument call from event_service.dart:36
  static PageEvent fromJson(Map<String, dynamic> json, String id) {
    return PageEvent.fromMap(json, id);
  }

  /// Converts the object to a map for Firestore storage.
  Map<String, dynamic> toMap() {
    return {
      'pageId': pageId,
      'eventName': eventName,
      'venueName': venueName,
      'address': address,
      'city': city,
      'state': state,
      'zip': zip,
      'username': username,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'category': category,
      'description': description,
      'imageUrl': imageUrl,
    };
  }

  /// Alias for toMap to support event_service.dart requirements.
  Map<String, dynamic> toJson() {
    return toMap();
  }
}