import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/admin_request.dart';
import '../models/complaint.dart';
import '../models/trade.dart';
import '../state/app_state.dart';
import 'admin_overview.dart';
import 'admin_screen.dart';
import 'theme.dart';

/// Soft fill and ink for a stage, the same in the table and the detail.
(Color, Color) stageColors(RequestStage s) => switch (s) {
  RequestStage.noAnswer || RequestStage.unassigned => (alertFill, alertInk),
  RequestStage.waiting ||
  RequestStage.cancelled => (const Color(0xFFECEDEA), const Color(0xFF4A524F)),
  RequestStage.taken || RequestStage.priceSent => (infoFill, infoInk),
  RequestStage.priceDeclined ||
  RequestStage.working => (const Color(0xFFFCEBC7), warnInk),
  RequestStage.done => (const Color(0xFFDCEFE2), const Color(0xFF135C37)),
};

class StagePill extends StatelessWidget {
  const StagePill(this.stage, {super.key});
  final RequestStage stage;

  @override
  Widget build(BuildContext context) {
    final (fill, ink) = stageColors(stage);
    return AdminPill(stage.label, fill: fill, ink: ink);
  }
}

/// Stuck first (nobody has it, or nobody is answering), then newest.
List<AdminRequest> sortForAdmin(Iterable<AdminRequest> rows) {
  final list = [...rows];
  list.sort((a, b) {
    if (a.stage.stuck != b.stage.stuck) return a.stage.stuck ? -1 : 1;
    if (a.stage.open != b.stage.open) return a.stage.open ? -1 : 1;
    return b.createdAt.compareTo(a.createdAt);
  });
  return list;
}

enum _Filter { open, stuck, all }

/// Live requests: every open request with where it stands, refreshed every
/// 30 seconds. Laptop: the table and the chosen request side by side.
/// Phone: a list; a tap opens the request.
class AdminRequestsView extends ConsumerStatefulWidget {
  const AdminRequestsView({super.key, this.focusId, required this.onGo});

  /// A request to open straight away (from search or the overview).
  final String? focusId;
  final ValueChanged<AdminSection> onGo;

  static const refreshEvery = Duration(seconds: 30);

  @override
  ConsumerState<AdminRequestsView> createState() => _RequestsState();
}

class _RequestsState extends ConsumerState<AdminRequestsView> {
  List<AdminRequest>? rows;
  bool failed = false;
  _Filter filter = _Filter.open;
  late String? selected = widget.focusId;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _load(first: true);
    timer = Timer.periodic(AdminRequestsView.refreshEvery, (_) => _load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool first = false}) async {
    try {
      final next = await ref.read(adminProvider).requests();
      if (!mounted) return;
      setState(() {
        rows = next;
        failed = false;
        // A focused request that is already finished is under All.
        if (first && selected != null) {
          final hit = next.where((r) => r.id == selected);
          if (hit.isNotEmpty && !hit.first.stage.open) filter = _Filter.all;
        }
      });
    } catch (_) {
      if (mounted) setState(() => failed = rows == null);
    }
  }

  List<AdminRequest> _shown(List<AdminRequest> all) => sortForAdmin(
    all.where(
      (r) => switch (filter) {
        _Filter.open => r.stage.open,
        _Filter.stuck => r.stage.stuck,
        _Filter.all => true,
      },
    ),
  );

  void _open(AdminRequest r, bool wide) {
    if (wide) {
      setState(() => selected = r.id);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: consolePage,
          appBar: AppBar(
            backgroundColor: consolePage,
            title: Text('Request ${r.ref}'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: RequestDetail(
              r,
              onGo: (s) {
                Navigator.of(context).pop();
                widget.onGo(s);
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = rows;
    if (all == null) {
      return failed
          ? Center(
              child: FilledButton(
                onPressed: () => _load(first: true),
                child: const Text('Could not load. Try again'),
              ),
            )
          : const Center(child: CircularProgressIndicator());
    }
    final open = all.where((r) => r.stage.open).length;
    final stuck = all.where((r) => r.stage.stuck).length;
    final shown = _shown(all);
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 860;
        final toolbar = Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<_Filter>(
                key: const Key('requests-filter'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: _Filter.open,
                    label: Text('Open · $open'),
                  ),
                  ButtonSegment(
                    value: _Filter.stuck,
                    label: Text('Stuck · $stuck'),
                  ),
                  ButtonSegment(
                    value: _Filter.all,
                    label: Text('Last 7 days · ${all.length}'),
                  ),
                ],
                selected: {filter},
                onSelectionChanged: (s) => setState(() => filter = s.first),
              ),
            ],
          ),
        );
        Widget body;
        if (shown.isEmpty) {
          body = AdminEmpty(
            icon: Icons.forum_outlined,
            title: switch (filter) {
              _Filter.stuck => 'Nothing is stuck',
              _Filter.open => 'No open requests',
              _Filter.all => 'No requests in the last 7 days',
            },
            body:
                'Requests from "Find me a mechanic" show here with who has '
                'them and where they stand. It refreshes every 30 seconds.',
          );
        } else if (wide) {
          final pick = shown.where((r) => r.id == selected);
          final current = pick.isEmpty ? shown.first : pick.first;
          body = Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _Table(
                    shown,
                    selectedId: current.id,
                    onTap: (r) => _open(r, true),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                    child: RequestDetail(
                      current,
                      key: ValueKey('detail-${current.id}'),
                      onGo: widget.onGo,
                    ),
                  ),
                ),
              ],
            ),
          );
        } else {
          body = ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: shown.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) =>
                _RequestCard(shown[i], onTap: () => _open(shown[i], false)),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            toolbar,
            Expanded(
              child: RefreshIndicator(onRefresh: _load, child: body),
            ),
          ],
        );
      },
    );
  }
}

/// Laptop table: area, problem, mechanic, status, age.
class _Table extends StatelessWidget {
  const _Table(this.rows, {required this.selectedId, required this.onTap});
  final List<AdminRequest> rows;
  final String selectedId;
  final ValueChanged<AdminRequest> onTap;

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: muted,
    );
    final now = DateTime.now();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                SizedBox(width: 120, child: Text('Area', style: head)),
                Expanded(child: Text('Problem', style: head)),
                SizedBox(width: 150, child: Text('Mechanic', style: head)),
                SizedBox(width: 150, child: Text('Status', style: head)),
                SizedBox(
                  width: 44,
                  child: Text('Age', style: head, textAlign: TextAlign.right),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: hairline),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final r = rows[i];
                final on = r.id == selectedId;
                return Material(
                  color: on ? const Color(0xFFF1F6EC) : Colors.white,
                  child: InkWell(
                    key: Key('request-row-${r.id}'),
                    onTap: () => onTap(r),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: on ? forest : Colors.transparent,
                            width: 3,
                          ),
                          bottom: const BorderSide(color: Color(0xFFEEF0EC)),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(13, 12, 16, 12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 120,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.area ?? 'Unknown',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  r.ref,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    r.problem,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (r.hasComplaint) ...[
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.flag,
                                    size: 16,
                                    color: alertInk,
                                    semanticLabel: 'Complaint',
                                  ),
                                ],
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 150,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: Text(
                                r.providerName ?? 'Nobody yet',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: r.providerName == null ? muted : ink,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 150,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: StagePill(r.stage),
                            ),
                          ),
                          SizedBox(
                            width: 44,
                            child: Text(
                              shortAge(now.difference(r.createdAt)),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Phone: one request per card.
class _RequestCard extends StatelessWidget {
  const _RequestCard(this.r, {required this.onTap});
  final AdminRequest r;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final age = shortAge(DateTime.now().difference(r.createdAt));
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: Key('request-row-${r.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: r.stage.stuck ? alertInk : hairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.problem,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${r.area ?? 'Unknown'} · ${r.providerName ?? 'Nobody yet'} · $age',
                      style: const TextStyle(fontSize: 13, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StagePill(r.stage),
                  if (r.hasComplaint)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Icon(
                        Icons.flag,
                        size: 16,
                        color: alertInk,
                        semanticLabel: 'Complaint',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Everything about one request, and the calls the admin can make.
class RequestDetail extends ConsumerWidget {
  const RequestDetail(this.r, {super.key, required this.onGo});
  final AdminRequest r;
  final ValueChanged<AdminSection> onGo;

  String? get _advice => switch (r.stage) {
    RequestStage.noAnswer =>
      'No answer for ${shortAge(DateTime.now().difference(r.waitingSince))}. '
          'Call the mechanic. The owner\'s screen can also send it on to the '
          'next free mechanic.',
    RequestStage.unassigned =>
      r.rematchCount >= 3
          ? 'Sent on 3 times and nobody took it. The owner now sees the '
                'mechanics nearby and can call one.'
          : 'No free mechanic fitted. The owner sees the mechanics nearby '
                'and can call one.',
    RequestStage.priceDeclined =>
      'The owner said no to the price. The mechanic can send a new one.',
    _ => null,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const label = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: muted,
    );
    Widget fact(String name, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: label),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 14)),
      ],
    );
    final dial = ref.read(dialerProvider);
    final advice = _advice;
    final handedOn = r.rematchCount == 0
        ? null
        : 'Sent on ${r.rematchCount == 1 ? 'once' : '${r.rematchCount} times'}'
              ' after ${r.handoff == 'no_answer' ? 'no answer' : 'a pass'}';
    return Container(
      key: Key('request-detail-${r.id}'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Request ${r.ref}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              StagePill(r.stage),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Sent ${clockText(r.createdAt)} · '
            '${shortAge(DateTime.now().difference(r.createdAt))} ago',
            style: const TextStyle(fontSize: 13, color: muted),
          ),
          if (advice != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: r.stage.stuck ? alertFill : warnFill,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                advice,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: r.stage.stuck ? alertInk : warnInk,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Text('What the owner said', style: label),
          const SizedBox(height: 4),
          Text(
            r.note?.trim().isNotEmpty == true
                ? '"${r.note!.trim()}"'
                : 'No note.',
            style: const TextStyle(fontSize: 15, height: 1.4),
          ),
          if (r.hasVoice || r.hasPhoto) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                if (r.hasVoice)
                  const AdminPill('Voice note sent', fill: tint, ink: forest),
                if (r.hasPhoto)
                  const AdminPill('Photo sent', fill: tint, ink: forest),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              fact('Area', r.area ?? 'Unknown'),
              fact('Where', r.comeToMe ? 'Comes to the car' : 'At the garage'),
              fact('Car', r.carMake ?? 'Not given'),
              fact(
                'Price',
                r.quoteTotalKes == null ? 'None yet' : kes(r.quoteTotalKes!),
              ),
            ],
          ),
          const Divider(height: 32, color: hairline),
          const Text('Mechanic', style: label),
          const SizedBox(height: 6),
          Row(
            children: [
              if (r.providerName != null) ...[
                AdminAvatar(r.providerName!, size: 36),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.providerName ?? 'Nobody has it yet',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (handedOn != null)
                      Text(
                        handedOn,
                        style: const TextStyle(fontSize: 13, color: muted),
                      ),
                  ],
                ),
              ),
              if (r.providerPhone != null)
                OutlinedButton.icon(
                  key: const Key('request-call-mechanic'),
                  onPressed: () => dial(r.providerPhone!),
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('Call'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Owner', style: label),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  r.ownerPhone ??
                      'Guest with no number. The owner calls the mechanic.',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              if (r.ownerPhone != null)
                OutlinedButton.icon(
                  key: const Key('request-call-owner'),
                  onPressed: () => dial(r.ownerPhone!),
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('Call'),
                ),
            ],
          ),
          if (r.hasComplaint) ...[
            const Divider(height: 32, color: hairline),
            Row(
              children: [
                const Icon(Icons.flag_outlined, color: alertInk),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(switch (r.complaintStatus!) {
                    ComplaintStatus.open => 'Complaint waiting for you',
                    ComplaintStatus.upheld =>
                      r.refundStatus == RefundStatus.due
                          ? 'Complaint upheld · refund to send'
                          : 'Complaint upheld',
                    ComplaintStatus.rejected => 'Complaint not upheld',
                  }, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  key: const Key('request-open-complaint'),
                  onPressed: () => onGo(AdminSection.complaints),
                  child: const Text('Open complaints'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The overview's table of the newest open requests, stuck ones first.
class LiveRequestsCard extends StatelessWidget {
  const LiveRequestsCard(this.rows, {super.key, required this.onOpen});
  final List<AdminRequest> rows;

  /// Opens Live requests, on one request or (null) the whole list.
  final ValueChanged<String?> onOpen;

  @override
  Widget build(BuildContext context) {
    final open = sortForAdmin(rows.where((r) => r.stage.open)).take(6);
    final now = DateTime.now();
    return Container(
      key: const Key('live-requests'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Live requests',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  key: const Key('live-requests-all'),
                  onPressed: () => onOpen(null),
                  child: const Text('See all'),
                ),
              ],
            ),
          ),
          if (open.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Text(
                'No open requests right now. New ones show here as owners send them.',
                style: TextStyle(color: muted, height: 1.4),
              ),
            ),
          for (final r in open)
            InkWell(
              key: Key('live-${r.id}'),
              onTap: () => onOpen(r.id),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFEEF0EC))),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        r.area ?? 'Unknown',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        r.problem,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 140,
                      child: Text(
                        r.providerName ?? 'Nobody yet',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: r.providerName == null ? muted : ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 150,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: StagePill(r.stage),
                      ),
                    ),
                    SizedBox(
                      width: 52,
                      child: Text(
                        shortAge(now.difference(r.createdAt)),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
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
}
