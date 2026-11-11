import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/service_provider.dart';

enum ListingStatus { pending, approved, suspended }

/// The signed-in mechanic's or garage's own listing.
class MyListing {
  const MyListing({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.availability,
    this.availableUntil,
  });
  final String id;
  final String name;
  final ProviderType type;
  final ListingStatus status;
  final Availability availability;
  final DateTime? availableUntil;
}

/// Documents a provider uploads so we can verify them.
enum DocumentKind {
  nationalId('national_id', 'National ID (front)'),
  selfie('selfie', 'A photo of you holding your ID'),
  certificate('certificate', 'Trade certificate or reference letter'),
  businessRegistration('business_registration', 'Business registration'),
  countyPermit('county_permit', 'County business permit');

  const DocumentKind(this.code, this.label);
  final String code;
  final String label;

  /// What we ask each kind of provider for. The first two are required.
  static List<DocumentKind> forType(ProviderType type) => [
    nationalId,
    selfie,
    if (type == ProviderType.garage) ...[
      businessRegistration,
      countyPermit,
    ] else
      certificate,
  ];
}

/// What a mechanic or garage fills in to join.
class ListingApplication {
  const ListingApplication({
    required this.type,
    required this.name,
    required this.businessPhone,
    required this.area,
    required this.lat,
    required this.lng,
    required this.serviceRadiusKm,
    this.calloutFeeKes,
    this.makes = const [],
  });
  final ProviderType type;
  final String name;
  final String businessPhone;
  final String area;
  final double lat;
  final double lng;
  final double serviceRadiusKm;
  final int? calloutFeeKes;
  final List<String> makes;
}

/// Turns what people type (0712 345 678, 712345678, +254712345678) into
/// +2547XXXXXXXX. Returns null if it is not a Kenyan mobile number.
String? normalizeKenyanPhone(String input) {
  var d = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('254')) d = d.substring(3);
  if (d.startsWith('0')) d = d.substring(1);
  if (d.length != 9 || !(d.startsWith('7') || d.startsWith('1'))) return null;
  return '+254$d';
}

/// Sign-in and listing management for mechanics and garages.
abstract class AccountRepository {
  bool get isSignedIn;
  Future<void> sendCode(String phone);
  Future<void> verifyCode(String phone, String code);
  Future<void> signOut();
  Future<MyListing?> myListing();
  Future<void> apply(ListingApplication application);

  /// Returns when this availability expires.
  Future<DateTime> setAvailability(Availability status);

  Future<Set<DocumentKind>> myDocuments();
  Future<void> uploadDocument(DocumentKind kind, Uint8List bytes, String mime);

  /// True if the signed-in user may open the admin console.
  Future<bool> isAdmin();
}

class AccountException implements Exception {
  AccountException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Real backend. Phone sign-in needs an SMS provider configured in Supabase
/// (Authentication → Sign In / Providers → Phone).
class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository(this._client);
  final SupabaseClient _client;

  // An anonymous guest session does not count as a signed-in provider.
  @override
  bool get isSignedIn {
    final u = _client.auth.currentUser;
    return u != null && !u.isAnonymous;
  }

  @override
  Future<void> sendCode(String phone) async {
    try {
      await _client.auth.signInWithOtp(phone: phone);
    } on AuthException catch (e) {
      throw AccountException(e.message);
    }
  }

  @override
  Future<void> verifyCode(String phone, String code) async {
    try {
      await _client.auth.verifyOTP(
        phone: phone,
        token: code,
        type: OtpType.sms,
      );
    } on AuthException catch (e) {
      throw AccountException(e.message);
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<MyListing?> myListing() async {
    final rows = await _client.rpc('my_provider') as List;
    if (rows.isEmpty) return null;
    final r = rows.first as Map<String, dynamic>;
    final until = r['availability_expires_at'] as String?;
    return MyListing(
      id: r['id'] as String,
      name: r['display_name'] as String,
      type: r['type'] == 'garage'
          ? ProviderType.garage
          : ProviderType.mobileMechanic,
      status: ListingStatus.values.firstWhere(
        (s) => s.name == r['status'],
        orElse: () => ListingStatus.pending,
      ),
      availability: Availability.values.firstWhere(
        (a) => a.name == r['availability'],
        orElse: () => Availability.offline,
      ),
      availableUntil: until == null ? null : DateTime.parse(until).toLocal(),
    );
  }

  @override
  Future<void> apply(ListingApplication a) async {
    final uid = _client.auth.currentUser!.id;
    final garage = a.type == ProviderType.garage;
    await _client.from('profiles').upsert({
      'id': uid,
      'phone': _client.auth.currentUser!.phone,
      'full_name': a.name,
      'role': garage ? 'garage_staff' : 'mechanic',
    });
    await _client.from('providers').insert({
      'owner_user_id': uid,
      'type': garage ? 'garage' : 'mobile_mechanic',
      'display_name': a.name,
      'business_phone': a.businessPhone,
      'area': a.area,
      'location': 'SRID=4326;POINT(${a.lng} ${a.lat})',
      'service_radius_km': garage ? 0 : a.serviceRadiusKm,
      'callout_fee_kes': a.calloutFeeKes,
      'makes': a.makes,
    });
  }

  @override
  Future<DateTime> setAvailability(Availability status) async {
    final until = await _client.rpc(
      'set_my_availability',
      params: {'p_status': status.name},
    ) as String;
    return DateTime.parse(until).toLocal();
  }

  @override
  Future<Set<DocumentKind>> myDocuments() async {
    final listing = await myListing();
    if (listing == null) return {};
    final rows = await _client
        .from('provider_documents')
        .select('kind')
        .eq('provider_id', listing.id);
    return {
      for (final r in rows)
        ...DocumentKind.values.where((k) => k.code == r['kind']),
    };
  }

  @override
  Future<void> uploadDocument(
    DocumentKind kind,
    Uint8List bytes,
    String mime,
  ) async {
    final uid = _client.auth.currentUser!.id;
    final listing = await myListing();
    if (listing == null) throw AccountException('Create your listing first.');
    // Private bucket; the path starts with the owner's id, which the
    // storage rules check.
    final path = '$uid/${kind.code}';
    await _client.storage
        .from('kyc')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: true),
        );
    await _client.from('provider_documents').upsert({
      'provider_id': listing.id,
      'kind': kind.code,
      'storage_path': path,
      'uploaded_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'provider_id,kind');
  }

  @override
  Future<bool> isAdmin() async => await _client.rpc('is_admin') as bool;
}

/// In-memory stand-in used until Supabase keys are supplied.
/// Any phone works; the code is always 123456. A new listing starts as
/// pending and is approved once both required documents are uploaded, so the
/// whole journey can be tried. Signing in as [adminPhone] opens the admin console.
class SampleAccountRepository implements AccountRepository {
  static const sampleCode = '123456';
  static const adminPhone = '+254700000000';
  bool _signedIn = false;
  bool _admin = false;
  final Set<DocumentKind> _documents = {};
  MyListing? _listing;
  ListingApplication? lastApplication;

  @override
  bool get isSignedIn => _signedIn;

  @override
  Future<void> sendCode(String phone) async {}

  @override
  Future<void> verifyCode(String phone, String code) async {
    if (code != sampleCode) throw AccountException('That code is not correct.');
    _signedIn = true;
    _admin = phone == adminPhone;
  }

  @override
  Future<void> signOut() async => _signedIn = false;

  @override
  Future<MyListing?> myListing() async => _listing;

  @override
  Future<void> apply(ListingApplication a) async {
    lastApplication = a;
    _listing = MyListing(
      id: 'mine',
      name: a.name,
      type: a.type,
      status: ListingStatus.pending,
      availability: Availability.offline,
    );
  }

  @override
  Future<Set<DocumentKind>> myDocuments() async => {..._documents};

  @override
  Future<void> uploadDocument(
    DocumentKind kind,
    Uint8List bytes,
    String mime,
  ) async {
    _documents.add(kind);
    final l = _listing!;
    if (_documents.containsAll({
      DocumentKind.nationalId,
      DocumentKind.selfie,
    })) {
      _listing = MyListing(
        id: l.id,
        name: l.name,
        type: l.type,
        status: ListingStatus.approved,
        availability: l.availability,
      );
    }
  }

  @override
  Future<bool> isAdmin() async => _admin;

  @override
  Future<DateTime> setAvailability(Availability status) async {
    final l = _listing!;
    final until = DateTime.now().add(const Duration(hours: 4));
    _listing = MyListing(
      id: l.id,
      name: l.name,
      type: l.type,
      status: l.status,
      availability: status,
      availableUntil: until,
    );
    return until;
  }
}
