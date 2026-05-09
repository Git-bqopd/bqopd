import 'dart:js_interop';
// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;
import 'package:flutter/foundation.dart';
import '../env.dart';

/// Global setter for the Maps initialization callback using modern JS interop.
@JS('initMap')
external set _initMap(JSFunction value);

/// Injects the Google Maps JavaScript SDK into the document head.
/// Migrated to package:web and dart:js_interop to resolve lint warnings
/// and support modern Flutter web standards.
Future<void> loadGoogleMapsScript() async {
  if (Env.googleApiKeyWeb.isEmpty) {
    debugPrint('Warning: Google Maps config not loaded or API key is empty.');
    return;
  }

  // Prevent multiple injections by checking the DOM
  if (web.document.getElementById('google-maps-sdk') != null) {
    return;
  }

  // Define the global callback that the Maps API expects.
  // Using .toJS to convert the Dart function to a JavaScript function.
  _initMap = (() {
    debugPrint('Google Maps JavaScript SDK initialized via callback.');
  }).toJS;

  // Create the script element using the modern package:web API
  final script = web.document.createElement('script') as web.HTMLScriptElement
    ..id = 'google-maps-sdk'
    ..src =
        'https://maps.googleapis.com/maps/api/js?key=${Env.googleApiKeyWeb}&libraries=places&loading=async&callback=initMap'
    ..async = true
    ..defer = true;

  // Append to the head of the document
  web.document.head?.append(script);
  debugPrint('Google Maps SDK injection initiated.');
}