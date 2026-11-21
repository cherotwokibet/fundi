import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account_repository.dart';
import '../data/admin_repository.dart';
import '../models/complaint.dart';
import '../models/trade.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// Where the admin console can go. The overview links into the others.
enum AdminSection { overview, listings, shops, complaints }

/// Verified providers needed before Phase 2 opens (see PROJECT_CONTEXT.md).
const phase2Gate = 90;

/// Everything the overview shows, loaded in one go.
class AdminSnapshot {
  const AdminSnapshot({
    required this.waiting,
    required this.live,
    required this.paused,
    required this.shops,
    required this.complaints,
  });
  final List<AdminListing> waiting;
  final List<AdminListing> live;
  final List<AdminListing> paused;
  final List<PartsShop> shops;
  final List<Complaint> complaints;

  List<Complaint> get openComplaints => [
    for (final c in complaints)
      if (c.open) c,
  ];
  List<Complaint> get refundsDue => [
    for (final c in complaints)
      if (c.refundStatus == RefundStatus.due) c,
  ];
  int get refundsDueKes => refundsDue.fold(0, (sum, c) => sum + c.refundKes);
  int get liveShops => shops.where((s) => s.active).length;

  static Future<AdminSnapshot> load(AdminRepository admin) async {
    final results = await Future.wait<Object>([
      admin.listings(ListingStatus.pending),
      admin.listings(ListingStatus.approved),
      admin.listings(ListingStatus.suspended),
      admin.shops(),
      admin.complaints(),
    ]);
    return AdminSnapshot(
      waiting: results[0] as List<AdminListing>,
      live: results[1] as List<AdminListing>,
      paused: results[2] as List<AdminListing>,
      shops: results[3] as List<PartsShop>,
      complaints: results[4] as List<Complaint>,
    );
  }
}

/// The admin's first screen: the numbers that matter and a "Needs you" list.
class AdminOverview extends ConsumerStatefulWidget {
  const AdminOverview({super.key, required this.onGo});
  final ValueChanged<AdminSection> onGo;

  @override
  ConsumerState<AdminOverview> createState() => _AdminOverviewState();
}

class _AdminOverviewState extends ConsumerState<AdminOverview> {
  late Future<AdminSnapshot> data = AdminSnapshot.load(ref.read(adminProvider));

  void _reload() {
    final next = AdminSnapshot.load(ref.read(adminProvider));
    setState(() {
      data = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminSnapshot>(
      future: data,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load the overview.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _reload,
                  child: const Text('Try again'),
                ),
              ],
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final s = snap.data!;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              _Kpis(s),
              const SizedBox(height: 20),
              _NeedsYou(s, onGo: widget.onGo),
            ],
          ),
        );
      },
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis(this.s);
  final AdminSnapshot s;

  @override
  Widget build(BuildContext context) {
    final live = s.live.length;
    final tiles = [
      _Kpi(
        key: const Key('kpi-live'),
        label: 'Verified and live',
        value: '$live',
        suffix: ' / $phase2Gate',
        progress: (live / phase2Gate).clamp(0, 1).toDouble(),
        note: 'Needed before Phase 2',
      ),
      _Kpi(
        key: const Key('kpi-waiting'),
        label: 'Waiting for checks',
        value: '${s.waiting.length}',
        note: s.paused.isEmpty ? 'None paused' : '${s.paused.length} paused',
      ),
      _Kpi(
        key: const Key('kpi-shops'),
        label: 'Parts shops open',
        value: '${s.liveShops}',
        note: '${s.shops.length} added in total',
      ),
      _Kpi(
        key: const Key('kpi-complaints'),
        label: 'Open complaints',
        value: '${s.openComplaints.length}',
        alert: s.openComplaints.isNotEmpty,
        note: s.refundsDue.isEmpty
            ? 'No refunds due'
            : '${s.refundsDue.length} refund due · ${kes(s.refundsDueKes)}',
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth >= 840 ? 4 : 2;
        const gap = 12.0;
        final w = (c.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: w, child: t)],
        );
      },
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    super.key,
    required this.label,
    required this.value,
    required this.note,
    this.suffix,
    this.progress,
    this.alert = false,
  });
  final String label;
  final String value;
  final String? suffix;
  final String note;
  final double? progress;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Same height in a row, with or without the progress bar.
      constraints: const BoxConstraints(minHeight: 134),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: muted)),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: alert ? alertInk : ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              children: [
                if (suffix != null)
                  TextSpan(
                    text: suffix,
                    style: const TextStyle(
                      fontSize: 16,
                      color: muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                color: forest,
                backgroundColor: tint,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(note, style: const TextStyle(fontSize: 12, color: muted)),
        ],
      ),
    );
  }
}

/// One thing waiting on the admin, with the button that deals with it.
typedef _Task = ({
  String key,
  IconData icon,
  Color fill,
  Color ink,
  String title,
  String detail,
  String action,
  AdminSection go,
});

class _NeedsYou extends StatelessWidget {
  const _NeedsYou(this.s, {required this.onGo});
  final AdminSnapshot s;
  final ValueChanged<AdminSection> onGo;

  List<_Task> get tasks => [
    if (s.waiting.isNotEmpty)
      (
        key: 'task-checks',
        icon: Icons.verified_user_outlined,
        fill: infoFill,
        ink: infoInk,
        title: s.waiting.length == 1
            ? '1 mechanic or garage waiting for checks'
            : '${s.waiting.length} mechanics and garages waiting for checks',
        detail: 'Next: ${s.waiting.first.name}',
        action: 'Review',
        go: AdminSection.listings,
      ),
    for (final c in s.openComplaints)
      (
        key: 'task-complaint-${c.id}',
        icon: Icons.flag_outlined,
        fill: alertFill,
        ink: alertInk,
        title: 'Complaint: "${_short(c.message)}"',
        detail: c.providerReply == null
            ? '${c.providerName ?? 'The mechanic'} has not answered yet'
            : '${c.providerName ?? 'The mechanic'} answered · decide',
        action: 'Decide',
        go: AdminSection.complaints,
      ),
    for (final c in s.refundsDue)
      (
        key: 'task-refund-${c.id}',
        icon: Icons.payments_outlined,
        fill: warnFill,
        ink: warnInk,
        title: 'Send a refund of ${kes(c.refundKes)} by M-Pesa',
        detail: 'Then enter the M-Pesa code',
        action: 'Record',
        go: AdminSection.complaints,
      ),
  ];

  static String _short(String s) =>
      s.length <= 48 ? s : '${s.substring(0, 45).trimRight()}…';

  @override
  Widget build(BuildContext context) {
    final list = tasks;
    return Container(
      key: const Key('needs-you'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Needs you',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                _CountPill(list.length),
              ],
            ),
          ),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: forest),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Nothing is waiting on you. New checks, complaints and refunds show up here.',
                      style: TextStyle(color: muted, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          for (final t in list)
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEF0EC))),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: t.fill,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(t.icon, size: 18, color: t.ink),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            t.detail,
                            style: const TextStyle(fontSize: 13, color: muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      key: Key(t.key),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        side: const BorderSide(color: hairline),
                        foregroundColor: forest,
                      ),
                      onPressed: () => onGo(t.go),
                      child: Text(t.action),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill(this.n);
  final int n;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: n == 0 ? tint : lime,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      '$n',
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: forest,
      ),
    ),
  );
}
