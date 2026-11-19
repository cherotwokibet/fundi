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

/// A parts shop's own screen: orders from garages and mechanics, and the
/// shop's parts. Owners and workers see the same thing; our team manages
/// who works here.
class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key, required this.shopId, required this.shopName});
  final String shopId;
  final String shopName;

  @override
  ConsumerState<ShopScreen> createState() => _ShopState();
}

class _ShopState extends ConsumerState<ShopScreen> {
  late Future<List<PartsOrder>> orders = _loadOrders();
  late Future<List<PartListing>> parts = _loadParts();

  Future<List<PartsOrder>> _loadOrders() =>
      ref.read(partsProvider).shopOrders(widget.shopId);
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.shopName),
          actions: [
            TextButton(
              onPressed: () async {
                await ref.read(accountProvider).signOut();
                ref.read(accountVersionProvider.notifier).bump();
                if (context.mounted) {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                }
              },
              child: const Text('Sign out'),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(key: Key('shop-tab-orders'), text: 'Orders'),
              Tab(key: Key('shop-tab-parts'), text: 'Our parts'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          key: const Key('add-part'),
          onPressed: _edit,
          icon: const Icon(Icons.add),
          label: const Text('Add a part'),
        ),
        body: ContentWidth(
          max: 760,
          child: TabBarView(
            children: [
              _FutureList<PartsOrder>(
                future: orders,
                empty: 'No orders yet. Garages and mechanics see your parts as soon as you add them.',
                item: (o) => OrderCard(
                  order: o,
                  who: o.buyerName,
                  phone: o.buyerPhone,
                  actions: [
                    if (o.status.shopNext case final next?)
                      FilledButton(
                        key: Key('order-next-${o.id}'),
                        onPressed: () => _move(o, next),
                        child: Text(switch (next) {
                          OrderStatus.confirmed => 'Confirm order',
                          OrderStatus.ready => 'Ready to collect',
                          _ => 'Mark collected',
                        }),
                      ),
                    if (o.status.isOpen)
                      TextButton(
                        key: Key('order-cancel-${o.id}'),
                        onPressed: () => _move(o, OrderStatus.cancelled),
                        child: const Text('Cancel'),
                      ),
                  ],
                ),
              ),
              _FutureList<PartListing>(
                future: parts,
                empty: 'No parts yet. Tap "Add a part".',
                item: (p) => Card(
                  child: ListTile(
                    key: Key('shop-part-${p.id}'),
                    leading: p.photoPath == null
                        ? const Icon(Icons.inventory_2_outlined)
                        : PartPhoto(p.photoPath!, size: 44),
                    title: Text(
                      p.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${kes(p.priceKes)} · ${p.stockQty} in stock'
                      '${p.active ? '' : ' · Hidden'}\n${p.fitment}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _edit(p),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FutureList<T> extends StatelessWidget {
  const _FutureList({
    required this.future,
    required this.empty,
    required this.item,
  });
  final Future<List<T>> future;
  final String empty;
  final Widget Function(T) item;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<T>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text(_friendly(snap.error!)));
        }
        final list = snap.data!;
        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(empty, textAlign: TextAlign.center),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) => item(list[i]),
        );
      },
    );
  }
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
