class OrgModel {
  final String id;
  final String name;
  final String ownerPhone;
  final String address;
  final double? addressLatitude;
  final double? addressLongitude;
  final String ownerName;
  final String? ownerEmail;
  final String? driveServiceEmail;
  final String plan;
  final DateTime? planExpiresAt;
  final int staffCount;
  /// On/off per [AppFeature] key for the org's current plan.
  final Map<String, bool> features;

  OrgModel({
    required this.id,
    required this.name,
    required this.ownerPhone,
    this.address = '',
    this.addressLatitude,
    this.addressLongitude,
    required this.ownerName,
    this.ownerEmail,
    this.driveServiceEmail,
    required this.plan,
    this.planExpiresAt,
    this.staffCount = 0,
    this.features = const {},
  });

  /// Mobile number and address are both required for an owner profile.
  bool get isProfileComplete => ownerPhone.trim().isNotEmpty && address.trim().isNotEmpty;

  // FIX #24 — Check plan is active AND not expired
  String get activePlan {
    if (plan == 'free') return 'free';
    if (planExpiresAt != null && planExpiresAt!.isBefore(DateTime.now())) return 'free';
    return plan;
  }

  /// Features the server hasn't reported (older backend or cached org) stay on.
  bool isFeatureEnabled(String feature) => features[feature] ?? true;

  factory OrgModel.fromJson(Map<String, dynamic> json) => OrgModel(
    id:           json['_id'] ?? '',
    name:         json['name'] ?? '',
    ownerPhone:   json['ownerPhone'] ?? '',
    address:      json['address'] ?? '',
    addressLatitude:  (json['addressLocation']?['latitude'] as num?)?.toDouble(),
    addressLongitude: (json['addressLocation']?['longitude'] as num?)?.toDouble(),
    ownerName:    json['ownerName'] ?? '',
    ownerEmail:   json['ownerEmail'],
    driveServiceEmail: json['driveServiceEmail'],
    plan:         json['plan'] ?? 'free',
    staffCount:   json['staffCount'] ?? 0,
    features:     parseFeatures(json['features']),
    planExpiresAt: json['planExpiresAt'] != null
        ? DateTime.tryParse(json['planExpiresAt'])
        : null,
  );

  Map<String, dynamic> toJson() => {
    '_id':         id,
    'name':        name,
    'ownerPhone':  ownerPhone,
    'address':     address,
    'addressLocation': {'latitude': addressLatitude, 'longitude': addressLongitude},
    'ownerName':   ownerName,
    'ownerEmail':  ownerEmail,
    'driveServiceEmail': driveServiceEmail,
    'plan':        plan,
    'staffCount':  staffCount,
    'features':    features,
    'planExpiresAt': planExpiresAt?.toIso8601String(),
  };

  OrgModel copyWith({
    String? id,
    String? name,
    String? ownerPhone,
    String? address,
    double? addressLatitude,
    double? addressLongitude,
    String? ownerName,
    String? ownerEmail,
    String? driveServiceEmail,
    String? plan,
    DateTime? planExpiresAt,
    int? staffCount,
    Map<String, bool>? features,
  }) => OrgModel(
    id: id ?? this.id,
    name: name ?? this.name,
    ownerPhone: ownerPhone ?? this.ownerPhone,
    address: address ?? this.address,
    addressLatitude: addressLatitude ?? this.addressLatitude,
    addressLongitude: addressLongitude ?? this.addressLongitude,
    ownerName: ownerName ?? this.ownerName,
    ownerEmail: ownerEmail ?? this.ownerEmail,
    driveServiceEmail: driveServiceEmail ?? this.driveServiceEmail,
    plan: plan ?? this.plan,
    planExpiresAt: planExpiresAt ?? this.planExpiresAt,
    staffCount: staffCount ?? this.staffCount,
    features: features ?? this.features,
  );

  static Map<String, bool> parseFeatures(dynamic raw) {
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.value is bool) e.key.toString(): e.value as bool,
    };
  }
}