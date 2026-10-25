import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_service.dart';
import '../../../core/utils/api_error_utils.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../../shared/widgets/multi_photo_picker.dart';
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

  static const _maxPhotosPerSlot = 10;
  static const _parallelUploads = 3;
  // Client-side hints only (refreshed from GET /media/limits); the server enforces the real limits.
  int _maxVideoSeconds = 180;
  int? _maxVideoBytes;

  final List<ReportPhoto> _beforePhotos = [];
  final List<ReportPhoto> _afterPhotos = [];
  bool _pickingBefore = false;
  bool _pickingAfter = false;
  String? _orgName;
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
    AuthStorage.getOrg().then((org) => _orgName = org?.name);
    _loadJobs();
    _loadMediaLimits();
    _getLocation();
    if (widget.reportId != null) _loadDraft();
  }

  Future<void> _loadMediaLimits() async {
    try {
      final res = await ref.read(apiServiceProvider).get('/media/limits');
      final d = res.data['data'];
      if (!mounted || d is! Map) return;
      setState(() {
        _maxVideoSeconds = (d['maxVideoDurationSec'] as num?)?.toInt() ?? _maxVideoSeconds;
        _maxVideoBytes = (d['maxVideoBytes'] as num?)?.toInt();
      });
    } catch (_) {}
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
      _beforePhotos
        ..clear()
        ..addAll(r.beforePhotos.map((m) =>
            ReportPhoto.remote(m, normalizedUrl: _normalizePhotoUrl(m.url))));
      _afterPhotos
        ..clear()
        ..addAll(r.afterPhotos.map((m) =>
            ReportPhoto.remote(m, normalizedUrl: _normalizePhotoUrl(m.url))));
      if (r.location != null) {
        _lat = r.location!.latitude;
        _lng = r.location!.longitude;
        _address = r.location!.address;
      }
    });
  }

  List<ReportPhoto> _photosFor(String slot) =>
      slot == 'before' ? _beforePhotos : _afterPhotos;

  bool _slotReady(List<ReportPhoto> photos) =>
      photos.isNotEmpty && photos.every((p) => p.isDone);

  String? _normalizePhotoUrl(String? url) {
    if (url == null || url.isEmpty) return url;
    // App / cleartext may block http; API is served over https.
    if (url.startsWith('http://api.proofitapp.in')) {
      return 'https://${url.substring('http://'.length)}';
    }
    return url;
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  void _setPicking(String slot, bool value) => setState(() {
        if (slot == 'before') {
          _pickingBefore = value;
        } else {
          _pickingAfter = value;
        }
      });

  /// Opens the picker, then adds the photos to the grid straight away (each
  /// tile shows its own spinner) and stamps + uploads them in the background.
  /// Videos skip stamping and upload with a progress indicator.
  Future<void> _addPhotos(String slot, MediaSource source) async {
    final photos = _photosFor(slot);
    final remaining = _maxPhotosPerSlot - photos.length;
    if (remaining <= 0) return;

    if (source == MediaSource.cameraVideo || source == MediaSource.galleryVideo) {
      _setPicking(slot, true);
      final video = await CameraService.pickVideo(context,
          fromCamera: source == MediaSource.cameraVideo,
          maxDuration: Duration(seconds: _maxVideoSeconds),
          maxBytes: _maxVideoBytes);
      if (!mounted) return;
      _setPicking(slot, false);
      if (video == null) return;
      final item = ReportPhoto.video(video);
      setState(() {
        photos.add(item);
        _error = null;
      });
      await _uploadVideo(item, slot);
      return;
    }

    final fromCamera = source == MediaSource.cameraPhoto;
    _setPicking(slot, true);
    final raws = await CameraService.pickRaw(context,
        fromCamera: fromCamera, limit: remaining);
    if (!mounted) return;
    final added = raws.map(ReportPhoto.local).toList();
    setState(() {
      photos.addAll(added);
      _error = null;
    });
    _setPicking(slot, false);
    await _processAll(added, slot);
  }

  /// Runs [_processPhoto] over [items] with a small worker pool so several
  /// photos upload at once without decoding ten images in parallel.
  Future<void> _processAll(List<ReportPhoto> items, String slot) async {
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        await _processPhoto(items[next++], slot);
      }
    }

    await Future.wait(List.generate(
        math.min(_parallelUploads, items.length), (_) => worker()));
  }

  Future<void> _uploadVideo(ReportPhoto item, String slot) async {
    setState(() {
      item.status = PhotoUploadStatus.uploading;
      item.progress = 0;
      item.error = null;
    });
    final result = await ref.read(staffControllerProvider.notifier).uploadMedia(
          file: item.capture!.file,
          onProgress: (p) {
            if (mounted) setState(() => item.progress = p);
          },
        );
    if (!mounted) return;
    setState(() {
      if (result.asset != null) {
        item.applyUpload(result.asset!);
        item.url = _normalizePhotoUrl(item.url);
      } else {
        item.status = PhotoUploadStatus.failed;
        item.progress = null;
        item.error = result.error;
      }
    });
  }

  Future<void> _processPhoto(ReportPhoto photo, String slot) async {
    if (photo.isVideo) return _uploadVideo(photo, slot);
    final user = ref.read(staffControllerProvider).userName;
    try {
      if (photo.capture == null) {
        setState(() => photo.status = PhotoUploadStatus.processing);
        final captured = await CameraService.stamp(photo.raw!,
            staffName: user, jobTitle: _jobTitle);
        if (!mounted) return;
        photo.capture = captured;
      }
      if (!_photosFor(slot).contains(photo)) return; // removed meanwhile
      setState(() {
        photo.status = PhotoUploadStatus.uploading;
        photo.progress = 0;
        photo.error = null;
      });

      final index = _photosFor(slot).indexOf(photo) + 1;
      final result = await ref
          .read(staffControllerProvider.notifier)
          .uploadPhotoWithFallback(
            file: photo.capture!.file,
            orgName: _orgName ?? 'ProofIt',
            jobTitle: _jobTitle.isNotEmpty ? _jobTitle : 'Report',
            label: '${slot == 'before' ? 'Before' : 'After'} $index',
            onDriveSaved: (id) => photo.driveId = id,
            onProgress: (p) {
              if (mounted) setState(() => photo.progress = p);
            },
          );
      if (!mounted) return;
      setState(() {
        photo.progress = null;
        if (result.serverUrl != null) {
          photo.url = _normalizePhotoUrl(result.serverUrl);
          photo.assetId = result.assetId;
          photo.status = PhotoUploadStatus.done;
          photo.error = null;
        } else {
          photo.status = PhotoUploadStatus.failed;
          photo.error = result.error;
        }
      });
    } catch (_) {
      if (mounted) setState(() => photo.status = PhotoUploadStatus.failed);
    }
  }

  void _removePhoto(String slot, ReportPhoto photo) =>
      setState(() => _photosFor(slot).remove(photo));

  String? _photosNotReadyError({required bool asDraft}) {
    final all = [..._beforePhotos, ..._afterPhotos];
    if (all.any((p) => p.isBusy)) {
      return 'Photos and videos are still uploading - please wait';
    }
    if (all.any((p) => p.status == PhotoUploadStatus.failed)) {
      return 'Some files failed to upload. Tap a red tile to retry, or remove it.';
    }
    if (asDraft) return null;
    if (_beforePhotos.isEmpty) return 'Add at least one before photo or video';
    if (_afterPhotos.isEmpty) return 'Add at least one after photo or video';
    return null;
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
    final photoError = _photosNotReadyError(asDraft: asDraft);
    if (photoError != null) {
      setState(() => _error = photoError);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final result =
        await ref.read(staffControllerProvider.notifier).saveReport(
              jobTitle: _jobTitle,
              notes: _notesCtrl.text.trim(),
              beforePhotos: [
                for (int i = 0; i < _beforePhotos.length; i++)
                  _beforePhotos[i].toMedia('before_${i + 1}'),
              ],
              afterPhotos: [
                for (int i = 0; i < _afterPhotos.length; i++)
                  _afterPhotos[i].toMedia('after_${i + 1}'),
              ],
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
      if (!asDraft) unawaited(_shareDriveCopies());
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

  /// Shares whichever Drive archive copies exist with the owner. Runs in the
  /// background so submitting never waits on Drive.
  Future<void> _shareDriveCopies() async {
    final org = await AuthStorage.getOrg();
    final before = _beforePhotos.map((p) => p.driveId).whereType<String>().toList();
    final after = _afterPhotos.map((p) => p.driveId).whereType<String>().toList();
    for (int i = 0; i < math.max(before.length, after.length); i++) {
      await DriveService.shareReportPhotos(
        beforeFileId: i < before.length ? before[i] : null,
        afterFileId: i < after.length ? after[i] : null,
        ownerEmail: org?.ownerEmail ?? '',
        serviceAccountEmail: org?.driveServiceEmail,
      );
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
                  'BEFORE & AFTER PHOTOS / VIDEOS',
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
                    'Add the before and after photos or videos the job needs. Photos are stamped with date, time and GPS and appear in the report PDF; videos are shared as separate files.',
                    style: TextStyle(color: AppColors.silver, fontSize: 13, height: 1.5)),
                const SizedBox(height: 16),

                MultiPhotoPicker(
                  label: 'Before',
                  photos: _beforePhotos,
                  maxPhotos: _maxPhotosPerSlot,
                  enabled: !_submitting,
                  picking: _pickingBefore,
                  photoSlot: 'before',
                  reportId: _savedDraftId ?? widget.reportId,
                  onAdd: (source) => _addPhotos('before', source),
                  onRemove: (p) => _removePhoto('before', p),
                  onRetry: (p) => _processPhoto(p, 'before'),
                ),
                const SizedBox(height: 22),

                MultiPhotoPicker(
                  label: 'After',
                  photos: _afterPhotos,
                  maxPhotos: _maxPhotosPerSlot,
                  enabled: !_submitting,
                  picking: _pickingAfter,
                  photoSlot: 'after',
                  reportId: _savedDraftId ?? widget.reportId,
                  onAdd: (source) => _addPhotos('after', source),
                  onRemove: (p) => _removePhoto('after', p),
                  onRetry: (p) => _processPhoto(p, 'after'),
                ),
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
                    _check('Before', _slotReady(_beforePhotos)),
                    _div(),
                    _check('After', _slotReady(_afterPhotos)),
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
