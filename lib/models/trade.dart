/// The trade side: who works where, parts shops, parts and parts orders.
/// None of this is ever shown to car owners.
library;

enum OrgKind { provider, shop }

enum MemberRole { owner, worker }

/// One business the signed-in person was added to by an admin.
class Membership {
  const Membership({
    required this.id,
    required this.kind,
    required this.orgId,
    required this.orgName,
    required this.orgStatus,
    required this.role,
  });
  final String id;
  final OrgKind kind;
  final String orgId;
  final String orgName;

  /// provider: pending | approved | suspended. shop: active | suspended.
  final String orgStatus;
  final MemberRole role;

  bool get isLive =>
      orgStatus == (kind == OrgKind.provider ? 'approved' : 'active');

  factory Membership.fromRow(Map<String, dynamic> r) => Membership(
    id: r['membership_id'] as String,
    kind: r['kind'] == 'shop' ? OrgKind.shop : OrgKind.provider,
    orgId: r['org_id'] as String,
    orgName: r['org_name'] as String,
    orgStatus: r['org_status'] as String,
    role: r['role'] == 'owner' ? MemberRole.owner : MemberRole.worker,
  );
}

/// Everything the signed-in person may do on the trade side.
class TradeAccess {
  const TradeAccess({this.memberships = const [], this.isAdmin = false});
  final List<Membership> memberships;
  final bool isAdmin;

  bool get isRegistered => isAdmin || memberships.isNotEmpty;

  /// Garage or mechanic listings this person can order parts for.
  List<Membership> get buyers => [
    for (final m in memberships)
      if (m.kind == OrgKind.provider && m.isLive) m,
  ];

  /// Parts shops this person works at.
  List<Membership> get shops => [
    for (final m in memberships)
      if (m.kind == OrgKind.shop) m,
  ];

  bool get canSeeParts =>
      isAdmin || buyers.isNotEmpty || shops.any((s) => s.isLive);
}

class PartsShop {
  const PartsShop({
    required this.id,
    required this.name,
    required this.phone,
    required this.area,
    required this.active,
  });
  final String id;
  final String name;
  final String phone;
  final String area;
  final bool active;
}

/// A person on a business's list, as the admin sees them.
class OrgMember {
  const OrgMember({
    required this.id,
    required this.phone,
    required this.role,
    required this.active,
    required this.signedIn,
    this.name,
  });
  final String id;

  /// +2547XXXXXXXX
  final String phone;
  final String? name;
  final MemberRole role;
  final bool active;

  /// True once the person has signed in with this number.
  final bool signedIn;
}

enum PartCondition {
  brandNew('new', 'New'),
  used('used', 'Used (ex-Japan)'),
  refurbished('refurbished', 'Refurbished');

  const PartCondition(this.code, this.label);
  final String code;
  final String label;

  static PartCondition fromCode(String? c) =>
      values.firstWhere((v) => v.code == c, orElse: () => brandNew);
}

class PartListing {
  const PartListing({
    required this.id,
    required this.shopId,
    required this.title,
    required this.priceKes,
    required this.stockQty,
    this.partNumber,
    this.makes = const [],
    this.models,
    this.yearFrom,
    this.yearTo,
    this.condition = PartCondition.brandNew,
    this.photoPath,
    this.active = true,
    this.shopName = '',
    this.shopPhone = '',
    this.shopArea = '',
    this.distanceKm,
  });
  final String id;
  final String shopId;
  final String title;
  final String? partNumber;

  /// Empty means it fits all makes.
  final List<String> makes;
  final String? models;
  final int? yearFrom;
  final int? yearTo;
  final PartCondition condition;
  final int priceKes;
  final int stockQty;
  final String? photoPath;
  final bool active;
  final String shopName;
  final String shopPhone;
  final String shopArea;
  final double? distanceKm;

  /// "Toyota Probox, Succeed · 2014–2022", or "Fits all makes".
  String get fitment {
    final who = [
      if (makes.isNotEmpty) makes.join(', '),
      if (models != null && models!.trim().isNotEmpty) models!.trim(),
    ].join(' ');
    final years = switch ((yearFrom, yearTo)) {
      (int a, int b) when a == b => '$a',
      (int a, int b) => '$a–$b',
      (int a, null) => '$a on',
      (null, int b) => 'up to $b',
      _ => '',
    };
    final line = [if (who.isNotEmpty) who, if (years.isNotEmpty) years];
    return line.isEmpty ? 'Fits all makes' : line.join(' · ');
  }

  factory PartListing.fromRow(Map<String, dynamic> r) => PartListing(
    id: r['id'] as String,
    shopId: r['shop_id'] as String,
    title: r['title'] as String,
    partNumber: r['part_number'] as String?,
    makes: [for (final m in (r['makes'] as List? ?? const [])) m as String],
    models: r['models'] as String?,
    yearFrom: r['year_from'] as int?,
    yearTo: r['year_to'] as int?,
    condition: PartCondition.fromCode(r['condition'] as String?),
    priceKes: r['price_kes'] as int,
    stockQty: r['stock_qty'] as int,
    photoPath: r['photo_path'] as String?,
    active: r['active'] as bool? ?? true,
    shopName: r['shop_name'] as String? ?? '',
    shopPhone: r['shop_phone'] as String? ?? '',
    shopArea: r['shop_area'] as String? ?? '',
    distanceKm: (r['distance_km'] as num?)?.toDouble(),
  );
}

/// What a shop fills in to list or change a part.
class PartDraft {
  const PartDraft({
    this.id,
    required this.shopId,
    required this.title,
    required this.priceKes,
    required this.stockQty,
    this.partNumber,
    this.makes = const [],
    this.models,
    this.yearFrom,
    this.yearTo,
    this.condition = PartCondition.brandNew,
    this.active = true,
  });

  /// Null for a new part.
  final String? id;
  final String shopId;
  final String title;
  final String? partNumber;
  final List<String> makes;
  final String? models;
  final int? yearFrom;
  final int? yearTo;
  final PartCondition condition;
  final int priceKes;
  final int stockQty;
  final bool active;

  factory PartDraft.from(PartListing l) => PartDraft(
    id: l.id,
    shopId: l.shopId,
    title: l.title,
    partNumber: l.partNumber,
    makes: l.makes,
    models: l.models,
    yearFrom: l.yearFrom,
    yearTo: l.yearTo,
    condition: l.condition,
    priceKes: l.priceKes,
    stockQty: l.stockQty,
    active: l.active,
  );

  Map<String, dynamic> toRow() => {
    'shop_id': shopId,
    'title': title,
    'part_number': partNumber,
    'makes': makes,
    'models': models,
    'year_from': yearFrom,
    'year_to': yearTo,
    'condition': condition.code,
    'price_kes': priceKes,
    'stock_qty': stockQty,
    'active': active,
  };
}

enum OrderStatus {
  placed('Waiting for the shop'),
  confirmed('Confirmed by the shop'),
  ready('Ready to collect'),
  collected('Collected'),
  cancelled('Cancelled');

  const OrderStatus(this.label);
  final String label;

  bool get isOpen => this != collected && this != cancelled;

  /// The next step a shop can take, if any.
  OrderStatus? get shopNext => switch (this) {
    placed => confirmed,
    confirmed => ready,
    ready => collected,
    _ => null,
  };

  static OrderStatus fromName(String? n) =>
      values.firstWhere((v) => v.name == n, orElse: () => placed);
}

/// One line of an order being placed: which part and how many.
typedef OrderLine = ({String partId, int qty});

class OrderItem {
  const OrderItem({
    required this.title,
    required this.unitPriceKes,
    required this.qty,
  });
  final String title;
  final int unitPriceKes;
  final int qty;
}

class PartsOrder {
  const PartsOrder({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.shopPhone,
    required this.buyerName,
    required this.buyerPhone,
    required this.status,
    required this.totalKes,
    required this.createdAt,
    required this.items,
    this.note,
  });
  final String id;
  final String shopId;
  final String shopName;
  final String shopPhone;
  final String buyerName;
  final String buyerPhone;
  final OrderStatus status;
  final int totalKes;
  final DateTime createdAt;
  final List<OrderItem> items;
  final String? note;

  PartsOrder withStatus(OrderStatus s) => PartsOrder(
    id: id,
    shopId: shopId,
    shopName: shopName,
    shopPhone: shopPhone,
    buyerName: buyerName,
    buyerPhone: buyerPhone,
    status: s,
    totalKes: totalKes,
    createdAt: createdAt,
    items: items,
    note: note,
  );
}

/// KES 3,400
String kes(int amount) {
  final s = amount.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return 'KES $b';
}
