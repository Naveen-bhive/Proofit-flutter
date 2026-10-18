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

class PlacesServiceException implements Exception {
  final String message;

  const PlacesServiceException(this.message);

  @override
  String toString() => message;
}

/// Google Places Autocomplete + Details (Places API New).
class PlacesService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  static String get _key => AppConstants.googleMapsApiKey;

  static Future<List<PlaceSuggestion>> autocomplete(String input) async {
    final query = input.trim();
    if (query.length < 3) return [];
    if (_key.isEmpty) {
      throw const PlacesServiceException('Google Maps API key is missing.');
    }

    try {
      final res = await _dio.post(
        'https://places.googleapis.com/v1/places:autocomplete',
        data: {
          'input': query,
          'includedRegionCodes': ['in'],
          'languageCode': 'en',
        },
        options: Options(headers: {
          'X-Goog-Api-Key': _key,
          'X-Goog-FieldMask':
              'suggestions.placePrediction.placeId,suggestions.placePrediction.text.text',
        }),
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      final suggestions = data['suggestions'];
      if (suggestions is! List) return [];

      return suggestions
          .whereType<Map>()
          .map((suggestion) => suggestion['placePrediction'])
          .whereType<Map>()
          .where((prediction) =>
              prediction['placeId'] is String &&
              prediction['text'] is Map &&
              (prediction['text'] as Map)['text'] is String)
          .map((prediction) => PlaceSuggestion(
                placeId: prediction['placeId'] as String,
                description:
                    (prediction['text'] as Map)['text'] as String,
              ))
          .toList();
    } on DioException catch (error) {
      throw PlacesServiceException(_errorMessage(error.response?.data));
    } on PlacesServiceException {
      rethrow;
    } catch (error) {
      throw PlacesServiceException(
        'Could not read address suggestions: $error',
      );
    }
  }

  static Future<SelectedPlace?> placeDetails(String placeId) async {
    if (placeId.isEmpty) {
      throw const PlacesServiceException('The selected address is invalid.');
    }
    if (_key.isEmpty) {
      throw const PlacesServiceException('Google Maps API key is missing.');
    }

    try {
      final res = await _dio.get(
        'https://places.googleapis.com/v1/places/${Uri.encodeComponent(placeId)}',
        options: Options(headers: {
          'X-Goog-Api-Key': _key,
          'X-Goog-FieldMask': 'formattedAddress,location,displayName',
        }),
      );
      final result = Map<String, dynamic>.from(res.data as Map);
      final location = result['location'];
      if (location is! Map ||
          location['latitude'] is! num ||
          location['longitude'] is! num) {
        throw const PlacesServiceException(
          'Google Places did not return coordinates for this address.',
        );
      }

      final displayName = result['displayName'];
      return SelectedPlace(
        address: result['formattedAddress'] as String? ??
            (displayName is Map ? displayName['text'] as String? : null) ??
            '',
        latitude: (location['latitude'] as num).toDouble(),
        longitude: (location['longitude'] as num).toDouble(),
      );
    } on DioException catch (error) {
      throw PlacesServiceException(_errorMessage(error.response?.data));
    } on PlacesServiceException {
      rethrow;
    } catch (error) {
      throw PlacesServiceException('Could not load this address: $error');
    }
  }

  static String _errorMessage(dynamic responseData) {
    final data = responseData is Map ? responseData : null;
    final error = data?['error'];
    final message = error is Map ? error['message'] : null;
    if (message is String && message.isNotEmpty) return message;
    return 'Address search failed. Check that Places API (New) is enabled for this API key.';
  }
}
