import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/api_error_utils.dart';
import 'google_auth_service.dart';

class DriveUploadResult {
  final String? fileId;
  final String? error;

  const DriveUploadResult({this.fileId, this.error});

  bool get ok => fileId != null;
}

class DriveService {
  static final Map<String, String> _folderCache = {};

  static String _escapeDriveQuery(String value) => value.replaceAll("'", "\\'");

  static Future<drive.DriveApi?> _ensureApi() async {
    if (GoogleAuthService.driveApi != null) return GoogleAuthService.driveApi;
    final access = await GoogleAuthService.ensureDriveAccess();
    return access.ok ? GoogleAuthService.driveApi : null;
  }

  static Future<String?> _getOrCreateFolder(
    String name, {String? parentId}
  ) async {
    final cacheKey = '$name-${parentId ?? 'root'}';
    if (_folderCache.containsKey(cacheKey)) return _folderCache[cacheKey];

    final api = await _ensureApi();
    if (api == null) return null;

    try {
      final q = parentId != null
        ? "name='${_escapeDriveQuery(name)}' and mimeType='application/vnd.google-apps.folder' and '$parentId' in parents and trashed=false"
        : "name='${_escapeDriveQuery(name)}' and mimeType='application/vnd.google-apps.folder' and 'root' in parents and trashed=false";

      final result = await api.files.list(q: q, spaces: 'drive', $fields: 'files(id,name)');

      if (result.files != null && result.files!.isNotEmpty) {
        final id = result.files!.first.id!;
        _folderCache[cacheKey] = id;
        return id;
      }

      final folder = drive.File()
        ..name     = name
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents  = parentId != null ? [parentId] : ['root'];

      final created = await api.files.create(folder);
      final id      = created.id!;
      _folderCache[cacheKey] = id;
      return id;
    } catch (e) {
      debugPrint('Drive folder error: $e');
      return null;
    }
  }

  static Future<String?> _getDateFolder(String orgName) async {
    final rootId = await _getOrCreateFolder(AppConstants.driveFolderName);
    if (rootId == null) return null;

    final orgId = await _getOrCreateFolder(orgName, parentId: rootId);
    if (orgId == null) return null;

    final today  = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return _getOrCreateFolder(today, parentId: orgId);
  }

  static Future<DriveUploadResult> uploadPhoto({
    required File file,
    required String orgName,
    required String jobTitle,
    required String label,
  }) async {
    String? lastError;

    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        if (attempt > 1) {
          DriveService.clearCache();
          await GoogleAuthService.refreshIfNeeded();
          await Future.delayed(const Duration(seconds: 1));
        }

        final access = await GoogleAuthService.ensureDriveAccess()
            .timeout(const Duration(seconds: 8), onTimeout: () {
          return const DriveAccessResult(
            ok: false,
            error: 'Google Drive authorization timed out',
          );
        });
        if (!access.ok) {
          lastError = access.error ?? 'Google Drive is not authorized';
          break;
        }

        final api = GoogleAuthService.driveApi;
        if (api == null) {
          lastError = 'Google Drive is not authorized';
          break;
        }

        final folderId = await _getDateFolder(orgName)
            .timeout(const Duration(seconds: 12), onTimeout: () => null);
        if (folderId == null) {
          lastError = 'Could not create Drive folder for $orgName';
          continue;
        }

        final time     = DateFormat('HHmmss').format(DateTime.now());
        final safeName = jobTitle.replaceAll(RegExp(r'[^a-zA-Z0-9 ]'), '').replaceAll(' ', '_');
        final fileName = '${safeName}_${label}_$time.jpg';

        final media = drive.Media(file.openRead(), await file.length(), contentType: 'image/jpeg');
        final driveFile = drive.File()
          ..name    = fileName
          ..parents = [folderId];

        final result = await api.files
            .create(driveFile, uploadMedia: media)
            .timeout(const Duration(seconds: 45));
        debugPrint('Drive upload success: ${result.id} — $fileName');
        return DriveUploadResult(fileId: result.id);
      } catch (e) {
        lastError = friendlyErrorMessage(e, fallback: 'Upload to Google Drive failed');
        debugPrint('Drive upload attempt $attempt error: $e');
        if (lastError!.contains('not authorized') || lastError.contains('Drive not linked')) {
          break;
        }
      }
    }
    return DriveUploadResult(
      error: lastError ?? 'Upload to Google Drive failed',
    );
  }

  /// Share a Drive file with a Google account (owner or service account).
  static Future<bool> shareFileWithEmail({
    required String fileId,
    required String email,
    String role = 'reader',
  }) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return false;

    final api = await _ensureApi();
    if (api == null) return false;

    try {
      await api.permissions.create(
        drive.Permission()
          ..type = 'user'
          ..role = role
          ..emailAddress = trimmed,
        fileId,
        sendNotificationEmail: false,
      );
      debugPrint('Drive shared $fileId with $trimmed');
      return true;
    } catch (e) {
      debugPrint('Drive share error ($trimmed): $e');
      return false;
    }
  }

  /// After submit — share before/after photos with owner + backend service account.
  static Future<void> shareReportPhotos({
    String? beforeFileId,
    String? afterFileId,
    required String ownerEmail,
    String? serviceAccountEmail,
  }) async {
    final recipients = <String>{
      if (ownerEmail.trim().isNotEmpty) ownerEmail.trim(),
      if (serviceAccountEmail != null && serviceAccountEmail.trim().isNotEmpty) serviceAccountEmail.trim(),
    };

    for (final email in recipients) {
      if (beforeFileId != null) {
        await shareFileWithEmail(fileId: beforeFileId, email: email);
      }
      if (afterFileId != null) {
        await shareFileWithEmail(fileId: afterFileId, email: email);
      }
    }
  }

  static Future<Uint8List?> fetchPhotoBytes(String fileId) async {
    if (!await GoogleAuthService.refreshIfNeeded()) return null;

    try {
      final api = GoogleAuthService.driveApi;
      if (api == null) return null;

      final media = await api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final chunks = <List<int>>[];
      await for (final chunk in media.stream) { chunks.add(chunk); }

      return Uint8List.fromList(chunks.expand((c) => c).toList());
    } catch (e) {
      debugPrint('Drive fetch error: $e');
      return null;
    }
  }

  static void clearCache() => _folderCache.clear();

  static Future<drive.File?> uploadPhotoMultipart({
    required File file,
    required String fileName,
    required String folderId,
  }) async {
    final api = await _ensureApi();
    if (api == null) return null;

    try {
      final media = drive.Media(file.openRead(), await file.length(), contentType: 'image/jpeg');
      final driveFile = drive.File()
        ..name    = fileName
        ..parents = [folderId];
      return await api.files.create(driveFile, uploadMedia: media);
    } catch (e) {
      debugPrint('Drive upload multipart error: $e');
      return null;
    }
  }
}
