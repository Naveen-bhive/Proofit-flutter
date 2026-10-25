import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../models/report_model.dart';
import '../models/storage_models.dart' show formatBytes, formatDuration;
import 'drive_photo_widget.dart';
import 'video_player_screen.dart';

/// One report attachment in a detail view: a photo (as before), a video
/// (poster + play, marked as a separate file from the PDF), or a placeholder
/// for media the owner deleted to free storage.
class ReportMediaTile extends StatelessWidget {
  final MediaData? media;
  final String? reportId;
  final String slot;
  final int index;
  final double height;
  final String label;
  /// Photo tap (e.g. open the photo viewer). Videos always open the player.
  final VoidCallback? onPhotoTap;

  const ReportMediaTile({
    super.key,
    required this.media,
    required this.reportId,
    required this.slot,
    required this.index,
    required this.label,
    this.height = 200,
    this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    final m = media;
    if (m != null && m.isDeleted) return _placeholder(Icons.delete_outline_rounded, 'Deleted to free storage');
    if (m != null && m.isVideo) return _video(context, m);
    if (m == null || !m.hasStoredPhoto) return _placeholder(Icons.image_outlined, null);
    return DrivePhotoWidget(
      driveFileId: m.driveFileId,
      reportId: reportId,
      photoSlot: slot,
      photoIndex: index,
      height: height,
      showFullscreen: false,
      onTap: onPhotoTap,
    );
  }

  Widget _placeholder(IconData icon, String? text) => Container(
        height: height,
        decoration: BoxDecoration(color: AppColors.dark3, borderRadius: BorderRadius.circular(12)),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: AppColors.muted, size: 36),
            if (text != null) ...[
              const SizedBox(height: 6),
              Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
            ],
          ]),
        ),
      );

  Widget _video(BuildContext context, MediaData m) {
    final meta = [formatDuration(m.durationSec), if (m.bytes != null) formatBytes(m.bytes!)].where((s) => s.isNotEmpty).join(' · ');
    return GestureDetector(
      onTap: m.url == null ? null : () => VideoPlayerScreen.open(context, url: m.url, title: label),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: height,
          child: Stack(fit: StackFit.expand, children: [
            if (m.thumbnailUrl != null)
              Image.network(m.thumbnailUrl!, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF1F2937)))
            else
              const ColoredBox(color: Color(0xFF1F2937)),
            const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 48)),
            Positioned(
              left: 8,
              top: 8,
              child: _chip(Icons.videocam_rounded, 'Video'),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Row(children: [
                if (meta.isNotEmpty) _chip(Icons.schedule_rounded, meta),
                const Spacer(),
                _chip(Icons.attach_file_rounded, 'Separate file'),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 11),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
        ]),
      );
}
