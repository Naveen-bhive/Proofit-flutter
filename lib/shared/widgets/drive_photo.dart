import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../services/drive_service.dart';

class DrivePhoto extends StatefulWidget {
  final String? driveFileId;
  final double? height;
  final double? width;
  final BoxFit  fit;
  final Widget? placeholder;
  final VoidCallback? onTap;

  const DrivePhoto({
    super.key,
    required this.driveFileId,
    this.height,
    this.width,
    this.fit      = BoxFit.cover,
    this.placeholder,
    this.onTap,
  });

  @override
  State<DrivePhoto> createState() => _DrivePhotoState();
}

class _DrivePhotoState extends State<DrivePhoto> {
  Uint8List? _bytes;
  bool       _loading = true;
  bool       _error   = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DrivePhoto old) {
    super.didUpdateWidget(old);
    if (old.driveFileId != widget.driveFileId) _load();
  }

  Future<void> _load() async {
    if (widget.driveFileId == null || widget.driveFileId!.isEmpty) {
      setState(() { _loading = false; _error = true; });
      return;
    }
    setState(() { _loading = true; _error = false; });
    final bytes = await DriveService.fetchPhotoBytes(widget.driveFileId!);
    if (mounted) setState(() { _bytes = bytes; _loading = false; _error = bytes == null; });
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (_loading) {
      child = Container(
        width: widget.width, height: widget.height,
        color: AppColors.dark3,
        child: const Center(child: SizedBox(
          width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))));
    } else if (_error || _bytes == null) {
      child = widget.placeholder ?? Container(
        width: widget.width, height: widget.height,
        color: AppColors.dark3,
        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.broken_image_outlined, color: AppColors.muted, size: 36),
          SizedBox(height: 8),
          Text('Photo unavailable', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ]));
    } else {
      child = Image.memory(
        _bytes!,
        width:  widget.width,
        height: widget.height,
        fit:    widget.fit,
        gaplessPlayback: true);
    }

    if (widget.onTap != null) {
      return GestureDetector(onTap: widget.onTap, child: child);
    }
    return child;
  }
}