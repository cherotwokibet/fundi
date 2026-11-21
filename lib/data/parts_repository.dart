import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/trade.dart';
import 'account_repository.dart';
import 'sample_directory.dart';

/// The trade-only spare parts marketplace. The database refuses every call
/// from anyone who is not at an approved garage or mechanic listing, at an
/// active parts shop, or an admin.
abstract class PartsRepository {
  /// Parts in stock, nearest shop first.
  Future<List<PartListing>> search({String? query, String? make});

  /// Every part a shop has listed, including hidden and sold-out ones.
  Future<List<PartListing>> shopParts(String shopId);

  /// Adds or changes a part. Returns its id.
  Future<String> savePart(PartDraft draft);

  Future<void> uploadPhoto(
    String shopId,
    String partId,
    Uint8List bytes,
    String mime,
  );

  /// A short-lived link to a part photo, or '' when there is none to show.
  Future<String> photoUrl(String path);

  /// Orders parts for a garage or mechanic listing. All [lines] must be
  /// from one shop; the database refuses anything else.
  Future<String> placeOrder({
    required String buyerId,
    required List<OrderLine> lines,
    String? note,
  });

  /// Orders placed for these garage or mechanic listings, newest first.
  Future<List<PartsOrder>> buyerOrders(List<String> buyerIds);

  /// Orders sent to a shop, newest first.
  Future<List<PartsOrder>> shopOrders(String shopId);

  Future<void> updateOrder(String orderId, OrderStatus status);
}

class SupabasePartsRepository implements PartsRepository {
  SupabasePartsRepository(this._client);
  final SupabaseClient _client;

  static const _orderColumns =
      'id, shop_id, status, note, total_kes, created_at, '
      'parts_shops(name, business_phone), '
      'providers(display_name, business_phone), '
      'parts_order_items(title, unit_price_kes, qty)';

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (e) {
      throw AccountException(e.message);
    }
  }

  @override
  Future<List<PartListing>> search({String? query, String? make}) async {
    final rows = await _guard(
      () => _client.rpc(
        'search_parts',
        params: {'p_query': query, 'p_make': make},
      ),
    ) as List;
    return [
      for (final r in rows) PartListing.fromRow(r as Map<String, dynamic>),
    ];
  }

  @override
  Future<List<PartListing>> shopParts(String shopId) async {
    final rows = await _client
        .from('parts_listings')
        .select()
        .eq('shop_id', shopId)
        .order('title');
    return [for (final r in rows) PartListing.fromRow(r)];
  }

  @override
  Future<String> savePart(PartDraft d) => _guard(() async {
    if (d.id == null) {
      final row = await _client
          .from('parts_listings')
          .insert(d.toRow())
          .select('id')
          .single();
      return row['id'] as String;
    }
    await _client.from('parts_listings').update(d.toRow()).eq('id', d.id!);
    return d.id!;
  });

  @override
  Future<void> uploadPhoto(
    String shopId,
    String partId,
    Uint8List bytes,
    String mime,
  ) async {
    final path = 'shops/$shopId/$partId';
    await _client.storage
        .from('parts')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: true),
        );
    await _guard(
      () => _client
          .from('parts_listings')
          .update({'photo_path': path})
          .eq('id', partId),
    );
  }

  @override
  Future<String> photoUrl(String path) =>
      _client.storage.from('parts').createSignedUrl(path, 600);

  @override
  Future<String> placeOrder({
    required String buyerId,
    required List<OrderLine> lines,
    String? note,
  }) async {
    final id = await _guard(
      () => _client.rpc(
        'place_parts_order',
        params: {
          'p_provider': buyerId,
          'p_items': [
            for (final l in lines) {'listing_id': l.partId, 'qty': l.qty},
          ],
          'p_note': note,
        },
      ),
    );
    return id as String;
  }

  PartsOrder _order(Map<String, dynamic> r) {
    final shop = r['parts_shops'] as Map<String, dynamic>?;
    final buyer = r['providers'] as Map<String, dynamic>?;
    return PartsOrder(
      id: r['id'] as String,
      shopId: r['shop_id'] as String,
      shopName: shop?['name'] as String? ?? 'Parts shop',
      shopPhone: shop?['business_phone'] as String? ?? '',
      buyerName: buyer?['display_name'] as String? ?? 'Garage or mechanic',
      buyerPhone: buyer?['business_phone'] as String? ?? '',
      status: OrderStatus.fromName(r['status'] as String?),
      totalKes: r['total_kes'] as int,
      note: r['note'] as String?,
      createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      items: [
        for (final i in (r['parts_order_items'] as List? ?? const []))
          OrderItem(
            title: i['title'] as String,
            unitPriceKes: i['unit_price_kes'] as int,
            qty: i['qty'] as int,
          ),
      ],
    );
  }

  @override
  Future<List<PartsOrder>> buyerOrders(List<String> buyerIds) async {
    if (buyerIds.isEmpty) return [];
    final rows = await _client
        .from('parts_orders')
        .select(_orderColumns)
        .inFilter('provider_id', buyerIds)
        .order('created_at', ascending: false)
        .limit(50);
    return [for (final r in rows) _order(r)];
  }

  @override
  Future<List<PartsOrder>> shopOrders(String shopId) async {
    final rows = await _client
        .from('parts_orders')
        .select(_orderColumns)
        .eq('shop_id', shopId)
        .order('created_at', ascending: false)
        .limit(100);
    return [for (final r in rows) _order(r)];
  }

  @override
  Future<void> updateOrder(String orderId, OrderStatus status) => _guard(
    () => _client.rpc(
      'update_parts_order',
      params: {'p_order': orderId, 'p_status': status.name},
    ),
  );
}

/// Sample marketplace on the shared [SampleDirectory]. [phone] returns the
/// signed-in number; the same access rules as the database apply.
class SamplePartsRepository implements PartsRepository {
  SamplePartsRepository(this.directory, this.phone);
  final SampleDirectory directory;
  final String? Function() phone;
  int _seq = 0;

  bool get _isAdmin => phone() == SampleAccountRepository.adminPhone;

  void _requireTrade() {
    final p = phone();
    final ok =
        _isAdmin ||
        (p != null && directory.membershipsFor(p).any((m) => m.isLive));
    if (!ok) {
      throw AccountException(
        'The parts marketplace is for registered garages, mechanics and parts shops',
      );
    }
  }

  SampleShopRecord _shop(String id) =>
      directory.shops.firstWhere((s) => s.id == id);

  PartListing _withShop(PartListing l) {
    final s = _shop(l.shopId);
    return PartListing(
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
      photoPath: l.photoPath,
      active: l.active,
      shopName: s.name,
      shopPhone: s.phone,
      shopArea: s.area,
    );
  }

  @override
  Future<List<PartListing>> search({String? query, String? make}) async {
    _requireTrade();
    final q = query?.trim().toLowerCase() ?? '';
    final mk = make?.trim().toLowerCase() ?? '';
    return [
      for (final l in directory.parts)
        if (l.active &&
            l.stockQty > 0 &&
            _shop(l.shopId).active &&
            (q.isEmpty ||
                l.title.toLowerCase().contains(q) ||
                (l.partNumber ?? '').toLowerCase().contains(q) ||
                (l.models ?? '').toLowerCase().contains(q)) &&
            (mk.isEmpty ||
                l.makes.isEmpty ||
                l.makes.any((m) => m.toLowerCase() == mk)))
          _withShop(l),
    ]..sort((a, b) => a.priceKes.compareTo(b.priceKes));
  }

  void _requireShop(String shopId) {
    if (!_isAdmin && !directory.isMember(phone(), OrgKind.shop, shopId)) {
      throw AccountException('Only this shop\'s people can change its parts');
    }
  }

  @override
  Future<List<PartListing>> shopParts(String shopId) async {
    _requireShop(shopId);
    return [
      for (final l in directory.parts)
        if (l.shopId == shopId) _withShop(l),
    ]..sort((a, b) => a.title.compareTo(b.title));
  }

  @override
  Future<String> savePart(PartDraft d) async {
    _requireShop(d.shopId);
    final id = d.id ?? 'np${++_seq}';
    final listing = PartListing(
      id: id,
      shopId: d.shopId,
      title: d.title,
      partNumber: d.partNumber,
      makes: d.makes,
      models: d.models,
      yearFrom: d.yearFrom,
      yearTo: d.yearTo,
      condition: d.condition,
      priceKes: d.priceKes,
      stockQty: d.stockQty,
      active: d.active,
    );
    final i = directory.parts.indexWhere((l) => l.id == id);
    i < 0 ? directory.parts.add(listing) : directory.parts[i] = listing;
    return id;
  }

  @override
  Future<void> uploadPhoto(
    String shopId,
    String partId,
    Uint8List bytes,
    String mime,
  ) async => _requireShop(shopId);

  @override
  Future<String> photoUrl(String path) async => '';

  @override
  Future<String> placeOrder({
    required String buyerId,
    required List<OrderLine> lines,
    String? note,
  }) async {
    if (!directory.isMember(phone(), OrgKind.provider, buyerId)) {
      throw AccountException(
        'Only people at an approved garage or mechanic listing can order parts',
      );
    }
    if (lines.isEmpty) throw AccountException('Add at least one part');
    final parts = [
      for (final line in lines)
        directory.parts.firstWhere((l) => l.id == line.partId),
    ];
    if (parts.map((p) => p.shopId).toSet().length > 1) {
      throw AccountException('One order is for one shop');
    }
    for (var i = 0; i < lines.length; i++) {
      final l = parts[i];
      if (!l.active) {
        throw AccountException('A part in this order is no longer listed');
      }
      if (lines[i].qty < 1 || lines[i].qty > 100) {
        throw AccountException('Quantity must be between 1 and 100');
      }
      if (l.stockQty < lines[i].qty) {
        throw AccountException('Only ${l.stockQty} left of ${l.title}');
      }
    }
    var total = 0;
    for (var i = 0; i < lines.length; i++) {
      final at = directory.parts.indexWhere((l) => l.id == lines[i].partId);
      final l = directory.parts[at];
      directory.parts[at] = _withStock(l, l.stockQty - lines[i].qty);
      total += l.priceKes * lines[i].qty;
    }
    final shop = _shop(parts.first.shopId);
    final buyer = directory.listings.firstWhere((p) => p.id == buyerId);
    final id = 'o${++_seq}';
    directory.orders.insert(
      0,
      SampleOrderRecord(
        PartsOrder(
          id: id,
          shopId: shop.id,
          shopName: shop.name,
          shopPhone: shop.phone,
          buyerName: buyer.name,
          buyerPhone: buyer.phone,
          status: OrderStatus.placed,
          totalKes: total,
          createdAt: DateTime.now(),
          note: note,
          items: [
            for (var i = 0; i < lines.length; i++)
              OrderItem(
                title: parts[i].title,
                unitPriceKes: parts[i].priceKes,
                qty: lines[i].qty,
              ),
          ],
        ),
        buyerId,
        lines,
      ),
    );
    return id;
  }

  PartListing _withStock(PartListing l, int stock) => PartListing(
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
    stockQty: stock,
    photoPath: l.photoPath,
    active: l.active,
  );

  @override
  Future<List<PartsOrder>> buyerOrders(List<String> buyerIds) async => [
    for (final o in directory.orders)
      if (buyerIds.contains(o.buyerId) &&
          directory.isMember(phone(), OrgKind.provider, o.buyerId))
        o.order,
  ];

  @override
  Future<List<PartsOrder>> shopOrders(String shopId) async {
    _requireShop(shopId);
    return [
      for (final o in directory.orders)
        if (o.order.shopId == shopId) o.order,
    ];
  }

  @override
  Future<void> updateOrder(String orderId, OrderStatus status) async {
    final o = directory.orders.firstWhere((o) => o.order.id == orderId);
    final from = o.order.status;
    final shop =
        _isAdmin || directory.isMember(phone(), OrgKind.shop, o.order.shopId);
    final buyer = directory.isMember(phone(), OrgKind.provider, o.buyerId);
    final ok =
        (shop &&
            (from.shopNext == status ||
                (status == OrderStatus.cancelled && from.isOpen))) ||
        (buyer &&
            from == OrderStatus.placed &&
            status == OrderStatus.cancelled);
    if (!ok) {
      throw AccountException(
        'This order cannot move from ${from.name} to ${status.name}',
      );
    }
    o.order = o.order.withStatus(status);
    if (status == OrderStatus.cancelled) {
      for (final line in o.lines) {
        final i = directory.parts.indexWhere((l) => l.id == line.partId);
        final l = directory.parts[i];
        directory.parts[i] = _withStock(l, l.stockQty + line.qty);
      }
    }
  }
}
