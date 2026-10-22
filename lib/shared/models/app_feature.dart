/// Feature keys the backend can switch off per organisation (see
/// backend/src/config/features.js). The server sends an on/off map for these
/// with the org; screens for disabled features are hidden.
abstract final class AppFeature {
  static const attendance = 'attendance';
  static const jobs = 'jobs';
  static const customers = 'customers';
  static const leaves = 'leaves';
  static const holidays = 'holidays';
  static const workingHours = 'workingHours';
  static const liveMap = 'liveMap';
  static const export = 'export';
  static const shareReport = 'shareReport';
}
