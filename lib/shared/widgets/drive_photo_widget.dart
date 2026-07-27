import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../services/auth_storage.dart';
import '../services/drive_service.dart';

class DrivePhotoWidget extends StatefulWidget {
  final String?  driveFileId;
  final String?  reportId;
  final String?  photoSlot;
  final double   height;
  final double?  width;
  final BoxFit   fit;
  final bool     showFullscreen;
  final VoidCallback? onTap;
  /// Fired once when photo bytes load successfully (e.g. draft reopen).
  final VoidCallback? onLoaded;

  const DrivePhotoWidget({
    super.key,
    this.driveFileId,
    this.reportId,
    this.photoSlot,
    this.height        = 200,
    this.width,
    this.fit           = BoxFit.cover,
    this.showFullscreen = true,
    this.onTap,
    this.onLoaded,
  });

  @override State<DrivePhotoWidget> createState() => _DrivePhotoWidgetState();
}

class _DrivePhotoWidgetState extends State<DrivePhotoWidget> {
  Uint8List? _bytes;
  bool       _loading = true;
  bool       _error   = false;
  bool       _notifiedLoad = false;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  @override
  void didUpdateWidget(DrivePhotoWidget old) {
    super.didUpdateWidget(old);
    if (old.driveFileId != widget.driveFileId ||
        old.reportId != widget.reportId ||
        old.photoSlot != widget.photoSlot) {
      _notifiedLoad = false;
      _loadPhoto();
    }
  }

  Future<Uint8List?> _loadFromApi() async {
    final token = await AuthStorage.getToken();
    if (token == null || widget.reportId == null || widget.photoSlot == null) return null;

    final dio = Dio(BaseOptions(
      baseUrl: AppConstants.baseUrl,
      headers: {'Authorization': 'Bearer $token'},
      responseType: ResponseType.bytes,
    ));
    final res = await dio.get('/reports/${widget.reportId}/photo/${widget.photoSlot}');
    return Uint8List.fromList(res.data as List<int>);
  }

  Future<void> _loadPhoto() async {
    if (widget.driveFileId == null && widget.reportId == null) {
      setState(() { _loading = false; _error = true; });
      return;
    }

    setState(() { _loading = true; _error = false; });
    try {
      Uint8List? bytes;
      if (widget.reportId != null && widget.photoSlot != null) {
        bytes = await _loadFromApi();
      }
      bytes ??= widget.driveFileId != null
          ? await DriveService.fetchPhotoBytes(widget.driveFileId!)
          : null;

      if (!mounted) return;
      setState(() { _bytes = bytes; _loading = false; _error = bytes == null; });
      if (bytes != null && !_notifiedLoad) {
        _notifiedLoad = true;
        widget.onLoaded?.call();
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _placeholder(child: const CircularProgressIndicator(color: AppColors.brand, strokeWidth: 2));
    if (_error || _bytes == null) return _placeholder(child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.broken_image_outlined, color: AppColors.muted, size: 36),
      SizedBox(height: 8),
      Text('Photo unavailable', style: TextStyle(color: AppColors.muted, fontSize: 12)),
    ]));

    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(children: [
        ClipRRect(borderRadius: BorderRadius.circular(12),
          child: Image.memory(_bytes!, height: widget.height, width: widget.width ?? double.infinity, fit: widget.fit)),
        if (widget.showFullscreen)
          Positioned(bottom: 8, right: 8,
            child: Container(padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 18))),
      ]),
    );
  }

  Widget _placeholder({required Widget child}) => Container(
    height: widget.height, width: widget.width ?? double.infinity,
    decoration: BoxDecoration(color: AppColors.dark3, borderRadius: BorderRadius.circular(12)),
    child: Center(child: child));
}
