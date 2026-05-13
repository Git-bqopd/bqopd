DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  try { return value.toDate(); } catch (_) {}
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}

class StaticPage {
  final String id;
  final String imageUrl;
  final double aspectRatio;
  final DateTime createdAt;

  StaticPage({
    required this.id,
    required this.imageUrl,
    this.aspectRatio = 0.625,
    required this.createdAt,
  });

  factory StaticPage.fromMap(String id, Map<String, dynamic> data) {
    return StaticPage(
      id: id,
      imageUrl: data['imageUrl'] ?? '',
      aspectRatio: (data['aspectRatio'] as num?)?.toDouble() ?? 0.625,
      createdAt: _parseDate(data['createdAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'imageUrl': imageUrl,
      'aspectRatio': aspectRatio,
      'createdAt': createdAt,
    };
  }
}