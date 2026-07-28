class AppConstants {
  // Override at run time: flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.proofitapp.in/api',
  );
  static const String socketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: 'https://api.proofitapp.in',
  );

  // Web OAuth client ID — must match GOOGLE_CLIENT_ID on the backend
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '529731801742-nce1qeoi0rcqasjof6knels1s5c63ejq.apps.googleusercontent.com',
  );

  // Google Maps + Places — override via --dart-define=GOOGLE_MAPS_API_KEY=...
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyCMWX4y7t-DGwyH6R3hDMDNNh4Ed0ZVmeI',
  );

  // Google Drive folder name — created in staff's Drive
  static const String driveFolderName = 'ProofIt';

  // Google OAuth scopes
  static const List<String> googleScopes = [
    'email',
    'profile',
    'https://www.googleapis.com/auth/drive.file',
  ];

  static const String tokenKey    = 'auth_token';
  static const String userKey     = 'user_data';
  static const String orgKey      = 'org_data';
  static const int    locationEmitIntervalSec = 30;
}
