import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart';
import 'package:flutter/foundation.dart';
import '../env.dart';
import '../utils/script_loader.dart';

/// Service to handle Google Maps and Places SDK operations.
class LocationService {
  late final FlutterGooglePlacesSdk _places;
  bool _isInitialized = false;

  void initialize() {
    if (_isInitialized) return;

    // Load script for web if necessary
    loadGoogleMapsScript();

    // Select correct API key for the platform
    String apiKey = kIsWeb ? Env.googleApiKeyWeb : Env.googleApiKeyAndroid;
    _places = FlutterGooglePlacesSdk(apiKey);

    _isInitialized = true;
  }

  Future<List<AutocompletePrediction>> getPredictions(String query) async {
    if (!_isInitialized) initialize();
    try {
      final response = await _places.findAutocompletePredictions(query);
      return response.predictions;
    } catch (e) {
      debugPrint("Error fetching predictions: $e");
      return [];
    }
  }

  Future<Map<String, String>?> getPlaceDetails(String placeId) async {
    if (!_isInitialized) initialize();
    try {
      final response = await _places.fetchPlace(
        placeId,
        fields: [PlaceField.AddressComponents, PlaceField.Location],
      );

      final place = response.place;
      if (place == null || place.addressComponents == null) return null;

      String streetNum = '';
      String route = '';
      String city = '';
      String state = '';
      String zip = '';
      String country = '';

      for (var c in place.addressComponents!) {
        final types = c.types;
        if (types.contains('street_number')) streetNum = c.name;
        if (types.contains('route')) route = c.name;
        if (types.contains('locality') || types.contains('postal_town')) city = c.name;
        if (types.contains('administrative_area_level_1')) state = c.shortName;
        if (types.contains('postal_code')) zip = c.name;
        if (types.contains('country')) country = c.name;
      }

      return {
        'street1': "$streetNum $route".trim(),
        'city': city,
        'state': state,
        'zipCode': zip,
        'country': country,
      };
    } catch (e) {
      debugPrint("Error fetching place details: $e");
      return null;
    }
  }
}