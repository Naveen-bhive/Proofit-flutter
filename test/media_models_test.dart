import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:proofit/shared/models/report_model.dart';
import 'package:proofit/shared/models/storage_models.dart';
import 'package:proofit/shared/services/camera_service.dart';
import 'package:proofit/shared/widgets/multi_photo_picker.dart';

void main() {
  group('MediaData', () {
    test('reads video fields and keeps legacy photos as photos', () {
      final video = MediaData.fromJson({
        'type': 'video', 'assetId': 'a1', 'url': 'https://x/v.mp4', 'thumbnailUrl': 'https://x/v.jpg',
        'bytes': 1048576, 'durationSec': 42.4, 'originalFilename': 'site.mp4',
      });
      expect(video.isVideo, isTrue);
      expect(video.bytes, 1048576);
      expect(video.durationSec, 42.4);

      final legacy = MediaData.fromJson({'url': 'https://x/p.jpg'});
      expect(legacy.isVideo, isFalse);
      expect(legacy.type, 'photo');
      expect(legacy.toJson().containsKey('assetId'), isFalse);
    });

    test('deleted media still counts as an entry so history is preserved', () {
      final r = ReportModel.fromJson({
        'jobTitle': 'Job', 'orgId': 'o', 'staffId': 's',
        'beforePhotos': [{'type': 'photo', 'assetId': 'a', 'deletedAt': '2026-10-01T00:00:00Z'}],
      });
      expect(r.beforePhotos.single.isDeleted, isTrue);
    });
  });

  group('ReportPhoto.toMedia', () {
    test('sends the server asset reference, never a client-reported size', () {
      final item = ReportPhoto.video(CapturedPhoto(file: File('/tmp/v.mp4'), capturedAt: DateTime.utc(2026, 10, 1), latitude: 9.9, longitude: 78.1))
        ..applyUpload({'_id': 'asset123', 'url': 'https://x/v.mp4', 'bytes': 5000, 'durationSec': 12});
      final m = item.toMedia('before_1');
      expect(m['assetId'], 'asset123');
      expect(m['type'], 'video');
      expect(m.containsKey('bytes'), isFalse);
      expect(m['capturedAt'], '2026-10-01T00:00:00.000Z');
      expect(item.isDone, isTrue);
    });
  });

  group('storage formatting', () {
    test('formats sizes and durations', () {
      expect(formatBytes(1024 * 1024 * 1024), '1.00 GB');
      expect(formatBytes(150 * 1024 * 1024), '150 MB');
      expect(formatBytes(2048), '2 KB');
      expect(formatDuration(65), '1:05');
      expect(formatDuration(null), '');
    });

    test('parses the storage summary', () {
      final s = StorageSummary.fromJson({
        'includedBytes': 1073741824, 'addOnBytes': 5368709120, 'capacityBytes': 6442450944,
        'usedBytes': 100, 'freeBytes': 6442450844, 'percentUsed': 0, 'overQuota': false,
        'images': {'count': 3, 'bytes': 60}, 'videos': {'count': 1, 'bytes': 40},
        'activeAddOns': [{'_id': 'x', 'name': '5 GB storage', 'sizeBytes': 5368709120, 'expiresAt': '2026-11-01T00:00:00Z', 'isCurrent': true}],
      });
      expect(s.videoCount, 1);
      expect(s.activeAddOns.single.name, '5 GB storage');
    });
  });
}
