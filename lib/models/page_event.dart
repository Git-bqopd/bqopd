import 'package:cloud_firestore/cloud_firestore.dart';

class PageEvent {
  final String id;
  final String pageId;
  final String eventName;
  final DateTime startDate;
  final DateTime endDate;
  final String venueName;
  final String address;
  final String city;
  final String state;
  final String zip;
  final String? username;

  PageEvent({
    required this.id,
    required this.pageId,
    required this.eventName,
    required this.startDate,
    required this.endDate,
    required this.venueName,
    required this.address,
    required this.city,
    required this.state,
    required this.zip,
    this.username,
  });

  factory PageEvent.fromJson(Map<String, dynamic> json, String documentId) {
    return PageEvent(
      id: documentId,
      pageId: json['pageId'] as String? ?? '',
      eventName: json['eventName'] as String? ?? '',
      startDate: (json['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (json['endDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      venueName: json['venueName'] as String? ?? '',
      address: json['address'] as String? ?? '',
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? '',
      zip: json['zip'] as String? ?? '',
      username: json['username'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pageId': pageId,
      'eventName': eventName,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'venueName': venueName,
      'address': address,
      'city': city,
      'state': state,
      'zip': zip,
      'username': username,
    };
  }
}