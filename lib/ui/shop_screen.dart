import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account_repository.dart';
import '../models/trade.dart';
import '../state/app_state.dart';
import 'parts_screen.dart';
import 'theme.dart';
import 'widgets.dart';

String _friendly(Object e) => e is AccountException
    ? e.message
    : 'Something went wrong. Check your connection and try again.';

/// From this width a shop sees a sidebar and its orders in columns.
const shopBoardBreakpoint = 1000.0;

const _onForest = Color(0xFFCFDCD4);
const _column = Color(0xFFECEBE5);

/// A part counts as running low at this many left.
const lowStockAt = 2;

/// A parts shop's own screen: orders from garages and mechanics, and the
/// shop's parts. Owners and workers see the same thing; our team manages
/// who works here.
class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key, required this.shopId, required this.shopName});
  final String shopId;
  final String shopName;

  /// While the screen is open, new orders are fetched this often.
  static const checkEvery = Duration(seconds: 30);

  @override
  ConsumerState<ShopScreen> createState() => _ShopState();
}

class _ShopState extends ConsumerState<ShopScreen> {
  late Future<List<PartsOrder>> orders = _loadOrders();
  late Future<List<PartListing>> parts = _loadParts();
  Timer? _timer;

  /// Orders still waiting for the shop to confirm them.
  int waiting = 0;

  /// 0: orders, 1: our parts.
  int tab = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(ShopScreen.checkEvery, (_) {
      if (!mounted) return;
      final next = _loadOrders();
      setState(() {
        orders = next;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<List<PartsOrder>> _loadOrders() async {
    final list = await ref.read(partsProvider).shopOrders(widget.shopId);
    final count = list.where((o) => o.status == OrderStatus.placed).length;
    if (mounted && count != waiting) setState(() => waiting = count);
    return list;
  }

  Future<List<PartListing>> _loadParts() =>
      ref.read(partsProvider).shopParts(widget.shopId);

  void _reload() => setState(() {
    orders = _loadOrders();
    parts = _loadParts();
  });

  Future<void> _move(PartsOrder o, OrderStatus to) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(partsProvider).updateOrder(o.id, to);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendly(e))));
    }
    if (mounted) _reload();
  }

  Future<void> _edit([PartListing? part]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PartFormScreen(shopId: widget.shopId, part: part),
      ),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _signOut() async {
    await ref.read(accountProvider).signOut();
    ref.read(accountVersionProvider.notifier).bump();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  List<Widget> _actions(PartsOrder o) => [
    if (o.status.shopNext case final next?)
      BigButton(
        key: Key('order-next-${o.id}'),
        kind: next == OrderStatus.confirmed
            ? ButtonKind.lime
            : ButtonKind.forest,
        label: switch (next) {
          OrderStatus.confirmed => 'Confirm order',
          OrderStatus.ready => 'Ready to collect',
          _ => 'Mark collected',
        },
        onPressed: () => _move(o, next),
      ),
    if (o.status.isOpen)
      TextButton(
        key: Key('order-cancel-${o.id}'),
        style: TextButton.styleFrom(
          foregroundColor: muted,
          minimumSize: const Size(0, 48),
        ),
        onPressed: () => _move(o, OrderStatus.cancelled),
        child: Text(
          o.status == OrderStatus.placed ? "Can't supply it" : 'Cancel',
        ),
      ),
  ];

  String get _ordersLine => waiting == 0
      ? 'New orders also come to the shop phone as a text.'
      : waiting == 1
      ? '1 new order to confirm'
      : '$waiting new orders to confirm';

  Widget _body({required bool wide}) {
    if (tab == 1) {
      return _Loaded<List<PartListing>>(
        future: parts,
        builder: (list) =>
            _PartsPanel(parts: list, wide: wide, onAdd: _edit, onEdit: _edit),
      );
    }
    return _Loaded<List<PartsOrder>>(
      future: orders,
      builder: (list) => FutureBuilder<List<PartListing>>(
        future: parts,
        builder: (_, p) => _OrdersPanel(
          orders: list,
          parts: p.data ?? const [],
          wide: wide,
          line: _ordersLine,
          actions: _actions,
          onEditPart: _edit,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= shopBoardBreakpoint) {
          return Scaffold(
            backgroundColor: consolePage,
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Sidebar(
                  shopName: widget.shopName,
                  waiting: waiting,
                  tab: tab,
                  onTab: (i) => setState(() => tab = i),
                  onSignOut: _signOut,
                ),
                Expanded(child: _body(wide: true)),
              ],
            ),
          );
        }
        return Scaffold(
          backgroundColor: consolePage,
          appBar: AppBar(
            backgroundColor: consolePage,
            title: Text(widget.shopName),
            actions: [
              TextButton(onPressed: _signOut, child: const Text('Sign out')),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            backgroundColor: Colors.white,
            indicatorColor: lime,
            onDestinationSelected: (i) => setState(() => tab = i),
            destinations: [
              NavigationDestination(
                key: const Key('shop-tab-orders'),
                icon: Badge(
                  isLabelVisible: waiting > 0,
                  label: Text('$waiting'),
                  child: const Icon(Icons.receipt_long_outlined),
                ),
                label: 'Orders',
              ),
              const NavigationDestination(
                key: Key('shop-tab-parts'),
                icon: Icon(Icons.inventory_2_outlined),
                label: 'Our parts',
              ),
            ],
          ),
          body: ContentWidth(max: 760, child: _body(wide: false)),
        );
      },
    );
  }
}

/// Waits for a list once; a background refresh keeps showing the last one.
class _Loaded<T> extends StatelessWidget {
  const _Loaded({required this.future, required this.builder});
  final Future<T> future;
  final Widget Function(T) builder;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snap) {
      if (!snap.hasData && snap.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snap.hasError) {
        return Center(child: Text(_friendly(snap.error!)));
      }
      return builder(snap.data as T);
    },
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.shopName,
    required this.waiting,
    required this.tab,
    required this.onTab,
    required this.onSignOut,
  });
  final String shopName;
  final int waiting;
  final int tab;
  final ValueChanged<int> onTab;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => Container(
    width: 240,
    color: forest,
    padding: const EdgeInsets.fromLTRB(14, 20, 14, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Text(
              'fundi',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(width: 6),
            Text(
              'parts',
              style: TextStyle(color: lime, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(shopName, style: const TextStyle(color: _onForest, fontSize: 13)),
        const SizedBox(height: 16),
        for (final (i, label, icon, count, key) in [
          (
            0,
            'Orders',
            Icons.receipt_long_outlined,
            waiting,
            'shop-tab-orders',
          ),
          (1, 'Our parts', Icons.inventory_2_outlined, 0, 'shop-tab-parts'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: tab == i
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: Key(key),
                borderRadius: BorderRadius.circular(10),
                onTap: () => onTab(i),
                child: SizedBox(
                  height: 42,
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(icon, size: 20, color: tab == i ? lime : _onForest),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: tab == i ? Colors.white : _onForest,
                            fontWeight: tab == i
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (count > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: lime,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: forest,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      const SizedBox(width: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const Spacer(),
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: _onForest,
            alignment: Alignment.centerLeft,
          ),
          onPressed: onSignOut,
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Sign out'),
        ),
      ],
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.count);
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: hairline),
        ),
        child: Text(
          '$count',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: muted,
          ),
        ),
      ),
    ],
  );
}

/// Orders by where they stand: new, getting ready, waiting for pickup.
class _OrdersPanel extends StatelessWidget {
  const _OrdersPanel({
    required this.orders,
    required this.parts,
    required this.wide,
    required this.line,
    required this.actions,
    required this.onEditPart,
  });
  final List<PartsOrder> orders;
  final List<PartListing> parts;
  final bool wide;
  final String line;
  final List<Widget> Function(PartsOrder) actions;
  final void Function(PartListing) onEditPart;

  @override
  Widget build(BuildContext context) {
    List<PartsOrder> by(OrderStatus s) => [
      for (final o in orders)
        if (o.status == s) o,
    ];
    final fresh = by(OrderStatus.placed);
    final preparing = by(OrderStatus.confirmed);
    final ready = by(OrderStatus.ready);
    final finished = [
      for (final o in orders)
        if (!o.status.isOpen) o,
    ].take(10).toList();
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final collected = orders
        .where(
          (o) =>
              o.status == OrderStatus.collected && o.createdAt.isAfter(weekAgo),
        )
        .fold(0, (sum, o) => sum + o.totalKes);
    final low = [
      for (final p in parts)
        if (p.active && p.stockQty <= lowStockAt) p,
    ]..sort((a, b) => a.stockQty.compareTo(b.stockQty));

    final groups = [
      ('New, not confirmed', 'new', fresh),
      ('Getting ready', 'preparing', preparing),
      ('Ready for pickup', 'ready', ready),
    ];
    Widget card(PartsOrder o) => OrderCard(
      order: o,
      who: o.buyerName,
      phone: o.buyerPhone,
      subtitle: 'Verified buyer · ordered ${agoText(o.createdAt)}',
      showStatus: false,
      actions: actions(o),
    );

    if (!wide) {
      return ListView(
        key: const Key('shop-orders'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text(
            line,
            key: const Key('shop-orders-line'),
            style: const TextStyle(color: muted),
          ),
          if (orders.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Text(
                'No orders yet. Garages and mechanics see your parts as soon as you add them.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final (title, key, list) in groups)
            if (list.isNotEmpty) ...[
              const SizedBox(height: 18),
              _Group(title, list.length),
              const SizedBox(height: 8),
              for (final o in list)
                Padding(
                  key: Key('group-$key-${o.id}'),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: card(o),
                ),
            ],
          if (low.isNotEmpty) ...[
            const SizedBox(height: 18),
            _LowStock(low, onEditPart),
          ],
          if (finished.isNotEmpty) ...[
            const SizedBox(height: 18),
            _Group('Done recently', finished.length),
            const SizedBox(height: 8),
            for (final o in finished)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: card(o),
              ),
          ],
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Orders',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          Text(
            line,
            key: const Key('shop-orders-line'),
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final (i, (label, value, key)) in [
                ('New, not confirmed', '${fresh.length}', 'kpi-new'),
                ('To get ready', '${preparing.length}', 'kpi-preparing'),
                ('Waiting for pickup', '${ready.length}', 'kpi-ready'),
                ('Collected, last 7 days', kes(collected), 'kpi-sold'),
              ].indexed) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    key: Key(key),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(color: muted, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          value,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, (title, key, list)) in groups.indexed) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      key: Key('shop-col-$key'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _column,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Group(title, list.length),
                          const SizedBox(height: 10),
                          Expanded(
                            child: list.isEmpty
                                ? const Text(
                                    'Nothing here',
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 13,
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: list.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (_, j) => card(list[j]),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 16),
                SizedBox(
                  width: 280,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      _LowStock(low, onEditPart),
                      if (finished.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _DoneList(finished),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Parts almost out of stock, to update before garages are turned away.
class _LowStock extends StatelessWidget {
  const _LowStock(this.parts, this.onEdit);
  final List<PartListing> parts;
  final void Function(PartListing) onEdit;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('shop-low-stock'),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Running low',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        if (parts.isEmpty)
          const Text(
            'Every part has more than 2 in stock.',
            style: TextStyle(color: muted, fontSize: 13),
          ),
        for (final p in parts)
          InkWell(
            key: Key('low-${p.id}'),
            onTap: () => onEdit(p),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text(p.title)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: p.stockQty == 0 ? alertFill : warnFill,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      p.stockQty == 0 ? 'Out' : '${p.stockQty} left',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: p.stockQty == 0 ? alertInk : warnInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _DoneList extends StatelessWidget {
  const _DoneList(this.orders);
  final List<PartsOrder> orders;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Done recently',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        for (final o in orders)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${o.buyerName}\n${o.status.label}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Text(
                  kes(o.totalKes),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// The shop's parts: price, stock, and whether garages can see each one.
class _PartsPanel extends StatelessWidget {
  const _PartsPanel({
    required this.parts,
    required this.wide,
    required this.onAdd,
    required this.onEdit,
  });
  final List<PartListing> parts;
  final bool wide;
  final VoidCallback onAdd;
  final void Function(PartListing) onEdit;

  @override
  Widget build(BuildContext context) {
    final shown = parts.where((p) => p.active).length;
    return ListView(
      padding: wide
          ? const EdgeInsets.fromLTRB(24, 20, 24, 24)
          : const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (wide)
          const Text(
            'Our parts',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
        Text(
          parts.isEmpty
              ? 'No parts yet. Garages and mechanics see each part as soon as you list it.'
              : '${parts.length} ${parts.length == 1 ? 'part' : 'parts'} · $shown shown to garages and mechanics',
          style: const TextStyle(color: muted),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: wide ? 220 : double.infinity,
            child: BigButton(
              key: const Key('add-part'),
              icon: Icons.add,
              label: 'List a part',
              onPressed: onAdd,
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (parts.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: hairline),
            ),
            child: Column(
              children: [
                for (final (i, p) in parts.indexed)
                  InkWell(
                    key: Key('shop-part-${p.id}'),
                    onTap: () => onEdit(p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: i == 0
                            ? null
                            : const Border(
                                top: BorderSide(color: Color(0xFFEEF0EC)),
                              ),
                      ),
                      child: Row(
                        children: [
                          if (p.photoPath != null)
                            PartPhoto(p.photoPath!, size: 44)
                          else
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: tint,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.settings_outlined,
                                color: forest,
                                size: 20,
                              ),
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  p.fitment,
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    _Tag(
                                      p.stockQty == 0
                                          ? 'Out of stock'
                                          : '${p.stockQty} in stock',
                                      warn: p.stockQty <= lowStockAt,
                                    ),
                                    if (!p.active) const _Tag('Hidden'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            kes(p.priceKes),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: muted),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.warn = false});
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: warn ? warnFill : tint,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: warn ? warnInk : forest,
      ),
    ),
  );
}

/// Add or change one of the shop's parts.
class PartFormScreen extends ConsumerStatefulWidget {
  const PartFormScreen({super.key, required this.shopId, this.part});
  final String shopId;
  final PartListing? part;

  @override
  ConsumerState<PartFormScreen> createState() => _PartFormState();
}

class _PartFormState extends ConsumerState<PartFormScreen> {
  final form = GlobalKey<FormState>();
  late final title = TextEditingController(text: widget.part?.title);
  late final number = TextEditingController(text: widget.part?.partNumber);
  late final makes = TextEditingController(text: widget.part?.makes.join(', '));
  late final models = TextEditingController(text: widget.part?.models);
  late final yearFrom = TextEditingController(
    text: widget.part?.yearFrom?.toString(),
  );
  late final yearTo = TextEditingController(
    text: widget.part?.yearTo?.toString(),
  );
  late final price = TextEditingController(
    text: widget.part?.priceKes.toString(),
  );
  late final stock = TextEditingController(
    text: (widget.part?.stockQty ?? 1).toString(),
  );
  late PartCondition condition =
      widget.part?.condition ?? PartCondition.brandNew;
  late bool active = widget.part?.active ?? true;
  PickedPhoto? photo;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    for (final c in [
      title,
      number,
      makes,
      models,
      yearFrom,
      yearTo,
      price,
      stock,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  String? _year(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final y = int.tryParse(v.trim());
    return (y == null || y < 1970 || y > 2100)
        ? 'Enter a year like 2016'
        : null;
  }

  Future<void> _save() async {
    if (!form.currentState!.validate()) return;
    final from = int.tryParse(yearFrom.text.trim());
    final to = int.tryParse(yearTo.text.trim());
    if (from != null && to != null && from > to) {
      setState(() => error = 'The first year must come before the last year.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final parts = ref.read(partsProvider);
    try {
      final id = await parts.savePart(
        PartDraft(
          id: widget.part?.id,
          shopId: widget.shopId,
          title: title.text.trim(),
          partNumber: _opt(number),
          makes: [
            for (final m in makes.text.split(','))
              if (m.trim().isNotEmpty) m.trim(),
          ],
          models: _opt(models),
          yearFrom: from,
          yearTo: to,
          condition: condition,
          priceKes: int.parse(price.text.trim()),
          stockQty: int.parse(stock.text.trim()),
          active: active,
        ),
      );
      if (photo != null) {
        await parts.uploadPhoto(widget.shopId, id, photo!.bytes, photo!.mime);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = _friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pickPhoto() async {
    final p = await ref.read(photoPickerProvider)(camera: true);
    if (p != null) setState(() => photo = p);
  }

  InputDecoration _box(String label, {String? hint, String? helper}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        border: const OutlineInputBorder(),
      );

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.part == null ? 'Add a part' : 'Change part'),
      ),
      body: ContentWidth(
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              TextFormField(
                key: const Key('part-title'),
                controller: title,
                textCapitalization: TextCapitalization.sentences,
                decoration: _box('What is it', hint: 'Front brake pads'),
                validator: (v) => (v == null || v.trim().length < 3)
                    ? 'Enter the part name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('part-number'),
                controller: number,
                decoration: _box('Part number (optional)', hint: '04465-52180'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('part-makes'),
                controller: makes,
                textCapitalization: TextCapitalization.words,
                decoration: _box(
                  'Car makes (optional)',
                  hint: 'Toyota, Nissan',
                  helper: 'Leave empty if it fits all makes.',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: models,
                textCapitalization: TextCapitalization.words,
                decoration: _box('Models (optional)', hint: 'Probox, Succeed'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: yearFrom,
                      keyboardType: TextInputType.number,
                      inputFormatters: digits,
                      decoration: _box('From year'),
                      validator: _year,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: yearTo,
                      keyboardType: TextInputType.number,
                      inputFormatters: digits,
                      decoration: _box('To year'),
                      validator: _year,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Condition',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in PartCondition.values)
                    ChoiceChip(
                      key: Key('condition-${c.code}'),
                      label: Text(c.label),
                      selected: condition == c,
                      onSelected: (_) => setState(() => condition = c),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('part-price'),
                      controller: price,
                      keyboardType: TextInputType.number,
                      inputFormatters: digits,
                      decoration: _box('Price in KES'),
                      validator: (v) =>
                          (int.tryParse(v?.trim() ?? '') ?? 0) <= 0
                          ? 'Enter the price'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      key: const Key('part-stock'),
                      controller: stock,
                      keyboardType: TextInputType.number,
                      inputFormatters: digits,
                      decoration: _box('How many in stock'),
                      validator: (v) => int.tryParse(v?.trim() ?? '') == null
                          ? 'Enter a number'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('part-active'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Show to garages and mechanics'),
                value: active,
                onChanged: (v) => setState(() => active = v),
              ),
              OutlinedButton.icon(
                key: const Key('part-photo'),
                onPressed: busy ? null : _pickPhoto,
                icon: Icon(
                  photo == null ? Icons.photo_camera_outlined : Icons.check,
                ),
                label: Text(
                  photo == null ? 'Add a photo (optional)' : 'Photo added',
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(error!, style: const TextStyle(color: danger)),
                ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('part-save'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: busy ? null : _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
