import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../services/camera_service.dart';
import 'drive_photo_widget.dart';

enum _CaptureChoice { camera, gallery, remove }

class CameraCaptureWidget extends StatelessWidget {
  final String  label;
  final File?   image;
  final bool    isRequired;
  final String? staffName;
  final String? jobTitle;
  final bool    isUploading;
  final bool    uploadSucceeded;
  final bool    uploadFailed;
  final String? uploadStatus;
  final VoidCallback? onRetry;
  final Function(CapturedPhoto?) onCaptured;
  /// Remote draft preview when local [image] is unavailable.
  final String? networkImageUrl;
  final String? driveFileId;
  final String? reportId;
  final String? photoSlot;
  /// Called when a remote draft photo finishes loading from the server.
  final VoidCallback? onRemoteLoaded;

  const CameraCaptureWidget({
    super.key,
    required this.label,
    required this.image,
    required this.onCaptured,
    this.isRequired   = true,
    this.staffName,
    this.jobTitle,
    this.isUploading  = false,
    this.uploadSucceeded = false,
    this.uploadFailed = false,
    this.uploadStatus,
    this.onRetry,
    this.networkImageUrl,
    this.driveFileId,
    this.reportId,
    this.photoSlot,
    this.onRemoteLoaded,
  });

  bool get _hasRemoteIds =>
      (networkImageUrl != null && networkImageUrl!.isNotEmpty) ||
      (driveFileId != null && driveFileId!.isNotEmpty);

  bool get _hasRemotePreview =>
      _hasRemoteIds ||
      (reportId != null && reportId!.isNotEmpty && photoSlot != null);

  bool get _hasPreview => image != null || _hasRemotePreview;

  /// Saved when upload IDs exist, or when parent says uploadSucceeded (includes remote confirmed).
  bool get _showSaved => uploadSucceeded || _hasRemoteIds;

  Future<void> _showOptions(BuildContext context) async {
    final choice = await showModalBottomSheet<_CaptureChoice>(
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
            Text(
              _hasPreview ? 'Replace $label Photo' : 'Capture $label Photo',
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '📍 Date · Time · GPS auto-stamped on photo',
              style: TextStyle(color: AppColors.silver, fontSize: 12),
            ),
            const SizedBox(height: 20),
            _opt(
              Icons.camera_alt_rounded,
              AppColors.brand,
              'Open Camera',
              'Stamped + saved to Google Drive',
              () => Navigator.pop(sheetContext, _CaptureChoice.camera),
            ),
            const SizedBox(height: 10),
            _opt(
              Icons.photo_library_outlined,
              AppColors.blue,
              'Choose from Gallery',
              'Stamped with current time + GPS',
              () => Navigator.pop(sheetContext, _CaptureChoice.gallery),
            ),
            if (_hasPreview) ...[
              const SizedBox(height: 10),
              _opt(
                Icons.delete_outline_rounded,
                AppColors.red,
                'Remove',
                'Clear this photo',
                () => Navigator.pop(sheetContext, _CaptureChoice.remove),
              ),
            ],
            const SizedBox(height: 4),
          ]),
        ),
      ),
    );

    if (!context.mounted || choice == null) return;

    if (choice == _CaptureChoice.remove) {
      onCaptured(null);
      return;
    }

    // Wait for the sheet close animation so the camera/gallery picker opens reliably.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!context.mounted) return;

    final CapturedPhoto? captured = switch (choice) {
      _CaptureChoice.camera => await CameraService.takePhoto(
          context,
          staffName: staffName,
          jobTitle: jobTitle,
        ),
      _CaptureChoice.gallery => await CameraService.pickFromGallery(
          context,
          staffName: staffName,
          jobTitle: jobTitle,
        ),
      _CaptureChoice.remove => null,
    };

    if (captured != null) onCaptured(captured);
  }

  Widget _opt(IconData icon, Color color, String title, String sub, VoidCallback onTap) =>
    GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: color.withOpacity(0.07), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.2))),
      child: Row(children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 22)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600, fontSize: 15)),
          Text(sub,   style: const TextStyle(color: AppColors.silver, fontSize: 12)),
        ])),
        Icon(Icons.chevron_right_rounded, color: color.withOpacity(0.5), size: 20),
      ])));

  Widget _previewStack({required Widget child}) {
    return Stack(fit: StackFit.expand, children: [
      ClipRRect(borderRadius: BorderRadius.circular(13), child: child),
      Positioned(bottom: 0, left: 0, right: 0,
        child: Container(padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.6),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12))),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.camera_alt_outlined, color: Colors.white70, size: 14),
            SizedBox(width: 6),
            Text('Tap to retake', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ]))),
      Positioned(top: 10, right: 10,
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: uploadFailed
                ? AppColors.red.withOpacity(0.9)
                : _showSaved
                    ? AppColors.green.withOpacity(0.9)
                    : AppColors.yellow.withOpacity(0.9),
            borderRadius: BorderRadius.circular(100)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              uploadFailed
                  ? Icons.cloud_off_rounded
                  : _showSaved
                      ? Icons.cloud_done_rounded
                      : Icons.hourglass_empty_rounded,
              color: Colors.white,
              size: 12,
            ),
            const SizedBox(width: 4),
            Text(
              uploadFailed
                  ? 'Failed'
                  : _showSaved
                      ? 'Saved ✓'
                      : 'Pending',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ]))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: const TextStyle(color: AppColors.silver, fontSize: 13, fontWeight: FontWeight.w600)),
        if (isRequired) const Text(' *', style: TextStyle(color: AppColors.red, fontSize: 13)),
        const SizedBox(width: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: AppColors.brand.withOpacity(0.1), borderRadius: BorderRadius.circular(100)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.access_time_rounded, color: AppColors.brand, size: 10),
            SizedBox(width: 3),
            Text('Auto-stamped', style: TextStyle(color: AppColors.brand, fontSize: 10, fontWeight: FontWeight.w600)),
          ])),
        const Spacer(),
        if (_hasPreview && !isUploading)
          GestureDetector(
            onTap: uploadFailed ? onRetry : () => _showOptions(context),
            child: Text(
              uploadFailed ? 'Retry upload' : 'Retake',
              style: TextStyle(
                color: uploadFailed ? AppColors.red : AppColors.brand,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ]),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: isUploading
            ? null
            : uploadFailed
                ? onRetry
                : () => _showOptions(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 185, width: double.infinity,
          decoration: BoxDecoration(
            color:        _hasPreview ? Colors.transparent : AppColors.dark3,
            borderRadius: BorderRadius.circular(14),
            border:       Border.all(color: _hasPreview ? AppColors.brand : AppColors.border, width: _hasPreview ? 2 : 1)),
          child: isUploading
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const CircularProgressIndicator(color: AppColors.brand, strokeWidth: 2),
                const SizedBox(height: 12),
                Text(
                  uploadStatus ?? 'Uploading photo...',
                  style: const TextStyle(color: AppColors.silver, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ])
            : // Prefer remote draft preview over a local file once we have remote ids,
              // so we never show a local preview while stuck in "Pending".
              (_hasRemoteIds || (image == null && _hasRemotePreview))
                ? _previewStack(
                    child: networkImageUrl != null && networkImageUrl!.isNotEmpty
                        ? Image.network(
                            networkImageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => DrivePhotoWidget(
                              driveFileId: driveFileId,
                              reportId: reportId,
                              photoSlot: photoSlot,
                              height: 185,
                              showFullscreen: false,
                              onLoaded: onRemoteLoaded,
                            ),
                          )
                        : DrivePhotoWidget(
                            driveFileId: driveFileId,
                            reportId: reportId,
                            photoSlot: photoSlot,
                            height: 185,
                            showFullscreen: false,
                            onLoaded: onRemoteLoaded,
                          ),
                  )
              : image != null
              ? _previewStack(child: Image.file(image!, fit: BoxFit.cover))
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(width: 60, height: 60, decoration: BoxDecoration(color: AppColors.brand.withOpacity(0.1), shape: BoxShape.circle),
                    child: Icon(label == 'Before' ? Icons.camera_alt_outlined : Icons.camera_enhance_outlined, color: AppColors.brand, size: 30)),
                  const SizedBox(height: 12),
                  Text('Tap to capture $label photo', style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  const Text('📍 Timestamp + GPS · saved to Drive', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ]),
        ),
      ),
    ]);
  }
}
