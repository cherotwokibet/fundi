import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/service_provider.dart';
import 'account_repository.dart';

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

abstract class AdminRepository {
  Future<List<AdminListing>> listings(ListingStatus status);
  Future<void> setCheck(String providerId, CheckKind kind, bool passed);
  Future<void> setStatus(String providerId, ListingStatus status);

  /// A short-lived link to view a private document.
  Future<String> documentUrl(String storagePath);
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
  Future<void> setCheck(String providerId, CheckKind kind, bool passed) async {
    await _guard(
      () => _client.rpc(
        'admin_set_check',
        params: {
          'p_provider': providerId,
          'p_kind': kind.name,
          'p_passed': passed,
        },
      ),
    );
  }

  @override
  Future<void> setStatus(String providerId, ListingStatus status) async {
    await _guard(
      () => _client.rpc(
        'admin_set_status',
        params: {'p_provider': providerId, 'p_status': status.name},
      ),
    );
  }

  @override
  Future<String> documentUrl(String storagePath) =>
      _client.storage.from('kyc').createSignedUrl(storagePath, 300);

  Future<void> _guard(Future<dynamic> Function() call) async {
    try {
      await call();
    } on PostgrestException catch (e) {
      throw AccountException(e.message);
    }
  }
}

/// Invented applications so the console can be tried without a backend.
class SampleAdminRepository implements AdminRepository {
  final List<AdminListing> _all = [
    const AdminListing(
      id: 'p1',
      name: 'Mwangi Mobile Mechanic',
      type: ProviderType.mobileMechanic,
      phone: '+254700000011',
      area: 'Kasarani – Roysambu',
      status: ListingStatus.pending,
      checksPassed: {},
      documents: {
        DocumentKind.nationalId: 'sample/national_id',
        DocumentKind.selfie: 'sample/selfie',
      },
    ),
    const AdminListing(
      id: 'p2',
      name: 'Eastlands Auto Garage',
      type: ProviderType.garage,
      phone: '+254700000012',
      area: 'Kasarani – Roysambu',
      status: ListingStatus.pending,
      checksPassed: {CheckKind.identity},
      documents: {DocumentKind.nationalId: 'sample/national_id'},
    ),
  ];

  void _replace(String id, AdminListing Function(AdminListing) change) {
    final i = _all.indexWhere((l) => l.id == id);
    _all[i] = change(_all[i]);
  }

  AdminListing _copy(
    AdminListing l, {
    ListingStatus? status,
    Set<CheckKind>? checks,
  }) => AdminListing(
    id: l.id,
    name: l.name,
    type: l.type,
    phone: l.phone,
    area: l.area,
    status: status ?? l.status,
    checksPassed: checks ?? l.checksPassed,
    documents: l.documents,
  );

  @override
  Future<List<AdminListing>> listings(ListingStatus status) async =>
      _all.where((l) => l.status == status).toList();

  @override
  Future<void> setCheck(String providerId, CheckKind kind, bool passed) async {
    _replace(
      providerId,
      (l) => _copy(
        l,
        checks: {...l.checksPassed.where((k) => k != kind), if (passed) kind},
      ),
    );
  }

  @override
  Future<void> setStatus(String providerId, ListingStatus status) async {
    final l = _all.firstWhere((l) => l.id == providerId);
    if (status == ListingStatus.approved && !l.canApprove) {
      throw AccountException('Pass the identity check before approving');
    }
    _replace(providerId, (l) => _copy(l, status: status));
  }

  @override
  Future<String> documentUrl(String storagePath) async => '';
}
