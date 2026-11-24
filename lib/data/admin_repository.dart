import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_request.dart';
import '../models/complaint.dart';
import '../models/service_provider.dart';
import '../models/trade.dart';
import 'account_repository.dart';
import 'sample_directory.dart';

/// A provider as the admin sees it: details, checks and uploaded documents.
class AdminListing {
  const AdminListing({
    required this.id,
    required this.name,
    required this.type,
    required this.phone,
    required this.area,
    required this.status,
    required this.checksPassed,
    required this.documents,
  });
  final String id;
  final String name;
  final ProviderType type;
  final String phone;
  final String area;
  final ListingStatus status;
  final Set<CheckKind> checksPassed;

  /// Document kind → storage path.
  final Map<DocumentKind, String> documents;

  /// Business checks only apply to garages.
  List<CheckKind> get applicableChecks => [
    CheckKind.identity,
    CheckKind.location,
    CheckKind.experience,
    if (type == ProviderType.garage) CheckKind.business,
  ];

  bool get canApprove => checksPassed.contains(CheckKind.identity);
}

/// What the admin fills in to add a garage or mobile mechanic.
class NewListing {
  const NewListing({
    required this.type,
    required this.name,
    required this.businessPhone,
    required this.ownerPhone,
    required this.area,
    required this.lat,
    required this.lng,
    this.ownerName,
    this.serviceRadiusKm = 5,
    this.calloutFeeKes,
    this.makes = const [],
  });
  final ProviderType type;
  final String name;

  /// The number owners call.
  final String businessPhone;

  /// The number the account holder signs in with. +2547XXXXXXXX.
  final String ownerPhone;
  final String? ownerName;
  final String area;
  final double lat;
  final double lng;
  final double serviceRadiusKm;
  final int? calloutFeeKes;
  final List<String> makes;
}

/// What the admin fills in to add a parts shop.
class NewShop {
  const NewShop({
    required this.name,
    required this.businessPhone,
    required this.ownerPhone,
    required this.area,
    required this.lat,
    required this.lng,
    this.ownerName,
  });
  final String name;
  final String businessPhone;
  final String ownerPhone;
  final String? ownerName;
  final String area;
  final double lat;
  final double lng;
}

/// The admin console. Admins are the only way anyone gets onto the
/// platform's trade side.
abstract class AdminRepository {
  Future<List<AdminListing>> listings(ListingStatus status);
  Future<void> setCheck(String providerId, CheckKind kind, bool passed);
  Future<void> setStatus(String providerId, ListingStatus status);

  /// A short-lived link to view a private document.
  Future<String> documentUrl(String storagePath);

  /// Adds a garage or mechanic. It starts as waiting for checks.
  Future<String> createListing(NewListing listing);

  /// Uploads a document the admin collected in person.
  Future<void> uploadDocument(
    String providerId,
    DocumentKind kind,
    Uint8List bytes,
    String mime,
  );

  Future<List<PartsShop>> shops();
  Future<String> createShop(NewShop shop);
  Future<void> setShopActive(String shopId, bool active);

  /// The people who can sign in for a garage, mechanic listing or shop.
  Future<List<OrgMember>> members(OrgKind kind, String orgId);
  Future<void> addWorker(
    OrgKind kind,
    String orgId,
    String phone,
    String? name,
  );
  Future<void> setMemberActive(String memberId, bool active);

  /// Complaints to decide and refunds to pay first, then recent ones.
  Future<List<Complaint>> complaints();

  /// Upheld or not, with a note the owner reads. A refund needs an upheld
  /// complaint and is capped at what the job cost (checked by the server).
  Future<void> resolveComplaint(
    String complaintId, {
    required bool uphold,
    required String note,
    int refundKes = 0,
  });

  /// The refund reached the owner. [reference] is the M-Pesa code.
  Future<void> markRefundPaid(String complaintId, String reference);

  /// Every open request, plus the ones from the last [days] days.
  Future<List<AdminRequest>> requests({int days = 7});
}

class SupabaseAdminRepository implements AdminRepository {
  SupabaseAdminRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<AdminListing>> listings(ListingStatus status) async {
    final rows = await _client
        .from('providers')
        .select(
          'id, type, display_name, business_phone, area, status, '
          'verification_checks(kind, status), provider_documents(kind, storage_path)',
        )
        .eq('status', status.name)
        .order('created_at');
    return [
      for (final r in rows)
        AdminListing(
          id: r['id'] as String,
          name: r['display_name'] as String,
          type: r['type'] == 'garage'
              ? ProviderType.garage
              : ProviderType.mobileMechanic,
          phone: r['business_phone'] as String,
          area: r['area'] as String,
          status: status,
          checksPassed: {
            for (final c in (r['verification_checks'] as List? ?? const []))
              if (c['status'] == 'passed')
                ...CheckKind.values.where((k) => k.name == c['kind']),
          },
          documents: {
            for (final d in (r['provider_documents'] as List? ?? const []))
              for (final k in DocumentKind.values.where(
                (k) => k.code == d['kind'],
              ))
                k: d['storage_path'] as String,
          },
        ),
    ];
  }

  @override
  Future<void> setCheck(String providerId, CheckKind kind, bool passed) =>
      _guard(
        () => _client.rpc(
          'admin_set_check',
          params: {
            'p_provider': providerId,
            'p_kind': kind.name,
            'p_passed': passed,
          },
        ),
      );

  @override
  Future<void> setStatus(String providerId, ListingStatus status) => _guard(
    () => _client.rpc(
      'admin_set_status',
      params: {'p_provider': providerId, 'p_status': status.name},
    ),
  );

  @override
  Future<String> documentUrl(String storagePath) =>
      _client.storage.from('kyc').createSignedUrl(storagePath, 300);

  @override
  Future<String> createListing(NewListing l) async {
    final id = await _guard(
      () => _client.rpc(
        'admin_create_provider',
        params: {
          'p_type': l.type == ProviderType.garage
              ? 'garage'
              : 'mobile_mechanic',
          'p_name': l.name,
          'p_business_phone': l.businessPhone,
          'p_area': l.area,
          'p_lat': l.lat,
          'p_lng': l.lng,
          'p_owner_phone': l.ownerPhone,
          'p_owner_name': l.ownerName,
          'p_service_radius_km': l.serviceRadiusKm,
          'p_callout_fee_kes': l.calloutFeeKes,
          'p_makes': l.makes,
        },
      ),
    );
    return id as String;
  }

  @override
  Future<void> uploadDocument(
    String providerId,
    DocumentKind kind,
    Uint8List bytes,
    String mime,
  ) async {
    // Admin uploads live under admin/<provider id>/ in the private bucket.
    final path = 'admin/$providerId/${kind.code}';
    await _client.storage
        .from('kyc')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: true),
        );
    await _guard(
      () => _client.from('provider_documents').upsert({
        'provider_id': providerId,
        'kind': kind.code,
        'storage_path': path,
        'uploaded_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'provider_id,kind'),
    );
  }

  @override
  Future<List<PartsShop>> shops() async {
    final rows = await _client
        .from('parts_shops')
        .select('id, name, business_phone, area, status')
        .order('created_at');
    return [
      for (final r in rows)
        PartsShop(
          id: r['id'] as String,
          name: r['name'] as String,
          phone: r['business_phone'] as String,
          area: r['area'] as String,
          active: r['status'] == 'active',
        ),
    ];
  }

  @override
  Future<String> createShop(NewShop s) async {
    final id = await _guard(
      () => _client.rpc(
        'admin_create_shop',
        params: {
          'p_name': s.name,
          'p_business_phone': s.businessPhone,
          'p_area': s.area,
          'p_lat': s.lat,
          'p_lng': s.lng,
          'p_owner_phone': s.ownerPhone,
          'p_owner_name': s.ownerName,
        },
      ),
    );
    return id as String;
  }

  @override
  Future<void> setShopActive(String shopId, bool active) => _guard(
    () => _client.rpc(
      'admin_set_shop_status',
      params: {'p_shop': shopId, 'p_status': active ? 'active' : 'suspended'},
    ),
  );

  @override
  Future<List<OrgMember>> members(OrgKind kind, String orgId) async {
    final rows = await _client
        .from('memberships')
        .select('id, phone, full_name, role, active, user_id')
        .eq(kind == OrgKind.provider ? 'provider_id' : 'shop_id', orgId)
        .order('created_at');
    return [
      for (final r in rows)
        OrgMember(
          id: r['id'] as String,
          phone: '+${r['phone']}',
          name: r['full_name'] as String?,
          role: r['role'] == 'owner' ? MemberRole.owner : MemberRole.worker,
          active: r['active'] as bool,
          signedIn: r['user_id'] != null,
        ),
    ];
  }

  @override
  Future<void> addWorker(
    OrgKind kind,
    String orgId,
    String phone,
    String? name,
  ) => _guard(
    () => _client.rpc(
      'admin_add_member',
      params: {
        'p_provider': kind == OrgKind.provider ? orgId : null,
        'p_shop': kind == OrgKind.shop ? orgId : null,
        'p_phone': phone,
        'p_name': name,
      },
    ),
  );

  @override
  Future<void> setMemberActive(String memberId, bool active) => _guard(
    () => _client.rpc(
      'admin_set_member_active',
      params: {'p_member': memberId, 'p_active': active},
    ),
  );

  @override
  Future<List<Complaint>> complaints() async {
    final rows = await _guard(() => _client.rpc('admin_complaints')) as List;
    return [for (final r in rows) Complaint.fromRow(r as Map<String, dynamic>)];
  }

  @override
  Future<void> resolveComplaint(
    String complaintId, {
    required bool uphold,
    required String note,
    int refundKes = 0,
  }) => _guard(
    () => _client.rpc(
      'admin_resolve_complaint',
      params: {
        'p_complaint': complaintId,
        'p_uphold': uphold,
        'p_note': note,
        'p_refund_kes': refundKes,
      },
    ),
  );

  @override
  Future<void> markRefundPaid(String complaintId, String reference) => _guard(
    () => _client.rpc(
      'admin_mark_refund_paid',
      params: {'p_complaint': complaintId, 'p_reference': reference},
    ),
  );

  @override
  Future<List<AdminRequest>> requests({int days = 7}) async {
    final rows = await _guard(
      () => _client.rpc('admin_requests', params: {'p_days': days}),
    ) as List;
    return [
      for (final r in rows) AdminRequest.fromRow(r as Map<String, dynamic>),
    ];
  }

  Future<dynamic> _guard(Future<dynamic> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (e) {
      throw AccountException(e.message);
    }
  }
}

/// Works on the shared sample data so the console can be tried without a
/// backend. Everything in it is invented.
class SampleAdminRepository implements AdminRepository {
  SampleAdminRepository([SampleDirectory? directory])
    : directory = directory ?? SampleDirectory.seeded();
  final SampleDirectory directory;

  SampleListingRecord _listing(String id) =>
      directory.listings.firstWhere((l) => l.id == id);

  @override
  Future<List<AdminListing>> listings(ListingStatus status) async => [
    for (final l in directory.listings)
      if (l.status == status)
        AdminListing(
          id: l.id,
          name: l.name,
          type: l.type,
          phone: l.phone,
          area: l.area,
          status: l.status,
          checksPassed: {...l.checks},
          documents: {...l.documents},
        ),
  ];

  @override
  Future<void> setCheck(String providerId, CheckKind kind, bool passed) async {
    final l = _listing(providerId);
    passed ? l.checks.add(kind) : l.checks.remove(kind);
  }

  @override
  Future<void> setStatus(String providerId, ListingStatus status) async {
    final l = _listing(providerId);
    if (status == ListingStatus.approved &&
        !l.checks.contains(CheckKind.identity)) {
      throw AccountException('Pass the identity check before approving');
    }
    l.status = status;
  }

  @override
  Future<String> documentUrl(String storagePath) async => '';

  @override
  Future<String> createListing(NewListing n) async => directory.addListing(
    type: n.type,
    name: n.name,
    phone: n.businessPhone,
    area: n.area,
    ownerPhone: n.ownerPhone,
    ownerName: n.ownerName,
  );

  @override
  Future<void> uploadDocument(
    String providerId,
    DocumentKind kind,
    Uint8List bytes,
    String mime,
  ) async {
    _listing(providerId).documents[kind] = 'sample/${kind.code}';
  }

  @override
  Future<List<PartsShop>> shops() async => [
    for (final s in directory.shops)
      PartsShop(
        id: s.id,
        name: s.name,
        phone: s.phone,
        area: s.area,
        active: s.active,
      ),
  ];

  @override
  Future<String> createShop(NewShop s) async => directory.addShop(
    name: s.name,
    phone: s.businessPhone,
    area: s.area,
    ownerPhone: s.ownerPhone,
    ownerName: s.ownerName,
  );

  @override
  Future<void> setShopActive(String shopId, bool active) async {
    directory.shops.firstWhere((s) => s.id == shopId).active = active;
  }

  @override
  Future<List<OrgMember>> members(OrgKind kind, String orgId) async => [
    for (final m in directory.members)
      if (m.kind == kind && m.orgId == orgId)
        OrgMember(
          id: m.id,
          phone: m.phone,
          name: m.name,
          role: m.role,
          active: m.active,
          signedIn: m.signedIn,
        ),
  ];

  @override
  Future<void> addWorker(
    OrgKind kind,
    String orgId,
    String phone,
    String? name,
  ) async => directory.addWorker(kind, orgId, phone, name: name);

  @override
  Future<void> setMemberActive(String memberId, bool active) async {
    directory.members.firstWhere((m) => m.id == memberId).active = active;
  }

  /// One invented complaint, so the tab can be tried without a backend.
  final List<Complaint> sampleComplaints = [
    Complaint(
      id: 'sample-c1',
      requestId: 'sample-job-1',
      message: 'Sample complaint: the brakes still squeal after the repair.',
      wantsRefund: true,
      refundPhone: '254700000000',
      providerReply: 'Sample reply: I can come back and adjust them for free.',
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      providerName: 'Otieno Mobile Mechanic (sample)',
      providerPhone: '+254700000001',
      jobCostKes: 2500,
    ),
  ];

  int _i(String id) {
    final i = sampleComplaints.indexWhere((c) => c.id == id);
    if (i < 0) throw AccountException('Complaint not found');
    return i;
  }

  @override
  Future<List<Complaint>> complaints() async => [
    ...sampleComplaints.where((c) => c.needsAdmin),
    ...sampleComplaints.where((c) => !c.needsAdmin),
  ];

  @override
  Future<void> resolveComplaint(
    String complaintId, {
    required bool uphold,
    required String note,
    int refundKes = 0,
  }) async {
    final i = _i(complaintId);
    final c = sampleComplaints[i];
    if (!c.open) throw AccountException('This complaint was already decided');
    if (note.trim().length < 2) {
      throw AccountException(
        'Write a note for the owner, up to 500 characters',
      );
    }
    if (refundKes > 0 && !uphold) {
      throw AccountException('Only an upheld complaint can have a refund');
    }
    if (refundKes > (c.jobCostKes ?? 0)) {
      throw AccountException(
        'The refund cannot be more than the job cost (${kes(c.jobCostKes ?? 0)})',
      );
    }
    sampleComplaints[i] = c.copyWith(
      status: uphold ? ComplaintStatus.upheld : ComplaintStatus.rejected,
      adminNote: note.trim(),
      refundKes: refundKes,
      refundStatus: refundKes > 0 ? RefundStatus.due : RefundStatus.none,
    );
  }

  @override
  Future<void> markRefundPaid(String complaintId, String reference) async {
    final i = _i(complaintId);
    final c = sampleComplaints[i];
    if (c.refundStatus != RefundStatus.due) {
      throw AccountException('No refund is due on this complaint');
    }
    if (reference.trim().length < 2) {
      throw AccountException('Enter the M-Pesa code of the refund');
    }
    sampleComplaints[i] = c.copyWith(
      refundStatus: RefundStatus.paid,
      refundReference: reference.trim().toUpperCase(),
    );
  }

  /// Invented requests, so Live requests can be tried without a backend.
  /// Every name says "(sample)".
  late final List<AdminRequest> sampleRequests = () {
    final now = DateTime.now();
    AdminRequest r(
      String id,
      RequestStage stage,
      Duration age, {
      String? area,
      String? note,
      String? mechanic,
      String? phone,
      int? quote,
      bool voice = false,
      bool photo = false,
      int rematch = 0,
      String handoff = 'first',
      ComplaintStatus? complaint,
      RefundStatus? refund,
    }) => AdminRequest(
      id: id,
      createdAt: now.subtract(age),
      waitingSince: now.subtract(age),
      stage: stage,
      area: area,
      note: note,
      providerId: mechanic == null ? null : 'sample-$id',
      providerName: mechanic,
      providerPhone: phone,
      quoteTotalKes: quote,
      hasVoice: voice,
      hasPhoto: photo,
      rematchCount: rematch,
      handoff: handoff,
      doneAt: stage == RequestStage.done ? now.subtract(age ~/ 2) : null,
      complaintStatus: complaint,
      refundStatus: refund,
    );
    return [
      r(
        'a1f30000-0000-4000-8000-000000000001',
        RequestStage.unassigned,
        const Duration(minutes: 9),
        area: 'Thika Road',
        note: 'Sample: flat battery, car will not start',
        rematch: 2,
        handoff: 'passed',
      ),
      r(
        'b27c0000-0000-4000-8000-000000000002',
        RequestStage.waiting,
        const Duration(minutes: 2),
        area: 'Kasarani',
        mechanic: 'Peter Mwangi (sample)',
        phone: '+254700000002',
        voice: true,
      ),
      r(
        'c3d40000-0000-4000-8000-000000000003',
        RequestStage.priceSent,
        const Duration(minutes: 24),
        area: 'Westlands',
        note: 'Sample: brakes squeal',
        mechanic: 'Otieno Mobile Mechanic (sample)',
        phone: '+254700000001',
        quote: 2500,
      ),
      r(
        'd4e50000-0000-4000-8000-000000000004',
        RequestStage.working,
        const Duration(minutes: 51),
        area: 'Ngong Road',
        note: 'Sample: overheating in traffic',
        mechanic: 'Kowino Mechs (sample)',
        phone: '+254700000003',
        quote: 4200,
        photo: true,
      ),
      r(
        'e5f60000-0000-4000-8000-000000000005',
        RequestStage.done,
        const Duration(hours: 26),
        area: 'Westlands',
        note: 'Sample: brakes',
        mechanic: 'Otieno Mobile Mechanic (sample)',
        phone: '+254700000001',
        quote: 2500,
        complaint: ComplaintStatus.open,
        refund: RefundStatus.none,
      ),
    ];
  }();

  @override
  Future<List<AdminRequest>> requests({int days = 7}) async => [
    for (final r in sampleRequests)
      if (r.stage.open ||
          DateTime.now().difference(r.createdAt) < Duration(days: days))
        r,
  ];
}
