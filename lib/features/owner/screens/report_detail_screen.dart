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
import '../../../core/network/api_service.dart';
import '../../../core/utils/export_file_utils.dart';
import '../../../shared/widgets/report_media_tile.dart';
import '../../../shared/models/report_model.dart';
import '../../../shared/services/auth_storage.dart';
import '../controllers/owner_controller.dart';
import '../../../shared/permissions/app_permissions.dart';
import '../../../shared/permissions/permission_session.dart';

class ReportDetailScreen extends ConsumerStatefulWidget {
  final String reportId;
  const ReportDetailScreen({super.key, required this.reportId});
  @override ConsumerState<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends ConsumerState<ReportDetailScreen> {
  bool _sharing = false;
  String? _shareStatus;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(ownerControllerProvider.notifier).loadReportDetail(widget.reportId));
  }

  // -- Generate single report PDF + share via WhatsApp ---
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

      // Videos aren't inside the PDF — download each one as its own file and
      // share it alongside the PDF.
      final videos = await _downloadVideos(dir.path);
      if (!mounted) return;

      // Share sheet
      final box = context.findRenderObject() as RenderBox?;
      final videoNote = videos.isEmpty ? '' : ' Photos are in the PDF; ${videos.length} video${videos.length == 1 ? ' is' : 's are'} attached as separate file${videos.length == 1 ? '' : 's'}.';
      await SharePlus.instance.share(ShareParams(
        files: [XFile(path, mimeType: 'application/pdf'), ...videos],
        subject: 'Work Completion Report',
        text: customer != null
            ? 'Dear ${customer['name']}, please find attached the work completion report.$videoNote - ${ref.read(ownerControllerProvider).orgName}'
            : 'Work Completion Report.$videoNote',
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
      if (mounted) setState(() { _sharing = false; _shareStatus = null; });
    }
  }

  /// Downloads every (non-deleted) video on the report through the
  /// authorised API endpoint, keeping the original filename (sanitised and
  /// prefixed with its slot so names never collide).
  Future<List<XFile>> _downloadVideos(String dirPath) async {
    final report = ref.read(ownerControllerProvider).selectedReport;
    if (report == null) return [];
    final api = ref.read(apiServiceProvider);
    final out = <XFile>[];
    final entries = [
      for (final (i, m) in report.beforePhotos.indexed) ('Before', i, m),
      for (final (i, m) in report.afterPhotos.indexed) ('After', i, m),
    ].where((e) => e.$3.isVideo && !e.$3.isDeleted && e.$3.assetId != null).toList();
    for (final (n, (slot, i, m)) in entries.indexed) {
      final original = m.originalFilename ?? 'video.mp4';
      final dot = original.lastIndexOf('.');
      final ext = dot > 0 ? original.substring(dot + 1).toLowerCase() : 'mp4';
      final base = exportFileNamePart(dot > 0 ? original.substring(0, dot) : original, fallback: 'video');
      final file = '$dirPath/$slot-${i + 1}-$base.$ext';
      if (mounted) setState(() => _shareStatus = 'Downloading video ${n + 1} of ${entries.length}…');
      await api.downloadToFile('/media/${m.assetId}/download', file, onReceiveProgress: (r, t) {
        if (mounted && t > 0) setState(() => _shareStatus = 'Downloading video ${n + 1} of ${entries.length} — ${(r * 100 / t).round()}%');
      });
      out.add(XFile(file, mimeType: m.mimeType ?? 'video/mp4'));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final report   = ref.watch(ownerControllerProvider).selectedReport;
    final customer = report?.customer;
    final canShare = ref.watch(permissionSessionProvider).can(AppPermissions.reportsShare);

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
          else if (canShare)
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
                  Text(report.staffName, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 16)),
                  if (report.submittedAt != null)
                    Text(DateFormat('d MMM yyyy, h:mm a').format(report.submittedAt!),
                      style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                ])),
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (report.isFlagged ? AppColors.red : AppColors.green).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(100)),
                  child: Text(report.isFlagged ? '! Flagged' : 'Verified',
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
                    Text(customer['name'] ?? '', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
                  ]),
                  const Spacer(),
                  // Quick WhatsApp button
                  if (customer['phone'] != null && canShare)
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

          // Before / After Photos and videos
          Text(_videoCount(report) > 0 ? 'BEFORE & AFTER PHOTOS / VIDEOS' : 'BEFORE & AFTER PHOTOS',
            style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
          if (_videoCount(report) > 0) ...[
            const SizedBox(height: 6),
            Text('Photos are included in the PDF. ${_videoCount(report)} video${_videoCount(report) == 1 ? ' is' : 's are'} shared as separate files.',
              style: const TextStyle(color: AppColors.silver, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _slotColumn(context, 'Before', report.beforePhotos, 'before')),
            const SizedBox(width: 12),
            Expanded(child: _slotColumn(context, 'After', report.afterPhotos, 'after')),
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
            label: Text(_shareStatus ?? (customer != null
              ? 'Share PDF${_videoCount(report) > 0 ? ' + videos' : ''} to ${customer['name']}'
              : 'Export PDF${_videoCount(report) > 0 ? ' + ${_videoCount(report)} video${_videoCount(report) == 1 ? '' : 's'}' : ''}')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brand,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w700))),

          const SizedBox(height: 40),
        ])),
    );
  }


  /// "Before" for a single photo, "Before 2/3" when there are several.
  static String _slotLabel(String label, int i, int count) =>
      count > 1 ? '$label ${i + 1}/$count' : label;

  Widget _slotColumn(BuildContext context, String label, List<MediaData> photos, String slot) {
    if (photos.isEmpty) return _photoCol(context, label, null, slot, 0);
    return Column(children: [
      for (int i = 0; i < photos.length; i++)
        Padding(
          padding: EdgeInsets.only(bottom: i == photos.length - 1 ? 0 : 16),
          child: _photoCol(context, _slotLabel(label, i, photos.length), photos[i], slot, i),
        ),
    ]);
  }

  static int _videoCount(ReportModel r) =>
      [...r.beforePhotos, ...r.afterPhotos].where((m) => m.isVideo && !m.isDeleted).length;

  Widget _photoCol(BuildContext context, String label, MediaData? media, String slot, int index) {
    final driveFileId = media?.driveFileId;
    final capturedAt = media?.capturedAt;
    final gps = media?.gpsLine;
    final address = media?.address;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(media?.isVideo == true ? '$label (video)' : label, style: const TextStyle(color: AppColors.silver, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      ReportMediaTile(
        media: media,
        reportId: widget.reportId,
        slot: slot,
        index: index,
        label: label,
        height: 200,
        // Photos can be stored via direct upload (no driveFileId) or Drive —
        // the viewer itself handles both, so don't gate navigation on Drive only.
        onPhotoTap: () => context.push('/owner/photo-viewer?fileId=${driveFileId ?? ''}&label=${Uri.encodeQueryComponent(label)}&reportId=${widget.reportId}&slot=$slot&index=$index')),
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