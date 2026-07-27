class CustomerModel {
  final String  id;
  final String  name;
  final String  phone;
  final String? email;
  final String? address;
  final String? city;
  final String? notes;
  final int     totalJobs;

  CustomerModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.address,
    this.city,
    this.notes,
    this.totalJobs = 0,
  });

  factory CustomerModel.fromJson(Map<String, dynamic> json) => CustomerModel(
    id:        json['_id']       ?? '',
    name:      json['name']      ?? '',
    phone:     json['phone']     ?? '',
    email:     json['email'],
    address:   json['address'],
    city:      json['city'],
    notes:     json['notes'],
    totalJobs: json['totalJobs'] ?? 0,
  );

  Map<String, dynamic> toJson() => {
    '_id':      id,
    'name':     name,
    'phone':    phone,
    'email':    email,
    'address':  address,
    'city':     city,
    'notes':    notes,
    'totalJobs':totalJobs,
  };

  String get displayAddress => [address, city].where((s) => s != null && s.isNotEmpty).join(', ');
  String get initials => name.isNotEmpty ? name[0].toUpperCase() : '?';
}