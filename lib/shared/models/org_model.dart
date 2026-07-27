class OrgModel {
  final String id;
  final String name;
  final String ownerPhone;
  final String ownerName;
  final String? ownerEmail;
  final String? driveServiceEmail;
  final String plan;
  final DateTime? planExpiresAt;
  final int staffCount;

  OrgModel({
    required this.id,
    required this.name,
    required this.ownerPhone,
    required this.ownerName,
    this.ownerEmail,
    this.driveServiceEmail,
    required this.plan,
    this.planExpiresAt,
    this.staffCount = 0,
  });

  // FIX #24 — Check plan is active AND not expired
  String get activePlan {
    if (plan == 'free') return 'free';
    if (planExpiresAt != null && planExpiresAt!.isBefore(DateTime.now())) return 'free';
    return plan;
  }

  bool hasFeature(String feature) {
    const features = {
      'free':     {'video': false, 'export': false, 'liveMap': false},
      'starter':  {'video': false, 'export': true,  'liveMap': false},
      'pro':      {'video': true,  'export': true,  'liveMap': true},
      'business': {'video': true,  'export': true,  'liveMap': true},
    };
    return (features[activePlan] ?? features['free']!)[feature] ?? false;
  }

  factory OrgModel.fromJson(Map<String, dynamic> json) => OrgModel(
    id:           json['_id'] ?? '',
    name:         json['name'] ?? '',
    ownerPhone:   json['ownerPhone'] ?? '',
    ownerName:    json['ownerName'] ?? '',
    ownerEmail:   json['ownerEmail'],
    driveServiceEmail: json['driveServiceEmail'],
    plan:         json['plan'] ?? 'free',
    staffCount:   json['staffCount'] ?? 0,
    planExpiresAt: json['planExpiresAt'] != null
        ? DateTime.tryParse(json['planExpiresAt'])
        : null,
  );

  Map<String, dynamic> toJson() => {
    '_id':         id,
    'name':        name,
    'ownerPhone':  ownerPhone,
    'ownerName':   ownerName,
    'ownerEmail':  ownerEmail,
    'driveServiceEmail': driveServiceEmail,
    'plan':        plan,
    'staffCount':  staffCount,
    'planExpiresAt': planExpiresAt?.toIso8601String(),
  };

  OrgModel copyWith({
    String? id,
    String? name,
    String? ownerPhone,
    String? ownerName,
    String? ownerEmail,
    String? driveServiceEmail,
    String? plan,
    DateTime? planExpiresAt,
    int? staffCount,
  }) => OrgModel(
    id: id ?? this.id,
    name: name ?? this.name,
    ownerPhone: ownerPhone ?? this.ownerPhone,
    ownerName: ownerName ?? this.ownerName,
    ownerEmail: ownerEmail ?? this.ownerEmail,
    driveServiceEmail: driveServiceEmail ?? this.driveServiceEmail,
    plan: plan ?? this.plan,
    planExpiresAt: planExpiresAt ?? this.planExpiresAt,
    staffCount: staffCount ?? this.staffCount,
  );
}