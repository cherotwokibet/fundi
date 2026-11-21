import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/service_provider.dart';
import '../models/trade.dart';
import 'sample_directory.dart';

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

/// Turns what people type (0712 345 678, 712345678, +254712345678) into
/// +2547XXXXXXXX. Returns null if it is not a Kenyan mobile number.
String? normalizeKenyanPhone(String input) {
  var d = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('254')) d = d.substring(3);
  if (d.startsWith('0')) d = d.substring(1);
  if (d.length != 9 || !(d.startsWith('7') || d.startsWith('1'))) return null;
  return '+254$d';
}

/// Sign-in and listing management for mechanics, garages and parts shops.
/// Nobody joins here: an admin adds every business and its people first
/// (see AdminRepository). Signing in links a person to what they were added to.
abstract class AccountRepository {
  bool get isSignedIn;
  Future<void> sendCode(String phone);
  Future<void> verifyCode(String phone, String code);
  Future<void> signOut();
  Future<MyListing?> myListing();

  /// Links the signed-in person to the businesses an admin added their
  /// number to, and returns what they belong to. Safe to call every time.
  Future<TradeAccess> access();

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
  Future<TradeAccess> access() async {
    final rows = await _client.rpc('claim_my_access') as List;
    return TradeAccess(
      memberships: [
        for (final r in rows) Membership.fromRow(r as Map<String, dynamic>),
      ],
      isAdmin: await isAdmin(),
    );
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

/// In-memory stand-in used until Supabase keys are supplied. It shares a
/// [SampleDirectory] with the sample admin and parts repositories, so an
/// admin can add a mechanic in sample mode and then sign in as them.
/// Any phone works; the code is always 123456. Sign in as [adminPhone] for
/// the admin console, [sampleMechanicPhone] for a live sample mechanic, or
/// [sampleShopPhone] for a sample parts shop.
class SampleAccountRepository implements AccountRepository {
  SampleAccountRepository([SampleDirectory? directory])
    : directory = directory ?? SampleDirectory.seeded();

  static const sampleCode = '123456';
  static const adminPhone = '+254700000000';
  static const sampleMechanicPhone = SampleDirectory.mechanicPhone;
  static const sampleShopPhone = SampleDirectory.shopPhone;

  final SampleDirectory directory;
  String? _phone;

  /// The signed-in number, or null.
  String? get phone => _phone;

  @override
  bool get isSignedIn => _phone != null;

  @override
  Future<void> sendCode(String phone) async {}

  @override
  Future<void> verifyCode(String phone, String code) async {
    if (code != sampleCode) throw AccountException('That code is not correct.');
    _phone = phone;
    directory.claim(phone);
  }

  @override
  Future<void> signOut() async => _phone = null;

  @override
  Future<TradeAccess> access() async => TradeAccess(
    memberships: _phone == null ? const [] : directory.membershipsFor(_phone!),
    isAdmin: _phone == adminPhone,
  );

  @override
  Future<MyListing?> myListing() async {
    final p = _phone == null ? null : directory.listingOwnedBy(_phone!);
    if (p == null) return null;
    return MyListing(
      id: p.id,
      name: p.name,
      type: p.type,
      status: p.status,
      availability: p.availability,
      availableUntil: p.availableUntil,
    );
  }

  @override
  Future<Set<DocumentKind>> myDocuments() async {
    final p = _phone == null ? null : directory.listingOwnedBy(_phone!);
    return p == null ? {} : {...p.documents.keys};
  }

  @override
  Future<void> uploadDocument(
    DocumentKind kind,
    Uint8List bytes,
    String mime,
  ) async {
    final p = directory.listingOwnedBy(_phone!);
    if (p == null) throw AccountException('Your listing was not found.');
    p.documents[kind] = 'sample/${kind.code}';
  }

  @override
  Future<bool> isAdmin() async => _phone == adminPhone;

  @override
  Future<DateTime> setAvailability(Availability status) async {
    final p = directory.listingOwnedBy(_phone!);
    if (p == null || p.status != ListingStatus.approved) {
      throw AccountException('Only an approved provider can set availability');
    }
    final until = DateTime.now().add(const Duration(hours: 4));
    p.availability = status;
    p.availableUntil = until;
    return until;
  }
}
