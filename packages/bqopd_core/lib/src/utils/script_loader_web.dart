import 'dart:js_interop';
// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;
import 'package:flutter/foundation.dart';
import '../env.dart';

@JS('initMap')
external set _initMap(JSFunction value);

Future<void> loadGoogleMapsScript() async {
  if (Env.googleApiKeyWeb.isEmpty) {
    debugPrint('Warning: Google Maps config not loaded or API key is empty.');
    return;
  }

  if (web.document.getElementById('google-maps-sdk') != null) {
    return;
  }

  _initMap = (() {
    debugPrint('Google Maps JavaScript SDK initialized via callback.');
  }).toJS;

  final script = web.document.createElement('script') as web.HTMLScriptElement
    ..id = 'google-maps-sdk'
    ..src =
        'https://maps.googleapis.com/maps/api/js?key=${Env.googleApiKeyWeb}&libraries=places&loading=async&callback=initMap'
    ..async = true
    ..defer = true;

  web.document.head?.append(script);
  debugPrint('Google Maps SDK injection initiated.');
}