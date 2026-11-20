import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/complaint.dart';
import '../models/quote.dart';
import '../models/service_provider.dart';
import 'account_repository.dart';
import 'zones.dart';

/// A photo or voice note attached to a request.
typedef Attachment = ({Uint8List bytes, String mime});

enum ContactKind { profileView, callTap, callHelped, callNotHelped }

/// A finished job the owner can still rate.
typedef ReviewDue = ({String requestId, String providerName});

/// The request was refused by a limit (too many open, too many today, or the
/// mechanic has too many waiting). [message] says what the owner can do.
class RequestLimitException implements Exception {
  RequestLimitException(this.message);
  final String message;
  @override
  String toString() => message;
}

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

  /// The owner's latest open request, or null. For "My repair".
  Future<OwnerRequest?> myOpenRequest();

  /// After 5 minutes with no answer, asks for the request to go to the next
  /// free mechanic. True when it moved. The server checks the 5 minutes.
  Future<bool> nudgeRequest(String requestId);

  /// The mechanic's latest quote on this request, or null.
  Future<Quote?> latestQuote(String requestId);

  /// The owner approves or declines the quote waiting for them.
  Future<void> respondToQuote(String quoteId, {required bool approve});

  /// The owner says the work on their accepted request is done.
  Future<void> markJobDone(String requestId);

  /// The owner's latest finished job not yet rated, or null.
  Future<ReviewDue?> reviewDue();

  /// The owner rates a finished job, 1 to 5 stars, once.
  Future<void> leaveReview(String requestId, int stars, {String? comment});

  /// The owner cancels their own request.
  Future<void> cancelRequest(String requestId);

  /// The owner's latest finished job in the last 30 days, or null.
  Future<LastJob?> lastJob();

  /// The owner's complaint about this job, or null.
  Future<Complaint?> complaintFor(String requestId);

  /// The owner says something went wrong, in their own words. Once per job.
  /// Asking for money back needs the M-Pesa number to send it to.
  Future<void> raiseComplaint(
    String requestId,
    String message, {
    bool wantsRefund = false,
    String? refundPhone,
  });
}

/// The server refused a complaint or reply; [message] says why, for the user.
class ComplaintException implements Exception {
  ComplaintException(this.message);
  final String message;
  @override
  String toString() => message;
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
    try {
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
    } on PostgrestException catch (e) {
      if (e.message.startsWith('LIMIT: ')) {
        throw RequestLimitException(e.message.substring(7));
      }
      rethrow;
    }
  }

  @override
  Future<OwnerRequest?> myOpenRequest() async {
    // No session means this device never sent a request.
    if (_client.auth.currentUser == null) return null;
    final rows = await _client.rpc('my_open_request') as List;
    if (rows.isEmpty) return null;
    return OwnerRequest.fromRow(rows.first as Map<String, dynamic>);
  }

  @override
  Future<void> cancelRequest(String requestId) async {
    await _client.rpc('cancel_my_request', params: {'p_request': requestId});
  }

  @override
  Future<bool> nudgeRequest(String requestId) async =>
      await _client.rpc('nudge_my_request', params: {'p_request': requestId})
          as bool;

  @override
  Future<Quote?> latestQuote(String requestId) async {
    final row = await _client
        .from('quotes')
        .select(Quote.columns)
        .eq('request_id', requestId)
        .neq('status', 'withdrawn')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : Quote.fromRow(row);
  }

  @override
  Future<void> respondToQuote(String quoteId, {required bool approve}) =>
      _client.rpc(
        'respond_to_quote',
        params: {'p_quote': quoteId, 'p_approve': approve},
      );

  @override
  Future<void> markJobDone(String requestId) =>
      _client.rpc('mark_job_done', params: {'p_request': requestId});

  @override
  Future<ReviewDue?> reviewDue() async {
    final rows = await _client.rpc('my_review_due') as List;
    if (rows.isEmpty) return null;
    final r = rows.first as Map<String, dynamic>;
    return (
      requestId: r['request_id'] as String,
      providerName: r['provider_name'] as String,
    );
  }

  @override
  Future<void> leaveReview(String requestId, int stars, {String? comment}) =>
      _client.rpc(
        'leave_review',
        params: {
          'p_request': requestId,
          'p_stars': stars,
          'p_comment': comment,
        },
      );

  @override
  Future<LastJob?> lastJob() async {
    if (_client.auth.currentUser == null) return null;
    final rows = await _client.rpc('my_last_job') as List;
    if (rows.isEmpty) return null;
    final r = rows.first as Map<String, dynamic>;
    return (
      requestId: r['request_id'] as String,
      providerName: r['provider_name'] as String,
      doneAt: DateTime.parse(r['done_at'] as String).toLocal(),
    );
  }

  @override
  Future<Complaint?> complaintFor(String requestId) async {
    if (_client.auth.currentUser == null) return null;
    final row = await _client
        .from('complaints')
        .select(Complaint.columns)
        .eq('request_id', requestId)
        .maybeSingle();
    return row == null ? null : Complaint.fromRow(row);
  }

  @override
  Future<void> raiseComplaint(
    String requestId,
    String message, {
    bool wantsRefund = false,
    String? refundPhone,
  }) async {
    try {
      await _client.rpc(
        'raise_complaint',
        params: {
          'p_request': requestId,
          'p_message': message,
          'p_wants_refund': wantsRefund,
          'p_refund_phone': wantsRefund ? refundPhone : null,
        },
      );
    } on PostgrestException catch (e) {
      throw ComplaintException(e.message);
    }
  }
}

/// Built-in sample data, used until Supabase keys are supplied.
/// Names are marked "Sample" and phone numbers are placeholders.
class SampleProviderRepository implements ProviderRepository {
  /// [acceptAfter]: how long until the sample mechanic "accepts" a request,
  /// so the waiting screen can be tried without a backend. Null = never.
  SampleProviderRepository({this.acceptAfter = const Duration(seconds: 15)});
  final Duration? acceptAfter;

  final List<({String id, ContactKind kind})> loggedContacts = [];
  OwnerRequest? _open;

  /// Test hooks: what the sample mechanic does with the open request.
  void mechanicAccepts() => _open = _with(
    _open!,
    status: OwnerRequestStatus.accepted,
    respondedAt: DateTime.now(),
  );

  /// The mechanic passes. Like the database, the request goes on to the
  /// next best free mechanic who has not passed, at most three times.
  void mechanicPasses() {
    final r = _open!;
    if (r.providerId != null) _declined.add(r.providerId!);
    final next = _next(r);
    _open = next == null
        ? _with(r, provider: null, respondedAt: DateTime.now())
        : _with(
            r,
            provider: next,
            assignedAt: DateTime.now(),
            rematchCount: r.rematchCount + 1,
            handoff: Handoff.passed,
          );
  }

  /// The next best free mechanic who has not had this request.
  ServiceProvider? _next(OwnerRequest r) => r.rematchCount >= 3
      ? null
      : _ranked(_lat, _lng).where((p) {
          if (_declined.contains(p.id) || p.id == r.providerId) return false;
          if (p.availability == Availability.busy ||
              p.availability == Availability.offline) {
            return false;
          }
          return r.mode == RequestMode.comeToMe
              ? p.canComeToOwner
              : !p.isMobile;
        }).firstOrNull;

  /// Test hook: pretend the current mechanic got the request [by] ago.
  void ageRequest(Duration by) {
    final r = _open!;
    _open = _with(r, assignedAt: r.waitingSince.subtract(by));
  }

  Quote? _quote;
  int _quoteSeq = 0;

  /// Test hook: the mechanic sends a quote on the accepted request.
  void mechanicSendsQuote(List<QuoteLine> lines, {String? note}) {
    _quote = Quote.draft(
      id: 'q${++_quoteSeq}',
      requestId: _open!.id,
      lines: lines,
      note: note,
    );
  }

  @override
  Future<Quote?> latestQuote(String requestId) async =>
      _quote?.requestId == requestId ? _quote : null;

  @override
  Future<void> respondToQuote(String quoteId, {required bool approve}) async {
    final q = _quote;
    if (q == null || q.id != quoteId || !q.waiting) {
      throw StateError('This quote was already answered or replaced');
    }
    _quote = q.withStatus(
      approve ? QuoteStatus.approved : QuoteStatus.declined,
    );
  }

  /// The last finished job, and the stars given to it (null until rated).
  ({String requestId, String providerName, int? stars, String? comment})?
  finished;

  @override
  Future<void> markJobDone(String requestId) async {
    final r = _open;
    if (r == null || r.id != requestId || !r.accepted) {
      throw StateError('Only an accepted job can be marked done');
    }
    finished = (
      requestId: r.id,
      providerName: r.providerName ?? 'The mechanic',
      stars: null,
      comment: null,
    );
    finishedAt = DateTime.now();
    _open = null;
  }

  /// When the last job was marked done. Tests can move it back in time.
  DateTime? finishedAt;

  /// Complaints by request id.
  final Map<String, Complaint> complaints = {};

  @override
  Future<LastJob?> lastJob() async {
    final f = finished;
    final at = finishedAt;
    if (f == null || at == null) return null;
    if (DateTime.now().difference(at) > const Duration(days: 30)) return null;
    return (requestId: f.requestId, providerName: f.providerName, doneAt: at);
  }

  @override
  Future<Complaint?> complaintFor(String requestId) async =>
      complaints[requestId];

  @override
  Future<void> raiseComplaint(
    String requestId,
    String message, {
    bool wantsRefund = false,
    String? refundPhone,
  }) async {
    // Same rules as the database.
    final underWay = _open?.id == requestId && _open!.accepted;
    final done =
        finished?.requestId == requestId &&
        DateTime.now().difference(finishedAt!) <= const Duration(days: 14);
    if (!underWay && !done) {
      throw ComplaintException(
        'You can report a problem while a job is under way or up to 14 days after.',
      );
    }
    if (complaints.containsKey(requestId)) {
      throw ComplaintException('You already reported a problem with this job');
    }
    final text = message.trim();
    if (text.length < 10) {
      throw ComplaintException('Say in a few words what went wrong');
    }
    if (wantsRefund && normalizeKenyanPhone(refundPhone ?? '') == null) {
      throw ComplaintException(
        'Enter a Kenyan mobile number, for example 0712 345 678',
      );
    }
    complaints[requestId] = Complaint(
      id: 'c${complaints.length + 1}',
      requestId: requestId,
      message: text,
      wantsRefund: wantsRefund,
      createdAt: DateTime.now(),
    );
  }

  /// Test hook: the mechanic marks the accepted job done.
  void mechanicMarksDone() => markJobDone(_open!.id);

  @override
  Future<ReviewDue?> reviewDue() async {
    final f = finished;
    if (f == null || f.stars != null) return null;
    return (requestId: f.requestId, providerName: f.providerName);
  }

  @override
  Future<void> leaveReview(
    String requestId,
    int stars, {
    String? comment,
  }) async {
    final f = finished;
    if (f == null || f.requestId != requestId || f.stars != null) {
      throw StateError('Nothing to rate');
    }
    if (stars < 1 || stars > 5) throw StateError('Pick from 1 to 5 stars');
    finished = (
      requestId: f.requestId,
      providerName: f.providerName,
      stars: stars,
      comment: comment,
    );
  }

  /// Requests sent in sample mode, for the daily limit.
  final List<DateTime> _sent = [];

  @override
  Future<bool> nudgeRequest(String requestId) async {
    final r = _open;
    if (r == null ||
        r.id != requestId ||
        r.accepted ||
        r.providerId == null ||
        DateTime.now().difference(r.waitingSince) <
            const Duration(minutes: 5)) {
      return false;
    }
    final next = _next(r);
    if (next == null) return false;
    _declined.add(r.providerId!);
    _open = _with(
      r,
      provider: next,
      assignedAt: DateTime.now(),
      rematchCount: r.rematchCount + 1,
      handoff: Handoff.noAnswer,
    );
    return true;
  }

  final Set<String> _declined = {};
  double _lat = 0;
  double _lng = 0;

  static const _keep = Object();

  OwnerRequest _with(
    OwnerRequest r, {
    OwnerRequestStatus? status,
    Object? provider = _keep,
    DateTime? respondedAt,
    DateTime? assignedAt,
    int? rematchCount,
    Handoff? handoff,
  }) {
    final p = provider == _keep ? null : provider as ServiceProvider?;
    final keep = provider == _keep;
    return OwnerRequest(
      id: r.id,
      mode: r.mode,
      status: status ?? r.status,
      createdAt: r.createdAt,
      respondedAt: respondedAt ?? (assignedAt != null ? null : r.respondedAt),
      hasNote: r.hasNote,
      hasPhoto: r.hasPhoto,
      hasVoice: r.hasVoice,
      providerId: keep ? r.providerId : p?.id,
      providerName: keep ? r.providerName : p?.name,
      providerPhone: keep ? r.providerPhone : p?.phone,
      providerIsMobile: keep
          ? r.providerIsMobile
          : (p?.isMobile ?? r.providerIsMobile),
      calloutFeeKes: keep ? r.calloutFeeKes : p?.calloutFeeKes,
      assignedAt: assignedAt ?? r.assignedAt,
      rematchCount: rematchCount ?? r.rematchCount,
      handoff: handoff ?? r.handoff,
    );
  }

  // Minutes since each sample mechanic "set" their availability.
  static const _setMinutesAgo = {
    's1': 4, 's2': 12, 's3': 300, 's4': 25, 's5': 9, 's6': 31, 's7': 2, //
  };

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
  }) async => _ranked(lat, lng, radiusKm: radiusKm);

  List<ServiceProvider> _ranked(
    double lat,
    double lng, {
    double radiusKm = 10,
  }) {
    final list = [
      for (final p in _all)
        p.copyWith(
          distanceKm:
              (distanceKm(lat, lng, p.lat, p.lng) * 10).roundToDouble() / 10,
          availabilitySetAt: _setMinutesAgo[p.id] == null
              ? null
              : DateTime.now().subtract(
                  Duration(minutes: _setMinutesAgo[p.id]!),
                ),
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
    final dayAgo = DateTime.now().subtract(const Duration(days: 1));
    _sent.removeWhere((t) => t.isBefore(dayAgo));
    if (_sent.length >= 6) {
      throw RequestLimitException(
        'You have sent many requests today. You can still call a mechanic from Browse and call.',
      );
    }
    _sent.add(DateTime.now());
    requests.add(mode);
    lastAttachments = (photo: photo != null, voice: voice != null);
    _declined.clear();
    _lat = lat;
    _lng = lng;
    final p = _all.where((x) => x.id == providerId).firstOrNull;
    _open = OwnerRequest(
      id: 'sample-${requests.length}',
      mode: mode,
      status: OwnerRequestStatus.waiting,
      createdAt: DateTime.now(),
      hasNote: note != null && note.trim().isNotEmpty,
      hasPhoto: photo != null,
      hasVoice: voice != null,
      providerId: p?.id,
      providerName: p?.name,
      providerPhone: p?.phone,
      providerIsMobile: p?.isMobile ?? true,
      calloutFeeKes: p?.calloutFeeKes,
      assignedAt: DateTime.now(),
    );
  }

  @override
  Future<OwnerRequest?> myOpenRequest() async {
    final r = _open;
    if (r != null &&
        !r.accepted &&
        !r.passed &&
        acceptAfter != null &&
        DateTime.now().difference(r.waitingSince) >= acceptAfter!) {
      mechanicAccepts();
    }
    return _open;
  }

  @override
  Future<void> cancelRequest(String requestId) async {
    if (_open?.id == requestId) _open = null;
  }
}
