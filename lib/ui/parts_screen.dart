import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account_repository.dart';
import '../models/trade.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets.dart';

String _friendly(Object e) => e is AccountException
    ? e.message
    : 'Something went wrong. Check your connection and try again.';

/// The spare parts marketplace for registered garages and mechanics (and
/// parts shop people, who can look but not order). Car owners never reach it.
class PartsMarketScreen extends ConsumerStatefulWidget {
  const PartsMarketScreen({super.key, required this.access});
  final TradeAccess access;

  @override
  ConsumerState<PartsMarketScreen> createState() => _MarketState();
}

class _MarketState extends ConsumerState<PartsMarketScreen> {
  final query = TextEditingController();
  final make = TextEditingController();
  late Future<List<PartListing>> results = _load();

  /// The garage or mechanic listing orders are placed for.
  Membership? get buyer =>
      widget.access.buyers.isEmpty ? null : widget.access.buyers.first;

  Future<List<PartListing>> _load() =>
      ref.read(partsProvider).search(query: query.text, make: make.text);

  void _search() {
    FocusScope.of(context).unfocus();
    setState(() {
      results = _load();
    });
  }

  @override
  void dispose() {
    query.dispose();
    make.dispose();
    super.dispose();
  }

  /// Parts picked for the next order, by part id. One shop at a time,
  /// because one order is for one shop.
  final Map<String, ({PartListing part, int qty})> basket = {};

  String? get basketShop =>
      basket.isEmpty ? null : basket.values.first.part.shopName;

  int get basketTotal =>
      basket.values.fold(0, (sum, l) => sum + l.part.priceKes * l.qty);

  int get basketCount => basket.values.fold(0, (sum, l) => sum + l.qty);

  Future<void> _add(PartListing part) async {
    if (basket.isNotEmpty && basket.values.first.part.shopId != part.shopId) {
      final fresh = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('One shop per order'),
          content: Text(
            'Your order is with $basketShop. Start a new order with ${part.shopName}?',
          ),
          actions: [
            TextButton(
              key: const Key('basket-keep'),
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Keep my order'),
            ),
            FilledButton(
              key: const Key('basket-replace'),
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Start a new order'),
            ),
          ],
        ),
      );
      if (fresh != true) return;
      basket.clear();
    }
    final now = basket[part.id]?.qty ?? 0;
    if (now >= part.stockQty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('Only ${part.stockQty} in stock.')),
          );
      }
      return;
    }
    setState(() => basket[part.id] = (part: part, qty: now + 1));
  }

  Future<void> _review() async {
    final shop = basketShop!;
    final sent = await showModalBottomSheet<bool>(
      context: context,
      constraints: sheetConstraints,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OrderSheet(
        basket: basket,
        buyer: buyer!,
        onChanged: () => setState(() {}),
      ),
    );
    if (!mounted) return;
    if (sent == true) {
      basket.clear();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Order sent to $shop.')));
      _search();
    } else {
      setState(() {});
    }
  }

  /// Quick searches for the parts asked for most.
  static const _shortcuts = [
    ('Brakes', 'brake'),
    ('Filters', 'filter'),
    ('Battery', 'battery'),
    ('Oil', 'oil'),
  ];

  void _shortcut(String word) {
    query.text = word;
    _search();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: consolePage,
      bottomNavigationBar: basket.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Align(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: _BasketBar(
                      shop: basketShop!,
                      summary:
                          '$basketCount ${basketCount == 1 ? 'part' : 'parts'} · ${kes(basketTotal)}',
                      count: basketCount,
                      onReview: _review,
                    ),
                  ),
                ),
              ),
            ),
      appBar: AppBar(
        backgroundColor: consolePage,
        title: const Text('Spare parts'),
        actions: [
          if (buyer != null)
            TextButton.icon(
              key: const Key('parts-my-orders'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BuyerOrdersScreen(access: widget.access),
                ),
              ),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('My orders'),
            ),
        ],
      ),
      body: ContentWidth(
        max: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('parts-search'),
                    controller: query,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: _field(
                      'Part name or number',
                      'Brake pads, 04465-52180',
                      icon: Icons.search,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('parts-make'),
                          controller: make,
                          textCapitalization: TextCapitalization.words,
                          onSubmitted: (_) => _search(),
                          decoration: _field(
                            'Car make (optional)',
                            'Toyota',
                            icon: Icons.directions_car_outlined,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 104,
                        child: BigButton(
                          key: const Key('parts-search-go'),
                          kind: ButtonKind.forest,
                          label: 'Search',
                          onPressed: _search,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (label, word) in _shortcuts)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              key: Key('parts-shortcut-$word'),
                              label: Text(label),
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: hairline),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(99),
                              ),
                              onPressed: () => _shortcut(word),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (buyer == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'You can look at parts here. Ordering is for garages and mechanics.',
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                    )
                  else if (widget.access.buyers.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Orders are placed for ${buyer!.orgName}.',
                        style: const TextStyle(fontSize: 13, color: muted),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<PartListing>>(
                future: results,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _friendly(snap.error!),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  final list = snap.data!;
                  if (list.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No parts in stock match that. Try fewer words, or no car make.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    key: const Key('parts-results'),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: list.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => i == 0
                        ? Text(
                            '${list.length} ${list.length == 1 ? 'part' : 'parts'} in stock'
                            '${make.text.trim().isEmpty ? '' : ' for ${make.text.trim()}'}',
                            key: const Key('parts-count'),
                            style: const TextStyle(color: muted, fontSize: 13),
                          )
                        : _PartCard(
                            part: list[i - 1],
                            inBasket: basket[list[i - 1].id]?.qty ?? 0,
                            onOrder: buyer == null
                                ? null
                                : () => _add(list[i - 1]),
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _field(String label, String hint, {IconData? icon}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: hairline),
      ),
    );

/// The order being put together: one shop, how many parts, the total.
class _BasketBar extends StatelessWidget {
  const _BasketBar({
    required this.shop,
    required this.summary,
    required this.count,
    required this.onReview,
  });
  final String shop;
  final String summary;
  final int count;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
    decoration: BoxDecoration(
      color: forest,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: lime, shape: BoxShape.circle),
          child: Text(
            '$count',
            style: const TextStyle(color: forest, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                shop,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFCFDCD4), fontSize: 12),
              ),
              Text(
                summary,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const Key('basket-review'),
          style: FilledButton.styleFrom(
            backgroundColor: lime,
            foregroundColor: forest,
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: onReview,
          child: const Text('Review order'),
        ),
      ],
    ),
  );
}

class _PartCard extends ConsumerWidget {
  const _PartCard({
    required this.part,
    required this.onOrder,
    this.inBasket = 0,
  });
  final PartListing part;
  final VoidCallback? onOrder;

  /// How many of this part are in the order being put together.
  final int inBasket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = part;
    final where = [
      p.shopName,
      if (p.distanceKm != null) '${p.distanceKm!.toStringAsFixed(1)} km',
      '${p.stockQty} in stock',
    ].where((s) => s.isNotEmpty).join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: inBasket > 0 ? forest : hairline,
          width: inBasket > 0 ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.photoPath != null)
                PartPhoto(p.photoPath!, size: 56)
              else
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.settings_outlined, color: forest),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      where,
                      style: const TextStyle(fontSize: 13, color: muted),
                    ),
                    Text(
                      [
                        p.fitment,
                        p.condition.label,
                        if (p.partNumber != null && p.partNumber!.isNotEmpty)
                          'No. ${p.partNumber}',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 13, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                kes(p.priceKes),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: Key('call-shop-${p.id}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: forest,
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: hairline),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => ref.read(dialerProvider)(p.shopPhone),
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('Call shop'),
                ),
              ),
              if (onOrder != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: Key('add-${p.id}'),
                    style: FilledButton.styleFrom(
                      backgroundColor: inBasket == 0 ? lime : forest,
                      foregroundColor: inBasket == 0 ? forest : Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onOrder,
                    child: Text(
                      inBasket == 0 ? 'Add to order' : 'Added ($inBasket)',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A part photo from the private bucket, through a short-lived link.
class PartPhoto extends ConsumerWidget {
  const PartPhoto(this.path, {super.key, this.size = 64});
  final String path;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String>(
      future: ref.read(partsProvider).photoUrl(path),
      builder: (_, snap) {
        final url = snap.data ?? '';
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: size,
            height: size,
            color: tint,
            child: url.isEmpty
                ? const Icon(Icons.image_outlined, color: muted)
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined, color: muted),
                  ),
          ),
        );
      },
    );
  }
}

class _OrderSheet extends ConsumerStatefulWidget {
  const _OrderSheet({
    required this.basket,
    required this.buyer,
    required this.onChanged,
  });

  /// Edited in place, so the screen behind keeps the changes.
  final Map<String, ({PartListing part, int qty})> basket;
  final Membership buyer;
  final VoidCallback onChanged;

  @override
  ConsumerState<_OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends ConsumerState<_OrderSheet> {
  final note = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  void _set(PartListing part, int qty) {
    setState(() {
      if (qty <= 0) {
        widget.basket.remove(part.id);
      } else {
        widget.basket[part.id] = (part: part, qty: qty);
      }
    });
    widget.onChanged();
    if (widget.basket.isEmpty) Navigator.pop(context, false);
  }

  Future<void> _send() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(partsProvider)
          .placeOrder(
            buyerId: widget.buyer.orgId,
            lines: [
              for (final l in widget.basket.values)
                (partId: l.part.id, qty: l.qty),
            ],
            note: note.text.trim().isEmpty ? null : note.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = _friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.basket.values.toList();
    if (lines.isEmpty) return const SizedBox.shrink();
    final total = lines.fold(0, (sum, l) => sum + l.part.priceKes * l.qty);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your order', style: heading(22)),
          Text(lines.first.part.shopName),
          const SizedBox(height: 10),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.part.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${kes(l.part.priceKes)} each',
                          style: const TextStyle(fontSize: 13, color: muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton.outlined(
                    key: Key('qty-minus-${l.part.id}'),
                    onPressed: busy ? null : () => _set(l.part, l.qty - 1),
                    icon: Icon(
                      l.qty == 1 ? Icons.delete_outline : Icons.remove,
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${l.qty}',
                      key: Key('qty-${l.part.id}'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton.outlined(
                    key: Key('qty-plus-${l.part.id}'),
                    onPressed: busy || l.qty >= l.part.stockQty
                        ? null
                        : () => _set(l.part, l.qty + 1),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('order-note'),
            controller: note,
            decoration: const InputDecoration(
              labelText: 'Note to the shop (optional)',
              hintText: 'I will collect at 4 pm',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Total ${kes(total)}. Pay the shop when you collect.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: const TextStyle(color: danger)),
            ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('order-send'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: busy ? null : _send,
            child: Text('Send order for ${widget.buyer.orgName}'),
          ),
        ],
      ),
    );
  }
}

/// Orders placed by the signed-in person's garage or mechanic listing.
class BuyerOrdersScreen extends ConsumerStatefulWidget {
  const BuyerOrdersScreen({super.key, required this.access});
  final TradeAccess access;

  @override
  ConsumerState<BuyerOrdersScreen> createState() => _BuyerOrdersState();
}

class _BuyerOrdersState extends ConsumerState<BuyerOrdersScreen> {
  late Future<List<PartsOrder>> rows = _load();

  Future<List<PartsOrder>> _load() => ref.read(partsProvider).buyerOrders([
    for (final b in widget.access.buyers) b.orgId,
  ]);

  Future<void> _cancel(PartsOrder o) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(partsProvider).updateOrder(o.id, OrderStatus.cancelled);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendly(e))));
    }
    if (!mounted) return;
    final next = _load();
    setState(() {
      rows = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: consolePage,
      appBar: AppBar(
        backgroundColor: consolePage,
        title: const Text('My parts orders'),
      ),
      body: ContentWidth(
        child: FutureBuilder<List<PartsOrder>>(
          future: rows,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text(_friendly(snap.error!)));
            }
            final list = snap.data!;
            if (list.isEmpty) {
              return const Center(child: Text('No parts orders yet.'));
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final o = list[i];
                return OrderCard(
                  order: o,
                  who: o.shopName,
                  phone: o.shopPhone,
                  actions: [
                    if (o.status == OrderStatus.placed)
                      TextButton(
                        key: Key('cancel-order-${o.id}'),
                        onPressed: () => _cancel(o),
                        child: const Text('Cancel order'),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// One parts order, as the buyer or the shop sees it.
class OrderCard extends ConsumerWidget {
  const OrderCard({
    super.key,
    required this.order,
    required this.who,
    required this.phone,
    this.subtitle,
    this.showStatus = true,
    this.actions = const [],
  });
  final PartsOrder order;
  final String who;
  final String phone;

  /// Under the name; the time and status when not given.
  final String? subtitle;

  /// Off where the order's group already says where it stands.
  final bool showStatus;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = order;
    final initials = who
        .replaceFirst('Sample: ', '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    const money = TextStyle(
      fontWeight: FontWeight.w600,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Container(
      key: Key('order-${o.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: tint,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: forest,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      who,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle ?? 'Ordered ${agoText(o.createdAt)}',
                      style: const TextStyle(fontSize: 13, color: muted),
                    ),
                  ],
                ),
              ),
              if (phone.isNotEmpty)
                IconButton.filledTonal(
                  key: Key('call-order-${o.id}'),
                  tooltip: 'Call $who',
                  style: IconButton.styleFrom(
                    backgroundColor: tint,
                    foregroundColor: forest,
                  ),
                  onPressed: () => ref.read(dialerProvider)(phone),
                  icon: const Icon(Icons.call, size: 20),
                ),
            ],
          ),
          if (showStatus) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: switch (o.status) {
                    OrderStatus.placed => lime,
                    OrderStatus.confirmed => infoFill,
                    OrderStatus.ready => warnFill,
                    _ => tint,
                  },
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  o.status.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: forest,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          for (final i in o.items)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFEEF0EC))),
              ),
              child: Row(
                children: [
                  Expanded(child: Text('${i.qty} × ${i.title}')),
                  const SizedBox(width: 8),
                  Text(kes(i.qty * i.unitPriceKes), style: money),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  kes(o.totalKes),
                  style: money.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          if (o.note != null) ...[
            const SizedBox(height: 6),
            Text(
              '"${o.note}"',
              style: const TextStyle(fontStyle: FontStyle.italic, color: muted),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}
