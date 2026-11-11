import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/service_provider.dart';
import 'account_repository.dart';

enum RequestStatus { requested, accepted, other }

/// A "Find me a mechanic" request as the mechanic sees it.
class IncomingRequest {
  const IncomingRequest({
    required this.id,
    required this.mode,
    required this.createdAt,
    required this.status,
    this.area,
    this.note,
    this.carMake,
    this.contactPhone,
    this.photoPath,
    this.voicePath,
    this.distanceKm,
  });
  final String id;
  final RequestMode mode;
  final DateTime createdAt;
  final RequestStatus status;
  final String? area;
  final String? note;
  final String? carMake;
  final String? contactPhone;
  final String? photoPath;
  final String? voicePath;
  final double? distanceKm;

  bool get waiting => status == RequestStatus.requested;

  factory IncomingRequest.fromRow(Map<String, dynamic> r) => IncomingRequest(
    id: r['id'] as String,
    mode: r['mode'] == 'visit_garage'
        ? RequestMode.visitGarage
        : RequestMode.comeToMe,
    createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
    status: switch (r['status']) {
      'requested' => RequestStatus.requested,
      'accepted' => RequestStatus.accepted,
      _ => RequestStatus.other,
    },
    area: r['area'] as String?,
    note: r['note'] as String?,
    carMake: r['car_make'] as String?,
    contactPhone: r['contact_phone'] as String?,
    photoPath: r['photo_path'] as String?,
    voicePath: r['voice_path'] as String?,
    distanceKm: (r['distance_km'] as num?)?.toDouble(),
  );
}

/// Requests sent to the signed-in mechanic or garage.
abstract class InboxRepository {
  /// Newest first. Cancelled and old requests are left out by the server.
  Future<List<IncomingRequest>> myRequests();

  /// Take the request, or pass on it so it can go to someone else.
  Future<void> respond(String requestId, {required bool accept});

  /// A short-lived link to a request's photo or voice note.
  /// Empty in sample mode, where there is no real file.
  Future<String> fileUrl(String path);
}

class SupabaseInboxRepository implements InboxRepository {
  SupabaseInboxRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<IncomingRequest>> myRequests() async {
    final rows = await _client.rpc('my_requests') as List;
    return [
      for (final r in rows) IncomingRequest.fromRow(r as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> respond(String requestId, {required bool accept}) async {
    try {
      await _client.rpc(
        'respond_to_request',
        params: {'p_request': requestId, 'p_accept': accept},
      );
    } on PostgrestException catch (e) {
      throw AccountException(e.message);
    }
  }

  @override
  Future<String> fileUrl(String path) =>
      _client.storage.from('requests').createSignedUrl(path, 600);
}

/// Invented requests so the inbox can be tried without a backend.
class SampleInboxRepository implements InboxRepository {
  SampleInboxRepository() {
    final now = DateTime.now();
    _requests.addAll([
      IncomingRequest(
        id: 'r1',
        mode: RequestMode.comeToMe,
        createdAt: now.subtract(const Duration(minutes: 6)),
        status: RequestStatus.requested,
        area: 'Kasarani (sample)',
        note: 'Sample request: the car makes a clicking sound and will not start.',
        photoPath: 'sample/photo',
        voicePath: 'sample/voice',
        distanceKm: 1.4,
      ),
      IncomingRequest(
        id: 'r2',
        mode: RequestMode.visitGarage,
        createdAt: now.subtract(const Duration(hours: 2)),
        status: RequestStatus.requested,
        area: 'Roysambu (sample)',
        distanceKm: 3.2,
      ),
    ]);
  }

  final List<IncomingRequest> _requests = [];

  @override
  Future<List<IncomingRequest>> myRequests() async => [..._requests];

  @override
  Future<void> respond(String requestId, {required bool accept}) async {
    final i = _requests.indexWhere((r) => r.id == requestId && r.waiting);
    if (i < 0) {
      throw AccountException('This request is no longer waiting for you.');
    }
    final r = _requests[i];
    if (!accept) {
      _requests.removeAt(i);
      return;
    }
    _requests[i] = IncomingRequest(
      id: r.id,
      mode: r.mode,
      createdAt: r.createdAt,
      status: RequestStatus.accepted,
      area: r.area,
      note: r.note,
      carMake: r.carMake,
      contactPhone: r.contactPhone,
      photoPath: r.photoPath,
      voicePath: r.voicePath,
      distanceKm: r.distanceKm,
    );
  }

  @override
  Future<String> fileUrl(String path) async => '';
}
