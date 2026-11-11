import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/service_provider.dart';
import 'zones.dart';

/// A photo or voice note attached to a request.
typedef Attachment = ({Uint8List bytes, String mime});

enum ContactKind { profileView, callTap, callHelped, callNotHelped }

/// Everything the owner app needs from the backend.
abstract class ProviderRepository {
  /// Verified providers near a point, really-available first, then nearest.
  Future<List<ServiceProvider>> nearby({
    required double lat,
    required double lng,
    double radiusKm = 10,
  });

  /// Records a tap in the app. Never the content of a call.
  Future<void> logContact(String providerId, ContactKind kind, {String? area});

  /// Saves a "Find Me a Mechanic" request.
  Future<void> createRequest({
    required RequestMode mode,
    required double lat,
    required double lng,
    String? area,
    String? note,
    String? providerId,
    Attachment? photo,
    Attachment? voice,
  });
}

/// Real backend: Supabase (Postgres + PostGIS).
class SupabaseProviderRepository implements ProviderRepository {
  SupabaseProviderRepository(this._client);
  final SupabaseClient _client;

  static const _kinds = {
    ContactKind.profileView: 'profile_view',
    ContactKind.callTap: 'call_tap',
    ContactKind.callHelped: 'call_helped',
    ContactKind.callNotHelped: 'call_not_helped',
  };

  @override
  Future<List<ServiceProvider>> nearby({
    required double lat,
    required double lng,
    double radiusKm = 10,
  }) async {
    final rows = await _client.rpc(
      'nearby_providers',
      params: {'p_lat': lat, 'p_lng': lng, 'p_radius_km': radiusKm},
    ) as List;
    return [
      for (final r in rows) ServiceProvider.fromRow(r as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> logContact(
    String providerId,
    ContactKind kind, {
    String? area,
  }) async {
    await _client.from('contact_events').insert({
      'provider_id': providerId,
      'kind': _kinds[kind],
      'area': area,
      'user_id': _client.auth.currentUser?.id,
    });
  }

  @override
  Future<void> createRequest({
    required RequestMode mode,
    required double lat,
    required double lng,
    String? area,
    String? note,
    String? providerId,
    Attachment? photo,
    Attachment? voice,
  }) async {
    // A request needs an account row to belong to. Guests get a silent
    // anonymous session; phone OTP replaces this in Phase 2.
    if (_client.auth.currentUser == null) {
      await _client.auth.signInAnonymously();
    }
    final uid = _client.auth.currentUser!.id;
    // Attachments go to the private 'requests' bucket, in the sender's folder.
    final folder = '$uid/${DateTime.now().toUtc().millisecondsSinceEpoch}';
    Future<String?> put(Attachment? a, String name) async {
      if (a == null) return null;
      final path = '$folder/$name';
      await _client.storage
          .from('requests')
          .uploadBinary(
            path,
            a.bytes,
            fileOptions: FileOptions(contentType: a.mime),
          );
      return path;
    }

    final photoPath = await put(photo, 'photo');
    final voicePath = await put(voice, 'voice');
    await _client.from('service_requests').insert({
      'photo_path': photoPath,
      'voice_path': voicePath,
      'user_id': uid,
      'provider_id': providerId,
      'mode': mode == RequestMode.comeToMe ? 'come_to_me' : 'visit_garage',
      'location': 'SRID=4326;POINT($lng $lat)',
      'area': area,
      'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
    });
  }
}

/// Built-in sample data, used until Supabase keys are supplied.
/// Names are marked "Sample" and phone numbers are placeholders.
class SampleProviderRepository implements ProviderRepository {
  final List<({String id, ContactKind kind})> loggedContacts = [];
  final List<RequestMode> requests = [];

  /// What the last request carried, for tests.
  ({bool photo, bool voice})? lastAttachments;

  static const _all = <ServiceProvider>[
    ServiceProvider(
      id: 's1',
      type: ProviderType.mobileMechanic,
      name: 'Otieno Mobile Mechanic',
      phone: '+254700000001',
      area: 'Kasarani',
      lat: -1.2203,
      lng: 36.8981,
      distanceKm: 0,
      availability: Availability.available,
      serviceRadiusKm: 8,
      checksPassed: {
        CheckKind.identity,
        CheckKind.location,
        CheckKind.experience,
      },
      calloutFeeKes: 500,
      makes: ['Toyota', 'Nissan', 'Mazda'],
      ratingAvg: 4.7,
      ratingCount: 38,
    ),
    ServiceProvider(
      id: 's2',
      type: ProviderType.garage,
      name: 'Roysambu Auto Garage',
      phone: '+254700000002',
      area: 'Roysambu',
      lat: -1.2186,
      lng: 36.8866,
      distanceKm: 0,
      availability: Availability.available,
      checksPassed: {
        CheckKind.identity,
        CheckKind.location,
        CheckKind.experience,
        CheckKind.business,
      },
      calloutFeeKes: 300,
      ratingAvg: 4.5,
      ratingCount: 112,
    ),
    ServiceProvider(
      id: 's3',
      type: ProviderType.mobileMechanic,
      name: 'Wanjiru Auto Electrics',
      phone: '+254700000003',
      area: 'Zimmerman',
      lat: -1.2098,
      lng: 36.8930,
      distanceKm: 0,
      availability: Availability.unconfirmed,
      serviceRadiusKm: 10,
      checksPassed: {
        CheckKind.identity,
        CheckKind.location,
        CheckKind.experience,
      },
      calloutFeeKes: 600,
      makes: ['Toyota', 'Subaru', 'Honda'],
      ratingAvg: 4.8,
      ratingCount: 54,
    ),
    ServiceProvider(
      id: 's4',
      type: ProviderType.garage,
      name: 'Thika Road Motor Works',
      phone: '+254700000004',
      area: 'Garden Estate',
      lat: -1.2301,
      lng: 36.8743,
      distanceKm: 0,
      availability: Availability.busy,
      checksPassed: {
        CheckKind.identity,
        CheckKind.location,
        CheckKind.experience,
        CheckKind.business,
      },
      calloutFeeKes: 0,
      ratingAvg: 4.3,
      ratingCount: 76,
    ),
    ServiceProvider(
      id: 's5',
      type: ProviderType.mobileMechanic,
      name: 'Kamau Roadside Rescue',
      phone: '+254700000005',
      area: 'Westlands',
      lat: -1.2676,
      lng: 36.8110,
      distanceKm: 0,
      availability: Availability.available,
      serviceRadiusKm: 12,
      checksPassed: {
        CheckKind.identity,
        CheckKind.location,
        CheckKind.experience,
      },
      calloutFeeKes: 800,
      ratingAvg: 4.6,
      ratingCount: 29,
    ),
    ServiceProvider(
      id: 's6',
      type: ProviderType.garage,
      name: 'Parklands Service Centre',
      phone: '+254700000006',
      area: 'Parklands',
      lat: -1.2606,
      lng: 36.8177,
      distanceKm: 0,
      availability: Availability.available,
      checksPassed: {
        CheckKind.identity,
        CheckKind.location,
        CheckKind.experience,
        CheckKind.business,
      },
      calloutFeeKes: 500,
      makes: ['Toyota', 'Mercedes', 'BMW', 'Volkswagen'],
      ratingAvg: 4.4,
      ratingCount: 91,
    ),
    ServiceProvider(
      id: 's7',
      type: ProviderType.mobileMechanic,
      name: 'Achieng Quick Fix',
      phone: '+254700000007',
      area: 'Kilimani',
      lat: -1.2921,
      lng: 36.7843,
      distanceKm: 0,
      availability: Availability.available,
      serviceRadiusKm: 7,
      checksPassed: {
        CheckKind.identity,
        CheckKind.location,
        CheckKind.experience,
      },
      calloutFeeKes: 500,
      makes: ['Toyota', 'Nissan', 'Mitsubishi'],
      ratingAvg: 4.9,
      ratingCount: 17,
    ),
    ServiceProvider(
      id: 's8',
      type: ProviderType.garage,
      name: 'Ngong Road Garage',
      phone: '+254700000008',
      area: 'Ngong Road',
      lat: -1.3009,
      lng: 36.7750,
      distanceKm: 0,
      availability: Availability.offline,
      checksPassed: {
        CheckKind.identity,
        CheckKind.location,
        CheckKind.experience,
        CheckKind.business,
      },
      calloutFeeKes: 400,
      ratingAvg: 4.2,
      ratingCount: 140,
    ),
  ];

  @override
  Future<List<ServiceProvider>> nearby({
    required double lat,
    required double lng,
    double radiusKm = 10,
  }) async {
    final list = [
      for (final p in _all)
        p.copyWith(
          distanceKm:
              (distanceKm(lat, lng, p.lat, p.lng) * 10).roundToDouble() / 10,
        ),
    ].where((p) => p.distanceKm <= radiusKm).toList()..sort(compareProviders);
    return list;
  }

  @override
  Future<void> logContact(
    String providerId,
    ContactKind kind, {
    String? area,
  }) async {
    loggedContacts.add((id: providerId, kind: kind));
  }

  @override
  Future<void> createRequest({
    required RequestMode mode,
    required double lat,
    required double lng,
    String? area,
    String? note,
    String? providerId,
    Attachment? photo,
    Attachment? voice,
  }) async {
    requests.add(mode);
    lastAttachments = (photo: photo != null, voice: voice != null);
  }
}
