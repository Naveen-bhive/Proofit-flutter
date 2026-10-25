import '../../core/utils/date_utils.dart';

int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

/// GET /storage/summary — capacity is included storage + active add-ons.
class StorageSummary {
  final int includedBytes;
  final int addOnBytes;
  final int capacityBytes;
  final int usedBytes;
  final int freeBytes;
  final double percentUsed;
  final bool overQuota;
  final int imageCount;
  final int imageBytes;
  final int videoCount;
  final int videoBytes;
  final List<ActiveAddOn> activeAddOns;

  const StorageSummary({
    required this.includedBytes,
    required this.addOnBytes,
    required this.capacityBytes,
    required this.usedBytes,
    required this.freeBytes,
    required this.percentUsed,
    required this.overQuota,
    required this.imageCount,
    required this.imageBytes,
    required this.videoCount,
    required this.videoBytes,
    required this.activeAddOns,
  });

  factory StorageSummary.fromJson(Map<String, dynamic> j) => StorageSummary(
        includedBytes: _int(j['includedBytes']),
        addOnBytes: _int(j['addOnBytes']),
        capacityBytes: _int(j['capacityBytes']),
        usedBytes: _int(j['usedBytes']),
        freeBytes: _int(j['freeBytes']),
        percentUsed: (j['percentUsed'] as num?)?.toDouble() ?? 0,
        overQuota: j['overQuota'] == true,
        imageCount: _int(j['images']?['count']),
        imageBytes: _int(j['images']?['bytes']),
        videoCount: _int(j['videos']?['count']),
        videoBytes: _int(j['videos']?['bytes']),
        activeAddOns: [
          for (final a in (j['activeAddOns'] as List? ?? const []))
            ActiveAddOn.fromJson(Map<String, dynamic>.from(a as Map)),
        ],
      );
}

class ActiveAddOn {
  final String id;
  final String name;
  final int sizeBytes;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final bool isCurrent;

  const ActiveAddOn({required this.id, required this.name, required this.sizeBytes, this.startsAt, this.expiresAt, required this.isCurrent});

  factory ActiveAddOn.fromJson(Map<String, dynamic> j) => ActiveAddOn(
        id: j['_id']?.toString() ?? '',
        name: j['name']?.toString() ?? 'Storage',
        sizeBytes: _int(j['sizeBytes']),
        startsAt: parseApiDate(j['startsAt']),
        expiresAt: parseApiDate(j['expiresAt']),
        isCurrent: j['isCurrent'] != false,
      );
}

/// A purchasable storage pack — price always comes from the server.
class AddOnProduct {
  final String id;
  final String name;
  final int sizeGb;
  final double price;
  final int durationDays;
  final String description;

  const AddOnProduct({required this.id, required this.name, required this.sizeGb, required this.price, required this.durationDays, required this.description});

  factory AddOnProduct.fromJson(Map<String, dynamic> j) => AddOnProduct(
        id: j['_id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        sizeGb: _int(j['sizeGb']),
        price: (j['price'] as num?)?.toDouble() ?? 0,
        durationDays: _int(j['durationDays']),
        description: j['description']?.toString() ?? '',
      );
}

/// One stored file, as listed in Media and Storage.
class StoredMedia {
  final String id;
  final bool isVideo;
  final String? url;
  final String? thumbnailUrl;
  final int bytes;
  final double? durationSec;
  final String? originalFilename;
  final DateTime? createdAt;
  final String? slot;
  final String? reportId;
  final String? reportTitle;
  final String? staffName;

  const StoredMedia({
    required this.id,
    required this.isVideo,
    this.url,
    this.thumbnailUrl,
    required this.bytes,
    this.durationSec,
    this.originalFilename,
    this.createdAt,
    this.slot,
    this.reportId,
    this.reportTitle,
    this.staffName,
  });

  factory StoredMedia.fromJson(Map<String, dynamic> j) {
    final report = j['report'] is Map ? Map<String, dynamic>.from(j['report'] as Map) : null;
    return StoredMedia(
      id: j['_id']?.toString() ?? '',
      isVideo: j['kind'] == 'video',
      url: j['url']?.toString(),
      thumbnailUrl: j['thumbnailUrl']?.toString(),
      bytes: _int(j['bytes']),
      durationSec: (j['durationSec'] as num?)?.toDouble(),
      originalFilename: j['originalFilename']?.toString(),
      createdAt: parseApiDate(j['createdAt']),
      slot: j['slot']?.toString(),
      reportId: j['reportId']?.toString(),
      reportTitle: report?['jobTitle']?.toString(),
      staffName: report?['staffName']?.toString(),
    );
  }
}

/// "1.2 GB", "340 MB", "86 KB".
String formatBytes(int bytes) {
  const kb = 1024, mb = kb * 1024, gb = mb * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(bytes >= 10 * gb ? 1 : 2)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(bytes >= 100 * mb ? 0 : 1)} MB';
  return '${(bytes / kb).ceil()} KB';
}

/// "0:42", "3:05".
String formatDuration(double? seconds) {
  if (seconds == null || seconds <= 0) return '';
  final s = seconds.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
