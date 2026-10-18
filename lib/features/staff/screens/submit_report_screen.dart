import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/api_error_utils.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../../shared/widgets/camera_capture_widget.dart';
import '../../../shared/services/location_service.dart';
import '../../../shared/services/drive_service.dart';
import '../../../shared/services/auth_storage.dart';
import '../../../shared/services/camera_service.dart';
import '../../../shared/services/review_service.dart';
import '../controllers/staff_controller.dart';

class SubmitReportScreen extends ConsumerStatefulWidget {
  final String? reportId;
  final String? jobId;
  final String? prefillTitle;
  const SubmitReportScreen(
      {super.key,
      this.reportId,
      this.jobId,
      String? prefillTitle,
      String? jobTitle})
      : prefillTitle = prefillTitle ?? jobTitle;
  @override
  ConsumerState<SubmitReportScreen> createState() => _SubmitReportScreenState();
}

class _SubmitReportScreenState extends ConsumerState<SubmitReportScreen> {
  final _notesCtrl = TextEditingController();

  File? _beforeImage;
  File? _afterImage;
  CapturedPhoto? _beforeCapture;
  CapturedPhoto? _afterCapture;
  String? _beforeDriveId;
  String? _afterDriveId;
  String? _beforeServerUrl;
  String? _afterServerUrl;

  /// True once the server-confirmed photo for this draft slot has loaded (or was in the draft payload).
  bool _beforeOnServer = false;
  bool _afterOnServer = false;
  bool _beforeUploading = false;
  bool _afterUploading = false;
  String? _beforeUploadStatus;
  String? _afterUploadStatus;
  double? _lat, _lng;
  String? _address;
  bool _locationLoading = false;
  bool _submitting = false;
  String? _error;
  String? _savedDraftId;
  List<Map<String, dynamic>> _assignableJobs = [];
  bool _jobsLoading = true;
  String? _selectedJobId;
  String? _selectedJobTitle;

  String get _jobTitle => _selectedJobTitle ?? '';

  @override
  void initState() {
    super.initState();
    // Keep continuing an existing draft on the same report id - never create a second draft.
    _savedDraftId = widget.reportId;
    _loadJobs();
    _getLocation();
    if (widget.reportId != null) _loadDraft();
  }

  Future<void> _loadJobs() async {
    final jobs = await ref
        .read(staffControllerProvider.notifier)
        .loadMyJobs(status: 'pending,in_progress');
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
    final r = await ref
        .read(staffControllerProvider.notifier)
        .fetchReportDetail(widget.reportId!);
    if (!mounted || r == null) return;
    setState(() {
      _notesCtrl.text = r.notes ?? '';
      _savedDraftId = r.id ?? widget.reportId;
      _selectedJobId = r.jobId ?? widget.jobId ?? _selectedJobId;
      _selectedJobTitle = (r.jobTitle.isNotEmpty ? r.jobTitle : null) ??
          widget.prefillTitle ??
          _selectedJobTitle;
      _beforeDriveId = r.beforeMedia?.driveFileId;
      _afterDriveId = r.afterMedia?.driveFileId;
      _beforeServerUrl = _normalizePhotoUrl(r.beforeMedia?.url);
      _afterServerUrl = _normalizePhotoUrl(r.afterMedia?.url);
      _beforeOnServer = r.beforeMedia?.hasStoredPhoto == true;
      _afterOnServer = r.afterMedia?.hasStoredPhoto == true;
      // Drop any stale local files - remote draft media is source of truth on reopen.
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
    return (drive != null && drive.isNotEmpty) ||
        (url != null && url.isNotEmpty);
  }

  bool get _hasAfterIds {
    final drive = _afterDriveId?.trim();
    final url = _afterServerUrl?.trim();
    return (drive != null && drive.isNotEmpty) ||
        (url != null && url.isNotEmpty);
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
    final r =
        await ref.read(staffControllerProvider.notifier).fetchReportDetail(id);
    if (!mounted || r == null) return;
    setState(() {
      _beforeDriveId = r.beforeMedia?.driveFileId ?? _beforeDriveId;
      _beforeServerUrl =
          _normalizePhotoUrl(r.beforeMedia?.url) ?? _beforeServerUrl;
      _afterDriveId = r.afterMedia?.driveFileId ?? _afterDriveId;
      _afterServerUrl =
          _normalizePhotoUrl(r.afterMedia?.url) ?? _afterServerUrl;
      _beforeOnServer =
          _beforeOnServer || r.beforeMedia?.hasStoredPhoto == true;
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
    onStatus('Uploading to Supabase...');

    final org = await AuthStorage.getOrg();
    final result = await ref
        .read(staffControllerProvider.notifier)
        .uploadPhotoWithFallback(
          file: file,
          orgName: org?.name ?? 'ProofIt',
          jobTitle: _jobTitle.isNotEmpty ? _jobTitle : 'Report',
          label: label,
          onStatus: onStatus,
        );

    if (result.serverUrl != null) {
      onSuccess(result.driveId, result.serverUrl);
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

    setState(() {
      _beforeUploading = true;
      _beforeUploadStatus = 'Uploading to Supabase...';
      _error = null;
    });
    var ok = false;
    await _uploadPhoto(
      file: file,
      label: 'Before',
      onStatus: (status) {
        if (mounted) setState(() => _beforeUploadStatus = status);
      },
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
    if (mounted) {
      setState(() {
        _beforeUploading = false;
        _beforeUploadStatus = null;
      });
    }
    return ok;
  }

  Future<bool> _uploadAfterPhoto([File? fileOverride]) async {
    final file = fileOverride ?? _afterImage;
    if (file == null) return false;

    setState(() {
      _afterUploading = true;
      _afterUploadStatus = 'Uploading to Supabase...';
      _error = null;
    });
    var ok = false;
    await _uploadPhoto(
      file: file,
      label: 'After',
      onStatus: (status) {
        if (mounted) setState(() => _afterUploadStatus = status);
      },
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
    if (mounted) {
      setState(() {
        _afterUploading = false;
        _afterUploadStatus = null;
      });
    }
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
    final hasLocalBefore =
        _beforeImage != null && _beforeImage!.path.isNotEmpty;
    final hasLocalAfter = _afterImage != null && _afterImage!.path.isNotEmpty;

    if (asDraft) {
      // Drafts may omit photos, but any captured photo must finish uploading first.
      if (_beforeUploading || _afterUploading) {
        setState(() => _error = 'Photos are still uploading - please wait');
        return false;
      }
      if (hasLocalBefore && !_beforeReady) await _uploadBeforePhoto();
      if (hasLocalAfter && !_afterReady) await _uploadAfterPhoto();
      if (hasLocalBefore && !_beforeReady) {
        setState(() => _error =
            'Before photo failed to upload. Tap Retry, or remove it, then save draft.');
        return false;
      }
      if (hasLocalAfter && !_afterReady) {
        setState(() => _error =
            'After photo failed to upload. Tap Retry, or remove it, then save draft.');
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
      setState(() => _error = 'Photos are still uploading - please wait');
      return false;
    }

    if (!_beforeReady && hasLocalBefore) await _uploadBeforePhoto();
    if (!_afterReady && hasLocalAfter) await _uploadAfterPhoto();

    if (_beforeUploading || _afterUploading) {
      setState(() => _error = 'Photos are still uploading - please wait');
      return false;
    }

    // Drive may fail - server backup is used automatically on submit if needed.
    return true;
  }

  Future<void> _getLocation() async {
    setState(() => _locationLoading = true);
    final pos = await LocationService.getCurrentPosition();
    if (pos != null && mounted) {
      final addr = await LocationService.getAddressFromCoords(
          pos.latitude, pos.longitude);
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _address = addr;
      });
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
    if ((_beforeOnServer && !_hasBeforeIds) ||
        (_afterOnServer && !_hasAfterIds)) {
      await _rehydrateMediaIds();
    }

    if (!asDraft && (!_beforeReady || !_afterReady)) {
      setState(() => _error =
          'Both photos must finish uploading before submit. Tap Retry on any failed photo.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final hasLocalBefore =
        _beforeImage != null && _beforeImage!.path.isNotEmpty;
    final hasLocalAfter = _afterImage != null && _afterImage!.path.isNotEmpty;
    final useServerBefore = !_hasBeforeIds && hasLocalBefore;
    final useServerAfter = !_hasAfterIds && hasLocalAfter;

    final result =
        await ref.read(staffControllerProvider.notifier).submitReport(
              jobTitle: _jobTitle,
              notes: _notesCtrl.text.trim(),
              beforeImage: useServerBefore ? _beforeImage : null,
              afterImage: useServerAfter ? _afterImage : null,
              beforeDriveId: _beforeDriveId,
              afterDriveId: _afterDriveId,
              beforeUrl: _beforeServerUrl,
              afterUrl: _afterServerUrl,
              beforeCapturedAt: _beforeCapture?.capturedAt,
              beforeLatitude: _beforeCapture?.latitude,
              beforeLongitude: _beforeCapture?.longitude,
              beforeAddress: _beforeCapture?.address,
              afterCapturedAt: _afterCapture?.capturedAt,
              afterLatitude: _afterCapture?.latitude,
              afterLongitude: _afterCapture?.longitude,
              afterAddress: _afterCapture?.address,
              latitude: _lat,
              longitude: _lng,
              address: _address,
              asDraft: asDraft,
              existingReportId: _savedDraftId ?? widget.reportId,
              jobId: _selectedJobId,
            );

    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.ok) {
      if (result.reportId != null) _savedDraftId = result.reportId;
      if (!asDraft) {
        final org = await AuthStorage.getOrg();
        await DriveService.shareReportPhotos(
          beforeFileId: _beforeDriveId,
          afterFileId: _afterDriveId,
          ownerEmail: org?.ownerEmail ?? '',
          serviceAccountEmail: org?.driveServiceEmail,
        );
      }
      if (!mounted) return;
      if (asDraft) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Row(children: [
              Icon(Icons.save_outlined, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Draft saved'),
            ]),
            backgroundColor: AppColors.amberDark,
            duration: Duration(seconds: 2)));
      } else {
        await _showSubmittedSheet();
        if (!mounted) return;
        ReviewService.maybePromptAfterSuccess();
      }
      context.pop();
    } else {
      setState(() => _error = friendlyErrorMessage(
            result.error,
            fallback: 'Failed to submit. Check your connection.',
          ));
    }
  }

  Future<void> _showSubmittedSheet() {
    final now = DateTime.now();
    return AppSheet.show<void>(
      context,
      builder: (ctx) => AppSheet(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFA7F3D0)),
              child: Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF065F46)),
                  child: const Icon(Icons.check_rounded, color: AppColors.white, size: 34),
                ),
              ),
            ),
            Positioned(
              right: -2,
              bottom: 2,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.brandDark,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.white, width: 3),
                ),
                child: const Icon(Icons.verified_rounded, color: AppColors.white, size: 14),
              ),
            ),
          ]),
          const SizedBox(height: 22),
          Text('Report Successfully Submitted!', textAlign: TextAlign.center, style: AppTextStyles.h1.copyWith(fontSize: 23)),
          const SizedBox(height: 12),
          const Text(
            'Verification data, GPS coordinates, and stamped photos have been recorded and synced to the company portal.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.light, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: BoxDecoration(color: AppColors.dark4, borderRadius: BorderRadius.circular(100)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.schedule_rounded, size: 15, color: AppColors.light),
              const SizedBox(width: 6),
              Text(DateFormat('h:mm a • d MMM yyyy').format(now), style: const TextStyle(color: AppColors.light, fontSize: 12.5)),
              const SizedBox(width: 8),
              const Text('•', style: TextStyle(color: AppColors.muted)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFF6EE7B7), borderRadius: BorderRadius.circular(100)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, size: 6, color: Color(0xFF065F46)),
                  SizedBox(width: 5),
                  Text('Sync Complete', style: TextStyle(color: Color(0xFF065F46), fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(label: 'Done', onPressed: () => Navigator.pop(ctx)),
          ),
        ]),
      ),
    );
  }

  Widget _sectionLabel(String text, {bool required = false, Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Text(text, style: const TextStyle(color: AppColors.silver, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          if (required) const Text(' *', style: TextStyle(color: AppColors.red, fontSize: 12, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (trailing != null) trailing,
        ]),
      );

  Widget _buildJobPicker() {
    if (_jobsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
            child: CircularProgressIndicator(
                color: AppColors.brand, strokeWidth: 2)),
      );
    }
    if (_assignableJobs.isEmpty) {
      return const SurfaceCard(
        radius: 16,
        padding: EdgeInsets.all(14),
        child: Text(
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
        final status = job['status']?.toString() ?? 'pending';
        final statusColor = status == 'in_progress' ? AppColors.brand : const Color(0xFFD97706);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: selected ? const Color(0xFF60A5FA) : AppColors.border, width: selected ? 2 : 1),
              boxShadow: AppColors.cardShadow,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _submitting
                    ? null
                    : () => setState(() {
                          _selectedJobId = id;
                          _selectedJobTitle = job['title']?.toString() ?? '';
                        }),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                        color: selected ? AppColors.brand : AppColors.muted,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(job['title']?.toString() ?? 'Job',
                            style: AppTextStyles.h3.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: selected ? AppColors.text : AppColors.light,
                            )),
                        if (job['location']?['address'] != null) ...[
                          const SizedBox(height: 3),
                          Text(job['location']['address'].toString(),
                              style: const TextStyle(color: AppColors.silver, fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ],
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text('${status.replaceAll('_', ' ')} • $priority priority',
                                style: TextStyle(color: statusColor == AppColors.brand ? AppColors.brandDark : AppColors.amberDark,
                                    fontSize: 12, fontWeight: FontWeight.w500)),
                          ]),
                        ),
                      ]),
                    ),
                  ]),
                ),
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
    final isDraft = widget.reportId != null;
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(children: [
          Container(
            color: AppColors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(children: [
              CircleBackButton(icon: isDraft ? Icons.chevron_left_rounded : Icons.arrow_back_rounded),
              const SizedBox(width: 14),
              Expanded(
                child: Text(isDraft ? 'Complete Draft' : 'New Report',
                    style: AppTextStyles.pageTitle.copyWith(fontSize: 20)),
              ),
              if (isDraft)
                GestureDetector(
                  onTap: _submitting ? null : () => _submit(asDraft: true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFED7AA),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppColors.softShadow,
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.bookmark_border_rounded, size: 17, color: Color(0xFF7C2D12)),
                      SizedBox(width: 5),
                      Text('Save Draft', style: TextStyle(color: Color(0xFF7C2D12), fontWeight: FontWeight.w600, fontSize: 13.5)),
                    ]),
                  ),
                )
              else
                GestureDetector(
                  onTap: _submitting ? null : () => _submit(asDraft: true),
                  child: const Text('Save Draft',
                      style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w600, fontSize: 15)),
                ),
            ]),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _sectionLabel('ASSIGNED JOB', required: true),
                _buildJobPicker(),
                const SizedBox(height: 4),

                // Location
                SurfaceCard(
                  radius: 16,
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _lat != null ? AppColors.greenSoft : AppColors.amberSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: (_lat != null ? AppColors.green : AppColors.yellow).withValues(alpha: 0.3)),
                      ),
                      child: Icon(
                        _locationLoading ? Icons.hourglass_empty_rounded : Icons.location_on_outlined,
                        color: _lat != null ? AppColors.greenDark : AppColors.yellow,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          _locationLoading ? 'Getting location...' : _address ?? 'Location unavailable',
                          style: const TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_lat != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text('${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                                style: const TextStyle(color: AppColors.silver, fontSize: 12)),
                          ),
                      ]),
                    ),
                    if (!_locationLoading)
                      GestureDetector(
                        onTap: _getLocation,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppColors.dark3,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Icon(Icons.refresh_rounded, color: AppColors.light, size: 18),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 26),

                _sectionLabel(
                  'BEFORE & AFTER PHOTOS',
                  required: isDraft,
                  trailing: isDraft
                      ? const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.cloud_done_outlined, size: 14, color: AppColors.greenDark),
                          SizedBox(width: 4),
                          Text('Cloud ready', style: TextStyle(color: AppColors.greenDark, fontSize: 12, fontWeight: FontWeight.w600)),
                        ])
                      : null,
                ),
                const Text(
                    'Photos are stamped with date, time and GPS – saved to Google Drive, with server backup if Drive is unavailable.',
                    style: TextStyle(color: AppColors.silver, fontSize: 13, height: 1.5)),
                const SizedBox(height: 16),

                CameraCaptureWidget(
                    label: 'Before',
                    image: _beforeImage,
                    isRequired: true,
                    isUploading: _beforeUploading,
                    uploadStatus: _beforeUploadStatus,
                    uploadSucceeded: _beforeReady,
                    uploadFailed:
                        (_beforeImage != null && _beforeImage!.path.isNotEmpty) &&
                            !_beforeUploading &&
                            !_beforeReady,
                    onRetry: _uploadBeforePhoto,
                    staffName: user,
                    jobTitle: _jobTitle,
                    networkImageUrl: _beforeServerUrl,
                    driveFileId: _beforeDriveId,
                    reportId: _savedDraftId ?? widget.reportId,
                    photoSlot: 'before',
                    onRemoteLoaded: () => _onRemotePhotoLoaded('before'),
                    onCaptured: _onBeforeCaptured),
                const SizedBox(height: 20),

                CameraCaptureWidget(
                    label: 'After',
                    image: _afterImage,
                    isRequired: true,
                    isUploading: _afterUploading,
                    uploadStatus: _afterUploadStatus,
                    uploadSucceeded: _afterReady,
                    uploadFailed:
                        (_afterImage != null && _afterImage!.path.isNotEmpty) &&
                            !_afterUploading &&
                            !_afterReady,
                    onRetry: _uploadAfterPhoto,
                    staffName: user,
                    jobTitle: _jobTitle,
                    networkImageUrl: _afterServerUrl,
                    driveFileId: _afterDriveId,
                    reportId: _savedDraftId ?? widget.reportId,
                    photoSlot: 'after',
                    onRemoteLoaded: () => _onRemotePhotoLoaded('after'),
                    onCaptured: _onAfterCaptured),
                const SizedBox(height: 22),

                // Progress checklist
                SurfaceCard(
                  radius: 16,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                  child: Row(children: [
                    _check('Job', _selectedJobId != null),
                    _div(),
                    _check('Location', _lat != null),
                    _div(),
                    _check('Before', _beforeReady),
                    _div(),
                    _check('After', _afterReady),
                  ]),
                ),
                const SizedBox(height: 18),

                SurfaceCard(
                  radius: 16,
                  padding: EdgeInsets.zero,
                  child: TextFormField(
                    controller: _notesCtrl,
                    style: const TextStyle(color: AppColors.text),
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      filled: false,
                      hintText: 'Notes (optional)',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      prefixIcon: Padding(
                        padding: EdgeInsets.only(bottom: 48),
                        child: Icon(Icons.notes_rounded, color: AppColors.muted, size: 20),
                      ),
                    ),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: AppColors.redSoft,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.red.withValues(alpha: 0.3))),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(_error!,
                                style: const TextStyle(color: AppColors.red, fontSize: 13, height: 1.4))),
                      ])),
                ],
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: AppColors.white,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: PrimaryButton(
              label: 'Submit Report',
              icon: isDraft ? Icons.verified_outlined : Icons.send_rounded,
              color: isDraft ? const Color(0xFF1D4ED8) : AppColors.brand,
              loading: _submitting,
              onPressed: () => _submit(),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _check(String label, bool done) => Expanded(
          child: Column(children: [
        Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
                color: done ? AppColors.greenSoft : AppColors.dark4,
                shape: BoxShape.circle,
                border: Border.all(color: done ? AppColors.green : AppColors.border)),
            child: Icon(done ? Icons.check_rounded : Icons.circle,
                color: done ? AppColors.greenDark : AppColors.border, size: done ? 16 : 10)),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(
                color: done ? AppColors.greenDark : AppColors.muted,
                fontSize: 12,
                fontWeight: done ? FontWeight.w600 : FontWeight.w400)),
      ]));

  Widget _div() => Container(width: 1, height: 40, color: AppColors.borderSoft);
}
