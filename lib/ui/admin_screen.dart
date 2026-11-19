import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/account_repository.dart';
import '../data/admin_repository.dart';
import '../data/zones.dart';
import '../models/service_provider.dart';
import '../models/trade.dart';
import '../state/app_state.dart';
import 'parts_screen.dart';
import 'theme.dart';
import 'widgets.dart';

String _friendly(Object e) =>
    e is AccountException ? e.message : 'That did not save. Try again.';

/// Admin console. Admins are the only way onto the trade side: they add
/// every garage, mobile mechanic and parts shop, and the people who work
/// there, then check and approve them.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin'),
          actions: [
            TextButton(
              key: const Key('admin-parts'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PartsMarketScreen(
                    access: TradeAccess(isAdmin: true),
                  ),
                ),
              ),
              child: const Text('Parts'),
            ),
            TextButton(
              onPressed: () async {
                await ref.read(accountProvider).signOut();
                ref.read(accountVersionProvider.notifier).bump();
              },
              child: const Text('Sign out'),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(key: Key('admin-tab-listings'), text: 'Mechanics & garages'),
              Tab(key: Key('admin-tab-shops'), text: 'Parts shops'),
            ],
          ),
        ),
        body: const TabBarView(children: [_ListingsTab(), _ShopsTab()]),
      ),
    );
  }
}

/// Check each listing, then approve or pause it.
class _ListingsTab extends ConsumerStatefulWidget {
  const _ListingsTab();

  @override
  ConsumerState<_ListingsTab> createState() => _State();
}

class _State extends ConsumerState<_ListingsTab> {
  ListingStatus tab = ListingStatus.pending;
  late Future<List<AdminListing>> rows = _load();

  Future<List<AdminListing>> _load() => ref.read(adminProvider).listings(tab);

  void _reload() {
    final next = _load();
    setState(() {
      rows = next;
    });
  }

  Future<void> _do(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      // Owners see approvals at once.
      ref.invalidate(nearbyProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendly(e))));
    }
    if (mounted) _reload();
  }

  Future<void> _view(String path) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await ref.read(adminProvider).documentUrl(path);
      if (url.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Sample mode: there is no real file to open.'),
          ),
        );
        return;
      }
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the document.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ContentWidth(
      max: 900,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: FilledButton.icon(
              key: const Key('admin-add-listing'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _add,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add a mechanic or garage'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: SegmentedButton<ListingStatus>(
              segments: const [
                ButtonSegment(
                  value: ListingStatus.pending,
                  label: Text('Waiting'),
                ),
                ButtonSegment(
                  value: ListingStatus.approved,
                  label: Text('Live'),
                ),
                ButtonSegment(
                  value: ListingStatus.suspended,
                  label: Text('Paused'),
                ),
              ],
              selected: {tab},
              onSelectionChanged: (s) {
                tab = s.first;
                _reload();
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<AdminListing>>(
              future: rows,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Could not load applications.'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _reload,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  );
                }
                final list = snap.data!;
                if (list.isEmpty) {
                  return Center(
                    child: Text(switch (tab) {
                      ListingStatus.pending => 'Nobody is waiting for checks.',
                      ListingStatus.approved => 'No providers are live yet.',
                      ListingStatus.suspended => 'No providers are paused.',
                    }),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _card(list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _add() async {
    final added = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddListingScreen()));
    if (added == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Added. Tick the checks, then approve to go live.'),
        ),
      );
      tab = ListingStatus.pending;
      _reload();
    }
  }

  Future<void> _uploadDoc(AdminListing l) async {
    final kind = await showModalBottomSheet<DocumentKind>(
      context: context,
      constraints: sheetConstraints,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final k in DocumentKind.forType(l.type))
              ListTile(
                key: Key('admin-doc-kind-${k.code}'),
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(k.label),
                onTap: () => Navigator.pop(sheet, k),
              ),
          ],
        ),
      ),
    );
    if (kind == null) return;
    final photo = await ref.read(photoPickerProvider)(camera: true);
    if (photo == null) return;
    await _do(
      () => ref
          .read(adminProvider)
          .uploadDocument(l.id, kind, photo.bytes, photo.mime),
    );
  }

  Widget _card(AdminListing l) {
    final admin = ref.read(adminProvider);
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              '${l.type.name == 'garage' ? 'Garage' : 'Mobile mechanic'} · ${l.area} · ${l.phone}',
              style: TextStyle(color: grey, fontSize: 13),
            ),
            const SizedBox(height: 10),
            const Text(
              'Documents',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            if (l.documents.isEmpty)
              Text('Nothing uploaded yet.', style: TextStyle(color: grey)),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final d in l.documents.entries)
                  ActionChip(
                    avatar: const Icon(Icons.description_outlined, size: 18),
                    label: Text(d.key.label),
                    onPressed: () => _view(d.value),
                  ),
                ActionChip(
                  key: Key('admin-doc-${l.id}'),
                  avatar: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: const Text('Add a document'),
                  onPressed: () => _uploadDoc(l),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: Key('people-${l.id}'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MembersScreen(
                      kind: OrgKind.provider,
                      orgId: l.id,
                      orgName: l.name,
                    ),
                  ),
                ),
                icon: const Icon(Icons.group_outlined),
                label: const Text('People who can sign in'),
              ),
            ),
            const SizedBox(height: 6),
            const Text('Checks', style: TextStyle(fontWeight: FontWeight.w600)),
            for (final k in l.applicableChecks)
              CheckboxListTile(
                key: Key('check-${l.id}-${k.name}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(k.title),
                subtitle: Text(k.explanation),
                value: l.checksPassed.contains(k),
                onChanged: (v) =>
                    _do(() => admin.setCheck(l.id, k, v ?? false)),
              ),
            const SizedBox(height: 8),
            if (l.status != ListingStatus.approved) ...[
              FilledButton(
                key: Key('approve-${l.id}'),
                onPressed: l.canApprove
                    ? () => _do(
                        () => admin.setStatus(l.id, ListingStatus.approved),
                      )
                    : null,
                child: const Text('Approve and go live'),
              ),
              if (!l.canApprove)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Pass the identity check first.',
                    style: TextStyle(color: grey, fontSize: 13),
                  ),
                ),
            ] else
              OutlinedButton(
                key: Key('pause-${l.id}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () =>
                    _do(() => admin.setStatus(l.id, ListingStatus.suspended)),
                child: const Text('Pause this listing'),
              ),
            if (l.status == ListingStatus.suspended)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Paused listings are hidden from owners.',
                  style: TextStyle(fontSize: 13, color: brandGreen),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Parts shops
// ---------------------------------------------------------------------------
class _ShopsTab extends ConsumerStatefulWidget {
  const _ShopsTab();

  @override
  ConsumerState<_ShopsTab> createState() => _ShopsState();
}

class _ShopsState extends ConsumerState<_ShopsTab> {
  late Future<List<PartsShop>> rows = ref.read(adminProvider).shops();

  void _reload() {
    final next = ref.read(adminProvider).shops();
    setState(() {
      rows = next;
    });
  }

  Future<void> _toggle(PartsShop s) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminProvider).setShopActive(s.id, !s.active);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendly(e))));
    }
    if (mounted) _reload();
  }

  Future<void> _add() async {
    final added = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const AddShopScreen()));
    if (added == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return ContentWidth(
      max: 900,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: FilledButton.icon(
              key: const Key('admin-add-shop'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _add,
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Add a parts shop'),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<PartsShop>>(
              future: rows,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: FilledButton(
                      onPressed: _reload,
                      child: const Text('Try again'),
                    ),
                  );
                }
                final list = snap.data!;
                if (list.isEmpty) {
                  return const Center(child: Text('No parts shops yet.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final s = list[i];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${s.area} · ${s.phone} · ${s.active ? 'Open to garages and mechanics' : 'Paused'}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: muted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton.icon(
                                  key: Key('people-${s.id}'),
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => MembersScreen(
                                        kind: OrgKind.shop,
                                        orgId: s.id,
                                        orgName: s.name,
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(Icons.group_outlined),
                                  label: const Text('People'),
                                ),
                                TextButton(
                                  key: Key('shop-toggle-${s.id}'),
                                  onPressed: () => _toggle(s),
                                  child: Text(
                                    s.active ? 'Pause shop' : 'Open shop again',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Onboarding forms
// ---------------------------------------------------------------------------

/// Where the business is: a pilot zone, or this phone's location when the
/// admin is standing at the garage or shop.
class _PlacePicker extends ConsumerWidget {
  const _PlacePicker({
    required this.area,
    required this.point,
    required this.onPoint,
  });
  final TextEditingController area;
  final ({double lat, double lng, String source})? point;
  final void Function(({double lat, double lng, String source})) onPoint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Where it is',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final z in zones)
              ChoiceChip(
                key: Key('zone-${zones.indexOf(z)}'),
                label: Text(z.name),
                selected: point?.source == z.name,
                onSelected: (_) {
                  if (area.text.trim().isEmpty) area.text = z.name;
                  onPoint((lat: z.lat, lng: z.lng, source: z.name));
                },
              ),
            ActionChip(
              key: const Key('place-gps'),
              avatar: const Icon(Icons.my_location, size: 18),
              label: Text(
                point?.source == 'gps'
                    ? 'Using this phone\'s location'
                    : 'I am there now',
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final gps = await ref.read(gpsLookupProvider)();
                if (gps == null) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Location is off. Pick an area instead.'),
                    ),
                  );
                  return;
                }
                onPoint((lat: gps.lat, lng: gps.lng, source: 'gps'));
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: const Key('new-area'),
          controller: area,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Area name people know',
            hintText: 'Roysambu, near Total petrol station',
            border: OutlineInputBorder(),
          ),
          validator: (v) =>
              (v == null || v.trim().length < 3) ? 'Enter the area' : null,
        ),
        if (point == null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Pick an area or "I am there now".',
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ),
      ],
    );
  }
}

String? _phoneError(String? v) => normalizeKenyanPhone(v ?? '') == null
    ? 'Enter a Kenyan mobile number'
    : null;

InputDecoration _box(String label, {String? hint, String? helper}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 2,
      border: const OutlineInputBorder(),
    );

/// Admin adds a garage or mobile mechanic, with the number its account
/// holder will sign in with.
class AddListingScreen extends ConsumerStatefulWidget {
  const AddListingScreen({super.key});

  @override
  ConsumerState<AddListingScreen> createState() => _AddListingState();
}

class _AddListingState extends ConsumerState<AddListingScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final ownerName = TextEditingController();
  final ownerPhone = TextEditingController();
  final businessPhone = TextEditingController();
  final fee = TextEditingController();
  final makes = TextEditingController();
  final area = TextEditingController();
  ProviderType type = ProviderType.mobileMechanic;
  double radius = 5;
  ({double lat, double lng, String source})? point;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    for (final c in [
      name,
      ownerName,
      ownerPhone,
      businessPhone,
      fee,
      makes,
      area,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!form.currentState!.validate()) return;
    if (point == null) {
      setState(() => error = 'Pick where it is.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final owner = normalizeKenyanPhone(ownerPhone.text)!;
    try {
      await ref
          .read(adminProvider)
          .createListing(
            NewListing(
              type: type,
              name: name.text.trim(),
              ownerName: ownerName.text.trim().isEmpty
                  ? null
                  : ownerName.text.trim(),
              ownerPhone: owner,
              businessPhone: businessPhone.text.trim().isEmpty
                  ? owner
                  : normalizeKenyanPhone(businessPhone.text)!,
              area: area.text.trim(),
              lat: point!.lat,
              lng: point!.lng,
              serviceRadiusKm: radius,
              calloutFeeKes: int.tryParse(fee.text.trim()),
              makes: [
                for (final m in makes.text.split(','))
                  if (m.trim().isNotEmpty) m.trim(),
              ],
            ),
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
    final garage = type == ProviderType.garage;
    return Scaffold(
      appBar: AppBar(title: const Text('Add a mechanic or garage')),
      body: ContentWidth(
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              SegmentedButton<ProviderType>(
                segments: const [
                  ButtonSegment(
                    value: ProviderType.mobileMechanic,
                    label: Text('Mobile mechanic'),
                    icon: Icon(Icons.build_outlined),
                  ),
                  ButtonSegment(
                    value: ProviderType.garage,
                    label: Text('Garage'),
                    icon: Icon(Icons.garage_outlined),
                  ),
                ],
                selected: {type},
                onSelectionChanged: (s) => setState(() => type = s.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('new-name'),
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: _box(
                  garage ? 'Garage name' : 'Name owners will see',
                ),
                validator: (v) => (v == null || v.trim().length < 3)
                    ? 'Enter the name owners will see'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('new-owner-name'),
                controller: ownerName,
                textCapitalization: TextCapitalization.words,
                decoration: _box(
                  garage ? 'Owner or manager\'s name' : 'Mechanic\'s full name',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('new-owner-phone'),
                controller: ownerPhone,
                keyboardType: TextInputType.phone,
                decoration: _box(
                  'Number they sign in with',
                  hint: '0712 345 678',
                  helper: 'Only this number can open the listing. Add helpers later under People.',
                ),
                validator: _phoneError,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('new-business-phone'),
                controller: businessPhone,
                keyboardType: TextInputType.phone,
                decoration: _box(
                  'Number owners call (optional)',
                  helper: 'Leave empty to use the sign-in number.',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? null : _phoneError(v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('new-fee'),
                controller: fee,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _box(
                  'Inspection or call-out fee in KES (optional)',
                  helper: 'Owners see this before they call. 0 means free.',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: makes,
                textCapitalization: TextCapitalization.words,
                decoration: _box(
                  'Car makes they work on (optional)',
                  hint: 'Toyota, Nissan, Subaru',
                  helper: 'Leave empty for all makes.',
                ),
              ),
              const SizedBox(height: 16),
              _PlacePicker(
                area: area,
                point: point,
                onPoint: (p) => setState(() => point = p),
              ),
              if (!garage) ...[
                const SizedBox(height: 12),
                Text(
                  'How far they travel: ${radius.round()} km',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Slider(
                  value: radius,
                  min: 2,
                  max: 20,
                  divisions: 18,
                  label: '${radius.round()} km',
                  onChanged: (v) => setState(() => radius = v),
                ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: const TextStyle(color: danger)),
                ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('new-submit'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: busy ? null : _submit,
                child: const Text('Add, then do the checks'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Admin adds a parts shop and its owner.
class AddShopScreen extends ConsumerStatefulWidget {
  const AddShopScreen({super.key});

  @override
  ConsumerState<AddShopScreen> createState() => _AddShopState();
}

class _AddShopState extends ConsumerState<AddShopScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final ownerName = TextEditingController();
  final ownerPhone = TextEditingController();
  final businessPhone = TextEditingController();
  final area = TextEditingController();
  ({double lat, double lng, String source})? point;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    for (final c in [name, ownerName, ownerPhone, businessPhone, area]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!form.currentState!.validate()) return;
    if (point == null) {
      setState(() => error = 'Pick where the shop is.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final owner = normalizeKenyanPhone(ownerPhone.text)!;
    try {
      await ref
          .read(adminProvider)
          .createShop(
            NewShop(
              name: name.text.trim(),
              ownerName: ownerName.text.trim().isEmpty
                  ? null
                  : ownerName.text.trim(),
              ownerPhone: owner,
              businessPhone: businessPhone.text.trim().isEmpty
                  ? owner
                  : normalizeKenyanPhone(businessPhone.text)!,
              area: area.text.trim(),
              lat: point!.lat,
              lng: point!.lng,
            ),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Add a parts shop')),
      body: ContentWidth(
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const Text(
                'Visit the shop and check the owner\'s ID and business permit before adding it. '
                'Garages and mechanics can see its parts as soon as it is added.',
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('shop-name'),
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: _box('Shop name'),
                validator: (v) => (v == null || v.trim().length < 3)
                    ? 'Enter the shop name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: ownerName,
                textCapitalization: TextCapitalization.words,
                decoration: _box('Owner\'s name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('shop-owner-phone'),
                controller: ownerPhone,
                keyboardType: TextInputType.phone,
                decoration: _box(
                  'Owner\'s sign-in number',
                  hint: '0712 345 678',
                  helper: 'Add workers later under People.',
                ),
                validator: _phoneError,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: businessPhone,
                keyboardType: TextInputType.phone,
                decoration: _box(
                  'Shop number mechanics call (optional)',
                  helper: 'Leave empty to use the owner\'s number.',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? null : _phoneError(v),
              ),
              const SizedBox(height: 16),
              _PlacePicker(
                area: area,
                point: point,
                onPoint: (p) => setState(() => point = p),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: const TextStyle(color: danger)),
                ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('shop-submit'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: busy ? null : _submit,
                child: const Text('Add the shop'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// People who can sign in for a business
// ---------------------------------------------------------------------------
class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({
    super.key,
    required this.kind,
    required this.orgId,
    required this.orgName,
  });
  final OrgKind kind;
  final String orgId;
  final String orgName;

  @override
  ConsumerState<MembersScreen> createState() => _MembersState();
}

class _MembersState extends ConsumerState<MembersScreen> {
  final phone = TextEditingController();
  final name = TextEditingController();
  late Future<List<OrgMember>> rows = _load();
  String? error;

  Future<List<OrgMember>> _load() =>
      ref.read(adminProvider).members(widget.kind, widget.orgId);

  @override
  void dispose() {
    phone.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => error = null);
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = _friendly(e));
    }
    if (!mounted) return;
    final next = _load();
    setState(() {
      rows = next;
    });
  }

  Future<void> _add() async {
    final p = normalizeKenyanPhone(phone.text);
    if (p == null) {
      setState(
        () => error = 'Enter a Kenyan mobile number, for example 0712 345 678.',
      );
      return;
    }
    await _run(
      () => ref
          .read(adminProvider)
          .addWorker(
            widget.kind,
            widget.orgId,
            p,
            name.text.trim().isEmpty ? null : name.text.trim(),
          ),
    );
    phone.clear();
    name.clear();
  }

  @override
  Widget build(BuildContext context) {
    final shop = widget.kind == OrgKind.shop;
    return Scaffold(
      appBar: AppBar(title: Text(widget.orgName)),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              shop
                  ? 'These numbers can sign in to run this shop: list parts and handle orders.'
                  : 'The owner runs the listing. Helpers can order spare parts for it.',
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<OrgMember>>(
              future: rows,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) return const Text('Could not load people.');
                return Column(
                  children: [
                    for (final m in snap.data!)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: SwitchListTile(
                          key: Key(
                            'member-active-${m.phone.replaceAll('+', '')}',
                          ),
                          title: Text(m.name ?? m.phone),
                          subtitle: Text(
                            [
                              if (m.name != null) m.phone,
                              m.role == MemberRole.owner
                                  ? 'Owner'
                                  : (shop ? 'Worker' : 'Helper'),
                              m.signedIn
                                  ? 'Has signed in'
                                  : 'Not signed in yet',
                            ].join(' · '),
                          ),
                          value: m.active,
                          onChanged: (v) => _run(
                            () => ref
                                .read(adminProvider)
                                .setMemberActive(m.id, v),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Text(shop ? 'Add a worker' : 'Add a helper', style: heading(18)),
            const SizedBox(height: 8),
            TextField(
              key: const Key('member-name'),
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: _box('Name (optional)'),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('member-phone'),
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: _box('Their phone number', hint: '0712 345 678'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: danger)),
              ),
            const SizedBox(height: 10),
            FilledButton(
              key: const Key('member-add'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _add,
              child: const Text('Add'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Switching someone off takes their access away the next time the app checks.',
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
