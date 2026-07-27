import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/services/auth_storage.dart';
import '../../../shared/services/drive_service.dart';

class OwnerPhotoViewerScreen extends StatefulWidget {
  final String  fileId;
  final String  label;
  final String? reportId;
  final String? photoSlot;
  const OwnerPhotoViewerScreen({
    super.key,
    required this.fileId,
    required this.label,
    this.reportId,
    this.photoSlot,
  });
  @override State<OwnerPhotoViewerScreen> createState() => _OwnerPhotoViewerScreenState();
}

class _OwnerPhotoViewerScreenState extends State<OwnerPhotoViewerScreen> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Uint8List? bytes;
    if (widget.reportId != null && widget.photoSlot != null) {
      try {
        final token = await AuthStorage.getToken();
        if (token != null) {
          final dio = Dio(BaseOptions(
            baseUrl: AppConstants.baseUrl,
            headers: {'Authorization': 'Bearer $token'},
            responseType: ResponseType.bytes,
          ));
          final res = await dio.get('/reports/${widget.reportId}/photo/${widget.photoSlot}');
          bytes = Uint8List.fromList(res.data as List<int>);
        }
      } catch (_) {}
    }
    bytes ??= await DriveService.fetchPhotoBytes(widget.fileId);
    if (mounted) setState(() { _bytes = bytes; _loading = false; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, title: Text(widget.label, style: const TextStyle(color: Colors.white))),
    body: _loading
      ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
      : _bytes == null
        ? const Center(child: Text('Photo unavailable', style: TextStyle(color: AppColors.silver)))
        : PhotoView(imageProvider: MemoryImage(_bytes!),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 3),
  );
}
