import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/drive_photo_widget.dart';
import '../../../shared/models/report_model.dart';
import '../controllers/staff_controller.dart';

class DraftDetailScreen extends ConsumerStatefulWidget {
  final String reportId;
  const DraftDetailScreen({super.key, required this.reportId});
  @override
  ConsumerState<DraftDetailScreen> createState() => _DraftDetailScreenState();
}

class _DraftDetailScreenState extends ConsumerState<DraftDetailScreen> {
  bool _deleting = false;
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadDetail);
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    final ok = await ref.read(staffControllerProvider.notifier).loadReportDetail(widget.reportId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadFailed = !ok;
    });
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.dark2,
        title: const Text('Delete Draft?', style: TextStyle(color: AppColors.white)),
        content: const Text('This cannot be undone.', style: TextStyle(color: AppColors.silver)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: AppColors.silver))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _deleting = true);
    final ok = await ref.read(staffControllerProvider.notifier).deleteReport(widget.reportId);
    if (!mounted) return;
    setState(() => _deleting = false);
    if (ok) {
      context.go('/staff');
      return;
    }
    showErrorSnackBar(context, null, fallback: 'Could not delete draft. Please try again.');
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
        title: const Text('Draft Report'),
        actions: [
          if (report != null)
            IconButton(
              icon: _deleting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.red))
                  : const Icon(Icons.delete_outline, color: AppColors.red),
              onPressed: _deleting ? null : _delete,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : _loadFailed || report == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.muted, size: 48),
                        const SizedBox(height: 16),
                        const Text(
                          'Could not load this draft.',
                          style: TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Check your connection and try again.',
                          style: TextStyle(color: AppColors.silver, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        AppButton(label: 'Retry', icon: Icons.refresh, onPressed: _loadDetail),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.yellow.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.yellow.withValues(alpha: 0.3)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.warning_amber_rounded, color: AppColors.yellow, size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Text(
                            'This report was saved as a draft${report.createdAt != null ? ' at ${DateFormat("h:mm a").format(report.createdAt!)}' : ''}. Complete and submit it.',
                            style: const TextStyle(color: AppColors.yellow, fontSize: 13),
                          )),
                        ]),
                      ),
                      const SizedBox(height: 20),
                      Text(report.jobTitle, style: const TextStyle(color: AppColors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      if (report.location?.address != null)
                        Row(children: [
                          const Icon(Icons.location_on_outlined, color: AppColors.muted, size: 16),
                          const SizedBox(width: 6),
                          Expanded(child: Text(report.location!.address!, style: const TextStyle(color: AppColors.silver, fontSize: 13))),
                        ]),
                      const SizedBox(height: 20),
                      const Text('BEFORE & AFTER', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _mediaBox('Before', report.beforeMedia, report.id ?? widget.reportId, 'before')),
                          const SizedBox(width: 12),
                          Expanded(child: _mediaBox('After', report.afterMedia, report.id ?? widget.reportId, 'after')),
                        ],
                      ),
                      if (report.notes != null && report.notes!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text('NOTES', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                        const SizedBox(height: 8),
                        Text(report.notes!, style: const TextStyle(color: AppColors.light, fontSize: 14, height: 1.5)),
                      ],
                      const SizedBox(height: 28),
                      AppButton(
                        label: 'Complete & Submit',
                        icon: Icons.send_outlined,
                        onPressed: () => context.push('/staff/submit?reportId=${report.id}'),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
    );
  }

  Widget _mediaBox(String label, MediaData? media, String reportId, String slot) {
    final hasPhoto = media?.driveFileId != null || media?.url != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.silver, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (hasPhoto)
          DrivePhotoWidget(
            driveFileId: media?.driveFileId,
            reportId: reportId,
            photoSlot: slot,
            height: 140,
            showFullscreen: false,
          )
        else
          Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.dark3,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.image_outlined, color: AppColors.muted, size: 32),
                const SizedBox(height: 8),
                Text('$label photo', style: const TextStyle(color: AppColors.silver, fontSize: 12)),
                const Text('Not added yet', style: TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
            ),
          ),
      ],
    );
  }
}
