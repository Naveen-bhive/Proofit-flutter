import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/date_utils.dart';
import '../models/report_model.dart';
import 'drive_photo_widget.dart';

/// Report row card (Report History design): dark proof tile, title, status
/// badge, location, then a footer with timestamp and an action link.
class ReportCard extends StatelessWidget {
  final ReportModel report;
  final VoidCallback? onTap;
  final bool showStaffName;
  final String actionLabel;

  const ReportCard({
    super.key,
    required this.report,
    this.onTap,
    this.showStaffName = false,
    this.actionLabel = 'View PDF',
  });

  List<MediaData> get _media => [...report.beforePhotos, ...report.afterPhotos].where((m) => !m.isDeleted).toList();
  int get _videoCount => _media.where((m) => m.isVideo).length;
  int get _photoCount => _media.length - _videoCount;
  String get _mediaLabel => _videoCount == 0
      ? '$_photoCount Photos'
      : '$_photoCount Photos · $_videoCount Video${_videoCount == 1 ? '' : 's'}';

  @override
  Widget build(BuildContext context) {
    final time = report.submittedAt != null
        ? formatApiDate(report.submittedAt, pattern: 'd MMM, h:mm a')
        : report.createdAt != null
            ? formatApiDate(report.createdAt, pattern: 'd MMM, h:mm a')
            : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: report.isFlagged ? AppColors.red.withValues(alpha: 0.45) : AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _thumb(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Text(report.jobTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.h3.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    _statusChip(),
                  ]),
                  if (showStaffName && report.staffName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(children: [
                        const Icon(Icons.person_outline_rounded, size: 14, color: AppColors.muted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(report.staffName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.silver, fontSize: 12.5)),
                        ),
                      ]),
                    ),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.location_on_outlined, size: 14, color: AppColors.muted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        report.location?.address ?? 'Location not available',
                        style: const TextStyle(color: AppColors.silver, fontSize: 12.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1, color: AppColors.borderSoft),
                  ),
                  Row(children: [
                    const Icon(Icons.schedule_rounded, size: 13, color: AppColors.muted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(time, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    ),
                    if (onTap != null) ...[
                      Text(actionLabel,
                          style: const TextStyle(color: AppColors.brand, fontSize: 13, fontWeight: FontWeight.w600)),
                      const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.brand),
                    ],
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _thumb() {
    final hasPhoto = report.beforeMedia?.hasStoredPhoto == true && report.id != null;
    return SizedBox(
      width: 64,
      height: 64,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(fit: StackFit.expand, children: [
          if (hasPhoto)
            DrivePhotoWidget(
              driveFileId: report.beforeMedia!.driveFileId,
              reportId: report.id,
              photoSlot: 'before',
              width: 64,
              height: 64,
              showFullscreen: false,
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.blue.withValues(alpha: 0.6)),
                    color: AppColors.blue.withValues(alpha: 0.15),
                  ),
                  child: const Icon(Icons.description_outlined, size: 14, color: Color(0xFF93C5FD)),
                ),
                const SizedBox(height: 3),
                Text(_mediaLabel, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 8.5)),
              ]),
            ),
          if (report.location != null)
            Positioned(
              right: 3,
              bottom: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: report.isFlagged ? AppColors.red : AppColors.green,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('GPS',
                    style: TextStyle(color: AppColors.white, fontSize: 7.5, fontWeight: FontWeight.w800)),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _statusChip() {
    final (color, label) = report.isFlagged
        ? (AppColors.red, 'Flagged')
        : report.isSubmitted
            ? (AppColors.green, 'Sent')
            : (AppColors.yellow, 'Draft');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                color: color == AppColors.green ? AppColors.greenDark : color,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
