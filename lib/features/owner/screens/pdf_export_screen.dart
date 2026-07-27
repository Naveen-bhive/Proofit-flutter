import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/services/drive_service.dart';
import '../../../shared/models/report_model.dart';
import '../controllers/owner_controller.dart';

class PdfExportScreen extends ConsumerStatefulWidget {
  final String reportId;
  const PdfExportScreen({super.key, required this.reportId});
  @override ConsumerState<PdfExportScreen> createState() => _PdfExportScreenState();
}

class _PdfExportScreenState extends ConsumerState<PdfExportScreen> {
  bool _generating = false;
  String _status   = '';
  Uint8List? _pdfBytes;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(ownerControllerProvider.notifier).loadReportDetail(widget.reportId);
      _generatePdf();
    });
  }

  Future<void> _generatePdf() async {
    setState(() { _generating = true; _status = 'Loading report...'; });
    final report = ref.read(ownerControllerProvider).selectedReport;
    if (report == null) { setState(() { _generating = false; _status = 'Report not found'; }); return; }
    final org = ref.read(ownerControllerProvider).orgName;

    setState(() => _status = 'Fetching before photo from Drive...');
    Uint8List? beforeBytes, afterBytes;
    if (report.beforeDriveFileId != null) {
      beforeBytes = await DriveService.fetchPhotoBytes(report.beforeDriveFileId!);
    }
    setState(() => _status = 'Fetching after photo from Drive...');
    if (report.afterDriveFileId != null) {
      afterBytes = await DriveService.fetchPhotoBytes(report.afterDriveFileId!);
    }

    setState(() => _status = 'Generating PDF...');

    final pdf    = pw.Document();
    final orange = PdfColor.fromHex('#FF4D00');
    final dark   = PdfColor.fromHex('#111111');
    final grey   = PdfColor.fromHex('#888888');
    final green  = PdfColor.fromHex('#22C55E');
    final red    = PdfColor.fromHex('#EF4444');

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [

        // Header
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('ProofIt', style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold, color: orange)),
            pw.Text('Work Done. Proved Instantly.', style: pw.TextStyle(fontSize: 11, color: grey)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text(org, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: dark)),
            pw.Text('Generated ${DateFormat("d MMM yyyy").format(DateTime.now())}',
              style: pw.TextStyle(fontSize: 10, color: grey)),
          ]),
        ]),
        pw.SizedBox(height: 4),
        pw.Divider(color: orange, thickness: 2),
        pw.SizedBox(height: 20),

        // Report info
        pw.Container(padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#F8F8F8'),
            borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(report.jobTitle,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: dark)),
            pw.SizedBox(height: 12),
            pw.Row(children: [
              pw.Text('Staff:  ', style: pw.TextStyle(color: grey, fontSize: 11)),
              pw.Text(report.staffName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.SizedBox(width: 24),
              pw.Text('Date:  ', style: pw.TextStyle(color: grey, fontSize: 11)),
              pw.Text(report.submittedAt != null
                ? DateFormat('d MMM yyyy, h:mm a').format(report.submittedAt!)
                : 'N/A', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
            ]),
            pw.SizedBox(height: 6),
            if (report.location?.address != null) pw.Row(children: [
              pw.Text('Location:  ', style: pw.TextStyle(color: grey, fontSize: 11)),
              pw.Expanded(child: pw.Text(report.location!.address!,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11))),
            ]),
            pw.SizedBox(height: 6),
            pw.Row(children: [
              pw.Text('Status:  ', style: pw.TextStyle(color: grey, fontSize: 11)),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(
                  color: report.isFlagged ? red.shade(0.15) : green.shade(0.15),
                  borderRadius: pw.BorderRadius.circular(100)),
                child: pw.Text(
                  report.isFlagged ? '⚠ Location Flagged' : '✓ Verified',
                  style: pw.TextStyle(
                    color: report.isFlagged ? red : green,
                    fontSize: 10, fontWeight: pw.FontWeight.bold))),
            ]),
          ])),
        pw.SizedBox(height: 24),

        // Before / After photos
        pw.Text('PROOF PHOTOS',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
              color: grey, letterSpacing: 1.5)),
        pw.SizedBox(height: 12),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          // Before
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: 6),
              color: orange,
              child: pw.Center(child: pw.Text('BEFORE',
                style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 11)))),
            if (beforeBytes != null)
              pw.Image(pw.MemoryImage(beforeBytes), height: 200, fit: pw.BoxFit.cover)
            else
              pw.Container(height: 200,
                color: PdfColor.fromHex('#EEEEEE'),
                child: pw.Center(child: pw.Text('No photo', style: pw.TextStyle(color: grey)))),
            pw.SizedBox(height: 6),
            ..._mediaCaptionWidgets(report.beforeMedia, report.location, grey),
          ])),
          pw.SizedBox(width: 12),
          // After
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: 6),
              color: green,
              child: pw.Center(child: pw.Text('AFTER',
                style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 11)))),
            if (afterBytes != null)
              pw.Image(pw.MemoryImage(afterBytes), height: 200, fit: pw.BoxFit.cover)
            else
              pw.Container(height: 200,
                color: PdfColor.fromHex('#EEEEEE'),
                child: pw.Center(child: pw.Text('No photo', style: pw.TextStyle(color: grey)))),
            pw.SizedBox(height: 6),
            ..._mediaCaptionWidgets(report.afterMedia, report.location, grey),
          ])),
        ]),

        if (report.notes != null && report.notes!.isNotEmpty) ...[
          pw.SizedBox(height: 20),
          pw.Text('NOTES', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
              color: grey, letterSpacing: 1.5)),
          pw.SizedBox(height: 8),
          pw.Text(report.notes!, style: pw.TextStyle(fontSize: 12, color: dark)),
        ],

        pw.Spacer(),
        pw.Divider(color: PdfColor.fromHex('#DDDDDD')),
        pw.SizedBox(height: 6),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Generated by ProofIt — proofitapp.in',
            style: pw.TextStyle(color: grey, fontSize: 9)),
          pw.Text(DateFormat('d MMM yyyy, h:mm a').format(DateTime.now()),
            style: pw.TextStyle(color: grey, fontSize: 9)),
        ]),
      ])));

    _pdfBytes = await pdf.save();
    setState(() { _generating = false; _status = 'PDF ready'; });
  }

  Future<void> _share() async {
    if (_pdfBytes == null) return;
    final dir  = await getTemporaryDirectory();
    final path = '${dir.path}/ProofIt_Report_${widget.reportId}.pdf';
    await File(path).writeAsBytes(_pdfBytes!);
    await Share.shareXFiles([XFile(path)],
      subject: 'Work Completion Report — ProofIt',
      text: 'Please find the work completion report attached.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(title: const Text('Export PDF')),
      body: _generating
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(color: AppColors.brand),
              const SizedBox(height: 20),
              Text(_status, style: const TextStyle(color: AppColors.silver, fontSize: 14)),
            ]))
          : _pdfBytes == null
              ? Center(child: Text(_status, style: const TextStyle(color: AppColors.red)))
              : Column(children: [
                  Expanded(child: PdfPreview(
                    build: (_) async => _pdfBytes!,
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                    pdfPreviewPageDecoration: const BoxDecoration(color: Colors.white),
                    actions: const [],
                  )),
                  Padding(padding: const EdgeInsets.all(16), child: Row(children: [
                    Expanded(child: ElevatedButton.icon(
                      onPressed: _share,
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Share to Customer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
                  ])),
                ]),
    );
  }

  List<pw.Widget> _mediaCaptionWidgets(MediaData? media, LocationData? fallback, PdfColor grey) {
    final lines = <String>[];
    if (media?.capturedAt != null) {
      lines.add('Captured: ${DateFormat('d MMM yyyy, h:mm:ss a').format(media!.capturedAt!.toLocal())}');
    }
    final lat = media?.latitude ?? fallback?.latitude;
    final lng = media?.longitude ?? fallback?.longitude;
    final addr = media?.address ?? fallback?.address;
    if (lat != null && lng != null) {
      lines.add('GPS: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}');
    }
    if (addr != null && addr.isNotEmpty) lines.add(addr);
    return lines
        .map((line) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text(line, style: pw.TextStyle(fontSize: 8, color: grey)),
            ))
        .toList();
  }
}