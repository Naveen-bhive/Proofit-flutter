import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/utils/api_error_utils.dart';
import '../../../core/network/api_service.dart';
import '../../../shared/models/report_model.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/services/auth_storage.dart';
import '../../../shared/models/org_model.dart';
import '../../../shared/services/live_location_tracker.dart';
import '../../../shared/services/location_service.dart';
import '../../../shared/services/drive_service.dart';
import '../../../shared/services/google_auth_service.dart';
import '../../../shared/services/battery_optimization_service.dart';

/// Staff-facing live tracking health shown on home while checked in.
enum TrackingHealthStatus {
  unknown,
  active,
  gpsOff,
  permissionMissing,
  batteryRisk,
  trackerFailed,
}

class StaffState {
  final bool todayLoading;
  final bool historyLoading;
  final bool notificationsLoading;
  final List<ReportModel> todayReports;
  final List<ReportModel> historyReports;
  final ReportModel? selectedReport;
  final String userName;
  final String orgName;
  final int dailyTarget;
  final int submittedToday;
  final int streak;
  final bool hasPendingDraft;
  final DateTime? checkInTime;
  final bool isCheckedIn;
  final List<Map<String, dynamic>> notifications;
  final int weekCount, monthCount, totalCount;
  final int draftCount;
  /// Bumped after report submit/save so jobs/home screens can refresh.
  final int jobsEpoch;
  final TrackingHealthStatus trackingHealth;

  const StaffState({
    this.todayLoading = false,
    this.historyLoading = false,
    this.notificationsLoading = false,
    this.todayReports = const [], this.historyReports = const [],
    this.selectedReport, this.userName = '', this.orgName = '',
    this.dailyTarget = 0, this.submittedToday = 0, this.streak = 0,
    this.hasPendingDraft = false, this.checkInTime, this.isCheckedIn = false,
    this.notifications = const [], this.weekCount = 0, this.monthCount = 0, this.totalCount = 0,
    this.draftCount = 0,
    this.jobsEpoch = 0,
    this.trackingHealth = TrackingHealthStatus.unknown,
  });

  StaffState copyWith({
    bool? todayLoading, bool? historyLoading, bool? notificationsLoading,
    List<ReportModel>? todayReports, List<ReportModel>? historyReports,
    ReportModel? selectedReport, bool clearSelectedReport = false,
    String? userName, String? orgName,
    int? dailyTarget, int? submittedToday, int? streak, bool? hasPendingDraft,
    DateTime? checkInTime, bool? isCheckedIn, List<Map<String,dynamic>>? notifications,
    int? weekCount, int? monthCount, int? totalCount, int? draftCount,
    int? jobsEpoch,
    TrackingHealthStatus? trackingHealth,
  }) => StaffState(
    todayLoading: todayLoading ?? this.todayLoading,
    historyLoading: historyLoading ?? this.historyLoading,
    notificationsLoading: notificationsLoading ?? this.notificationsLoading,
    todayReports: todayReports ?? this.todayReports,
    historyReports: historyReports ?? this.historyReports,
    selectedReport: clearSelectedReport ? null : (selectedReport ?? this.selectedReport),
    userName: userName ?? this.userName, orgName: orgName ?? this.orgName,
    dailyTarget: dailyTarget ?? this.dailyTarget, submittedToday: submittedToday ?? this.submittedToday,
    streak: streak ?? this.streak, hasPendingDraft: hasPendingDraft ?? this.hasPendingDraft,
    checkInTime: checkInTime ?? this.checkInTime, isCheckedIn: isCheckedIn ?? this.isCheckedIn,
    notifications: notifications ?? this.notifications, weekCount: weekCount ?? this.weekCount,
    monthCount: monthCount ?? this.monthCount, totalCount: totalCount ?? this.totalCount,
    draftCount: draftCount ?? this.draftCount,
    jobsEpoch: jobsEpoch ?? this.jobsEpoch,
    trackingHealth: trackingHealth ?? this.trackingHealth,
  );
}

final staffControllerProvider = StateNotifierProvider<StaffController, StaffState>(
  (ref) => StaffController(ref.read(apiServiceProvider)));

class StaffController extends StateNotifier<StaffState> {
  final ApiService _api;
  int _todayLoadSeq = 0;
  int? _todaySpinnerSeq;

  StaffController(this._api) : super(const StaffState()) { _initUser(); }

  void reset() => state = const StaffState();

  List<ReportModel> _parseReports(dynamic data) {
    final reportsRaw = data is Map ? data['reports'] : null;
    if (reportsRaw is! List) return [];
    final reports = <ReportModel>[];
    for (final raw in reportsRaw) {
      if (raw is! Map) continue;
      try {
        reports.add(ReportModel.fromJson(Map<String, dynamic>.from(raw)));
      } catch (_) {}
    }
    return reports;
  }

  Future<void> _initUser() async {
    await syncUserFromSession();
  }

  /// Reload display name / org from secure storage (after login or token refresh).
  Future<void> syncUserFromSession() async {
    final user = await AuthStorage.getUser();
    final org  = await AuthStorage.getOrg();
    if (user == null) return;
    state = state.copyWith(
      userName:    user.name,
      orgName:     org?.name ?? '',
      dailyTarget: user.dailyTarget,
      streak:      user.streak,
    );
  }

  Future<void> applyOrgName(String name) async {
    final org = await AuthStorage.getOrg();
    if (org != null) await AuthStorage.updateOrg(org.copyWith(name: name));
    state = state.copyWith(orgName: name);
  }

  Future<void> syncOrgFromServer() async {
    try {
      final res = await _api.get('/auth/org');
      if (res.data['success'] == true && res.data['data'] != null) {
        final org = OrgModel.fromJson(Map<String, dynamic>.from(res.data['data']));
        await AuthStorage.updateOrg(org);
        state = state.copyWith(orgName: org.name);
      }
    } catch (_) {}
  }

  /// One entry point from [StaffShell] — avoids overlapping loads that leave
  /// `todayLoading` stuck when requests race on cold start.
  Future<void> bootstrapHome() async {
    await syncUserFromSession();
    await Future.wait<void>([
      loadTodayReports(),
      loadCheckInStatus(),
      loadProfileStats(),
      syncOrgFromServer(),
    ]);
    if (state.isCheckedIn) {
      unawaited(evaluateTrackingHealth());
    }
  }

  Future<void> loadTodayReports({bool silent = false}) async {
    final seq = ++_todayLoadSeq;
    // Only show skeleton when we have nothing to display yet.
    final showSpinner = !silent && state.todayReports.isEmpty;
    if (showSpinner) {
      state = state.copyWith(todayLoading: true);
      _todaySpinnerSeq = seq;
    }

    try {
      final res = await _api
          .get('/reports/today')
          .timeout(const Duration(seconds: 10));
      if (seq != _todayLoadSeq) return;

      if (res.data['success'] == true) {
        final data = res.data['data'];
        final all = _parseReports(data);
        final submitted = all.where((r) => r.isSubmitted).toList();
        final submittedCount = data is Map ? data['submittedCount'] : null;
        state = state.copyWith(
          todayLoading: false,
          todayReports: submitted,
          submittedToday: (submittedCount is num)
              ? submittedCount.toInt()
              : submitted.length,
          hasPendingDraft: all.any((r) => !r.isSubmitted),
        );
        if (_todaySpinnerSeq == seq) _todaySpinnerSeq = null;
        unawaited(loadProfileStats());
        return;
      }
    } catch (_) {
      // Keep existing list on failure / timeout.
    } finally {
      if (_todaySpinnerSeq == seq) _todaySpinnerSeq = null;
      // Always clear skeleton for the request that showed it, or the latest call.
      if (state.todayLoading &&
          (seq == _todayLoadSeq || showSpinner)) {
        state = state.copyWith(todayLoading: false);
      }
    }
  }

  Future<List<Map<String, dynamic>>> loadMyJobs({String? status}) async {
    try {
      final params = <String, dynamic>{'limit': 100};
      if (status != null && status.isNotEmpty) params['status'] = status;
      final res = await _api.get('/jobs', params: params);
      if (res.data['success'] == true) {
        return List<Map<String, dynamic>>.from(res.data['data']['jobs'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  Future<void> loadHistory(String filter) async {
    state = state.copyWith(historyLoading: true);
    try {
      final res = await _api.get('/reports/history', params: {
        'filter': filter == 'all' ? 'all' : filter,
      });
      if (res.data['success'] == true) {
        final data = res.data['data'];
        final list = data is List
            ? data
            : (data is Map ? data['reports'] as List? : null) ?? [];
        final historyReports = <ReportModel>[];
        for (final raw in list) {
          if (raw is! Map) continue;
          try {
            historyReports.add(ReportModel.fromJson(Map<String, dynamic>.from(raw)));
          } catch (_) {}
        }
        state = state.copyWith(
          historyLoading: false,
          historyReports: historyReports,
        );
      } else {
        state = state.copyWith(historyLoading: false);
      }
    } catch (_) {
      state = state.copyWith(historyLoading: false);
    }
  }

  Future<bool> loadReportDetail(String reportId) async {
    final report = await fetchReportDetail(reportId);
    return report != null;
  }

  /// Loads a report and returns it directly (avoids provider race on resume).
  Future<ReportModel?> fetchReportDetail(String reportId) async {
    state = state.copyWith(clearSelectedReport: true);
    try {
      final res = await _api
          .get('/reports/$reportId')
          .timeout(const Duration(seconds: 10));
      if (res.data['success'] == true && res.data['data'] is Map) {
        final report = ReportModel.fromJson(
          Map<String, dynamic>.from(res.data['data'] as Map),
        );
        // API already fetched by id — accept when we got a report back.
        if (report.id != null && report.id!.isNotEmpty) {
          state = state.copyWith(selectedReport: report);
          return report;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String?> uploadPhotoToServer(File file) async => _uploadToApi(file);

  Future<String?> _uploadToApi(File file) async {
    try {
      final ext = file.path.split('.').last.toLowerCase();
      final mime = switch (ext) { 'png' => 'image/png', 'webp' => 'image/webp', _ => 'image/jpeg' };
      final res = await _api.uploadMultipart('/reports/upload-photo', file: file, mimeType: mime);
      if (res.data['success'] == true) return res.data['data']['publicUrl'] as String?;
      return null;
    } catch (_) { return null; }
  }

  /// Google Drive first, then server backup upload.
  Future<({String? driveId, String? serverUrl, String? error})> uploadPhotoWithFallback({
    required File file,
    required String orgName,
    required String jobTitle,
    required String label,
    void Function(String status)? onStatus,
  }) async {
    String? driveError;
    onStatus?.call('Saving to Google Drive...');

    if (GoogleAuthService.driveApi == null) {
      await GoogleAuthService.ensureDriveAccess().timeout(
        const Duration(seconds: 8),
        onTimeout: () => const DriveAccessResult(
          ok: false,
          error: 'Google Drive authorization timed out',
        ),
      );
    }

    if (GoogleAuthService.driveApi != null) {
      final driveResult = await DriveService.uploadPhoto(
        file:     file,
        orgName:  orgName,
        jobTitle: jobTitle,
        label:    label,
      );
      if (driveResult.ok) {
        return (driveId: driveResult.fileId, serverUrl: null, error: null);
      }
      driveError = driveResult.error;
    } else {
      driveError = 'Google Drive not linked on this device';
    }

    onStatus?.call('Uploading to server...');
    final serverUrl = await uploadPhotoToServer(file)
        .timeout(const Duration(seconds: 60), onTimeout: () => null);
    if (serverUrl != null) {
      return (driveId: null, serverUrl: serverUrl, error: null);
    }

    return (
      driveId: null,
      serverUrl: null,
      error: driveError ?? 'Photo upload failed. Check your connection and tap Retry.',
    );
  }

  Future<({bool ok, String? error, String? reportId})> submitReport({
    required String jobTitle,
    required String? notes,
    File? beforeImage,
    File? afterImage,
    String? beforeDriveId,
    String? afterDriveId,
    String? beforeUrl,
    String? afterUrl,
    DateTime? beforeCapturedAt,
    double? beforeLatitude,
    double? beforeLongitude,
    String? beforeAddress,
    DateTime? afterCapturedAt,
    double? afterLatitude,
    double? afterLongitude,
    String? afterAddress,
    required double? latitude,
    required double? longitude,
    required String? address,
    required bool asDraft,
    String? existingReportId,
    String? jobId,
  }) async {
    try {
      Map<String, dynamic>? beforeMedia;
      Map<String, dynamic>? afterMedia;

      Map<String, dynamic> mediaMeta({
        DateTime? capturedAt,
        double? lat,
        double? lng,
        String? addr,
      }) => {
        if (capturedAt != null) 'capturedAt': capturedAt.toUtc().toIso8601String(),
        if (lat != null) 'latitude': lat,
        if (lng != null) 'longitude': lng,
        if (addr != null && addr.isNotEmpty) 'address': addr,
      };

      if (beforeImage != null) {
        final org = await AuthStorage.getOrg();
        final uploaded = await uploadPhotoWithFallback(
          file:     beforeImage,
          orgName:  org?.name ?? state.orgName,
          jobTitle: jobTitle,
          label:    'Before',
        );
        if (uploaded.driveId != null) {
          beforeMedia = {
            'driveFileId': uploaded.driveId,
            'type': 'photo',
            ...mediaMeta(
              capturedAt: beforeCapturedAt,
              lat: beforeLatitude,
              lng: beforeLongitude,
              addr: beforeAddress,
            ),
          };
        } else if (uploaded.serverUrl != null) {
          beforeMedia = {
            'url': uploaded.serverUrl,
            'type': 'photo',
            ...mediaMeta(
              capturedAt: beforeCapturedAt,
              lat: beforeLatitude,
              lng: beforeLongitude,
              addr: beforeAddress,
            ),
          };
        }
      } else if (beforeDriveId != null) {
        beforeMedia = {
          'driveFileId': beforeDriveId,
          'type': 'photo',
          ...mediaMeta(
            capturedAt: beforeCapturedAt,
            lat: beforeLatitude,
            lng: beforeLongitude,
            addr: beforeAddress,
          ),
        };
      } else if (beforeUrl != null) {
        beforeMedia = {
          'url': beforeUrl,
          'type': 'photo',
          ...mediaMeta(
            capturedAt: beforeCapturedAt,
            lat: beforeLatitude,
            lng: beforeLongitude,
            addr: beforeAddress,
          ),
        };
      }

      if (afterImage != null) {
        final org = await AuthStorage.getOrg();
        final uploaded = await uploadPhotoWithFallback(
          file:     afterImage,
          orgName:  org?.name ?? state.orgName,
          jobTitle: jobTitle,
          label:    'After',
        );
        if (uploaded.driveId != null) {
          afterMedia = {
            'driveFileId': uploaded.driveId,
            'type': 'photo',
            ...mediaMeta(
              capturedAt: afterCapturedAt,
              lat: afterLatitude,
              lng: afterLongitude,
              addr: afterAddress,
            ),
          };
        } else if (uploaded.serverUrl != null) {
          afterMedia = {
            'url': uploaded.serverUrl,
            'type': 'photo',
            ...mediaMeta(
              capturedAt: afterCapturedAt,
              lat: afterLatitude,
              lng: afterLongitude,
              addr: afterAddress,
            ),
          };
        }
      } else if (afterDriveId != null) {
        afterMedia = {
          'driveFileId': afterDriveId,
          'type': 'photo',
          ...mediaMeta(
            capturedAt: afterCapturedAt,
            lat: afterLatitude,
            lng: afterLongitude,
            addr: afterAddress,
          ),
        };
      } else if (afterUrl != null) {
        afterMedia = {
          'url': afterUrl,
          'type': 'photo',
          ...mediaMeta(
            capturedAt: afterCapturedAt,
            lat: afterLatitude,
            lng: afterLongitude,
            addr: afterAddress,
          ),
        };
      }

      if (!asDraft && (jobId == null || jobId.isEmpty)) {
        return (ok: false, error: 'Select an assigned job before submitting.', reportId: null);
      }

      if (!asDraft) {
        if (beforeMedia == null) return (ok: false, error: 'Before photo is missing — tap Retry on the photo upload.', reportId: null);
        if (afterMedia == null) return (ok: false, error: 'After photo is missing — tap Retry on the photo upload.', reportId: null);
      }

      final payload = {
        'jobTitle': jobTitle,
        'notes': notes,
        'status': asDraft ? 'draft' : 'submitted',
        'location': latitude != null ? {'latitude': latitude, 'longitude': longitude, 'address': address} : null,
        if (beforeMedia != null) 'beforeMedia': beforeMedia,
        if (afterMedia != null) 'afterMedia': afterMedia,
        if (jobId != null && jobId.isNotEmpty) 'jobId': jobId,
      };

      final res = existingReportId != null
          ? await _api.put('/reports/$existingReportId', data: payload)
          : await _api.post('/reports', data: payload);

      if (res.data['success'] != true) {
        return (ok: false, error: res.data['message']?.toString() ?? 'Server rejected the report.', reportId: null);
      }
      final reportId = res.data['data']?['_id']?.toString();
      await loadTodayReports();
      await loadProfileStats();
      state = state.copyWith(jobsEpoch: state.jobsEpoch + 1);
      return (ok: true, error: null, reportId: reportId);
    } on DioException catch (e) {
      return (ok: false, error: friendlyErrorMessage(e, fallback: 'Could not submit report. Check your connection.'), reportId: null);
    } catch (e) {
      return (ok: false, error: friendlyErrorMessage(e, fallback: 'Could not submit report. Please try again.'), reportId: null);
    }
  }

  Future<void> loadCheckInStatus() async {
    try {
      final res = await _api
          .get('/location/checkin-status')
          .timeout(const Duration(seconds: 8));
      if (res.data['success'] == true) {
        final d = res.data['data'];
        state = state.copyWith(
          isCheckedIn: d['isCheckedIn'] ?? false,
          checkInTime: d['checkInTime'] != null ? parseApiDate(d['checkInTime']) : null,
          submittedToday: (d['submittedToday'] as num?)?.toInt() ?? state.submittedToday,
        );
      }
    } catch (_) {
      // Leave previous check-in state on failure.
    }
    // Never block dashboard load on GPS/permission work.
    unawaited(evaluateTrackingHealth());
  }

  Future<bool> checkIn({required double latitude, required double longitude, String? address}) async {
    try {
      await _api.post('/location/check-in', data: {'latitude': latitude, 'longitude': longitude, 'address': address});
      state = state.copyWith(isCheckedIn: true, checkInTime: DateTime.now());
      await evaluateTrackingHealth();
      return true;
    } catch (_) { return false; }
  }

  Future<({bool ok, String? message, String? jobId, String? jobTitle})> checkOut({
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    try {
      final res = await _api.post('/location/check-out', data: {
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
      });
      if (res.data['success'] == true) {
        final d = res.data['data'] as Map<String, dynamic>?;
        state = state.copyWith(
          isCheckedIn: false,
          checkInTime: null,
          submittedToday: (d?['todayCount'] as num?)?.toInt() ?? state.submittedToday,
          trackingHealth: TrackingHealthStatus.unknown,
        );
        LiveLocationTracker.stop();
        return (ok: true, message: null, jobId: null, jobTitle: null);
      }
      return (
        ok: false,
        message: res.data['message']?.toString() ?? 'Could not check out',
        jobId: null,
        jobTitle: null,
      );
    } on DioException catch (e) {
      final data = e.response?.data is Map ? e.response!.data as Map : null;
      final payload = data?['data'] is Map ? data!['data'] as Map : null;
      return (
        ok: false,
        message: friendlyErrorMessage(
          e,
          fallback: 'Could not check out. Please try again.',
        ),
        jobId: payload?['jobId']?.toString(),
        jobTitle: payload?['jobTitle']?.toString(),
      );
    } catch (e) {
      return (
        ok: false,
        message: friendlyErrorMessage(e, fallback: 'Could not check out. Please try again.'),
        jobId: null,
        jobTitle: null,
      );
    }
  }

  /// Start/stop GPS stream based on check-in state.
  /// Returns whether tracking is running after sync.
  Future<bool> syncLiveLocationTracking() async {
    if (!state.isCheckedIn) {
      LiveLocationTracker.stop();
      return false;
    }
    final started = await LiveLocationTracker.start(onLocation: (lat, lng) async {
      await updateLiveLocation(lat, lng);
    });
    return started && LiveLocationTracker.isRunning;
  }

  /// Report impaired/OK tracking to the server so the owner can be notified.
  Future<void> reportTrackingStatus({
    required String status,
    String? reason,
  }) async {
    try {
      await _api.post('/location/tracking-status', data: {
        'status': status,
        if (reason != null) 'reason': reason,
      });
    } catch (_) {}
  }

  /// On resume / home: if checked in, ensure tracker is up or notify owner why not.
  Future<void> evaluateTrackingHealth() async {
    if (!state.isCheckedIn) {
      state = state.copyWith(trackingHealth: TrackingHealthStatus.unknown);
      return;
    }

    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      LiveLocationTracker.stop();
      state = state.copyWith(trackingHealth: TrackingHealthStatus.gpsOff);
      await reportTrackingStatus(status: 'impaired', reason: 'gps_off');
      return;
    }

    final hasForeground = await LocationService.hasForegroundPermission();
    final hasAlways = await LocationService.hasAlwaysPermission();
    final hasPrecise = await LocationService.hasPreciseLocation();
    if (!hasForeground || !hasAlways || !hasPrecise) {
      LiveLocationTracker.stop();
      state = state.copyWith(trackingHealth: TrackingHealthStatus.permissionMissing);
      await reportTrackingStatus(status: 'impaired', reason: 'permission_denied');
      return;
    }

    final running = await syncLiveLocationTracking();
    if (!running) {
      state = state.copyWith(trackingHealth: TrackingHealthStatus.trackerFailed);
      await reportTrackingStatus(status: 'impaired', reason: 'tracker_failed');
      return;
    }

    // Tracker is running — warn if battery optimization may still kill it.
    final unrestricted = await BatteryOptimizationService.isIgnoringBatteryOptimizations();
    if (!unrestricted) {
      state = state.copyWith(trackingHealth: TrackingHealthStatus.batteryRisk);
      await reportTrackingStatus(status: 'ok');
      return;
    }

    state = state.copyWith(trackingHealth: TrackingHealthStatus.active);
    await reportTrackingStatus(status: 'ok');
  }

  Future<void> updateLiveLocation(double lat, double lng) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await _api.post('/location/update', data: {
          'latitude': lat,
          'longitude': lng,
        });
        if (res.data['success'] == true) return;
      } catch (_) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }
      }
    }
  }

  Future<void> loadProfileStats() async {
    try {
      final res = await _api.get('/staff/my-stats');
      if (res.data['success'] == true) {
        final d = res.data['data'];
        state = state.copyWith(
          weekCount: d['weekCount'] ?? 0,
          monthCount: d['monthCount'] ?? 0,
          totalCount: d['totalCount'] ?? 0,
          draftCount: d['draftCount'] ?? 0,
          submittedToday: (d['todayCount'] as num?)?.toInt() ?? state.submittedToday,
          hasPendingDraft: ((d['draftCount'] as num?)?.toInt() ?? 0) > 0,
        );
      }
    } catch (_) {}
  }

  Future<void> loadNotifications() async {
    state = state.copyWith(notificationsLoading: true);
    try {
      final res = await _api.get('/notifications/my');
      if (res.data['success'] == true) {
        state = state.copyWith(
          notificationsLoading: false,
          notifications: List<Map<String,dynamic>>.from(res.data['data']?['notifications'] ?? []),
        );
      } else {
        state = state.copyWith(notificationsLoading: false);
      }
    } catch (_) {
      state = state.copyWith(notificationsLoading: false);
    }
  }

  Future<int> getUnreadCount() async {
    try {
      final res = await _api.get('/notifications/my');
      return res.data['success'] == true ? (res.data['data']?['unreadCount'] ?? 0) : 0;
    } catch (_) { return 0; }
  }

  Future<void> markAllRead() async {
    try {
      await _api.post('/notifications/read-all');
      state = state.copyWith(notifications: state.notifications.map((n) => {...n, 'isRead': true}).toList());
    } catch (_) {}
  }

  Future<bool> deleteReport(String reportId) async {
    try {
      await _api.delete('/reports/$reportId');
      if (state.selectedReport?.id == reportId) {
        state = state.copyWith(clearSelectedReport: true);
      }
      state = state.copyWith(
        historyReports: state.historyReports.where((r) => r.id != reportId).toList(),
      );
      await loadTodayReports();
      await loadProfileStats();
      state = state.copyWith(jobsEpoch: state.jobsEpoch + 1);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> submitMultiPhotoReport({
    required String jobTitle, required String? notes,
    required List<File> beforePhotos, required List<File> afterPhotos,
    required double? latitude, required double? longitude, required String? address,
    String? jobId,
  }) async {
    try {
      final org = await AuthStorage.getOrg();
      final orgName = org?.name ?? state.orgName;
      final beforeUrls = <Map<String,dynamic>>[];
      final afterUrls  = <Map<String,dynamic>>[];
      for (int i = 0; i < beforePhotos.length; i++) {
        final uploaded = await uploadPhotoWithFallback(
          file: beforePhotos[i],
          orgName: orgName,
          jobTitle: jobTitle,
          label: 'before_${i + 1}',
        );
        if (uploaded.driveId != null) {
          beforeUrls.add({'driveFileId': uploaded.driveId, 'type': 'photo', 'label': 'before_${i + 1}'});
        } else if (uploaded.serverUrl != null) {
          beforeUrls.add({'url': uploaded.serverUrl, 'type': 'photo', 'label': 'before_${i + 1}'});
        }
      }
      for (int i = 0; i < afterPhotos.length; i++) {
        final uploaded = await uploadPhotoWithFallback(
          file: afterPhotos[i],
          orgName: orgName,
          jobTitle: jobTitle,
          label: 'after_${i + 1}',
        );
        if (uploaded.driveId != null) {
          afterUrls.add({'driveFileId': uploaded.driveId, 'type': 'photo', 'label': 'after_${i + 1}'});
        } else if (uploaded.serverUrl != null) {
          afterUrls.add({'url': uploaded.serverUrl, 'type': 'photo', 'label': 'after_${i + 1}'});
        }
      }
      await _api.post('/reports', data: {
        'jobTitle': jobTitle, 'notes': notes, 'status': 'submitted',
        'location': latitude != null ? {'latitude': latitude, 'longitude': longitude, 'address': address} : null,
        'beforeMedia':  beforeUrls.isNotEmpty ? beforeUrls.first : null,
        'afterMedia':   afterUrls.isNotEmpty  ? afterUrls.first  : null,
        'beforePhotos': beforeUrls,
        'afterPhotos':  afterUrls,
        if (jobId != null) 'jobId': jobId,
      });
      await loadTodayReports();
      return true;
    } catch (_) { return false; }
  }

  Future<List<Map<String, dynamic>>> loadCheckinHistory({int limit = 50, String filter = 'all'}) async {
    try {
      final res = await _api.get('/location/checkin-history', params: {
        'limit': '$limit',
        'filter': filter,
      });
      if (res.data['success'] == true) return List<Map<String,dynamic>>.from(res.data['data'] ?? []);
      return [];
    } catch (_) { return []; }
  }
}
