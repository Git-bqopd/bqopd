DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  try { return value.toDate(); } catch (_) {}
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}

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
      startDate: _parseDate(data['startDate']),
      endDate: _parseDate(data['endDate']),
      category: data['category'],
      description: data['description'],
      imageUrl: data['imageUrl'],
    );
  }

  static PageEvent fromJson(Map<String, dynamic> json, String id) {
    return PageEvent.fromMap(json, id);
  }

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
      'startDate': startDate,
      'endDate': endDate,
      'category': category,
      'description': description,
      'imageUrl': imageUrl,
    };
  }

  Map<String, dynamic> toJson() {
    return toMap();
  }
}