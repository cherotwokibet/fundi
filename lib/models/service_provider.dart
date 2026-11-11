/// A mobile mechanic or a garage, as shown to a car owner.
enum ProviderType { mobileMechanic, garage }

/// What the owner sees. `unconfirmed` means the mechanic said "Available"
/// but has not refreshed it in time, so we do not promise it.
enum Availability { available, unconfirmed, busy, offline }

enum CheckKind { identity, location, experience, business }

class ServiceProvider {
  const ServiceProvider({
    required this.id,
    required this.type,
    required this.name,
    required this.phone,
    required this.area,
    required this.lat,
    required this.lng,
    required this.distanceKm,
    required this.availability,
    required this.checksPassed,
    this.calloutFeeKes,
    this.makes = const [],
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.serviceRadiusKm = 0,
    this.photoUrl,
  });

  final String id;
  final ProviderType type;
  final String name;
  final String phone;
  final String area;
  final double lat;
  final double lng;
  final double distanceKm;
  final Availability availability;
  final Set<CheckKind> checksPassed;
  final int? calloutFeeKes;
  final List<String> makes;
  final double ratingAvg;
  final int ratingCount;
  final double serviceRadiusKm;
  final String? photoUrl;

  bool get isMobile => type == ProviderType.mobileMechanic;

  /// Can this provider come to an owner who is [distanceKm] away?
  bool get canComeToOwner => isMobile && distanceKm <= serviceRadiusKm;

  ServiceProvider copyWith({double? distanceKm}) => ServiceProvider(
    id: id,
    type: type,
    name: name,
    phone: phone,
    area: area,
    lat: lat,
    lng: lng,
    distanceKm: distanceKm ?? this.distanceKm,
    availability: availability,
    checksPassed: checksPassed,
    calloutFeeKes: calloutFeeKes,
    makes: makes,
    ratingAvg: ratingAvg,
    ratingCount: ratingCount,
    serviceRadiusKm: serviceRadiusKm,
    photoUrl: photoUrl,
  );

  /// Maps one row of the `nearby_providers` database function.
  factory ServiceProvider.fromRow(Map<String, dynamic> r) {
    return ServiceProvider(
      id: r['id'] as String,
      type: r['type'] == 'garage'
          ? ProviderType.garage
          : ProviderType.mobileMechanic,
      name: r['display_name'] as String,
      phone: r['business_phone'] as String,
      area: r['area'] as String,
      lat: (r['lat'] as num).toDouble(),
      lng: (r['lng'] as num).toDouble(),
      distanceKm: (r['distance_km'] as num).toDouble(),
      availability: Availability.values.firstWhere(
        (a) => a.name == r['availability'],
        orElse: () => Availability.offline,
      ),
      checksPassed: {
        for (final k in (r['checks_passed'] as List? ?? const []))
          ...CheckKind.values.where((c) => c.name == k),
      },
      calloutFeeKes: (r['callout_fee_kes'] as num?)?.toInt(),
      makes: [for (final m in (r['makes'] as List? ?? const [])) m as String],
      ratingAvg: (r['rating_avg'] as num?)?.toDouble() ?? 0,
      ratingCount: (r['rating_count'] as num?)?.toInt() ?? 0,
      serviceRadiusKm: (r['service_radius_km'] as num?)?.toDouble() ?? 0,
      photoUrl: r['photo_url'] as String?,
    );
  }
}

enum RequestMode { comeToMe, visitGarage }

/// Sort order used everywhere: really available first, then nearest.
int compareProviders(ServiceProvider a, ServiceProvider b) {
  final byAvailability = a.availability.index.compareTo(b.availability.index);
  if (byAvailability != 0) return byAvailability;
  return a.distanceKm.compareTo(b.distanceKm);
}
