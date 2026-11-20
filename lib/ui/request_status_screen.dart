import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/provider_repository.dart';
import '../models/quote.dart';
import '../models/service_provider.dart';
import '../state/app_state.dart';
import 'browse_screen.dart';
import 'complaint_ui.dart';
import 'quote_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// "My repair": what happened to the owner's request. Every state has a way
/// out: call the mechanic, call someone else, or cancel.
class RequestStatusScreen extends ConsumerStatefulWidget {
  const RequestStatusScreen({super.key});

  /// After this long with no answer, we suggest calling someone else.
  static const suggestOthersAfter = Duration(minutes: 5);

  /// How often the screen checks for an answer while it is open.
  static const checkEvery = Duration(seconds: 20);

  @override
  ConsumerState<RequestStatusScreen> createState() => _State();
}

class _State extends ConsumerState<RequestStatusScreen> {
  Timer? poll;
  bool cancelling = false;

  @override
  void initState() {
    super.initState();
    // Only while this screen is open, so it costs no data in the background.
    poll = Timer.periodic(RequestStatusScreen.checkEvery, (_) async {
      if (!mounted) return;
      try {
        final fresh = await ref.refresh(openRequestProvider.future);
        if (fresh != null && fresh.accepted) {
          ref.invalidate(quoteProvider(fresh.id));
        }
        if (mounted) await _maybeSendOn(fresh);
      } catch (_) {
        // Shown on screen by the provider's error state.
      }
    });
  }

  /// The assignment we already asked to move, so we ask once per mechanic.
  DateTime? _nudged;

  /// After 5 minutes with no answer, ask for the request to go to the next
  /// free mechanic. The owner does nothing; the server checks the time.
  Future<void> _maybeSendOn(OwnerRequest? r) async {
    if (r == null ||
        r.accepted ||
        r.providerId == null ||
        r.rematchCount >= 3 ||
        _nudged == r.waitingSince ||
        DateTime.now().difference(r.waitingSince) <
            RequestStatusScreen.suggestOthersAfter) {
      return;
    }
    _nudged = r.waitingSince;
    try {
      final moved = await ref.read(repositoryProvider).nudgeRequest(r.id);
      if (moved && mounted) ref.invalidate(openRequestProvider);
    } catch (_) {
      // The owner can still call or pick someone else themselves.
    }
  }

  @override
  void dispose() {
    poll?.cancel();
    super.dispose();
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _call(OwnerRequest r) async {
    ref
        .read(repositoryProvider)
        .logContact(r.providerId!, ContactKind.callTap)
        .catchError((_) {});
    bool opened;
    try {
      opened = await ref.read(dialerProvider)(r.providerPhone!);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      _say('Could not open the dialer. Call ${r.providerPhone}');
    }
  }

  void _others() =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const BrowseScreen()));

  Future<void> _done(OwnerRequest r) async {
    final navigator = Navigator.of(context);
    setState(() => cancelling = true);
    try {
      await ref.read(repositoryProvider).markJobDone(r.id);
      ref.read(requestVersionProvider.notifier).bump();
      navigator.popUntil((route) => route.isFirst);
    } catch (_) {
      if (mounted) {
        _say('Could not save that. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => cancelling = false);
    }
  }

  Future<void> _cancel(OwnerRequest r) async {
    final navigator = Navigator.of(context);
    setState(() => cancelling = true);
    try {
      await ref.read(repositoryProvider).cancelRequest(r.id);
      ref.read(requestVersionProvider.notifier).bump();
      navigator.popUntil((route) => route.isFirst);
    } catch (_) {
      if (mounted) {
        _say('Could not cancel. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(openRequestProvider);
    return Scaffold(
      appBar: AppBar(),
      body: ContentWidth(
        child: !state.hasValue
            ? state.hasError
                  ? _Empty(
                      title: 'Could not load your request',
                      body: 'Check your connection and try again.',
                      action: BigButton(
                        label: 'Try again',
                        kind: ButtonKind.tint,
                        onPressed: () => ref.invalidate(openRequestProvider),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator())
            : _body(state.value),
      ),
    );
  }

  Widget _body(OwnerRequest? r) {
    if (r == null) {
      return _Empty(
        title: 'No open request',
        body: 'When you request a mechanic, you can follow it here.',
        action: BigButton(
          label: 'Back to home',
          kind: ButtonKind.tint,
          onPressed: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      );
    }
    final cancel = TextButton(
      key: const Key('cancel-request'),
      style: TextButton.styleFrom(foregroundColor: danger),
      onPressed: cancelling ? null : () => _cancel(r),
      child: const Text('Cancel request'),
    );

    if (r.passed) {
      return _layout(
        title: 'They can\'t take it',
        subtitle: r.wasResent
            ? 'We tried ${r.rematchCount + 1} mechanics and none is free right now.'
            : 'No other mechanic nearby is free right now.',
        badge: const _Badge(icon: Icons.swap_horiz_rounded),
        children: [
          BigButton(
            key: const Key('status-others'),
            label: 'See other mechanics nearby',
            onPressed: _others,
          ),
          cancel,
        ],
      );
    }

    final name = r.providerName ?? 'The mechanic';
    if (r.accepted) {
      final at = r.respondedAt == null
          ? ''
          : ' at ${clockText(r.respondedAt!)}';
      return _layout(
        title: 'Request accepted',
        subtitle: '$name accepted your request$at.',
        badge: const _Badge(icon: Icons.check_rounded, strong: true),
        children: [
          const Text(
            'Call to agree where to meet. If they send a quote, it shows here. '
            'You pay the mechanic directly for now; paying in the app comes later.',
            style: TextStyle(color: muted, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 16),
          _QuoteCard(requestId: r.id, mechanic: name),
          BigButton(
            key: const Key('status-call'),
            label: 'Call $name',
            icon: Icons.call,
            onPressed: () => _call(r),
          ),
          TextButton(
            key: const Key('status-done'),
            onPressed: cancelling ? null : () => _done(r),
            child: const Text('The work is done'),
          ),
          _ProblemSection(requestId: r.id, mechanic: name),
          cancel,
        ],
      );
    }

    final waited = DateTime.now().difference(r.waitingSince);
    final late = waited >= RequestStatusScreen.suggestOthersAfter;
    final sent = [
      if (r.hasNote) 'note',
      if (r.hasPhoto) 'photo',
      if (r.hasVoice) 'voice note',
    ].join(', ');
    return _layout(
      title: 'Waiting for confirmation',
      subtitle: switch (r.handoff) {
        Handoff.passed =>
          'The last mechanic couldn\'t take it, so we sent your request to $name.',
        Handoff.noAnswer =>
          'The last mechanic didn\'t answer, so we sent your request to $name.',
        Handoff.first => '$name has your request.',
      },
      badge: const _Badge(icon: Icons.schedule_rounded),
      children: [
        _Step(
          done: true,
          title: 'Request sent',
          note: sent.isEmpty
              ? clockText(r.createdAt)
              : '${clockText(r.createdAt)} · with your $sent',
        ),
        if (r.wasResent)
          _Step(
            done: true,
            title: 'Sent to $name',
            note: clockText(r.waitingSince),
          ),
        _Step(
          done: false,
          title: 'Mechanic accepts',
          note: late
              ? 'No answer yet. Try calling, or call someone else.'
              : 'This screen updates by itself.',
        ),
        const SizedBox(height: 16),
        BigButton(
          key: const Key('status-call'),
          label: 'Call $name now',
          icon: Icons.call,
          kind: ButtonKind.forest,
          onPressed: () => _call(r),
        ),
        const SizedBox(height: 10),
        // After five minutes this becomes the main action.
        BigButton(
          key: const Key('status-others'),
          label: 'Call someone else',
          kind: late ? ButtonKind.lime : ButtonKind.tint,
          onPressed: _others,
        ),
        cancel,
      ],
    );
  }

  Widget _layout({
    required String title,
    required String subtitle,
    required Widget badge,
    required List<Widget> children,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        ScreenTitle(title, subtitle: Text(subtitle)),
        const SizedBox(height: 20),
        Center(child: badge),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, this.strong = false});
  final IconData icon;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        color: strong ? const Color(0x1F135C37) : const Color(0x59D8F27E),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: strong ? forest : lime,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 36, color: strong ? lime : forest),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.done, required this.title, required this.note});
  final bool done;
  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: done ? forest : const Color(0xFF7C8782),
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(note, style: const TextStyle(color: muted, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.body, required this.action});
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenTitle(title, subtitle: Text(body)),
          const SizedBox(height: 20),
          action,
        ],
      ),
    );
  }
}

/// The mechanic's quote, with Approve and Decline while it waits.
class _QuoteCard extends ConsumerStatefulWidget {
  const _QuoteCard({required this.requestId, required this.mechanic});
  final String requestId;
  final String mechanic;

  @override
  ConsumerState<_QuoteCard> createState() => _QuoteCardState();
}

class _QuoteCardState extends ConsumerState<_QuoteCard> {
  bool busy = false;

  Future<void> _answer(Quote q, bool approve) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      await ref.read(repositoryProvider).respondToQuote(q.id, approve: approve);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? 'Approved. ${widget.mechanic} can go ahead.'
                : 'Declined. ${widget.mechanic} can send a new quote.',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'That did not go through. Check your connection and try again.',
          ),
        ),
      );
    } finally {
      ref.invalidate(quoteProvider(widget.requestId));
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(quoteProvider(widget.requestId)).value;
    if (q == null) return const SizedBox.shrink();
    return Card(
      key: const Key('owner-quote'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              switch (q.status) {
                QuoteStatus.approved => 'You approved this quote',
                QuoteStatus.declined => 'You declined this quote',
                _ => 'Quote from ${widget.mechanic}',
              },
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            QuoteLines(q),
            if (q.waiting) ...[
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('quote-approve'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: busy ? null : () => _answer(q, true),
                child: Text('Approve ${q.totalText}'),
              ),
              TextButton(
                key: const Key('quote-decline'),
                onPressed: busy ? null : () => _answer(q, false),
                child: const Text('Decline'),
              ),
            ] else if (q.status == QuoteStatus.declined)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Call the mechanic to talk it through. They can send a new quote.',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// While a job is under way: "Report a problem", or what happened to the
/// report the owner already sent.
class _ProblemSection extends ConsumerWidget {
  const _ProblemSection({required this.requestId, required this.mechanic});
  final String requestId;
  final String mechanic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(complaintProvider(requestId));
    if (!state.hasValue) return const SizedBox.shrink();
    final c = state.value;
    if (c != null) return OwnerComplaintCard(c, mechanic: mechanic);
    return TextButton(
      key: const Key('status-report'),
      style: TextButton.styleFrom(foregroundColor: muted),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final sent = await showReportProblem(
          context,
          requestId: requestId,
          mechanic: mechanic,
        );
        if (sent) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Report sent. The outcome will show here.'),
            ),
          );
        }
      },
      child: const Text('Report a problem'),
    );
  }
}
