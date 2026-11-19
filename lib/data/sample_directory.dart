import '../models/service_provider.dart';
import '../models/trade.dart';
import 'account_repository.dart';

/// A garage or mechanic listing in sample mode.
class SampleListingRecord {
  SampleListingRecord({
    required this.id,
    required this.type,
    required this.name,
    required this.phone,
    required this.area,
    this.status = ListingStatus.pending,
  });
  final String id;
  final ProviderType type;
  final String name;
  final String phone;
  final String area;
  ListingStatus status;
  final Set<CheckKind> checks = {};
  final Map<DocumentKind, String> documents = {};
  Availability availability = Availability.offline;
  DateTime? availableUntil;
}

class SampleShopRecord {
  SampleShopRecord(this.id, this.name, this.phone, this.area);
  final String id;
  final String name;
  final String phone;
  final String area;
  bool active = true;
}

class SampleMemberRecord {
  SampleMemberRecord({
    required this.id,
    required this.kind,
    required this.orgId,
    required this.phone,
    required this.role,
    this.name,
  });
  final String id;
  final OrgKind kind;
  final String orgId;
  final String phone;
  final String? name;
  final MemberRole role;
  bool active = true;
  bool signedIn = false;
}

class SampleOrderRecord {
  SampleOrderRecord(this.order, this.buyerId, this.listingId, this.qty);
  PartsOrder order;
  final String buyerId;
  final String listingId;
  final int qty;
}

/// In-memory stand-in for the database, shared by the sample account,
/// admin and parts repositories. Everything in it is invented example data.
class SampleDirectory {
  SampleDirectory();

  static const mechanicPhone = '+254711000001';
  static const shopPhone = '+254711000002';

  final listings = <SampleListingRecord>[];
  final shops = <SampleShopRecord>[];
  final members = <SampleMemberRecord>[];
  final parts = <PartListing>[];
  final orders = <SampleOrderRecord>[];
  int _seq = 0;

  String _id(String prefix) => '$prefix${++_seq}';

  /// The example data sample mode starts with. All of it is marked as a sample.
  factory SampleDirectory.seeded() {
    final d = SampleDirectory();
    d.listings.addAll([
      SampleListingRecord(
          id: 'p1',
          type: ProviderType.mobileMechanic,
          name: 'Mwangi Mobile Mechanic',
          phone: '+254700000011',
          area: 'Kasarani – Roysambu',
        )
        ..documents.addAll({
          DocumentKind.nationalId: 'sample/national_id',
          DocumentKind.selfie: 'sample/selfie',
        }),
      SampleListingRecord(
          id: 'p2',
          type: ProviderType.garage,
          name: 'Eastlands Auto Garage',
          phone: '+254700000012',
          area: 'Kasarani – Roysambu',
        )
        ..checks.add(CheckKind.identity)
        ..documents[DocumentKind.nationalId] = 'sample/national_id',
    ]);
    d._member(OrgKind.provider, 'p1', '+254700000011', MemberRole.owner);
    d._member(OrgKind.provider, 'p2', '+254700000012', MemberRole.owner);

    final live = d.addListing(
      type: ProviderType.mobileMechanic,
      name: 'Sample: Baraka Mobile Mechanic',
      phone: mechanicPhone,
      area: 'Kasarani – Roysambu',
      ownerPhone: mechanicPhone,
      status: ListingStatus.approved,
    );
    d.listings.firstWhere((l) => l.id == live).checks.add(CheckKind.identity);

    final shop = d.addShop(
      name: 'Sample: Kirinyaga Road Spares',
      phone: shopPhone,
      area: 'Kirinyaga Road, CBD',
      ownerPhone: shopPhone,
    );
    d.parts.addAll([
      PartListing(
        id: 'part1',
        shopId: shop,
        title: 'Front brake pads',
        partNumber: '04465-52180',
        makes: const ['Toyota'],
        models: 'Probox, Succeed',
        yearFrom: 2014,
        yearTo: 2022,
        priceKes: 3400,
        stockQty: 6,
      ),
      PartListing(
        id: 'part2',
        shopId: shop,
        title: 'Alternator',
        makes: const ['Toyota'],
        models: 'Fielder, Axio',
        yearFrom: 2012,
        yearTo: 2018,
        condition: PartCondition.used,
        priceKes: 9500,
        stockQty: 2,
      ),
      PartListing(
        id: 'part3',
        shopId: shop,
        title: 'Engine oil 5W-30, 4 litres',
        priceKes: 4200,
        stockQty: 20,
      ),
    ]);
    return d;
  }

  SampleMemberRecord _member(
    OrgKind kind,
    String orgId,
    String phone,
    MemberRole role, {
    String? name,
  }) {
    final m = SampleMemberRecord(
      id: _id('m'),
      kind: kind,
      orgId: orgId,
      phone: phone,
      role: role,
      name: name,
    );
    members.add(m);
    return m;
  }

  /// Admin: adds a garage or mechanic listing with its account holder.
  String addListing({
    required ProviderType type,
    required String name,
    required String phone,
    required String area,
    required String ownerPhone,
    String? ownerName,
    ListingStatus status = ListingStatus.pending,
  }) {
    if (members.any(
      (m) =>
          m.kind == OrgKind.provider &&
          m.role == MemberRole.owner &&
          m.active &&
          m.phone == ownerPhone,
    )) {
      throw AccountException('This number already runs a listing');
    }
    final id = _id('p');
    listings.add(
      SampleListingRecord(
        id: id,
        type: type,
        name: name,
        phone: phone,
        area: area,
        status: status,
      ),
    );
    _member(
      OrgKind.provider,
      id,
      ownerPhone,
      MemberRole.owner,
      name: ownerName,
    );
    return id;
  }

  /// Admin: adds a parts shop with its owner.
  String addShop({
    required String name,
    required String phone,
    required String area,
    required String ownerPhone,
    String? ownerName,
  }) {
    final id = _id('s');
    shops.add(SampleShopRecord(id, name, phone, area));
    _member(OrgKind.shop, id, ownerPhone, MemberRole.owner, name: ownerName);
    return id;
  }

  /// Admin: adds a worker, or switches them back on if already listed.
  void addWorker(OrgKind kind, String orgId, String phone, {String? name}) {
    for (final m in members) {
      if (m.kind == kind && m.orgId == orgId && m.phone == phone) {
        m.active = true;
        return;
      }
    }
    _member(kind, orgId, phone, MemberRole.worker, name: name);
  }

  void claim(String phone) {
    for (final m in members) {
      if (m.phone == phone && m.active) m.signedIn = true;
    }
  }

  String _status(SampleMemberRecord m) => m.kind == OrgKind.provider
      ? listings.firstWhere((l) => l.id == m.orgId).status.name
      : (shops.firstWhere((s) => s.id == m.orgId).active
            ? 'active'
            : 'suspended');

  String _orgName(SampleMemberRecord m) => m.kind == OrgKind.provider
      ? listings.firstWhere((l) => l.id == m.orgId).name
      : shops.firstWhere((s) => s.id == m.orgId).name;

  List<Membership> membershipsFor(String phone) => [
    for (final m in members)
      if (m.phone == phone && m.active && m.signedIn)
        Membership(
          id: m.id,
          kind: m.kind,
          orgId: m.orgId,
          orgName: _orgName(m),
          orgStatus: _status(m),
          role: m.role,
        ),
  ];

  SampleListingRecord? listingOwnedBy(String phone) {
    for (final m in members) {
      if (m.kind == OrgKind.provider &&
          m.role == MemberRole.owner &&
          m.active &&
          m.signedIn &&
          m.phone == phone) {
        return listings.firstWhere((l) => l.id == m.orgId);
      }
    }
    return null;
  }

  bool isMember(String? phone, OrgKind kind, String orgId) =>
      phone != null &&
      members.any(
        (m) =>
            m.phone == phone &&
            m.kind == kind &&
            m.orgId == orgId &&
            m.active &&
            m.signedIn,
      ) &&
      (kind == OrgKind.provider
          ? listings.firstWhere((l) => l.id == orgId).status ==
                ListingStatus.approved
          : shops.firstWhere((s) => s.id == orgId).active);
}
