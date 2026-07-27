import 'dart:io';
import 'package:image/image.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class PhotoStampService {
  static Future<File> stampPhoto({
    required File originalFile,
    required DateTime capturedAt,
    double? latitude,
    double? longitude,
    String? address,
    String? staffName,
    String? jobTitle,
  }) async {
    final bytes    = await originalFile.readAsBytes();
    final original = decodeImage(bytes);
    if (original == null) return originalFile;

    Image image = original;
    if (image.width > 1920) image = copyResize(image, width: 1920);

    final iw = image.width;
    final ih = image.height;

    final dateStr     = DateFormat('dd MMM yyyy').format(capturedAt);
    final timeStr     = DateFormat('hh:mm:ss a').format(capturedAt);
    final locationStr = address ?? (latitude != null ? '${latitude.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}' : 'Location unavailable');

    final lines = [
      if (jobTitle != null && jobTitle.isNotEmpty) jobTitle,
      '$dateStr  $timeStr',
      locationStr,
      if (staffName != null && staffName.isNotEmpty) staffName,
      if (latitude != null) 'GPS: ${latitude.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}',
    ];

    final bannerH = 30 + (lines.length * 26);
    final bannerY = ih - bannerH;

    // Dark overlay
    for (int y = bannerY; y < ih; y++) {
      for (int x = 0; x < iw; x++) {
        final p = image.getPixel(x, y);
        image.setPixel(x, y, ColorRgb8(
          (p.r * 0.25).round(),
          (p.g * 0.25).round(),
          (p.b * 0.25).round(),
        ));
      }
    }

    // Orange left border
    for (int y = bannerY; y < ih; y++) {
      for (int x = 0; x < 5; x++) {
        image.setPixel(x, y, ColorRgb8(255, 77, 0));
      }
    }

    // Text lines
    int textY = bannerY + 10;
    for (int i = 0; i < lines.length; i++) {
      final isTitle = i == 0 && jobTitle != null && jobTitle.isNotEmpty;
      drawString(image, lines[i],
        font: isTitle ? arial24 : arial14,
        x: 14,
        y: textY,
        color: isTitle ? ColorRgb8(255, 77, 0) : ColorRgb8(255, 255, 255),
      );
      textY += isTitle ? 28 : 22;
    }

    // ProofIt watermark
    drawString(image, 'ProofIt',
      font: arial14,
      x: iw - 90,
      y: 12,
      color: ColorRgb8(255, 77, 0),
    );

    final dir     = await getTemporaryDirectory();
    final outPath = '${dir.path}/stamped_${capturedAt.millisecondsSinceEpoch}.jpg';
    final outFile = File(outPath);
    await outFile.writeAsBytes(encodeJpg(image, quality: 88));
    return outFile;
  }
}
