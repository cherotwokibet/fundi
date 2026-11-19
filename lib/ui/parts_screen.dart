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

  Future<void> _order(PartListing part) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      constraints: sheetConstraints,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OrderSheet(part: part, buyer: buyer!),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order sent to ${part.shopName}.')),
      );
      _search();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _PartCard(
                      part: list[i],
                      onOrder: buyer == null ? null : () => _order(list[i]),
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
  const _PartCard({required this.part, required this.onOrder});
  final PartListing part;
  final VoidCallback? onOrder;

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
                      key: Key('order-${p.id}'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: onOrder,
                      child: const Text('Order'),
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
  const _OrderSheet({required this.part, required this.buyer});
  final PartListing part;
  final Membership buyer;

  @override
  ConsumerState<_OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends ConsumerState<_OrderSheet> {
  int qty = 1;
  final note = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    note.dispose();
    super.dispose();
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
            partId: widget.part.id,
            qty: qty,
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
    final p = widget.part;
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
          Text(p.title, style: heading(22)),
          Text('${p.shopName} · ${kes(p.priceKes)} each'),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                'How many',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton.outlined(
                key: const Key('qty-minus'),
                onPressed: qty > 1 ? () => setState(() => qty--) : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '$qty',
                  key: const Key('qty'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton.outlined(
                key: const Key('qty-plus'),
                onPressed: qty < p.stockQty
                    ? () => setState(() => qty++)
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
            'Total ${kes(p.priceKes * qty)}. Pay the shop when you collect.',
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
