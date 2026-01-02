// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import '../env.dart';

Future<void> loadGoogleMapsScript() async {
  if (Env.googleApiKeyWeb.isEmpty) {
    debugPrint('Warning: Config not loaded or key is empty.');
    return;
  }

  if (html.document.getElementById('google-maps-sdk') != null) {
    return;
  }

  final script = html.ScriptElement()
    ..id = 'google-maps-sdk'
    ..src =
        'https://maps.googleapis.com/maps/api/js?key=${Env.googleApiKeyWeb}&libraries=places'
    ..async = true
    ..defer = true;

  html.document.head!.append(script);
  debugPrint('Google Maps SDK injected using key from config.json');
}
