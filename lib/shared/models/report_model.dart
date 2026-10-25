import '../../core/utils/date_utils.dart';

class LocationData {
  final double latitude;
  final double longitude;
  final String? address;
  final bool isMocked;
  final bool isVerified;
  final String? flagReason;

  LocationData({
    required this.latitude,
    required this.longitude,
    this.address,
    this.isMocked = false,
    this.isVerified = true,
    this.flagReason,
  });

  factory LocationData.fromJson(Map<String, dynamic> json) => LocationData(
    latitude:   (json['latitude'] ?? 0).toDouble(),
    longitude:  (json['longitude'] ?? 0).toDouble(),
    address:    json['address'],
    isMocked:   json['isMocked'] ?? false,
    isVerified: json['isVerified'] ?? true,
    flagReason: json['flagReason'],
  );

  Map<String, dynamic> toJson() => {
    'latitude': latitude, 'longitude': longitude,
    'address': address, 'isMocked': isMocked, 'isVerified': isVerified,
  };
}

class MediaData {
  final String? url;
  final String? driveFileId;
  final String? publicId;
  /// 'photo' or 'video'.
  final String type;
  final String? localPath;
  final DateTime? capturedAt;
  final double? latitude;
  final double? longitude;
  final String? address;
  /// Server-owned media record — the only reference the API trusts.
  final String? assetId;
  final String? thumbnailUrl;
  final int? bytes;
  final String? mimeType;
  final double? durationSec;
  final String? originalFilename;
  /// Set when the owner deleted the file in Media and Storage.
  final DateTime? deletedAt;

  MediaData({
    this.url,
    this.driveFileId,
    this.publicId,
    required this.type,
    this.localPath,
    this.capturedAt,
    this.latitude,
    this.longitude,
    this.address,
    this.assetId,
    this.thumbnailUrl,
    this.bytes,
    this.mimeType,
    this.durationSec,
    this.originalFilename,
    this.deletedAt,
  });

  bool get isVideo => type == 'video';
  bool get isDeleted => deletedAt != null;

  factory MediaData.fromJson(Map<String, dynamic> json) => MediaData(
    url:         _nonEmpty(json['url']),
    driveFileId: _nonEmpty(json['driveFileId']),
    publicId:    _nonEmpty(json['publicId']),
    type:        json['type']?.toString() ?? 'photo',
    capturedAt:  parseApiDate(json['capturedAt']),
    latitude:    json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
    longitude:   json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
    address:     json['address']?.toString(),
    assetId:     _nonEmpty(json['assetId']),
    thumbnailUrl: _nonEmpty(json['thumbnailUrl']),
    bytes:       (json['bytes'] as num?)?.toInt(),
    mimeType:    _nonEmpty(json['mimeType']),
    durationSec: (json['durationSec'] as num?)?.toDouble(),
    originalFilename: _nonEmpty(json['originalFilename']),
    deletedAt:   parseApiDate(json['deletedAt']),
  );

  static String? _nonEmpty(dynamic value) {
    final s = value?.toString().trim();
    if (s == null || s.isEmpty) return null;
    return s;
  }

  bool get hasStoredPhoto => driveFileId != null || url != null || isDeleted;

  /// What a report save sends back: the asset reference plus capture
  /// metadata. The server rebuilds URL, size and type from its own record.
  Map<String, dynamic> toJson() => {
    if (assetId != null) 'assetId': assetId,
    if (url != null) 'url': url,
    if (driveFileId != null) 'driveFileId': driveFileId,
    if (publicId != null) 'publicId': publicId,
    'type': type,
    if (capturedAt != null) 'capturedAt': capturedAt!.toUtc().toIso8601String(),
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
    if (address != null && address!.isNotEmpty) 'address': address,
  };

  String? get gpsLine {
    if (latitude == null || longitude == null) return null;
    return '${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}';
  }
}

class ReportModel {
  final String? id;
  final String orgId;
  final String staffId;
  final String staffName;
  final String jobTitle;
  final String? notes;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? jobId;
  final String status; // 'draft' | 'submitted'
  final LocationData? location;
  final MediaData? beforeMedia;
  final MediaData? afterMedia;
  /// Every before/after photo; falls back to the single legacy media.
  final List<MediaData> beforePhotos;
  final List<MediaData> afterPhotos;
  final DateTime? submittedAt;
  final DateTime? createdAt;

  ReportModel({
    this.id,
    required this.orgId,
    required this.staffId,
    required this.staffName,
    required this.jobTitle,
    this.notes,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.jobId,
    this.status = 'draft',
    this.location,
    this.beforeMedia,
    this.afterMedia,
    this.beforePhotos = const [],
    this.afterPhotos = const [],
    this.submittedAt,
    this.createdAt,
  });

  bool get isSubmitted => status == 'submitted';
  bool get isFlagged   => location?.isVerified == false;
  String? get beforeDriveFileId => beforeMedia?.driveFileId;
  String? get afterDriveFileId => afterMedia?.driveFileId;
  Map<String, dynamic>? get customer {
    if (customerName == null && customerId == null) return null;
    return {
      '_id': customerId,
      'name': customerName,
      'phone': customerPhone,
    };
  }

  static String _relationId(dynamic value) {
    if (value == null) return '';
    if (value is Map) return value['_id']?.toString() ?? '';
    return value.toString();
  }

  static String? _relationName(dynamic value, {String? fallback}) {
    if (value is Map) return value['name']?.toString();
    return fallback;
  }

  static Map<String, dynamic>? _asStringKeyedMap(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static List<MediaData> _mediaList(dynamic value, MediaData? fallback) {
    final list = <MediaData>[
      if (value is List)
        for (final item in value)
          if (_asStringKeyedMap(item) case final m?) MediaData.fromJson(m),
    ];
    if (list.isEmpty && fallback != null && fallback.hasStoredPhoto) {
      return [fallback];
    }
    return list;
  }

  factory ReportModel.fromJson(Map<String, dynamic> json) {
    final beforeMap = _asStringKeyedMap(json['beforeMedia']);
    final afterMap = _asStringKeyedMap(json['afterMedia']);
    final beforeMedia = beforeMap != null ? MediaData.fromJson(beforeMap) : null;
    final afterMedia = afterMap != null ? MediaData.fromJson(afterMap) : null;
    final locationMap = _asStringKeyedMap(json['location']);
    final jobId = _relationId(json['jobId']);
    return ReportModel(
      id:          json['_id']?.toString() ?? json['id']?.toString(),
      orgId:       _relationId(json['orgId']),
      staffId:     _relationId(json['staffId']),
      staffName:   _relationName(json['staffId'], fallback: json['staffName']?.toString()) ?? '',
      jobTitle:    json['jobTitle']?.toString() ?? '',
      notes:        json['notes']?.toString(),
      customerId:   json['customerId'] == null ? null : _relationId(json['customerId']),
      customerName: _relationName(json['customerId']),
      customerPhone: json['customerId'] is Map ? json['customerId']['phone']?.toString() : null,
      jobId:       jobId.isEmpty ? null : jobId,
      status:      json['status']?.toString() ?? 'draft',
      location:    locationMap != null ? LocationData.fromJson(locationMap) : null,
      beforeMedia: beforeMedia,
      afterMedia:  afterMedia,
      beforePhotos: _mediaList(json['beforePhotos'], beforeMedia),
      afterPhotos:  _mediaList(json['afterPhotos'], afterMedia),
      submittedAt: parseApiDate(json['submittedAt']),
      createdAt:   parseApiDate(json['createdAt']),
    );
  }
}