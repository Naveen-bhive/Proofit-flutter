import 'dart:io';
import 'dart:isolate';
import 'package:image/image.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class PhotoStampService {
  static int _seq = 0;

  static Future<File> stampPhoto({
    required File originalFile,
    required DateTime capturedAt,
    double? latitude,
    double? longitude,
    String? address,
    String? staffName,
    String? jobTitle,
  }) async {
    final dateStr = DateFormat('dd MMM yyyy').format(capturedAt);
    final timeStr = DateFormat('hh:mm:ss a').format(capturedAt);
    final locationStr = address ??
        (latitude != null
            ? '${latitude.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}'
            : 'Location unavailable');

    final hasTitle = jobTitle != null && jobTitle.isNotEmpty;
    final lines = [
      if (hasTitle) jobTitle,
      '$dateStr  $timeStr',
      locationStr,
      if (staffName != null && staffName.isNotEmpty) staffName,
      if (latitude != null)
        'GPS: ${latitude.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}',
    ];

    final dir = await getTemporaryDirectory();
    final outPath =
        '${dir.path}/stamped_${capturedAt.millisecondsSinceEpoch}_${_seq++}.jpg';
    final inPath = originalFile.path;

    // Decode / draw / encode is pure-Dart and takes 1-3s on a full-size
    // photo — run it off the UI isolate so the upload spinner keeps animating.
    final ok = await Isolate.run(
        () => _stampToFile(inPath, outPath, lines, hasTitle));
    return ok ? File(outPath) : originalFile;
  }
}

bool _stampToFile(
    String inPath, String outPath, List<String> lines, bool hasTitle) {
  final original = decodeImage(File(inPath).readAsBytesSync());
  if (original == null) return false;

  Image image = original;
  if (image.width > 1920) image = copyResize(image, width: 1920);

  final iw = image.width;
  final ih = image.height;

  final bannerH = 30 + (lines.length * 26);
  final bannerY = ih - bannerH;

  // Dark overlay (75% black blended over the photo)
  fillRect(image,
      x1: 0, y1: bannerY, x2: iw - 1, y2: ih - 1,
      color: ColorRgba8(0, 0, 0, 191));

  // Logo-blue left border
  fillRect(image,
      x1: 0, y1: bannerY, x2: 4, y2: ih - 1,
      color: ColorRgb8(47, 128, 237));

  // Text lines
  int textY = bannerY + 10;
  for (int i = 0; i < lines.length; i++) {
    final isTitle = i == 0 && hasTitle;
    drawString(
      image,
      lines[i],
      font: isTitle ? arial24 : arial14,
      x: 14,
      y: textY,
      color: isTitle ? ColorRgb8(47, 128, 237) : ColorRgb8(255, 255, 255),
    );
    textY += isTitle ? 28 : 22;
  }

  // ProofIt watermark
  drawString(
    image,
    'ProofIt',
    font: arial14,
    x: iw - 90,
    y: 12,
    color: ColorRgb8(47, 128, 237),
  );

  File(outPath).writeAsBytesSync(encodeJpg(image, quality: 85));
  return true;
}
