import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_service.dart';
import '../../../core/utils/export_file_utils.dart';
import '../../../shared/models/storage_models.dart' show formatBytes;

/// After a PDF export: videos are never embedded in the PDF, so if the
/// exported reports have any, offer to download them as separate files.
/// [filters] are the same body sent to POST /reports/export. Returns the
/// downloaded files (empty if there are none or the owner declines).
Future<List<XFile>> offerExportVideos(
  BuildContext context,
  ApiService api,
  Map<String, dynamic> filters,
  String dirPath, {
  void Function(String status)? onStatus,
}) async {
  Map data;
  try {
    final res = await api.post('/reports/export/videos', data: filters);
    data = res.data['data'] as Map? ?? const {};
  } catch (_) {
    return []; // the PDF is already saved — never lose it over the video list
  }
  final videos = List<Map<String, dynamic>>.from((data['videos'] as List? ?? const []).map((v) => Map<String, dynamic>.from(v as Map)));
  if (videos.isEmpty || !context.mounted) return [];

  final total = (data['totalBytes'] as num?)?.toInt() ?? 0;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${videos.length} video${videos.length == 1 ? '' : 's'} not in the PDF'),
      content: Text(
        'Photos are inside the PDF. Videos are separate files${total > 0 ? ' (${formatBytes(total)} in total)' : ''}. Download them now to share with the PDF?',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('PDF only')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Download videos', style: TextStyle(color: AppColors.brand))),
      ],
    ),
  );
  if (ok != true) return [];

  final files = <XFile>[];
  var failed = 0;
  for (final (n, v) in videos.indexed) {
    final assetId = v['assetId']?.toString();
    if (assetId == null) continue;
    final original = v['filename']?.toString() ?? 'video.mp4';
    final dot = original.lastIndexOf('.');
    final ext = dot > 0 ? original.substring(dot + 1).toLowerCase() : 'mp4';
    final name = exportFileNamePart(
      '${v['jobTitle'] ?? 'report'}-${v['slot'] ?? ''}-${(v['index'] as num? ?? 0).toInt() + 1}-${dot > 0 ? original.substring(0, dot) : original}',
      fallback: 'video-${n + 1}',
    );
    final path = '$dirPath/$name.$ext';
    onStatus?.call('Downloading video ${n + 1} of ${videos.length}…');
    try {
      await api.downloadToFile('/media/$assetId/download', path);
      files.add(XFile(path, mimeType: v['mimeType']?.toString() ?? 'video/mp4'));
    } catch (_) {
      failed += 1;
    }
  }
  if (failed > 0 && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$failed video${failed == 1 ? '' : 's'} could not be downloaded. Try the export again.'),
      backgroundColor: AppColors.red,
    ));
  }
  return files;
}
