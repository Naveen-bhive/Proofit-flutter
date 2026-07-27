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
  final String type;
  final String? localPath;
  final DateTime? capturedAt;
  final double? latitude;
  final double? longitude;
  final String? address;

  MediaData({
    this.url,
    this.driveFileId,
    required this.type,
    this.localPath,
    this.capturedAt,
    this.latitude,
    this.longitude,
    this.address,
  });

  factory MediaData.fromJson(Map<String, dynamic> json) => MediaData(
    url:         _nonEmpty(json['url']),
    driveFileId: _nonEmpty(json['driveFileId']),
    type:        json['type']?.toString() ?? 'photo',
    capturedAt:  parseApiDate(json['capturedAt']),
    latitude:    json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
    longitude:   json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
    address:     json['address']?.toString(),
  );

  static String? _nonEmpty(dynamic value) {
    final s = value?.toString().trim();
    if (s == null || s.isEmpty) return null;
    return s;
  }

  bool get hasStoredPhoto => driveFileId != null || url != null;

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

  factory ReportModel.fromJson(Map<String, dynamic> json) {
    final beforeMap = _asStringKeyedMap(json['beforeMedia']);
    final afterMap = _asStringKeyedMap(json['afterMedia']);
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
      beforeMedia: beforeMap != null ? MediaData.fromJson(beforeMap) : null,
      afterMedia:  afterMap != null ? MediaData.fromJson(afterMap) : null,
      submittedAt: parseApiDate(json['submittedAt']),
      createdAt:   parseApiDate(json['createdAt']),
    );
  }
}