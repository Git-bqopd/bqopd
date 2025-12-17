import 'dart:convert';
import 'package:flutter/services.dart';

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

      print('Config loaded successfully.');
    } catch (e) {
      print('Error loading config.json: $e');
      print('Make sure assets/config.json exists and is valid JSON.');
    }
  }
}