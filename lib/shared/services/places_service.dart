import 'package:dio/dio.dart';
import '../../core/constants/app_constants.dart';

class PlaceSuggestion {
  final String placeId;
  final String description;

  const PlaceSuggestion({required this.placeId, required this.description});
}

class SelectedPlace {
  final String address;
  final double latitude;
  final double longitude;

  const SelectedPlace({
    required this.address,
    required this.latitude,
    required this.longitude,
  });
}

/// Google Places Autocomplete + Details (REST API).
class PlacesService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  static String get _key => AppConstants.googleMapsApiKey;

  static Future<List<PlaceSuggestion>> autocomplete(String input) async {
    final query = input.trim();
    if (query.length < 3 || _key.isEmpty) return [];

    try {
      final res = await _dio.get(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json',
        queryParameters: {
          'input':    query,
          'key':      _key,
          'components': 'country:in',
          'language': 'en',
        },
      );
      final data = res.data as Map<String, dynamic>;
      if (data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS') {
        return [];
      }
      final preds = data['predictions'] as List? ?? [];
      return preds.map((p) => PlaceSuggestion(
        placeId:     p['place_id'] as String,
        description: p['description'] as String,
      )).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<SelectedPlace?> placeDetails(String placeId) async {
    if (placeId.isEmpty || _key.isEmpty) return null;

    try {
      final res = await _dio.get(
        'https://maps.googleapis.com/maps/api/place/details/json',
        queryParameters: {
          'place_id': placeId,
          'fields':   'geometry,formatted_address,name',
          'key':      _key,
        },
      );
      final data = res.data as Map<String, dynamic>;
      if (data['status'] != 'OK') return null;

      final result = data['result'] as Map<String, dynamic>;
      final loc    = result['geometry']?['location'] as Map<String, dynamic>?;
      if (loc == null) return null;

      return SelectedPlace(
        address:   result['formatted_address'] as String? ?? result['name'] as String? ?? '',
        latitude:  (loc['lat'] as num).toDouble(),
        longitude: (loc['lng'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}
