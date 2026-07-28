import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/drive_photo_widget.dart';
import '../../../shared/models/report_model.dart';
import '../controllers/staff_controller.dart';

class StaffReportDetailScreen extends ConsumerStatefulWidget {
  final String reportId;
  const StaffReportDetailScreen({super.key, required this.reportId});
  @override
  ConsumerState<StaffReportDetailScreen> createState() => _StaffReportDetailScreenState();
}

class _StaffReportDetailScreenState extends ConsumerState<StaffReportDetailScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(staffControllerProvider.notifier).loadReportDetail(widget.reportId));
  }

  ReportModel? _loadedReport(StaffState state) {
    final report = state.selectedReport;
    if (report == null || report.id != widget.reportId) return null;
    return report;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(staffControllerProvider);
    final report = _loadedReport(state);

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: Text(report?.jobTitle ?? 'Report Detail'),
        actions: [
          if (report?.status == 'draft')
            TextButton(
              onPressed: () => context.push('/staff/submit?reportId=${report!.id}'),
              child: const Text('Complete', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: report == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Status banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: report.isSubmitted ? AppColors.green.withValues(alpha: 0.08) : AppColors.yellow.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: report.isSubmitted ? AppColors.green.withValues(alpha: 0.3) : AppColors.yellow.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  Icon(report.isSubmitted ? Icons.check_circle_outline : Icons.edit_outlined,
                      color: report.isSubmitted ? AppColors.green : AppColors.yellow, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    report.isSubmitted ? 'Submitted Successfully' : 'Draft â€” Not Submitted',
                    style: TextStyle(
                      color: report.isSubmitted ? AppColors.green : AppColors.yellow,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (report.submittedAt != null) ...[
                    const Spacer(),
                    Text(DateFormat('h:mm a').format(report.submittedAt!),
                        style: const TextStyle(color: AppColors.silver, fontSize: 12)),
                  ],
                ]),
              ),
              const SizedBox(height: 20),

              // Location
              if (report.location != null) ...[
                const Text('LOCATION', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                  child: Row(children: [
                    Icon(Icons.location_on_outlined, color: report.isFlagged ? AppColors.red : AppColors.green, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      report.location!.address ?? '${report.location!.latitude}, ${report.location!.longitude}',
                      style: const TextStyle(color: AppColors.light, fontSize: 13),
                    )),
                    if (report.isFlagged)
                      const Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 18),
                  ]),
                ),
                const SizedBox(height: 20),
              ],

              // Before / After
              const Text('BEFORE & AFTER', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _mediaBox('Before', report.beforeMedia, report.id, 'before')),
                const SizedBox(width: 12),
                Expanded(child: _mediaBox('After', report.afterMedia, report.id, 'after')),
              ]),

              if (report.notes != null && report.notes!.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('NOTES', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                Text(report.notes!, style: const TextStyle(color: AppColors.light, fontSize: 14, height: 1.6)),
              ],
              const SizedBox(height: 40),
            ])),
    );
  }

  Widget _mediaBox(String label, MediaData? media, String? reportId, String slot) {
    final driveFileId = media?.driveFileId;
    final url = media?.url;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.silver, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      if (driveFileId != null || url != null)
        DrivePhotoWidget(
          driveFileId: driveFileId,
          reportId: reportId,
          photoSlot: slot,
          height: 180,
          showFullscreen: false,
        )
      else
        Container(height: 180, decoration: BoxDecoration(color: AppColors.dark3, borderRadius: BorderRadius.circular(12)),
          child: const Center(child: Icon(Icons.image_outlined, color: AppColors.muted, size: 40))),
      if (media?.capturedAt != null) ...[
        const SizedBox(height: 8),
        Text(DateFormat('d MMM yyyy, h:mm:ss a').format(media!.capturedAt!.toLocal()),
          style: const TextStyle(color: AppColors.light, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
      if (media?.gpsLine != null) ...[
        const SizedBox(height: 2),
        Text('GPS: ${media!.gpsLine}', style: const TextStyle(color: AppColors.muted, fontSize: 10)),
      ],
      if (media?.address != null && media!.address!.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(media.address!, style: const TextStyle(color: AppColors.muted, fontSize: 10), maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    ]);
  }
}