import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../models/report_model.dart';
import '../models/storage_models.dart' show formatBytes, formatDuration;
import '../services/camera_service.dart';
import 'drive_photo_widget.dart';
import 'ui_kit.dart' show DashedBorderPainter;
import 'video_player_screen.dart';

enum PhotoUploadStatus { processing, uploading, done, failed }

/// Where the user chose to add media from.
enum MediaSource { cameraPhoto, galleryPhotos, cameraVideo, galleryVideo }

/// One before/after photo or video on the report form — either picked on
/// this device (raw → stamped → uploaded; videos skip stamping) or loaded
/// from a saved draft.
class ReportPhoto {
  ReportPhoto.local(File this.raw)
      : remote = null,
        isVideo = false,
        status = PhotoUploadStatus.processing;

  /// A picked/recorded video; capture metadata is ready, upload is next.
  ReportPhoto.video(CapturedPhoto this.capture)
      : raw = null,
        remote = null,
        isVideo = true,
        status = PhotoUploadStatus.uploading;

  ReportPhoto.remote(MediaData this.remote, {String? normalizedUrl})
      : raw = null,
        isVideo = remote.isVideo,
        status = PhotoUploadStatus.done,
        url = normalizedUrl ?? remote.url,
        publicId = remote.publicId,
        driveId = remote.driveFileId,
        assetId = remote.assetId,
        thumbnailUrl = remote.thumbnailUrl,
        bytes = remote.bytes,
        durationSec = remote.durationSec;

  final File? raw;
  final MediaData? remote;
  final bool isVideo;
  CapturedPhoto? capture;
  PhotoUploadStatus status;
  String? url;
  String? publicId;
  String? driveId;
  /// Server MediaAsset id — what the report save references.
  String? assetId;
  String? thumbnailUrl;
  int? bytes;
  double? durationSec;
  /// 0..1 while uploading.
  double? progress;
  /// Last upload error from the server (e.g. storage full), shown on the tile.
  String? error;

  bool get isBusy =>
      status == PhotoUploadStatus.processing ||
      status == PhotoUploadStatus.uploading;
  bool get isDone => status == PhotoUploadStatus.done;
  bool get isDeleted => remote?.isDeleted ?? false;

  /// Best local preview: stamped file once ready, else the raw pick (photos only).
  File? get previewFile => isVideo ? null : (capture?.file ?? raw);

  /// Applies a successful upload response from POST /media/upload.
  void applyUpload(Map<String, dynamic> asset) {
    assetId = asset['_id']?.toString();
    url = asset['url'] as String?;
    thumbnailUrl = asset['thumbnailUrl'] as String?;
    bytes = (asset['bytes'] as num?)?.toInt();
    durationSec = (asset['durationSec'] as num?)?.toDouble();
    status = PhotoUploadStatus.done;
    progress = null;
    error = null;
  }

  Map<String, dynamic> toMedia(String label) {
    final c = capture;
    if (c == null && remote != null) {
      return {
        ...remote!.toJson(),
        if (url != null) 'url': url,
        if (driveId != null) 'driveFileId': driveId,
        'label': label,
      };
    }
    return {
      if (assetId != null) 'assetId': assetId,
      if (url != null) 'url': url,
      if (driveId != null) 'driveFileId': driveId,
      'type': isVideo ? 'video' : 'photo',
      'label': label,
      if (c != null) 'capturedAt': c.capturedAt.toUtc().toIso8601String(),
      if (c?.latitude != null) 'latitude': c!.latitude,
      if (c?.longitude != null) 'longitude': c!.longitude,
      if (c?.address != null && c!.address!.isNotEmpty) 'address': c.address,
    };
  }
}

/// Grid of before *or* after photos and videos with an "Add" tile. Each tile
/// shows its own progress while it is being stamped/uploaded, so feedback is
/// immediate; failed tiles explain why and retry on tap.
class MultiPhotoPicker extends StatelessWidget {
  final String label;
  final List<ReportPhoto> photos;
  final int maxPhotos;
  final bool isRequired;
  final bool enabled;
  final bool allowVideo;
  /// True while the camera/gallery picker is open or handing back files.
  final bool picking;
  final void Function(MediaSource source) onAdd;
  final void Function(ReportPhoto photo) onRemove;
  final void Function(ReportPhoto photo) onRetry;
  /// For legacy drafts whose photo only lives in Drive (no URL).
  final String? reportId;
  final String photoSlot;

  const MultiPhotoPicker({
    super.key,
    required this.label,
    required this.photos,
    required this.onAdd,
    required this.onRemove,
    required this.onRetry,
    required this.photoSlot,
    this.maxPhotos = 10,
    this.isRequired = true,
    this.enabled = true,
    this.allowVideo = true,
    this.picking = false,
    this.reportId,
  });

  Future<void> _showAddOptions(BuildContext context) async {
    final remaining = maxPhotos - photos.length;
    final source = await showModalBottomSheet<MediaSource>(
      context: context,
      backgroundColor: AppColors.dark2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(allowVideo ? 'Add $label Photos or Videos' : 'Add $label Photos',
                style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Photos are stamped with date · time · GPS  •  $remaining more allowed',
                style: const TextStyle(color: AppColors.silver, fontSize: 12)),
            const SizedBox(height: 20),
            _opt(Icons.camera_alt_rounded, AppColors.brand, 'Take Photo',
                'Take one photo', () => Navigator.pop(sheetContext, MediaSource.cameraPhoto)),
            const SizedBox(height: 10),
            _opt(
                Icons.photo_library_outlined,
                AppColors.blue,
                'Choose Photos',
                remaining > 1 ? 'Select up to $remaining photos' : 'Select a photo',
                () => Navigator.pop(sheetContext, MediaSource.galleryPhotos)),
            if (allowVideo) ...[
              const SizedBox(height: 10),
              _opt(Icons.videocam_rounded, AppColors.purple, 'Record Video',
                  'Shared as a separate file, not inside the PDF', () => Navigator.pop(sheetContext, MediaSource.cameraVideo)),
              const SizedBox(height: 10),
              _opt(Icons.video_library_outlined, AppColors.greenDark, 'Choose Video',
                  'Pick one video from your gallery', () => Navigator.pop(sheetContext, MediaSource.galleryVideo)),
            ],
            const SizedBox(height: 4),
          ]),
        ),
      ),
    );
    if (source == null || !context.mounted) return;
    // Let the sheet finish closing so the native picker opens reliably.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    onAdd(source);
  }

  Widget _opt(IconData icon, Color color, String title, String sub,
          VoidCallback onTap) =>
      GestureDetector(
          onTap: onTap,
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withValues(alpha: 0.2))),
              child: Row(children: [
                Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle),
                    child: Icon(icon, color: color, size: 22)),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: const TextStyle(
                              color: AppColors.text,
                              fontWeight: FontWeight.w600,
                              fontSize: 15)),
                      Text(sub,
                          style: const TextStyle(
                              color: AppColors.silver, fontSize: 12)),
                    ])),
                Icon(Icons.chevron_right_rounded,
                    color: color.withValues(alpha: 0.5), size: 20),
              ])));

  @override
  Widget build(BuildContext context) {
    final busy = photos.where((p) => p.isBusy).length;
    final failed = photos.where((p) => p.status == PhotoUploadStatus.failed).toList();
    final canAdd = photos.length < maxPhotos;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label,
            style: const TextStyle(
                fontFamily: 'Poppins',
                color: AppColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
        if (isRequired)
          const Text(' *',
              style: TextStyle(
                  color: AppColors.red, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Text('${photos.length}/$maxPhotos',
            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        const Spacer(),
        if (busy > 0)
          _statusChip(Icons.cloud_upload_outlined, 'Uploading $busy', AppColors.brand)
        else if (failed.isNotEmpty)
          _statusChip(Icons.cloud_off_rounded, '${failed.length} failed', AppColors.red)
        else if (photos.isNotEmpty)
          _statusChip(Icons.cloud_done_rounded, 'All saved', AppColors.greenDark),
      ]),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, constraints) {
        const gap = 8.0;
        final tile = (constraints.maxWidth - gap * 2) / 3;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (int i = 0; i < photos.length; i++)
            SizedBox(width: tile, height: tile, child: _photoTile(context, photos[i], i)),
          if (canAdd || picking)
            SizedBox(width: tile, height: tile, child: _addTile(context)),
        ]);
      }),
      if (failed.isNotEmpty && failed.first.error != null) ...[
        const SizedBox(height: 8),
        Text(failed.first.error!,
            style: const TextStyle(color: AppColors.red, fontSize: 12, height: 1.4)),
      ],
    ]);
  }

  Widget _statusChip(IconData icon, String text, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      );

  Widget _addTile(BuildContext context) {
    return GestureDetector(
      onTap: enabled && !picking ? () => _showAddOptions(context) : null,
      child: CustomPaint(
        foregroundPainter:
            const DashedBorderPainter(color: Color(0xFFCBD5E1), radius: 14),
        child: Container(
          decoration: BoxDecoration(
              color: AppColors.white, borderRadius: BorderRadius.circular(14)),
          child: picking
              ? const Center(
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: AppColors.brand, strokeWidth: 2)))
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: AppColors.brandSoft,
                          borderRadius: BorderRadius.circular(10)),
                      child: Icon(allowVideo ? Icons.add_photo_alternate_outlined : Icons.add_a_photo_outlined,
                          color: AppColors.brand, size: 19)),
                  const SizedBox(height: 6),
                  Text(photos.isEmpty ? 'Add $label' : 'Add more',
                      style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ]),
        ),
      ),
    );
  }

  Widget _videoPreview(ReportPhoto photo) {
    final thumb = photo.thumbnailUrl;
    return Stack(fit: StackFit.expand, children: [
      if (thumb != null)
        Image.network(thumb, fit: BoxFit.cover, cacheWidth: 360,
            errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF1F2937)))
      else
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF1F2937), Color(0xFF111827)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
        ),
      if (!photo.isBusy)
        const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 34)),
      Positioned(
        right: 6,
        bottom: 6,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.videocam_rounded, color: Colors.white, size: 11),
            const SizedBox(width: 3),
            Text(
              [formatDuration(photo.durationSec), if (photo.bytes != null) formatBytes(photo.bytes!)].where((s) => s.isNotEmpty).join(' · '),
              style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w600),
            ),
          ]),
        ),
      ),
    ]);
  }

  void _openVideo(BuildContext context, ReportPhoto photo, int index) {
    final file = photo.capture?.file;
    if (photo.url == null && file == null) return;
    VideoPlayerScreen.open(context, url: photo.url, file: photo.url == null ? file : null, title: '$label video ${index + 1}');
  }

  Widget _photoTile(BuildContext context, ReportPhoto photo, int index) {
    final file = photo.previewFile;
    final Widget preview;
    if (photo.isDeleted) {
      preview = const Center(
        child: Padding(
          padding: EdgeInsets.all(6),
          child: Text('Deleted to free storage', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
        ),
      );
    } else if (photo.isVideo) {
      preview = _videoPreview(photo);
    } else if (file != null) {
      preview = Image.file(file, fit: BoxFit.cover, cacheWidth: 360, gaplessPlayback: true);
    } else if (photo.url != null && photo.url!.isNotEmpty) {
      preview = Image.network(photo.url!,
          fit: BoxFit.cover,
          cacheWidth: 360,
          errorBuilder: (_, __, ___) => _remoteFallback(photo, index));
    } else {
      preview = _remoteFallback(photo, index);
    }

    final pct = photo.progress != null ? '${(photo.progress! * 100).clamp(0, 100).round()}%' : null;
    final overlay = switch (photo.status) {
      PhotoUploadStatus.processing => _overlay(
          const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
          'Stamping...'),
      PhotoUploadStatus.uploading => _overlay(
          CircularProgressIndicator(color: Colors.white, strokeWidth: 2, value: photo.progress),
          pct != null ? 'Uploading $pct' : 'Uploading...'),
      PhotoUploadStatus.failed => GestureDetector(
          onTap: enabled ? () => onRetry(photo) : null,
          child: _overlay(
              const Icon(Icons.refresh_rounded, color: Colors.white, size: 26),
              'Tap to retry',
              color: AppColors.red.withValues(alpha: 0.75)),
        ),
      PhotoUploadStatus.done => null,
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(fit: StackFit.expand, children: [
        GestureDetector(
          onTap: photo.isVideo && photo.isDone && !photo.isDeleted ? () => _openVideo(context, photo, index) : null,
          child: Container(color: AppColors.dark4, child: preview),
        ),
        if (overlay != null) overlay,
        Positioned(
          left: 6,
          top: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(100)),
            child: Text('${index + 1}',
                style: const TextStyle(
                    color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ),
        ),
        if (photo.isDone && !photo.isDeleted)
          const Positioned(
            left: 6,
            bottom: 6,
            child: CircleAvatar(
                radius: 9,
                backgroundColor: AppColors.green,
                child: Icon(Icons.check_rounded, color: Colors.white, size: 12)),
          ),
        if (!photo.isBusy && enabled)
          Positioned(
            right: 4,
            top: 4,
            child: GestureDetector(
              onTap: () => onRemove(photo),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 15),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _remoteFallback(ReportPhoto photo, int index) => DrivePhotoWidget(
        driveFileId: photo.driveId,
        reportId: reportId,
        photoSlot: photoSlot,
        photoIndex: index,
        height: double.infinity,
        showFullscreen: false,
      );

  Widget _overlay(Widget indicator, String text, {Color? color}) => Container(
        color: color ?? Colors.black.withValues(alpha: 0.45),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 24, height: 24, child: Center(child: indicator)),
          const SizedBox(height: 6),
          Text(text,
              style: const TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      );
}
