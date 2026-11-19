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
    this.availabilitySetAt,
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

  /// When the mechanic last set their availability. Null if never.
  final DateTime? availabilitySetAt;

  bool get isMobile => type == ProviderType.mobileMechanic;

  /// Can this provider come to an owner who is [distanceKm] away?
  bool get canComeToOwner => isMobile && distanceKm <= serviceRadiusKm;

  ServiceProvider copyWith({double? distanceKm, DateTime? availabilitySetAt}) =>
      ServiceProvider(
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
        availabilitySetAt: availabilitySetAt ?? this.availabilitySetAt,
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
      availabilitySetAt: r['availability_set_at'] == null
          ? null
          : DateTime.parse(r['availability_set_at'] as String).toLocal(),
    );
  }
}

enum RequestMode { comeToMe, visitGarage }

enum OwnerRequestStatus { waiting, accepted }

/// Why the current mechanic has the request.
enum Handoff {
  /// The owner picked them.
  first,

  /// The mechanic before them said they can't take it.
  passed,

  /// The mechanic before them did not answer within 5 minutes.
  noAnswer,
}

/// The owner's own open request, for "My repair" and the waiting screen.
class OwnerRequest {
  const OwnerRequest({
    required this.id,
    required this.mode,
    required this.status,
    required this.createdAt,
    this.respondedAt,
    this.hasNote = false,
    this.hasPhoto = false,
    this.hasVoice = false,
    this.providerId,
    this.providerName,
    this.providerPhone,
    this.providerIsMobile = true,
    this.calloutFeeKes,
    this.assignedAt,
    this.rematchCount = 0,
    this.handoff = Handoff.first,
  });
  final String id;
  final RequestMode mode;
  final OwnerRequestStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;
  final bool hasNote;
  final bool hasPhoto;
  final bool hasVoice;

  /// Null when the mechanic passed on the request.
  final String? providerId;
  final String? providerName;
  final String? providerPhone;
  final bool providerIsMobile;
  final int? calloutFeeKes;

  /// When the current mechanic got the request.
  final DateTime? assignedAt;

  /// How many times the request was sent on to another mechanic.
  final int rematchCount;

  final Handoff handoff;

  /// The owner's wait starts again each time the request is sent on.
  DateTime get waitingSince => assignedAt ?? createdAt;

  /// The request was sent on to another mechanic after a pass.
  bool get wasResent => rematchCount > 0;

  bool get accepted => status == OwnerRequestStatus.accepted;

  /// Nobody has the request: the mechanic passed and no other free
  /// mechanic fitted, or it was already sent on three times.
  bool get passed => providerId == null;

  /// Maps one row of the `my_open_request` database function.
  factory OwnerRequest.fromRow(Map<String, dynamic> r) => OwnerRequest(
    id: r['id'] as String,
    mode: r['mode'] == 'visit_garage'
        ? RequestMode.visitGarage
        : RequestMode.comeToMe,
    status: r['status'] == 'accepted'
        ? OwnerRequestStatus.accepted
        : OwnerRequestStatus.waiting,
    createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
    respondedAt: r['responded_at'] == null
        ? null
        : DateTime.parse(r['responded_at'] as String).toLocal(),
    hasNote: r['has_note'] == true,
    hasPhoto: r['has_photo'] == true,
    hasVoice: r['has_voice'] == true,
    providerId: r['provider_id'] as String?,
    providerName: r['provider_name'] as String?,
    providerPhone: r['provider_phone'] as String?,
    providerIsMobile: r['provider_type'] != 'garage',
    calloutFeeKes: (r['callout_fee_kes'] as num?)?.toInt(),
    assignedAt: r['assigned_at'] == null
        ? null
        : DateTime.parse(r['assigned_at'] as String).toLocal(),
    rematchCount: (r['rematch_count'] as num?)?.toInt() ?? 0,
    handoff: switch (r['handoff']) {
      'passed' => Handoff.passed,
      'no_answer' => Handoff.noAnswer,
      _ => Handoff.first,
    },
  );
}

/// Sort order used everywhere: really available first, then nearest.
int compareProviders(ServiceProvider a, ServiceProvider b) {
  final byAvailability = a.availability.index.compareTo(b.availability.index);
  if (byAvailability != 0) return byAvailability;
  return a.distanceKm.compareTo(b.distanceKm);
}
