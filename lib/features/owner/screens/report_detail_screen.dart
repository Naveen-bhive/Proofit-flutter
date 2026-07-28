import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/drive_photo_widget.dart';
import '../../../shared/models/report_model.dart';
import '../../../shared/services/auth_storage.dart';
import '../controllers/owner_controller.dart';

class ReportDetailScreen extends ConsumerStatefulWidget {
  final String reportId;
  const ReportDetailScreen({super.key, required this.reportId});
  @override ConsumerState<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends ConsumerState<ReportDetailScreen> {
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(ownerControllerProvider.notifier).loadReportDetail(widget.reportId));
  }

  // â”€â”€ Generate single report PDF + share via WhatsApp â”€â”€â”€
  Future<void> _shareToCustomer(Map<String, dynamic>? customer) async {
    setState(() => _sharing = true);
    try {
      final token = await AuthStorage.getToken();
      if (token == null) return;

      final dio  = Dio();
      final dir  = await getTemporaryDirectory();
      final path = '${dir.path}/proofit-report-${widget.reportId}.pdf';

      final res = await dio.post(
        '${AppConstants.baseUrl}/reports/${widget.reportId}/share',
        options: Options(headers: {'Authorization': 'Bearer $token'}, responseType: ResponseType.bytes));

      await File(path).writeAsBytes(res.data);
      if (!mounted) return;

      // Share sheet
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(ShareParams(
        files: [XFile(path, mimeType: 'application/pdf')],
        subject: 'Work Completion Report',
        text: customer != null
            ? 'Dear ${customer['name']}, please find attached the work completion report. - ${ref.read(ownerControllerProvider).orgName}'
            : 'Work Completion Report',
        sharePositionOrigin: box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      ));
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(
          context,
          e,
          fallback: 'Could not generate the PDF. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report   = ref.watch(ownerControllerProvider).selectedReport;
    final customer = report?.customer;

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: Text(report?.jobTitle ?? 'Report Detail'),
        actions: [
          // Share to customer button
          if (_sharing)
            const Padding(padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))))
          else
            IconButton(
              icon: const Icon(Icons.share_outlined, color: AppColors.brand),
              onPressed: () => _shareToCustomer(customer),
            ),
        ],
      ),
      body: report == null
        ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
        : SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Staff info row
          Container(padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
            child: Column(children: [
              Row(children: [
                CircleAvatar(radius: 22, backgroundColor: AppColors.brand.withValues(alpha: 0.2),
                  child: Text(report.staffName.isNotEmpty ? report.staffName[0].toUpperCase() : '?',
                    style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w800, fontSize: 18))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(report.staffName, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                  if (report.submittedAt != null)
                    Text(DateFormat('d MMM yyyy, h:mm a').format(report.submittedAt!),
                      style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                ])),
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (report.isFlagged ? AppColors.red : AppColors.green).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(100)),
                  child: Text(report.isFlagged ? 'âš  Flagged' : 'âœ“ Verified',
                    style: TextStyle(color: report.isFlagged ? AppColors.red : AppColors.green, fontSize: 12, fontWeight: FontWeight.w600))),
              ]),

              // Customer row (if linked)
              if (customer != null) ...[
                const SizedBox(height: 12),
                const Divider(color: AppColors.border),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.person_outline, color: AppColors.brand, size: 18),
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Customer', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                    Text(customer['name'] ?? '', style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  ]),
                  const Spacer(),
                  // Quick WhatsApp button
                  if (customer['phone'] != null)
                    GestureDetector(
                      onTap: () => _shareToCustomer(customer),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: const Color(0xFF25D366).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(100), border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.3))),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                         Icon(Icons.share_outlined, color: Color(0xFF25D366), size: 14),
                         SizedBox(width: 6),
                         Text('Share PDF', style: TextStyle(color: Color(0xFF25D366), fontSize: 12, fontWeight: FontWeight.w600)),
                        ]))),
                ]),
              ],
            ])),
          const SizedBox(height: 16),

          // Location
          if (report.location != null)
            Container(padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: Row(children: [
                Icon(Icons.location_on_outlined, color: report.isFlagged ? AppColors.red : AppColors.green, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(report.location!.address ?? '${report.location!.latitude}, ${report.location!.longitude}',
                  style: const TextStyle(color: AppColors.light, fontSize: 13))),
              ])),

          // Before / After Photos
          const Text('BEFORE & AFTER PHOTOS',
            style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _photoCol(context, 'Before', report.beforeMedia, 'before')),
            const SizedBox(width: 12),
            Expanded(child: _photoCol(context, 'After', report.afterMedia, 'after')),
          ]),

          if (report.notes != null && report.notes!.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('NOTES', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Text(report.notes!, style: const TextStyle(color: AppColors.light, fontSize: 14, height: 1.5)),
          ],

          const SizedBox(height: 24),

          // Share button
          ElevatedButton.icon(
            onPressed: _sharing ? null : () => _shareToCustomer(customer),
            icon: _sharing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.picture_as_pdf_outlined, size: 20),
            label: Text(customer != null
              ? 'Share PDF to ${customer['name']}'
              : 'Export as PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brand,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),

          const SizedBox(height: 40),
        ])),
    );
  }

  Widget _photoCol(BuildContext context, String label, MediaData? media, String slot) {
    final driveFileId = media?.driveFileId;
    final capturedAt = media?.capturedAt;
    final gps = media?.gpsLine;
    final address = media?.address;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.silver, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      DrivePhotoWidget(
        driveFileId: driveFileId,
        reportId: widget.reportId,
        photoSlot: slot,
        height: 200,
        onTap: driveFileId != null
          ? () => context.push('/owner/photo-viewer?fileId=$driveFileId&label=$label&reportId=${widget.reportId}&slot=$slot')
          : null),
      if (capturedAt != null) ...[
        const SizedBox(height: 8),
        Text(DateFormat('d MMM yyyy, h:mm:ss a').format(capturedAt.toLocal()),
          style: const TextStyle(color: AppColors.light, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
      if (gps != null) ...[
        const SizedBox(height: 2),
        Text('GPS: $gps', style: const TextStyle(color: AppColors.muted, fontSize: 10)),
      ],
      if (address != null && address.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(address, style: const TextStyle(color: AppColors.muted, fontSize: 10), maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    ]);
  }
}