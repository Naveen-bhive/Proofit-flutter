import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/services/camera_service.dart';
import '../../../shared/services/location_service.dart';
import '../controllers/staff_controller.dart';

class MultiPhotoReportScreen extends ConsumerStatefulWidget {
  final String? reportId;
  const MultiPhotoReportScreen({super.key, this.reportId});
  @override ConsumerState<MultiPhotoReportScreen> createState() => _MultiPhotoReportScreenState();
}

class _MultiPhotoReportScreenState extends ConsumerState<MultiPhotoReportScreen> {
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  final List<File> _beforePhotos = [];
  final List<File> _afterPhotos  = [];
  double? _lat, _lng;
  String? _address;
  bool _locLoading  = false;
  bool _submitting  = false;
  String? _error;

  static const int maxPhotos = 5;

  @override
  void initState() { super.initState(); _getLocation(); }

  Future<void> _getLocation() async {
    setState(() => _locLoading = true);
    final pos = await LocationService.getCurrentPosition();
    if (pos != null && mounted) {
      final addr = await LocationService.getAddressFromCoords(pos.latitude, pos.longitude);
      setState(() { _lat = pos.latitude; _lng = pos.longitude; _address = addr; });
    }
    if (mounted) setState(() => _locLoading = false);
  }

  Future<void> _addPhoto(bool isBefore) async {
    final list = isBefore ? _beforePhotos : _afterPhotos;
    if (list.length >= maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maximum 5 photos per section'), backgroundColor: AppColors.red));
      return;
    }
    final captured = await CameraService.takePhoto(context, jobTitle: _titleCtrl.text);
    if (captured != null) setState(() => isBefore ? _beforePhotos.add(captured.file) : _afterPhotos.add(captured.file));
  }

  void _removePhoto(bool isBefore, int index) {
    setState(() => isBefore ? _beforePhotos.removeAt(index) : _afterPhotos.removeAt(index));
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) { setState(() => _error = 'Job title is required'); return; }
    if (_beforePhotos.isEmpty)          { setState(() => _error = 'At least 1 before photo required'); return; }
    if (_afterPhotos.isEmpty)           { setState(() => _error = 'At least 1 after photo required'); return; }
    setState(() { _submitting = true; _error = null; });

    final ok = await ref.read(staffControllerProvider.notifier).submitMultiPhotoReport(
      jobTitle:     _titleCtrl.text.trim(),
      notes:        _notesCtrl.text.trim(),
      beforePhotos: _beforePhotos,
      afterPhotos:  _afterPhotos,
      latitude:     _lat, longitude: _lng, address: _address,
    );

    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted!'), backgroundColor: AppColors.green));
      context.pop();
    } else { setState(() => _error = 'Failed to submit. Try again.'); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(title: const Text('New Report (Multi-Photo)')),
      body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextFormField(controller: _titleCtrl, style: const TextStyle(color: AppColors.white),
          decoration: const InputDecoration(labelText: 'Job Title *', prefixIcon: Icon(Icons.work_outline_rounded, color: AppColors.muted))),
        const SizedBox(height: 16),

        // Location
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.dark3, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: Row(children: [
            Icon(_locLoading ? Icons.hourglass_empty : Icons.location_on_outlined, color: _lat != null ? AppColors.green : AppColors.yellow, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(_locLoading ? 'Getting location...' : _address ?? 'Unavailable',
              style: TextStyle(color: _lat != null ? AppColors.light : AppColors.silver, fontSize: 13))),
          ])),
        const SizedBox(height: 24),

        _photoSection('BEFORE PHOTOS', _beforePhotos, true),
        const SizedBox(height: 20),
        _photoSection('AFTER PHOTOS',  _afterPhotos,  false),
        const SizedBox(height: 16),

        TextFormField(controller: _notesCtrl, maxLines: 3, style: const TextStyle(color: AppColors.white),
          decoration: const InputDecoration(labelText: 'Notes (optional)')),

        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.red.withValues(alpha: 0.3))),
            child: Row(children: [const Icon(Icons.error_outline, color: AppColors.red, size: 18), const SizedBox(width: 8), Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 13)))])),
        ],
        const SizedBox(height: 28),
        AppButton(label: 'Submit Report', isLoading: _submitting, onPressed: _submit, icon: Icons.send_rounded),
        const SizedBox(height: 40),
      ])),
    );
  }

  Widget _photoSection(String title, List<File> photos, bool isBefore) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
        const Spacer(),
        Text('${photos.length}/$maxPhotos', style: TextStyle(color: photos.isEmpty ? AppColors.red : AppColors.silver, fontSize: 12)),
      ]),
      const SizedBox(height: 10),
      GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
        itemCount: photos.length + (photos.length < maxPhotos ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == photos.length) {
            return GestureDetector(
              onTap: () => _addPhoto(isBefore),
              child: Container(decoration: BoxDecoration(color: AppColors.dark3, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.brand.withValues(alpha: 0.4), width: 1.5)),
                child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_a_photo_outlined, color: AppColors.brand, size: 24),
                  SizedBox(height: 4),
                  Text('Add', style: TextStyle(color: AppColors.brand, fontSize: 11, fontWeight: FontWeight.w600)),
                ])));
          }
          return Stack(children: [
            ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(photos[i], fit: BoxFit.cover, width: double.infinity, height: double.infinity)),
            Positioned(top: 4, right: 4,
              child: GestureDetector(
                onTap: () => _removePhoto(isBefore, i),
                child: Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 12)))),
          ]);
        },
      ),
    ]);
  }
}
