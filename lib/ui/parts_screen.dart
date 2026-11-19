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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: basket.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  key: const Key('basket-review'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                  onPressed: _review,
                  child: Text(
                    'Review order · $basketCount '
                    '${basketCount == 1 ? 'part' : 'parts'} · ${kes(basketTotal)}',
                  ),
                ),
              ),
            ),
      appBar: AppBar(
        title: const Text('Spare parts'),
        actions: [
          if (buyer != null)
            TextButton(
              key: const Key('parts-my-orders'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BuyerOrdersScreen(access: widget.access),
                ),
              ),
              child: const Text('My orders'),
            ),
        ],
      ),
      body: ContentWidth(
        max: 760,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                children: [
                  TextField(
                    key: const Key('parts-search'),
                    controller: query,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      labelText: 'Part name or number',
                      hintText: 'Brake pads, 04465-52180',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
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
                          decoration: const InputDecoration(
                            labelText: 'Car make (optional)',
                            hintText: 'Toyota',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        key: const Key('parts-search-go'),
                        onPressed: _search,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(96, 56),
                        ),
                        child: const Text('Search'),
                      ),
                    ],
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
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _PartCard(
                      part: list[i],
                      inBasket: basket[list[i].id]?.qty ?? 0,
                      onOrder: buyer == null ? null : () => _add(list[i]),
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
      p.shopArea,
      if (p.distanceKm != null) '${p.distanceKm!.toStringAsFixed(1)} km',
    ].where((s) => s.isNotEmpty).join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (p.photoPath != null) ...[
                  PartPhoto(p.photoPath!),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(p.fitment),
                      Text(
                        [
                          p.condition.label,
                          if (p.partNumber != null && p.partNumber!.isNotEmpty)
                            'No. ${p.partNumber}',
                          '${p.stockQty} in stock',
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
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(where, style: const TextStyle(fontSize: 13, color: muted)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('call-shop-${p.id}'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () => ref.read(dialerProvider)(p.shopPhone),
                    icon: const Icon(Icons.call),
                    label: const Text('Call shop'),
                  ),
                ),
                if (onOrder != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: Key('add-${p.id}'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
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
      appBar: AppBar(title: const Text('My parts orders')),
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
    this.actions = const [],
  });
  final PartsOrder order;
  final String who;
  final String phone;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = order;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    who,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: o.status.isOpen ? lime : tint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    o.status.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              '${clockText(o.createdAt)} · ${kes(o.totalKes)}',
              style: const TextStyle(fontSize: 13, color: muted),
            ),
            const SizedBox(height: 6),
            for (final i in o.items) Text('${i.qty} × ${i.title}'),
            if (o.note != null) ...[
              const SizedBox(height: 4),
              Text(
                '"${o.note}"',
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (phone.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => ref.read(dialerProvider)(phone),
                    icon: const Icon(Icons.call, size: 18),
                    label: const Text('Call'),
                  ),
                ...actions,
              ],
            ),
          ],
        ),
      ),
    );
  }
}
