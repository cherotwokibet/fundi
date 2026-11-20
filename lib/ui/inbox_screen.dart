import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account_repository.dart';
import '../data/inbox_repository.dart';
import '../models/complaint.dart';
import '../models/quote.dart';
import '../models/trade.dart';
import '../models/service_provider.dart';
import '../state/app_state.dart';
import 'quote_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Entry on the mechanic's manage screen: how many requests are waiting.
class InboxEntry extends ConsumerWidget {
  const InboxEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(inboxProvider).value ?? const [];
    final waiting = requests.where((r) => r.waiting).length;
    return Card(
      child: ListTile(
        key: const Key('open-inbox'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Badge(
          isLabelVisible: waiting > 0,
          label: Text('$waiting'),
          child: const Icon(Icons.inbox_outlined, size: 30),
        ),
        title: const Text(
          'Requests from owners',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          waiting == 0
              ? 'No new requests'
              : waiting == 1
              ? '1 owner is waiting for an answer'
              : '$waiting owners are waiting for an answer',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const InboxScreen())),
      ),
    );
  }
}

/// The mechanic's inbox: each request with its note, photo and voice note.
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(inboxProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Requests from owners'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(inboxProvider),
          ),
        ],
      ),
      body: ContentWidth(
        max: 720,
        child: requests.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load your requests.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(inboxProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
          data: (list) => RefreshIndicator(
            onRefresh: () => ref.refresh(inboxProvider.future),
            child: list.isEmpty
                ? ListView(
                    children: const [
                      Padding(
                        padding: EdgeInsets.fromLTRB(24, 64, 24, 0),
                        child: Text(
                          'No requests yet. Set yourself as Available so owners nearby are matched with you.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _RequestCard(list[i]),
                  ),
          ),
        ),
      ),
    );
  }
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

class _RequestCard extends ConsumerStatefulWidget {
  const _RequestCard(this.request);
  final IncomingRequest request;

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool busy = false;
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

  Future<void> _markDone() async {
    setState(() => busy = true);
    try {
      await ref.read(inboxRepositoryProvider).markDone(r.id);
      ref.invalidate(inboxProvider);
      _say('Marked done. The owner can now rate the job.');
    } catch (e) {
      _say(
        e is AccountException
            ? e.message
            : 'Something went wrong. Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _respond(bool accept) async {
    setState(() => busy = true);
    try {
      await ref.read(inboxRepositoryProvider).respond(r.id, accept: accept);
      ref.invalidate(inboxProvider);
      _say(
        accept
            ? 'You took this job.'
            : 'Done. The request is free for another mechanic.',
      );
    } catch (e) {
      _say(
        e is AccountException
            ? e.message
            : 'Something went wrong. Check your connection and try again.',
      );
      ref.invalidate(inboxProvider);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comeToMe = r.mode == RequestMode.comeToMe;
    final where = [
      if (r.area != null) r.area!,
      if (r.distanceKm != null) '${r.distanceKm!.toStringAsFixed(1)} km away',
      _ago(r.createdAt),
    ].join(' · ');
    return Card(
      key: Key('request-${r.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  comeToMe
                      ? Icons.directions_car_outlined
                      : Icons.garage_outlined,
                  color: brandGreen,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    comeToMe
                        ? 'Come to the car'
                        : 'Owner will bring the car to you',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (r.status == RequestStatus.accepted)
                  const Chip(
                    label: Text('You took this'),
                    visualDensity: VisualDensity.compact,
                  ),
                if (r.status == RequestStatus.done)
                  const Chip(
                    label: Text('Done'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(where, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            Text(
              r.note ?? 'No note. The owner wants you to look at the car.',
              style: r.note == null
                  ? const TextStyle(fontStyle: FontStyle.italic)
                  : const TextStyle(fontSize: 15),
            ),
            if (r.carMake != null) ...[
              const SizedBox(height: 4),
              Text('Car: ${r.carMake}'),
            ],
            if (r.photoPath != null || r.voicePath != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (r.photoPath != null)
                    OutlinedButton.icon(
                      key: Key('photo-${r.id}'),
                      onPressed: _showPhoto,
                      icon: const Icon(Icons.photo_outlined),
                      label: const Text('See photo'),
                    ),
                  if (r.voicePath != null)
                    OutlinedButton.icon(
                      key: Key('voice-${r.id}'),
                      onPressed: _toggleVoice,
                      icon: Icon(
                        playing ? Icons.stop : Icons.play_arrow_rounded,
                      ),
                      label: Text(playing ? 'Stop' : 'Play voice note'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (r.contactPhone != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.icon(
                  key: Key('call-owner-${r.id}'),
                  style: FilledButton.styleFrom(backgroundColor: callGreen),
                  onPressed: () => ref.read(dialerProvider)(r.contactPhone!),
                  icon: const Icon(Icons.call),
                  label: const Text('Call the owner'),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'The owner was shown your number. Keep your phone close: they will call you.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            if (r.status == RequestStatus.accepted ||
                r.status == RequestStatus.done)
              _ComplaintSection(r.id),
            if (r.status == RequestStatus.accepted) ...[
              _QuoteSection(r.id),
              TextButton(
                key: Key('job-done-${r.id}'),
                onPressed: busy ? null : _markDone,
                child: const Text('Job done'),
              ),
            ],
            if (r.waiting) ...[
              FilledButton(
                key: Key('accept-${r.id}'),
                onPressed: busy ? null : () => _respond(true),
                child: const Text("I'll take it"),
              ),
              TextButton(
                key: Key('decline-${r.id}'),
                onPressed: busy ? null : () => _respond(false),
                child: const Text("I can't take it"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// On a job the mechanic took: the latest quote and a button to send one.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (q != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          key: Key('send-quote-$requestId'),
          onPressed: () => _write(context, ref),
          icon: const Icon(Icons.request_quote_outlined),
          label: Text(q == null ? 'Send a quote' : 'Send a new quote'),
        ),
      ],
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
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is AccountException
                ? e.message
                : 'Something went wrong. Check your connection and try again.',
          ),
        ),
      );
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3D6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'The owner reported a problem',
            style: TextStyle(fontWeight: FontWeight.w700),
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
