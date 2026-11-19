import 'package:flutter_test/flutter_test.dart';
import 'package:proofit/shared/models/report_model.dart';
import 'package:proofit/shared/widgets/multi_photo_picker.dart';

void main() {
  group('Report status', () {
    test('in-progress reports are editable and labelled', () {
      final r = ReportModel.fromJson(
          {'_id': 'r1', 'jobTitle': 'Paint', 'status': 'in_progress'});
      expect(r.isInProgress, isTrue);
      expect(r.isEditable, isTrue);
      expect(r.isSubmitted, isFalse);
      expect(r.statusLabel, 'In progress');
    });

    test('drafts are editable, submitted reports are locked', () {
      final draft = ReportModel.fromJson({'jobTitle': 'Paint'});
      expect(draft.status, 'draft');
      expect(draft.isEditable, isTrue);
      expect(draft.statusLabel, 'Draft');

      final done =
          ReportModel.fromJson({'jobTitle': 'Paint', 'status': 'submitted'});
      expect(done.isEditable, isFalse);
      expect(done.statusLabel, 'Completed');
    });
  });

  group('Progress media', () {
    test('parses progress media with capture and upload dates', () {
      final r = ReportModel.fromJson({
        'jobTitle': 'Paint',
        'status': 'in_progress',
        'progressMedia': [
          {
            'type': 'photo',
            'assetId': 'a1',
            'url': 'https://x/p.jpg',
            'capturedAt': '2026-11-09T06:00:00.000Z',
          },
          {
            'type': 'video',
            'assetId': 'a2',
            'uploadedAt': '2026-11-10T08:00:00.000Z',
          },
          {'type': 'photo', 'assetId': 'a3'},
        ],
      });
      expect(r.progressMedia, hasLength(3));
      // parseApiDate returns local time: compare instants, not representations.
      expect(
          r.progressMedia[0].takenAt!
              .isAtSameMomentAs(DateTime.parse('2026-11-09T06:00:00.000Z')),
          isTrue);
      // No capture time recorded: fall back to when the server stored it.
      expect(
          r.progressMedia[1].takenAt!
              .isAtSameMomentAs(DateTime.parse('2026-11-10T08:00:00.000Z')),
          isTrue);
      expect(r.progressMedia[1].isVideo, isTrue);
      expect(r.progressMedia[2].takenAt, isNull);
    });

    test('a saved progress item is sent back with its capture date', () {
      final remote = MediaData.fromJson({
        'type': 'photo',
        'assetId': 'a1',
        'url': 'https://x/p.jpg',
        'capturedAt': '2026-11-09T06:00:00.000Z',
        'latitude': 12.9,
        'longitude': 77.6,
      });
      final payload = ReportPhoto.remote(remote).toMedia('progress_1');
      expect(payload['assetId'], 'a1');
      expect(payload['label'], 'progress_1');
      expect(payload['capturedAt'], '2026-11-09T06:00:00.000Z');
      expect(payload['latitude'], 12.9);
    });

    test('legacy reports without progress media parse to an empty list', () {
      final r = ReportModel.fromJson({'jobTitle': 'Paint'});
      expect(r.progressMedia, isEmpty);
    });
  });
}
