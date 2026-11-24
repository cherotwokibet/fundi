import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/account_repository.dart';
import '../data/admin_repository.dart';
import '../data/zones.dart';
import '../models/complaint.dart';
import '../models/service_provider.dart';
import '../models/trade.dart';
import '../state/app_state.dart';
import 'admin_overview.dart';
import 'admin_requests.dart';
import 'admin_search.dart';
import 'parts_screen.dart';
import 'theme.dart';
import 'widgets.dart';

String _friendly(Object e) =>
    e is AccountException ? e.message : 'That did not save. Try again.';

/// Admin console. Admins are the only way onto the trade side: they add
/// every garage, mobile mechanic and parts shop, and the people who work
/// there, then check and approve them.
///
/// Laptop: a dark sidebar beside the page. Phone: tabs along the bottom.
/// It opens on the overview, which says what needs the admin first.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  AdminSection section = AdminSection.overview;
  late Future<AdminSnapshot> counts = _counts();

  /// What to open in the section: a listing or request id.
  String? focus;
  ListingStatus? focusStatus;

  /// The search box. While it has words, results replace the section.
  final search = TextEditingController();
  bool searchOpen = false;
  bool wasSearching = false;

  Future<AdminSnapshot> _counts() =>
      AdminSnapshot.load(ref.read(adminProvider));

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void _go(AdminSection to, {String? focus, ListingStatus? status}) {
    final next = _counts();
    setState(() {
      section = to;
      counts = next;
      this.focus = focus;
      focusStatus = status;
      search.clear();
      searchOpen = false;
      wasSearching = false;
    });
  }

  void _searchChanged(String v) {
    // Fresh numbers each time a search starts.
    final starting = v.trim().isNotEmpty && !wasSearching;
    wasSearching = v.trim().isNotEmpty;
    final next = starting ? _counts() : counts;
    setState(() {
      counts = next;
    });
  }

  Future<void> _signOut() async {
    await ref.read(accountProvider).signOut();
    ref.read(accountVersionProvider.notifier).bump();
  }

  void _openParts() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          const PartsMarketScreen(access: TradeAccess(isAdmin: true)),
    ),
  );

  static const _titles = {
    AdminSection.overview: (
      'Overview',
      'What needs you, and how the network is growing.',
    ),
    AdminSection.listings: (
      'Mechanics and garages',
      'Nobody is shown to owners until the ID check is passed.',
    ),
    AdminSection.shops: (
      'Parts shops',
      'Only approved garages and mechanics can see their parts.',
    ),
    AdminSection.requests: (
      'Live requests',
      'Every open request, who has it and where it stands. Refreshes every 30 seconds.',
    ),
    AdminSection.complaints: (
      'Complaints',
      'Decide with a note both sides can read. Refunds are capped at what the job cost.',
    ),
  };

  Widget _body() {
    if (search.text.trim().isNotEmpty) {
      return AdminSearchResults(
        key: const ValueKey('search'),
        query: search.text,
        data: counts,
        onListing: (l) =>
            _go(AdminSection.listings, focus: l.id, status: l.status),
        onShop: (_) => _go(AdminSection.shops),
        onRequest: (r) => _go(AdminSection.requests, focus: r.id),
      );
    }
    return _section();
  }

  Widget _section() => switch (section) {
    AdminSection.overview => AdminOverview(
      key: const ValueKey('overview'),
      onGo: _go,
      onOpenRequest: (id) => _go(AdminSection.requests, focus: id),
    ),
    AdminSection.listings => _ListingsTab(
      key: ValueKey('listings-$focus'),
      focusId: focus,
      focusStatus: focusStatus,
    ),
    AdminSection.shops => const _ShopsTab(key: ValueKey('shops')),
    AdminSection.requests => AdminRequestsView(
      key: ValueKey('requests-$focus'),
      focusId: focus,
      onGo: _go,
    ),
    AdminSection.complaints => const _ComplaintsTab(
      key: ValueKey('complaints'),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final searching = search.text.trim().isNotEmpty;
    final (title, subtitle) = searching
        ? ('Search', 'Mechanics, garages, parts shops and requests.')
        : _titles[section]!;
    final searchBox = SizedBox(
      width: wide ? 320 : double.infinity,
      child: TextField(
        key: const Key('admin-search'),
        controller: search,
        autofocus: !wide,
        onChanged: _searchChanged,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search name, phone or request',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: searching
              ? IconButton(
                  key: const Key('admin-search-clear'),
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() {
                    search.clear();
                    wasSearching = false;
                  }),
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: hairline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: hairline),
          ),
        ),
      ),
    );
    final heads = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: heading(wide ? 30 : 24)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 14, color: muted)),
      ],
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, wide ? 28 : 8, 20, 16),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: heads),
                    const SizedBox(width: 16),
                    searchBox,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (searchOpen) ...[searchBox, const SizedBox(height: 12)],
                    heads,
                  ],
                ),
        ),
        Expanded(child: _body()),
      ],
    );
    if (wide) {
      return Scaffold(
        backgroundColor: consolePage,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Sidebar(
              section: section,
              counts: counts,
              onGo: _go,
              onParts: _openParts,
              onSignOut: _signOut,
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: content,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: consolePage,
      appBar: AppBar(
        backgroundColor: consolePage,
        title: const Text('Admin'),
        actions: [
          IconButton(
            key: const Key('admin-search-open'),
            tooltip: 'Search',
            icon: Icon(searchOpen ? Icons.search_off : Icons.search),
            onPressed: () => setState(() {
              searchOpen = !searchOpen;
              if (!searchOpen) {
                search.clear();
                wasSearching = false;
              }
            }),
          ),
          TextButton(
            key: const Key('admin-parts'),
            onPressed: _openParts,
            child: const Text('Parts'),
          ),
          TextButton(onPressed: _signOut, child: const Text('Sign out')),
        ],
      ),
      body: content,
      bottomNavigationBar: FutureBuilder<AdminSnapshot>(
        future: counts,
        builder: (context, snap) {
          final s = snap.data;
          Widget badged(IconData icon, int n) => Badge(
            isLabelVisible: n > 0,
            label: Text('$n'),
            backgroundColor: lime,
            textColor: forest,
            child: Icon(icon),
          );
          return NavigationBar(
            selectedIndex: section.index,
            backgroundColor: Colors.white,
            indicatorColor: lime,
            onDestinationSelected: (i) => _go(AdminSection.values[i]),
            destinations: [
              const NavigationDestination(
                key: Key('admin-tab-overview'),
                icon: Icon(Icons.dashboard_outlined),
                label: 'Overview',
              ),
              NavigationDestination(
                key: const Key('admin-tab-listings'),
                icon: badged(
                  Icons.verified_user_outlined,
                  s?.waiting.length ?? 0,
                ),
                label: 'Mechanics',
              ),
              const NavigationDestination(
                key: Key('admin-tab-shops'),
                icon: Icon(Icons.storefront_outlined),
                label: 'Shops',
              ),
              NavigationDestination(
                key: const Key('admin-tab-requests'),
                icon: badged(
                  Icons.forum_outlined,
                  s?.stuckRequests.length ?? 0,
                ),
                label: 'Requests',
              ),
              NavigationDestination(
                key: const Key('admin-tab-complaints'),
                icon: badged(
                  Icons.flag_outlined,
                  s?.complaints.where((c) => c.needsAdmin).length ?? 0,
                ),
                label: 'Complaints',
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The laptop sidebar: forest green, a count on each queue.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.section,
    required this.counts,
    required this.onGo,
    required this.onParts,
    required this.onSignOut,
  });
  final AdminSection section;
  final Future<AdminSnapshot> counts;
  final ValueChanged<AdminSection> onGo;
  final VoidCallback onParts;
  final VoidCallback onSignOut;

  static const _soft = Color(0xFFCFDCD4);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 252,
      color: forest,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
      child: FutureBuilder<AdminSnapshot>(
        future: counts,
        builder: (context, snap) {
          final s = snap.data;
          Widget item(
            String key,
            IconData icon,
            String label, {
            AdminSection? to,
            VoidCallback? onTap,
            int count = 0,
          }) {
            final on = to != null && to == section;
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Material(
                color: on
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  key: Key(key),
                  borderRadius: BorderRadius.circular(10),
                  onTap: onTap ?? () => onGo(to!),
                  child: SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        Icon(icon, size: 19, color: on ? Colors.white : _soft),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: on
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: on ? Colors.white : _soft,
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
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: forest,
                              ),
                            ),
                          ),
                        const SizedBox(width: 10),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          Widget group(String text) => Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
            child: Text(
              text.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.9,
                color: Color(0xFF8FA59A),
              ),
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                child: Row(
                  children: [
                    Text('fundi', style: heading(22, color: Colors.white)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: lime.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text(
                        'Admin',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: lime,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              item(
                'admin-tab-overview',
                Icons.dashboard_outlined,
                'Overview',
                to: AdminSection.overview,
              ),
              group('People and businesses'),
              item(
                'admin-tab-listings',
                Icons.verified_user_outlined,
                'Mechanics & garages',
                to: AdminSection.listings,
                count: s?.waiting.length ?? 0,
              ),
              item(
                'admin-tab-shops',
                Icons.storefront_outlined,
                'Parts shops',
                to: AdminSection.shops,
              ),
              group('Work'),
              item(
                'admin-tab-requests',
                Icons.forum_outlined,
                'Live requests',
                to: AdminSection.requests,
                count: s?.stuckRequests.length ?? 0,
              ),
              item(
                'admin-tab-complaints',
                Icons.flag_outlined,
                'Complaints',
                to: AdminSection.complaints,
                count: s?.complaints.where((c) => c.needsAdmin).length ?? 0,
              ),
              item(
                'admin-parts',
                Icons.inventory_2_outlined,
                'Parts catalogue',
                onTap: onParts,
              ),
              const Spacer(),
              item(
                'admin-sign-out',
                Icons.logout,
                'Sign out',
                onTap: onSignOut,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Check each listing, then approve or pause it.
class _ListingsTab extends ConsumerStatefulWidget {
  const _ListingsTab({super.key, this.focusId, this.focusStatus});

  /// A listing to open straight away (from search).
  final String? focusId;
  final ListingStatus? focusStatus;

  @override
  ConsumerState<_ListingsTab> createState() => _State();
}

class _State extends ConsumerState<_ListingsTab> {
  late ListingStatus tab = widget.focusStatus ?? ListingStatus.pending;
  late Future<List<AdminListing>> rows = _load();

  /// The listing open beside the list on a laptop.
  late String? selected = widget.focusId;

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
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Toolbar(
              filter: SegmentedButton<ListingStatus>(
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
              action: FilledButton.icon(
                key: const Key('admin-add-listing'),
                onPressed: _add,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add a mechanic or garage'),
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
                    return switch (tab) {
                      ListingStatus.pending => const AdminEmpty(
                        icon: Icons.verified_user_outlined,
                        title: 'Nobody is waiting for checks',
                        body: 'When you add a mechanic or garage, they wait here until the ID check is done.',
                      ),
                      ListingStatus.approved => const AdminEmpty(
                        icon: Icons.build_outlined,
                        title: 'No providers are live yet',
                        body: 'Approved mechanics and garages show here.',
                      ),
                      ListingStatus.suspended => const AdminEmpty(
                        icon: Icons.pause_circle_outline,
                        title: 'No providers are paused',
                        body: 'Paused listings are hidden from owners.',
                      ),
                    };
                  }
                  return LayoutBuilder(
                    builder: (context, c) {
                      if (c.maxWidth < 860) {
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                          itemCount: list.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, i) => _card(list[i]),
                        );
                      }
                      // Laptop: the queue on the left, one listing open
                      // beside it.
                      final pick = list.where((l) => l.id == selected);
                      final current = pick.isEmpty ? list.first : pick.first;
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 340,
                              child: _Queue(
                                list,
                                selectedId: current.id,
                                onTap: (l) => setState(() => selected = l.id),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: SingleChildScrollView(
                                child: KeyedSubtree(
                                  key: ValueKey('listing-detail-${current.id}'),
                                  child: _card(current),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
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
            Row(
              children: [
                AdminAvatar(l.name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${l.type.name == 'garage' ? 'Garage' : 'Mobile mechanic'} · ${l.area} · ${l.phone}',
                        style: TextStyle(color: grey, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AdminPill(
                  '${l.applicableChecks.where(l.checksPassed.contains).length} of ${l.applicableChecks.length} checks',
                  fill: l.canApprove ? const Color(0xFFDCEFE2) : warnFill,
                  ink: l.canApprove ? const Color(0xFF135C37) : warnInk,
                ),
              ],
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

/// Laptop: the listings as a compact list; the chosen one is open beside it.
class _Queue extends StatelessWidget {
  const _Queue(this.list, {required this.selectedId, required this.onTap});
  final List<AdminListing> list;
  final String selectedId;
  final ValueChanged<AdminListing> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: list.length,
        itemBuilder: (_, i) {
          final l = list[i];
          final on = l.id == selectedId;
          final done = l.applicableChecks.where(l.checksPassed.contains).length;
          return Material(
            color: on ? const Color(0xFFF1F6EC) : Colors.white,
            child: InkWell(
              key: Key('listing-item-${l.id}'),
              onTap: () => onTap(l),
              child: Container(
                padding: const EdgeInsets.fromLTRB(13, 12, 14, 12),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: on ? forest : Colors.transparent,
                      width: 3,
                    ),
                    top: i == 0
                        ? BorderSide.none
                        : const BorderSide(color: Color(0xFFEEF0EC)),
                  ),
                ),
                child: Row(
                  children: [
                    AdminAvatar(l.name),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${l.area} · ${l.type == ProviderType.garage ? 'garage' : 'mobile'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AdminPill(
                      '$done of ${l.applicableChecks.length}',
                      fill: l.canApprove ? const Color(0xFFDCEFE2) : warnFill,
                      ink: l.canApprove ? const Color(0xFF135C37) : warnInk,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Parts shops
// ---------------------------------------------------------------------------
class _ShopsTab extends ConsumerStatefulWidget {
  const _ShopsTab({super.key});

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
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Toolbar(
              action: FilledButton.icon(
                key: const Key('admin-add-shop'),
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
                    return const AdminEmpty(
                      icon: Icons.storefront_outlined,
                      title: 'No parts shops yet',
                      body: "Visit the shop, check the owner's ID and permit, then add it. Garages and mechanics see its parts at once.",
                    );
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
                                      s.active
                                          ? 'Pause shop'
                                          : 'Open shop again',
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

/// Owners' reports. Decide each one with a note the owner reads, set a
/// refund if upheld (capped at the job cost by the server), and record the
/// M-Pesa code once the refund is sent.
class _ComplaintsTab extends ConsumerStatefulWidget {
  const _ComplaintsTab({super.key});

  @override
  ConsumerState<_ComplaintsTab> createState() => _ComplaintsState();
}

class _ComplaintsState extends ConsumerState<_ComplaintsTab> {
  late Future<List<Complaint>> rows = ref.read(adminProvider).complaints();

  void _reload() {
    final next = ref.read(adminProvider).complaints();
    setState(() {
      rows = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ContentWidth(
      max: 900,
      child: FutureBuilder<List<Complaint>>(
        future: rows,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: TextButton(
                onPressed: _reload,
                child: const Text('Could not load. Try again'),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return const AdminEmpty(
              icon: Icons.flag_outlined,
              title: 'No complaints',
              body: "When an owner reports a problem with a job, it shows here with the mechanic's answer.",
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final c in list)
                _ComplaintCard(c, key: ValueKey(c.id), onChanged: _reload),
            ],
          );
        },
      ),
    );
  }
}

class _ComplaintCard extends ConsumerStatefulWidget {
  const _ComplaintCard(this.c, {super.key, required this.onChanged});
  final Complaint c;
  final VoidCallback onChanged;

  @override
  ConsumerState<_ComplaintCard> createState() => _ComplaintCardState();
}

class _ComplaintCardState extends ConsumerState<_ComplaintCard> {
  final note = TextEditingController();
  final refund = TextEditingController();
  final code = TextEditingController();
  bool busy = false;

  Complaint get c => widget.c;

  @override
  void dispose() {
    note.dispose();
    refund.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> _do(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      await action();
      widget.onChanged();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendly(e))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _decide(bool uphold) => _do(
    () => ref
        .read(adminProvider)
        .resolveComplaint(
          c.id,
          uphold: uphold,
          note: note.text.trim(),
          refundKes: uphold ? int.tryParse(refund.text.trim()) ?? 0 : 0,
        ),
  );

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontSize: 13, color: muted);
    final status = switch (c.status) {
      ComplaintStatus.open => 'Open',
      ComplaintStatus.upheld => 'Upheld',
      ComplaintStatus.rejected => 'Not upheld',
    };
    return Card(
      key: Key('complaint-${c.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.providerName ?? 'Mechanic',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Chip(label: Text(status), visualDensity: VisualDensity.compact),
              ],
            ),
            Text(
              '${c.providerPhone ?? ''} · ${clockText(c.createdAt)} · '
              'job cost ${kes(c.jobCostKes ?? 0)}',
              style: small,
            ),
            const SizedBox(height: 8),
            Text('Owner: "${c.message}"'),
            if (c.wantsRefund)
              Text(
                'Wants their money back. M-Pesa: +${c.refundPhone ?? '?'}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            const SizedBox(height: 4),
            Text(
              c.providerReply == null
                  ? 'The mechanic has not answered.'
                  : 'Mechanic: "${c.providerReply}"',
              style: small,
            ),
            if (c.open) ...[
              const SizedBox(height: 12),
              TextField(
                key: Key('complaint-note-${c.id}'),
                controller: note,
                maxLength: 500,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: 'Note for the owner and the mechanic',
                  border: OutlineInputBorder(),
                ),
              ),
              TextField(
                key: Key('complaint-refund-${c.id}'),
                controller: refund,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Refund in KES if upheld (optional)',
                  helperText: 'At most ${kes(c.jobCostKes ?? 0)}',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    key: Key('complaint-uphold-${c.id}'),
                    onPressed: busy ? null : () => _decide(true),
                    child: const Text('Uphold'),
                  ),
                  OutlinedButton(
                    key: Key('complaint-reject-${c.id}'),
                    onPressed: busy ? null : () => _decide(false),
                    child: const Text('Not upheld'),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text('Decision: ${c.adminNote ?? ''}'),
              if (c.refundStatus == RefundStatus.paid)
                Text(
                  'Refund of ${kes(c.refundKes)} paid. M-Pesa code ${c.refundReference}.',
                  style: small,
                ),
              if (c.refundStatus == RefundStatus.due) ...[
                const SizedBox(height: 8),
                Text(
                  'Refund due: ${kes(c.refundKes)} to +${c.refundPhone ?? '?'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: Key('complaint-code-${c.id}'),
                  controller: code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'M-Pesa code of the refund',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  key: Key('complaint-paid-${c.id}'),
                  onPressed: busy
                      ? null
                      : () => _do(
                          () => ref
                              .read(adminProvider)
                              .markRefundPaid(c.id, code.text.trim()),
                        ),
                  child: const Text('Refund sent'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small pieces shared by the admin sections
// ---------------------------------------------------------------------------

/// A filter on the left and the section's main action on the right; they
/// stack on a phone.
class _Toolbar extends StatelessWidget {
  const _Toolbar({this.filter, required this.action});
  final Widget? filter;
  final Widget action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
    child: Wrap(
      spacing: 12,
      runSpacing: 10,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [?filter, action],
    ),
  );
}

/// Initials in a forest circle.
class AdminAvatar extends StatelessWidget {
  const AdminAvatar(this.name, {super.key, this.size = 40});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final initials = words.take(2).map((w) => w[0].toUpperCase()).join();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: forest, shape: BoxShape.circle),
      child: Text(
        initials,
        style: TextStyle(
          color: lime,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}

/// A status in words on a soft colour.
class AdminPill extends StatelessWidget {
  const AdminPill(
    this.text, {
    super.key,
    required this.fill,
    required this.ink,
  });
  final String text;
  final Color fill;
  final Color ink;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink),
    ),
  );
}

/// An empty list that says what will appear there, not just "nothing".
class AdminEmpty extends StatelessWidget {
  const AdminEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Align(
    alignment: const Alignment(0, -0.4),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: forest),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, height: 1.4),
            ),
          ],
        ),
      ),
    ),
  );
}
