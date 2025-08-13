import 'dart:convert';

class ReturnIntent {
  final String url;
  final String? action;
  final Map<String, String>? extras;

  ReturnIntent({required this.url, this.action, this.extras});

  String encode() {
    final map = <String, dynamic>{'url': url};
    if (action != null) map['action'] = action;
    if (extras != null && extras!.isNotEmpty) map['extras'] = extras;
    final jsonStr = jsonEncode(map);
    return base64Url.encode(utf8.encode(jsonStr));
  }

  static ReturnIntent decode(String encoded) {
    final jsonStr = utf8.decode(base64Url.decode(encoded));
    final Map<String, dynamic> map = jsonDecode(jsonStr);
    final extras = (map['extras'] as Map?)
        ?.map((key, value) => MapEntry(key.toString(), value.toString()));
    return ReturnIntent(
      url: map['url'] as String,
      action: map['action'] as String?,
      extras: extras?.cast<String, String>(),
    );
  }
}
