import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account_repository.dart';
import '../data/inbox_repository.dart';
import '../models/complaint.dart';
import '../models/quote.dart';
import '../models/service_provider.dart';
import '../models/trade.dart' show kes;
import '../state/app_state.dart';
import 'quote_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// From this width the garage portal shows a job board beside the
/// availability panel instead of one column.
const garageBoardBreakpoint = 1000.0;

const _onForest = Color(0xFFCFDCD4);
const _doneFill = Color(0xFFDCEFE2);
const _doneInk = Color(0xFF135C37);
const _column = Color(0xFFECEBE5);

String _friendly(Object e) => e is AccountException
    ? e.message
    : 'Something went wrong. Check your connection and try again.';

/// Where a job stands, from the request and its latest price.
enum JobStage {
  newRequest('New requests', 'New'),
  needsPrice('Write the price', 'Write the price'),
  waitingOwner('Waiting for owner', 'Price sent'),
  working('Working', 'Approved'),
  done('Done', 'Done');

  const JobStage(this.column, this.pill);

  /// Board column title.
  final String column;

  /// Short label on a job.
  final String pill;

  (Color, Color) get colors => switch (this) {
    JobStage.newRequest => (lime, forest),
    JobStage.needsPrice => (warnFill, warnInk),
    JobStage.waitingOwner => (infoFill, infoInk),
    JobStage.working => (tint, forest),
    JobStage.done => (_doneFill, _doneInk),
  };
}

JobStage stageOf(IncomingRequest r, Quote? q) {
  if (r.waiting) return JobStage.newRequest;
  if (r.status == RequestStatus.done) return JobStage.done;
  return switch (q?.status) {
    QuoteStatus.approved => JobStage.working,
    QuoteStatus.sent => JobStage.waitingOwner,
    _ => JobStage.needsPrice,
  };
}

bool _isJob(IncomingRequest r) =>
    r.status == RequestStatus.accepted || r.status == RequestStatus.done;

String _modeTitle(IncomingRequest r) => r.mode == RequestMode.comeToMe
    ? 'Come to the car'
    : 'Owner brings the car to you';

/// A job's name: the owner's note when there is one.
String _jobTitle(IncomingRequest r) {
  final n = r.note?.trim();
  return n == null || n.isEmpty ? _modeTitle(r) : n;
}

String _meta(IncomingRequest r, {bool mode = false, bool ago = false}) => [
  if (r.carMake != null) r.carMake!,
  if (r.area != null) r.area!,
  if (r.distanceKm != null) '${r.distanceKm!.toStringAsFixed(1)} km',
  if (mode) r.mode == RequestMode.comeToMe ? 'come to the car' : 'drive in',
  if (ago) agoText(r.createdAt),
].join(' · ');

void openJob(BuildContext context, String requestId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => JobScreen(requestId: requestId)),
  );
}

// ---------------------------------------------------------------------------
// Today: availability, new requests and jobs. A job board on a laptop.
// ---------------------------------------------------------------------------

/// The approved mechanic's or garage's home in the garage portal.
class GarageToday extends ConsumerStatefulWidget {
  const GarageToday({
    super.key,
    required this.listing,
    required this.onSignOut,
    this.parts,
  });
  final MyListing listing;
  final VoidCallback onSignOut;

  /// The way into the parts marketplace, when this person may order.
  final Widget? parts;

  @override
  ConsumerState<GarageToday> createState() => _GarageTodayState();
}

class _GarageTodayState extends ConsumerState<GarageToday> {
  bool busy = false;

  Future<void> _set(Availability a) async {
    setState(() => busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(accountProvider).setAvailability(a);
      ref.invalidate(myListingProvider);
      ref.invalidate(nearbyProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendly(e))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(inboxProvider);
    final availability = AvailabilityCard(
      listing: widget.listing,
      busy: busy,
      onSet: _set,
    );
    return Scaffold(
      backgroundColor: consolePage,
      appBar: AppBar(
        backgroundColor: consolePage,
        title: const Text('Today'),
        actions: [
          IconButton(
            key: const Key('garage-refresh'),
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(inboxProvider),
          ),
          TextButton(
            onPressed: widget.onSignOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final list = requests.value;
          final Widget jobs;
          if (list == null) {
            jobs = requests.hasError
                ? _LoadError(onRetry: () => ref.invalidate(inboxProvider))
                : const Center(child: CircularProgressIndicator());
          } else {
            jobs = const SizedBox.shrink();
          }
          final live = [
            for (final r in list ?? const <IncomingRequest>[])
              if (r.waiting || _isJob(r)) r,
          ];
          if (c.maxWidth >= garageBoardBreakpoint) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 340,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 8, 24),
                    children: [
                      availability,
                      if (widget.parts != null) ...[
                        const SizedBox(height: 16),
                        widget.parts!,
                      ],
                    ],
                  ),
                ),
                Expanded(child: list == null ? jobs : JobBoard(live)),
              ],
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(inboxProvider.future),
            child: ContentWidth(
              // A short page: build it all, so nothing waits on a scroll.
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    availability,
                    const SizedBox(height: 24),
                    if (list == null)
                      SizedBox(height: 160, child: jobs)
                    else ...[
                      _NewRequests(live),
                      const SizedBox(height: 24),
                      _YourJobs(live),
                    ],
                    if (widget.parts != null) ...[
                      const SizedBox(height: 24),
                      widget.parts!,
                    ],
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

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Could not load your requests.'),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}

/// The forest card on top: name, Verified, and Available / Busy / Offline.
class AvailabilityCard extends StatelessWidget {
  const AvailabilityCard({
    super.key,
    required this.listing,
    required this.busy,
    required this.onSet,
  });
  final MyListing listing;
  final bool busy;
  final void Function(Availability) onSet;

  String _statusLine(BuildContext context) {
    final until = listing.availableUntil;
    return switch (listing.availability) {
      Availability.available when until != null =>
        'Owners see you as available until ${TimeOfDay.fromDateTime(until).format(context)}.',
      Availability.unconfirmed =>
        'Your "Available" has expired. Tap Available to show up first again.',
      Availability.busy => 'Owners see you as busy.',
      _ => 'Owners see you as offline.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final a = listing.availability;
    return Container(
      key: const Key('garage-availability'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: forest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  listing.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: lime.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, size: 14, color: lime),
                    SizedBox(width: 4),
                    Text(
                      'Verified',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Taking jobs now?',
            style: TextStyle(color: _onForest, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                for (final (option, label) in const [
                  (Availability.available, 'Available'),
                  (Availability.busy, 'Busy'),
                  (Availability.offline, 'Offline'),
                ])
                  Expanded(
                    child: _Segment(
                      key: Key('set-${option.name}'),
                      label: label,
                      selected: a == option,
                      onTap: busy ? null : () => onSet(option),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _statusLine(context),
            style: const TextStyle(color: _onForest, fontSize: 13),
          ),
          if (a == Availability.available || a == Availability.unconfirmed)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('keep-on'),
                style: TextButton.styleFrom(
                  foregroundColor: lime,
                  padding: EdgeInsets.zero,
                ),
                onPressed: busy ? null : () => onSet(Availability.available),
                child: Text(
                  a == Availability.available
                      ? 'Keep me on for 4 more hours'
                      : 'Turn Available back on',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected ? lime : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? forest : Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.count);
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: count > 0 ? lime : tint,
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
    ],
  );
}

class _NewRequests extends StatelessWidget {
  const _NewRequests(this.list);
  final List<IncomingRequest> list;

  @override
  Widget build(BuildContext context) {
    final waiting = [
      for (final r in list)
        if (r.waiting) r,
    ];
    return Column(
      key: const Key('garage-new'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader('New requests', waiting.length),
        const SizedBox(height: 2),
        Text(
          waiting.isEmpty
              ? 'No new requests'
              : waiting.length == 1
              ? '1 owner is waiting for an answer'
              : '${waiting.length} owners are waiting for an answer',
          style: const TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 10),
        if (waiting.isEmpty)
          const Text(
            'Owners nearby are matched with you while you are Available.',
          ),
        for (final r in waiting)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: RequestCard(r),
          ),
      ],
    );
  }
}

class _YourJobs extends StatelessWidget {
  const _YourJobs(this.list);
  final List<IncomingRequest> list;

  @override
  Widget build(BuildContext context) {
    final jobs = [
      for (final r in list)
        if (_isJob(r)) r,
    ];
    return Column(
      key: const Key('garage-jobs'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader('Your jobs', jobs.length),
        const SizedBox(height: 10),
        if (jobs.isEmpty)
          const Text(
            'Jobs you take show here. Open one to call the owner and send your price.',
            style: TextStyle(color: muted),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: hairline),
            ),
            child: Column(
              children: [
                for (final (i, r) in jobs.indexed) _JobRow(r, first: i == 0),
              ],
            ),
          ),
      ],
    );
  }
}

class _StagePill extends StatelessWidget {
  const _StagePill(this.stage);
  final JobStage stage;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = stage.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        stage.pill,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _JobRow extends ConsumerWidget {
  const _JobRow(this.r, {required this.first});
  final IncomingRequest r;
  final bool first;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(inboxQuoteProvider(r.id)).value;
    final stage = stageOf(r, q);
    return InkWell(
      key: Key('job-${r.id}'),
      onTap: () => openJob(context, r.id),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: first
              ? null
              : const Border(top: BorderSide(color: Color(0xFFEEF0EC))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _jobTitle(r),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    _meta(r),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _StagePill(stage),
            const Icon(Icons.chevron_right, color: muted),
          ],
        ),
      ),
    );
  }
}

/// A request waiting for an answer: what the owner said, Take or Pass.
class RequestCard extends ConsumerStatefulWidget {
  const RequestCard(this.request, {super.key, this.compact = false});
  final IncomingRequest request;

  /// Smaller, for a job board column.
  final bool compact;

  @override
  ConsumerState<RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<RequestCard> {
  bool busy = false;
  IncomingRequest get r => widget.request;

  Future<void> _respond(bool accept) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      await ref.read(inboxRepositoryProvider).respond(r.id, accept: accept);
      ref.invalidate(inboxProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'You took this job. Open it to call the owner.'
                : 'Done. The request is free for another mechanic.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendly(e))));
      ref.invalidate(inboxProvider);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final note = r.note?.trim();
    return Container(
      key: Key('request-${r.id}'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact)
            Container(
              color: lime,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  const Text(
                    'New request',
                    style: TextStyle(
                      color: forest,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    agoText(r.createdAt),
                    style: const TextStyle(
                      color: forest,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.all(compact ? 12 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _modeTitle(r),
                  style: TextStyle(
                    fontSize: compact ? 15 : 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _meta(r, ago: compact),
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                if (note != null && note.isNotEmpty)
                  Text(
                    '"$note"',
                    maxLines: compact ? 3 : null,
                    overflow: compact ? TextOverflow.ellipsis : null,
                    style: TextStyle(fontSize: compact ? 13 : 15),
                  )
                else
                  const Text(
                    'No note. The owner wants you to look at the car.',
                    style: TextStyle(fontStyle: FontStyle.italic, color: muted),
                  ),
                if (r.photoPath != null || r.voicePath != null) ...[
                  const SizedBox(height: 10),
                  MediaButtons(r),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: BigButton(
                        key: Key('accept-${r.id}'),
                        label: compact ? 'Take' : 'Take the job',
                        busy: busy,
                        onPressed: () => _respond(true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      key: Key('decline-${r.id}'),
                      style: TextButton.styleFrom(
                        foregroundColor: muted,
                        minimumSize: const Size(64, 56),
                      ),
                      onPressed: busy ? null : () => _respond(false),
                      child: const Text('Pass'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// See the owner's photo, play their voice note.
class MediaButtons extends ConsumerStatefulWidget {
  const MediaButtons(this.request, {super.key});
  final IncomingRequest request;

  @override
  ConsumerState<MediaButtons> createState() => _MediaButtonsState();
}

class _MediaButtonsState extends ConsumerState<MediaButtons> {
  bool playing = false;
  IncomingRequest get r => widget.request;

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<String?> _url(String path) async {
    final url = await ref.read(inboxRepositoryProvider).fileUrl(path);
    if (url.isEmpty) {
      _say('Sample mode: there is no real file to open.');
      return null;
    }
    return url;
  }

  Future<void> _showPhoto() async {
    try {
      final url = await _url(r.photoPath!);
      if (url == null || !mounted) return;
      await showDialog<void>(
        context: context,
        builder: (d) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: InteractiveViewer(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Could not load the photo.'),
              ),
            ),
          ),
        ),
      );
    } catch (_) {
      _say('Could not open the photo.');
    }
  }

  Future<void> _toggleVoice() async {
    final player = ref.read(voicePlayerProvider);
    if (playing) {
      await player.stop();
      if (mounted) setState(() => playing = false);
      return;
    }
    try {
      final url = await _url(r.voicePath!);
      if (url == null) return;
      setState(() => playing = true);
      await player.play(url);
    } catch (_) {
      _say('Could not play the voice note.');
    } finally {
      if (mounted) setState(() => playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: forest,
      backgroundColor: tint,
      side: BorderSide.none,
      minimumSize: const Size(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (r.voicePath != null)
          OutlinedButton.icon(
            key: Key('voice-${r.id}'),
            style: style,
            onPressed: _toggleVoice,
            icon: Icon(playing ? Icons.stop : Icons.play_arrow_rounded),
            label: Text(playing ? 'Stop' : 'Play voice note'),
          ),
        if (r.photoPath != null)
          OutlinedButton.icon(
            key: Key('photo-${r.id}'),
            style: style,
            onPressed: _showPhoto,
            icon: const Icon(Icons.photo_outlined),
            label: const Text('See photo'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Job board (laptop)
// ---------------------------------------------------------------------------

/// Every request and job in columns, from new to done.
class JobBoard extends ConsumerWidget {
  const JobBoard(this.list, {super.key});
  final List<IncomingRequest> list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotes = <String, Quote?>{
      for (final r in list)
        if (_isJob(r)) r.id: ref.watch(inboxQuoteProvider(r.id)).value,
    };
    final columns = {for (final s in JobStage.values) s: <IncomingRequest>[]};
    for (final r in list) {
      columns[stageOf(r, quotes[r.id])]!.add(r);
    }
    int total(JobStage s) =>
        columns[s]!.fold(0, (sum, r) => sum + (quotes[r.id]?.totalKes ?? 0));
    return Column(
      key: const Key('job-board'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 24, 16),
          child: Wrap(
            spacing: 24,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.end,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Job board',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${list.length} ${list.length == 1 ? 'job' : 'jobs'} · tap a job to call the owner or send your price',
                    style: const TextStyle(color: muted),
                  ),
                ],
              ),
              Wrap(
                spacing: 24,
                children: [
                  _Stat('Waiting for owner', kes(total(JobStage.waitingOwner))),
                  _Stat(
                    'Approved',
                    kes(total(JobStage.working) + total(JobStage.done)),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              const gap = 12.0;
              final n = JobStage.values.length;
              final width = math.max(
                190.0,
                (c.maxWidth - 40 - gap * (n - 1)) / n,
              );
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 24, 24),
                child: SizedBox(
                  height: c.maxHeight - 24,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, s) in JobStage.values.indexed) ...[
                        if (i > 0) const SizedBox(width: gap),
                        SizedBox(
                          width: width,
                          child: _BoardColumn(s, columns[s]!, quotes),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(color: muted, fontSize: 12)),
      Text(
        value,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 18,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

class _BoardColumn extends StatelessWidget {
  const _BoardColumn(this.stage, this.items, this.quotes);
  final JobStage stage;
  final List<IncomingRequest> items;
  final Map<String, Quote?> quotes;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('board-${stage.name}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _column,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  stage.column,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${items.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: items.isEmpty
                ? const Text(
                    'Nothing here',
                    style: TextStyle(color: muted, fontSize: 13),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => stage == JobStage.newRequest
                        ? RequestCard(items[i], compact: true)
                        : _BoardJobCard(items[i], quotes[items[i].id], stage),
                  ),
          ),
        ],
      ),
    );
  }
}

class _BoardJobCard extends StatelessWidget {
  const _BoardJobCard(this.r, this.q, this.stage);
  final IncomingRequest r;
  final Quote? q;
  final JobStage stage;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: hairline),
      ),
      child: InkWell(
        key: Key('job-${r.id}'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => openJob(context, r.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _jobTitle(r),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _meta(r),
                style: const TextStyle(color: muted, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _StagePill(stage),
                  if (q != null)
                    Text(
                      q!.totalText,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
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

// ---------------------------------------------------------------------------
// One job: call the owner, send the price, mark it done.
// ---------------------------------------------------------------------------

class JobScreen extends ConsumerStatefulWidget {
  const JobScreen({super.key, required this.requestId});
  final String requestId;

  @override
  ConsumerState<JobScreen> createState() => _JobScreenState();
}

class _JobScreenState extends ConsumerState<JobScreen> {
  bool busy = false;

  Future<void> _markDone(IncomingRequest r) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      await ref.read(inboxRepositoryProvider).markDone(r.id);
      ref.invalidate(inboxProvider);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Marked done. The owner can now rate the job.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendly(e))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(inboxProvider).value;
    final r = list?.where((x) => x.id == widget.requestId).firstOrNull;
    if (r == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: list == null
              ? const CircularProgressIndicator()
              : const Text('This job is no longer here.'),
        ),
      );
    }
    final q = _isJob(r) ? ref.watch(inboxQuoteProvider(r.id)).value : null;
    final stage = stageOf(r, q);
    final note = r.note?.trim();
    return Scaffold(
      backgroundColor: consolePage,
      appBar: AppBar(
        backgroundColor: forest,
        foregroundColor: Colors.white,
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _modeTitle(r),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            Text(
              _meta(r),
              style: const TextStyle(fontSize: 13, color: _onForest),
            ),
          ],
        ),
      ),
      body: ContentWidth(
        max: 640,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _StageBar(stage),
            const SizedBox(height: 16),
            if (r.contactPhone != null)
              BigButton(
                key: Key('call-owner-${r.id}'),
                kind: ButtonKind.forest,
                icon: Icons.call,
                label: 'Call the owner',
                onPressed: () => ref.read(dialerProvider)(r.contactPhone!),
              )
            else
              const _Note(
                'The owner was shown your number. Keep your phone close: they will call you.',
              ),
            const SizedBox(height: 12),
            _Panel(
              title: 'What the owner said',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    note == null || note.isEmpty
                        ? 'No note. The owner wants you to look at the car.'
                        : '"$note"',
                    style: note == null || note.isEmpty
                        ? const TextStyle(fontStyle: FontStyle.italic)
                        : const TextStyle(fontSize: 15),
                  ),
                  if (r.photoPath != null || r.voicePath != null) ...[
                    const SizedBox(height: 10),
                    MediaButtons(r),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            _ComplaintSection(r.id),
            if (r.status == RequestStatus.accepted) ...[
              _QuoteSection(r.id),
              const SizedBox(height: 16),
              BigButton(
                key: Key('job-done-${r.id}'),
                kind: ButtonKind.outline,
                label: 'Job done',
                busy: busy,
                onPressed: () => _markDone(r),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tap when the work is finished. The owner is then asked to rate it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ],
            if (r.status == RequestStatus.done) ...[
              if (q != null) _Panel(title: 'Your price', child: QuoteLines(q)),
              const SizedBox(height: 12),
              Container(
                key: const Key('job-finished'),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _doneFill,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Job done. The owner can now rate it.',
                  style: TextStyle(
                    color: _doneInk,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text, style: const TextStyle(fontSize: 13)),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: const TextStyle(color: muted, fontSize: 13),
              ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}

/// Four bars: taken, price sent, approved, done.
class _StageBar extends StatelessWidget {
  const _StageBar(this.stage);
  final JobStage stage;

  @override
  Widget build(BuildContext context) {
    const labels = ['Taken', 'Price sent', 'Approved', 'Done'];
    final reached = switch (stage) {
      JobStage.newRequest => -1,
      JobStage.needsPrice => 0,
      JobStage.waitingOwner => 1,
      JobStage.working => 2,
      JobStage.done => 3,
    };
    return Semantics(
      label: reached < 0 ? 'Not taken yet' : 'Job stage: ${labels[reached]}',
      child: ExcludeSemantics(
        child: Row(
          key: const Key('job-stage'),
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: i <= reached ? forest : hairline,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 12,
                        color: i <= reached ? ink : muted,
                        fontWeight: i == reached
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The latest price on a job and a button to send one.
class _QuoteSection extends ConsumerWidget {
  const _QuoteSection(this.requestId);
  final String requestId;

  Future<void> _write(BuildContext context, WidgetRef ref) async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => QuoteFormScreen(requestId: requestId)),
    );
    if (sent == true) {
      ref.invalidate(inboxQuoteProvider(requestId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quote sent. The owner sees it in the app.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(inboxQuoteProvider(requestId)).value;
    return _Panel(
      title: 'Your price',
      subtitle: 'The owner approves in one tap',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (q != null) ...[
            Text(
              switch (q.status) {
                QuoteStatus.approved => 'Approved by the owner. Go ahead.',
                QuoteStatus.declined => 'Declined by the owner.',
                _ => 'Waiting for the owner to answer.',
              },
              key: Key('quote-status-$requestId'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            QuoteLines(q),
            const SizedBox(height: 12),
          ] else
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Check the car, then send your price. Start work only after the owner approves.',
              ),
            ),
          BigButton(
            key: Key('send-quote-$requestId'),
            kind: q == null ? ButtonKind.lime : ButtonKind.tint,
            icon: Icons.request_quote_outlined,
            label: q == null ? 'Send a quote' : 'Send a new quote',
            onPressed: () => _write(context, ref),
          ),
        ],
      ),
    );
  }
}

/// The owner's complaint about this job, if any, and the mechanic's one reply.
class _ComplaintSection extends ConsumerStatefulWidget {
  const _ComplaintSection(this.requestId);
  final String requestId;

  @override
  ConsumerState<_ComplaintSection> createState() => _ComplaintSectionState();
}

class _ComplaintSectionState extends ConsumerState<_ComplaintSection> {
  final reply = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    reply.dispose();
    super.dispose();
  }

  Future<void> _send(Complaint c) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      await ref
          .read(inboxRepositoryProvider)
          .replyToComplaint(c.id, reply.text.trim());
      ref.invalidate(inboxComplaintProvider(widget.requestId));
      messenger.showSnackBar(
        const SnackBar(content: Text('Reply sent. Fundi will decide.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendly(e))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(inboxComplaintProvider(widget.requestId)).value;
    if (c == null) return const SizedBox.shrink();
    final outcome = switch (c.status) {
      ComplaintStatus.open => 'Fundi will look at it and tell you the outcome.',
      ComplaintStatus.upheld =>
        c.refundKes > 0
            ? 'Upheld. The owner gets ${kes(c.refundKes)} back. ${c.adminNote ?? ''}'
            : 'Upheld. ${c.adminNote ?? ''}',
      ComplaintStatus.rejected => 'Not upheld. ${c.adminNote ?? ''}',
    };
    return Container(
      key: Key('complaint-${widget.requestId}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warnFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: warnLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'The owner reported a problem',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: warnInk,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text('"${c.message}"'),
          if (c.wantsRefund)
            const Text(
              'They asked for their money back.',
              style: TextStyle(fontSize: 13),
            ),
          const SizedBox(height: 6),
          if (c.providerReply != null)
            Text(
              'You answered: "${c.providerReply}"',
              style: const TextStyle(fontSize: 13),
            )
          else if (c.open) ...[
            TextField(
              key: Key('complaint-reply-${widget.requestId}'),
              controller: reply,
              maxLength: 500,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: 'Your side (you can answer once)',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: Key('complaint-reply-send-${widget.requestId}'),
                onPressed: busy ? null : () => _send(c),
                child: const Text('Send reply'),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            outcome.trim(),
            key: Key('complaint-outcome-${widget.requestId}'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
