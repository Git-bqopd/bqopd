import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class Env {
  static String _googleApiKeyWeb = '';
  static String _googleApiKeyAndroid = '';

  static String get googleApiKeyWeb => _googleApiKeyWeb;
  static String get googleApiKeyAndroid => _googleApiKeyAndroid;

  static Future<void> load() async {
    try {
      final String response = await rootBundle.loadString('assets/config.json');
      final data = json.decode(response);
      _googleApiKeyWeb = data['google_api_key_web'] ?? '';
      _googleApiKeyAndroid = data['google_api_key_android'] ?? '';

      debugPrint('Config loaded successfully.');
    } catch (e) {
      debugPrint('Error loading config.json: $e');
      debugPrint('Make sure assets/config.json exists and is valid JSON.');
    }
  }
}
