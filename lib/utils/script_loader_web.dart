// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js' as js; // Import for JavaScript interop
import 'package:flutter/foundation.dart';
import '../env.dart';

/// Injects the Google Maps JavaScript SDK into the document head.
/// Uses asynchronous loading to avoid performance warnings.
Future<void> loadGoogleMapsScript() async {
  if (Env.googleApiKeyWeb.isEmpty) {
    debugPrint('Warning: Google Maps config not loaded or API key is empty.');
    return;
  }

  // Prevent multiple injections
  if (html.document.getElementById('google-maps-sdk') != null) {
    return;
  }

  // Define the global callback that the Maps API expects.
  // We use allowInterop to make a Dart function accessible to JavaScript.
  js.context['initMap'] = js.allowInterop(() {
    debugPrint('Google Maps JavaScript SDK initialized via callback.');
  });

  final script = html.ScriptElement()
    ..id = 'google-maps-sdk'
  // Added 'loading=async' and 'callback=initMap' to follow Google's best practices
  // and suppress the performance warning in the console.
    ..src =
        'https://maps.googleapis.com/maps/api/js?key=${Env.googleApiKeyWeb}&libraries=places&loading=async&callback=initMap'
    ..async = true
    ..defer = true;

  html.document.head!.append(script);
  debugPrint('Google Maps SDK injection initiated.');
}