import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/api_error_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/camera_capture_widget.dart';
import '../../../shared/services/location_service.dart';
import '../../../shared/services/drive_service.dart';
import '../../../shared/services/auth_storage.dart';
import '../../../shared/services/camera_service.dart';
import '../controllers/staff_controller.dart';

class SubmitReportScreen extends ConsumerStatefulWidget {
  final String? reportId;
  final String? jobId;
  final String? prefillTitle;
  const SubmitReportScreen({super.key, this.reportId, this.jobId, String? prefillTitle, String? jobTitle})
      : prefillTitle = prefillTitle ?? jobTitle;
  @override ConsumerState<SubmitReportScreen> createState() => _SubmitReportScreenState();
}

class _SubmitReportScreenState extends ConsumerState<SubmitReportScreen> {
  final _notesCtrl = TextEditingController();

  File?   _beforeImage;
  File?   _afterImage;
  CapturedPhoto? _beforeCapture;
  CapturedPhoto? _afterCapture;
  String? _beforeDriveId;
  String? _afterDriveId;
  String? _beforeServerUrl;
  String? _afterServerUrl;
  /// True once the server-confirmed photo for this draft slot has loaded (or was in the draft payload).
  bool _beforeOnServer = false;
  bool _afterOnServer = false;
  bool    _beforeUploading = false;
  bool    _afterUploading  = false;
  String? _beforeUploadStatus;
  String? _afterUploadStatus;
  double? _lat, _lng;
  String? _address;
  bool    _locationLoading = false;
  bool    _submitting      = false;
  String? _error;
  String? _savedDraftId;
  List<Map<String, dynamic>> _assignableJobs = [];
  bool    _jobsLoading = true;
  String? _selectedJobId;
  String? _selectedJobTitle;

  String get _jobTitle => _selectedJobTitle ?? '';

  @override
  void initState() {
    super.initState();
    // Keep continuing an existing draft on the same report id — never create a second draft.
    _savedDraftId = widget.reportId;
    _loadJobs();
    _getLocation();
    if (widget.reportId != null) _loadDraft();
  }

  Future<void> _loadJobs() async {
    final jobs = await ref.read(staffControllerProvider.notifier).loadMyJobs(status: 'pending,in_progress');
    if (!mounted) return;
    setState(() {
      _assignableJobs = jobs;
      _jobsLoading = false;
      if (widget.jobId != null) {
        for (final j in jobs) {
          if (j['_id']?.toString() == widget.jobId) {
            _selectedJobId = widget.jobId;
            _selectedJobTitle = j['title']?.toString() ?? widget.prefillTitle;
            break;
          }
        }
        _selectedJobId ??= widget.jobId;
        _selectedJobTitle ??= widget.prefillTitle;
      }
    });
  }

  Future<void> _loadDraft() async {
    final r = await ref.read(staffControllerProvider.notifier).fetchReportDetail(widget.reportId!);
    if (!mounted || r == null) return;
    setState(() {
      _notesCtrl.text   = r.notes ?? '';
      _savedDraftId     = r.id ?? widget.reportId;
      _selectedJobId    = r.jobId ?? widget.jobId ?? _selectedJobId;
      _selectedJobTitle = (r.jobTitle.isNotEmpty ? r.jobTitle : null) ?? widget.prefillTitle ?? _selectedJobTitle;
      _beforeDriveId    = r.beforeMedia?.driveFileId;
      _afterDriveId     = r.afterMedia?.driveFileId;
      _beforeServerUrl  = _normalizePhotoUrl(r.beforeMedia?.url);
      _afterServerUrl   = _normalizePhotoUrl(r.afterMedia?.url);
      _beforeOnServer   = r.beforeMedia?.hasStoredPhoto == true;
      _afterOnServer    = r.afterMedia?.hasStoredPhoto == true;
      // Drop any stale local files — remote draft media is source of truth on reopen.
      if (_beforeOnServer) _beforeImage = null;
      if (_afterOnServer) _afterImage = null;
      if (r.location != null) {
        _lat = r.location!.latitude;
        _lng = r.location!.longitude;
        _address = r.location!.address;
      }
      if (r.beforeMedia?.capturedAt != null) {
        _beforeCapture = CapturedPhoto(
          file: File(''),
          capturedAt: r.beforeMedia!.capturedAt!,
          latitude: r.beforeMedia!.latitude,
          longitude: r.beforeMedia!.longitude,
          address: r.beforeMedia!.address,
        );
      }
      if (r.afterMedia?.capturedAt != null) {
        _afterCapture = CapturedPhoto(
          file: File(''),
          capturedAt: r.afterMedia!.capturedAt!,
          latitude: r.afterMedia!.latitude,
          longitude: r.afterMedia!.longitude,
          address: r.afterMedia!.address,
        );
      }
    });
  }

  bool get _beforeReady {
    if (_beforeOnServer) return true;
    return _hasBeforeIds;
  }

  bool get _afterReady {
    if (_afterOnServer) return true;
    return _hasAfterIds;
  }

  bool get _hasBeforeIds {
    final drive = _beforeDriveId?.trim();
    final url = _beforeServerUrl?.trim();
    return (drive != null && drive.isNotEmpty) || (url != null && url.isNotEmpty);
  }

  bool get _hasAfterIds {
    final drive = _afterDriveId?.trim();
    final url = _afterServerUrl?.trim();
    return (drive != null && drive.isNotEmpty) || (url != null && url.isNotEmpty);
  }

  String? _normalizePhotoUrl(String? url) {
    if (url == null || url.isEmpty) return url;
    // App / cleartext may block http; API is served over https.
    if (url.startsWith('http://api.proofitapp.in')) {
      return 'https://${url.substring('http://'.length)}';
    }
    return url;
  }

  Future<void> _rehydrateMediaIds() async {
    final id = _savedDraftId ?? widget.reportId;
    if (id == null) return;
    final r = await ref.read(staffControllerProvider.notifier).fetchReportDetail(id);
    if (!mounted || r == null) return;
    setState(() {
      _beforeDriveId = r.beforeMedia?.driveFileId ?? _beforeDriveId;
      _beforeServerUrl = _normalizePhotoUrl(r.beforeMedia?.url) ?? _beforeServerUrl;
      _afterDriveId = r.afterMedia?.driveFileId ?? _afterDriveId;
      _afterServerUrl = _normalizePhotoUrl(r.afterMedia?.url) ?? _afterServerUrl;
      _beforeOnServer = _beforeOnServer || r.beforeMedia?.hasStoredPhoto == true;
      _afterOnServer = _afterOnServer || r.afterMedia?.hasStoredPhoto == true;
    });
  }

  /// When a remote photo renders successfully, mark slot saved and re-pull IDs for submit.
  Future<void> _onRemotePhotoLoaded(String slot) async {
    final already = slot == 'before' ? _beforeReady : _afterReady;
    if (!already && mounted) {
      setState(() {
        if (slot == 'before') {
          _beforeOnServer = true;
          _beforeImage = null;
        } else {
          _afterOnServer = true;
          _afterImage = null;
        }
      });
    }
    await _rehydrateMediaIds();
  }

  Future<bool> _uploadPhoto({
    required File file,
    required String label,
    required void Function(String? driveId, String? serverUrl) onSuccess,
    required void Function(String message) onError,
    required void Function(String status) onStatus,
  }) async {
    onStatus('Saving to Google Drive...');

    final org = await AuthStorage.getOrg();
    final result = await ref.read(staffControllerProvider.notifier).uploadPhotoWithFallback(
      file:     file,
      orgName:  org?.name ?? 'ProofIt',
      jobTitle: _jobTitle.isNotEmpty ? _jobTitle : 'Report',
      label:    label,
      onStatus: onStatus,
    );

    if (result.driveId != null) {
      onSuccess(result.driveId, null);
      return true;
    }

    if (result.serverUrl != null) {
      onSuccess(null, result.serverUrl);
      return true;
    }

    onError(friendlyErrorMessage(
      result.error,
      fallback: 'Photo upload failed. Check your connection and tap Retry.',
    ));
    return false;
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<bool> _uploadBeforePhoto([File? fileOverride]) async {
    final file = fileOverride ?? _beforeImage;
    if (file == null) return false;

    setState(() { _beforeUploading = true; _beforeUploadStatus = 'Saving to Google Drive...'; _error = null; });
    var ok = false;
    await _uploadPhoto(
      file:  file,
      label: 'Before',
      onStatus: (status) { if (mounted) setState(() => _beforeUploadStatus = status); },
      onSuccess: (driveId, serverUrl) {
        if (!mounted) return;
        setState(() {
          if (driveId != null && driveId.isNotEmpty) _beforeDriveId = driveId;
          if (serverUrl != null && serverUrl.isNotEmpty) {
            _beforeServerUrl = _normalizePhotoUrl(serverUrl);
          }
          _beforeOnServer = true;
        });
        ok = true;
      },
      onError: (msg) {
        if (!mounted) return;
        setState(() => _error = 'Before photo: $msg');
      },
    );
    if (mounted) setState(() { _beforeUploading = false; _beforeUploadStatus = null; });
    return ok;
  }

  Future<bool> _uploadAfterPhoto([File? fileOverride]) async {
    final file = fileOverride ?? _afterImage;
    if (file == null) return false;

    setState(() { _afterUploading = true; _afterUploadStatus = 'Saving to Google Drive...'; _error = null; });
    var ok = false;
    await _uploadPhoto(
      file:  file,
      label: 'After',
      onStatus: (status) { if (mounted) setState(() => _afterUploadStatus = status); },
      onSuccess: (driveId, serverUrl) {
        if (!mounted) return;
        setState(() {
          if (driveId != null && driveId.isNotEmpty) _afterDriveId = driveId;
          if (serverUrl != null && serverUrl.isNotEmpty) {
            _afterServerUrl = _normalizePhotoUrl(serverUrl);
          }
          _afterOnServer = true;
        });
        ok = true;
      },
      onError: (msg) {
        if (!mounted) return;
        setState(() => _error = 'After photo: $msg');
      },
    );
    if (mounted) setState(() { _afterUploading = false; _afterUploadStatus = null; });
    return ok;
  }

  Future<void> _onBeforeCaptured(CapturedPhoto? captured) async {
    if (captured == null) {
      setState(() {
        _beforeCapture = null;
        _beforeImage = null;
        _beforeDriveId = null;
        _beforeServerUrl = null;
        _beforeOnServer = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _beforeCapture = captured;
      _beforeImage = captured.file;
      _beforeDriveId = null;
      _beforeServerUrl = null;
      _beforeOnServer = false;
      _error = null;
    });
    await _uploadBeforePhoto(captured.file);
  }

  Future<void> _onAfterCaptured(CapturedPhoto? captured) async {
    if (captured == null) {
      setState(() {
        _afterCapture = null;
        _afterImage = null;
        _afterDriveId = null;
        _afterServerUrl = null;
        _afterOnServer = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _afterCapture = captured;
      _afterImage = captured.file;
      _afterDriveId = null;
      _afterServerUrl = null;
      _afterOnServer = false;
      _error = null;
    });
    await _uploadAfterPhoto(captured.file);
  }

  Future<bool> _ensurePhotosReady({required bool asDraft}) async {
    final hasLocalBefore = _beforeImage != null && _beforeImage!.path.isNotEmpty;
    final hasLocalAfter = _afterImage != null && _afterImage!.path.isNotEmpty;

    if (asDraft) {
      // Drafts may omit photos, but any captured photo must finish uploading first.
      if (_beforeUploading || _afterUploading) {
        setState(() => _error = 'Photos are still uploading — please wait');
        return false;
      }
      if (hasLocalBefore && !_beforeReady) await _uploadBeforePhoto();
      if (hasLocalAfter && !_afterReady) await _uploadAfterPhoto();
      if (hasLocalBefore && !_beforeReady) {
        setState(() => _error = 'Before photo failed to upload. Tap Retry, or remove it, then save draft.');
        return false;
      }
      if (hasLocalAfter && !_afterReady) {
        setState(() => _error = 'After photo failed to upload. Tap Retry, or remove it, then save draft.');
        return false;
      }
      return true;
    }

    if (!hasLocalBefore && !_beforeReady) {
      setState(() => _error = 'Before photo is required');
      return false;
    }
    if (!hasLocalAfter && !_afterReady) {
      setState(() => _error = 'After photo is required');
      return false;
    }
    if (_beforeUploading || _afterUploading) {
      setState(() => _error = 'Photos are still uploading — please wait');
      return false;
    }

    if (!_beforeReady && hasLocalBefore) await _uploadBeforePhoto();
    if (!_afterReady && hasLocalAfter) await _uploadAfterPhoto();

    if (_beforeUploading || _afterUploading) {
      setState(() => _error = 'Photos are still uploading — please wait');
      return false;
    }

    // Drive may fail — server backup is used automatically on submit if needed.
    return true;
  }

  Future<void> _getLocation() async {
    setState(() => _locationLoading = true);
    final pos = await LocationService.getCurrentPosition();
    if (pos != null && mounted) {
      final addr = await LocationService.getAddressFromCoords(pos.latitude, pos.longitude);
      setState(() { _lat = pos.latitude; _lng = pos.longitude; _address = addr; });
    }
    if (mounted) setState(() => _locationLoading = false);
  }

  Future<void> _submit({bool asDraft = false}) async {
    if (_selectedJobId == null || _jobTitle.isEmpty) {
      setState(() => _error = 'Select an assigned job');
      return;
    }
    if (!await _ensurePhotosReady(asDraft: asDraft)) return;

    // Ensure Drive/URL ids are present for any photo already on the server.
    if ((_beforeOnServer && !_hasBeforeIds) || (_afterOnServer && !_hasAfterIds)) {
      await _rehydrateMediaIds();
    }

    if (!asDraft && (!_beforeReady || !_afterReady)) {
      setState(() => _error = 'Both photos must finish uploading before submit. Tap Retry on any failed photo.');
      return;
    }

    setState(() { _submitting = true; _error = null; });

    final hasLocalBefore = _beforeImage != null && _beforeImage!.path.isNotEmpty;
    final hasLocalAfter = _afterImage != null && _afterImage!.path.isNotEmpty;
    final useServerBefore = !_hasBeforeIds && hasLocalBefore;
    final useServerAfter  = !_hasAfterIds && hasLocalAfter;

    final result = await ref.read(staffControllerProvider.notifier).submitReport(
      jobTitle:        _jobTitle,
      notes:           _notesCtrl.text.trim(),
      beforeImage:     useServerBefore ? _beforeImage : null,
      afterImage:      useServerAfter ? _afterImage : null,
      beforeDriveId:   _beforeDriveId,
      afterDriveId:    _afterDriveId,
      beforeUrl:       _beforeServerUrl,
      afterUrl:        _afterServerUrl,
      beforeCapturedAt: _beforeCapture?.capturedAt,
      beforeLatitude:  _beforeCapture?.latitude,
      beforeLongitude: _beforeCapture?.longitude,
      beforeAddress:   _beforeCapture?.address,
      afterCapturedAt: _afterCapture?.capturedAt,
      afterLatitude:   _afterCapture?.latitude,
      afterLongitude:  _afterCapture?.longitude,
      afterAddress:    _afterCapture?.address,
      latitude:        _lat,
      longitude:       _lng,
      address:         _address,
      asDraft:         asDraft,
      existingReportId: _savedDraftId ?? widget.reportId,
      jobId:           _selectedJobId,
    );

    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.ok) {
      if (result.reportId != null) _savedDraftId = result.reportId;
      if (!asDraft) {
        final org = await AuthStorage.getOrg();
        await DriveService.shareReportPhotos(
          beforeFileId: _beforeDriveId,
          afterFileId:  _afterDriveId,
          ownerEmail:   org?.ownerEmail ?? '',
          serviceAccountEmail: org?.driveServiceEmail,
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          Icon(asDraft ? Icons.save_outlined : Icons.check_circle_outline, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(asDraft ? 'Draft saved' : 'Report submitted!'),
        ]),
        backgroundColor: asDraft ? AppColors.yellow : AppColors.green,
        duration: const Duration(seconds: 2)));
      context.pop();
    } else {
      setState(() => _error = friendlyErrorMessage(
            result.error,
            fallback: 'Failed to submit. Check your connection.',
          ));
    }
  }

  Widget _buildJobPicker() {
    if (_jobsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(color: AppColors.brand, strokeWidth: 2)),
      );
    }
    if (_assignableJobs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.dark3,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: const Text(
          'No assigned jobs right now. Ask your manager to assign a job, then come back here.',
          style: TextStyle(color: AppColors.silver, fontSize: 13, height: 1.4),
        ),
      );
    }

    return Column(
      children: _assignableJobs.map((job) {
        final id = job['_id']?.toString() ?? '';
        final selected = _selectedJobId == id;
        final priority = job['priority']?.toString() ?? 'normal';
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: selected ? AppColors.brand.withOpacity(0.12) : AppColors.dark3,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _submitting ? null : () => setState(() {
                _selectedJobId = id;
                _selectedJobTitle = job['title']?.toString() ?? '';
              }),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: selected ? AppColors.brand : AppColors.border),
                ),
                child: Row(children: [
                  Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: selected ? AppColors.brand : AppColors.muted,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(job['title']?.toString() ?? 'Job',
                        style: TextStyle(
                          color: selected ? AppColors.white : AppColors.silver,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        )),
                      if (job['location']?['address'] != null) ...[
                        const SizedBox(height: 4),
                        Text(job['location']['address'].toString(),
                          style: const TextStyle(color: AppColors.muted, fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        '${job['status'] ?? 'pending'} · $priority priority',
                        style: const TextStyle(color: AppColors.muted, fontSize: 11),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(staffControllerProvider).userName;
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        backgroundColor: AppColors.dark,
        title: Text(widget.reportId != null ? 'Complete Draft' : 'New Report'),
        actions: [
          TextButton(onPressed: _submitting ? null : () => _submit(asDraft: true),
            child: const Text('Save Draft', style: TextStyle(color: AppColors.yellow, fontWeight: FontWeight.w600))),
        ],
      ),
      body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ASSIGNED JOB *',
          style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        _buildJobPicker(),
        const SizedBox(height: 16),

        // Location
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.dark3, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: Row(children: [
            Icon(_locationLoading ? Icons.hourglass_empty : Icons.location_on_outlined,
              color: _lat != null ? AppColors.green : AppColors.yellow, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_locationLoading ? 'Getting location...' : _address ?? 'Location unavailable',
                style: TextStyle(color: _lat != null ? AppColors.light : AppColors.silver, fontSize: 13), maxLines: 2),
              if (_lat != null)
                Text('${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ])),
            if (!_locationLoading) GestureDetector(onTap: _getLocation,
              child: Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.brand.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.refresh_rounded, color: AppColors.brand, size: 16))),
          ])),
        const SizedBox(height: 24),

        const Text('BEFORE & AFTER PHOTOS',
          style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
        const SizedBox(height: 4),
        const Text('Photos are stamped with date, time and GPS — saved to Google Drive, with server backup if Drive is unavailable',
          style: TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 14),

        CameraCaptureWidget(label: 'Before', image: _beforeImage, isRequired: true,
          isUploading: _beforeUploading,
          uploadStatus: _beforeUploadStatus,
          uploadSucceeded: _beforeReady,
          uploadFailed: (_beforeImage != null && _beforeImage!.path.isNotEmpty) && !_beforeUploading && !_beforeReady,
          onRetry: _uploadBeforePhoto,
          staffName: user, jobTitle: _jobTitle,
          networkImageUrl: _beforeServerUrl,
          driveFileId: _beforeDriveId,
          reportId: _savedDraftId ?? widget.reportId,
          photoSlot: 'before',
          onRemoteLoaded: () => _onRemotePhotoLoaded('before'),
          onCaptured: _onBeforeCaptured),
        const SizedBox(height: 16),

        CameraCaptureWidget(label: 'After', image: _afterImage, isRequired: true,
          isUploading: _afterUploading,
          uploadStatus: _afterUploadStatus,
          uploadSucceeded: _afterReady,
          uploadFailed: (_afterImage != null && _afterImage!.path.isNotEmpty) && !_afterUploading && !_afterReady,
          onRetry: _uploadAfterPhoto,
          staffName: user, jobTitle: _jobTitle,
          networkImageUrl: _afterServerUrl,
          driveFileId: _afterDriveId,
          reportId: _savedDraftId ?? widget.reportId,
          photoSlot: 'after',
          onRemoteLoaded: () => _onRemotePhotoLoaded('after'),
          onCaptured: _onAfterCaptured),
        const SizedBox(height: 20),

        // Progress checklist
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: Row(children: [
            _check('Job',      _selectedJobId != null),
            _div(),
            _check('Location', _lat != null),
            _div(),
            _check('Before',   _beforeReady),
            _div(),
            _check('After',    _afterReady),
          ])),
        const SizedBox(height: 16),

        TextFormField(controller: _notesCtrl, style: const TextStyle(color: AppColors.white), maxLines: 3,
          decoration: const InputDecoration(labelText: 'Notes (optional)', hintText: 'Any additional details...',
            prefixIcon: Padding(padding: EdgeInsets.only(bottom: 44), child: Icon(Icons.notes_rounded, color: AppColors.muted)),
            alignLabelWithHint: true)),


        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.red.withOpacity(0.3))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.error_outline, color: AppColors.red, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 13, height: 1.4))),
            ])),
        ],
        const SizedBox(height: 28),
        AppButton(label: 'Submit Report', isLoading: _submitting, onPressed: () => _submit(), icon: Icons.send_rounded),
        const SizedBox(height: 40),
      ])),
    );
  }

  Widget _check(String label, bool done) => Expanded(child: Column(children: [
    Container(width: 28, height: 28,
      decoration: BoxDecoration(
        color:  done ? AppColors.green.withOpacity(0.15) : AppColors.dark3,
        shape:  BoxShape.circle,
        border: Border.all(color: done ? AppColors.green : AppColors.border)),
      child: Icon(done ? Icons.check_rounded : Icons.circle_outlined,
        color: done ? AppColors.green : AppColors.muted, size: 14)),
    const SizedBox(height: 5),
    Text(label, style: TextStyle(color: done ? AppColors.green : AppColors.muted, fontSize: 10,
      fontWeight: done ? FontWeight.w600 : FontWeight.w400)),
  ]));

  Widget _div() => Container(width: 1, height: 40, color: AppColors.border);
}