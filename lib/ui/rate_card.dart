import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/provider_repository.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// On the home screen after a finished job: "How did they do?" One tap on a
/// star, an optional comment, Send. Easy to skip; it never blocks anything.
class RateCard extends ConsumerStatefulWidget {
  const RateCard({super.key});

  @override
  ConsumerState<RateCard> createState() => _RateCardState();
}

class _RateCardState extends ConsumerState<RateCard> {
  /// Skipped for now: hidden until the app is opened again.
  bool skipped = false;

  /// The stars just sent, to say thanks in place of the card.
  int? sent;

  Future<void> _rate(ReviewDue due, int stars) async {
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RateSheet(due: due, stars: stars),
    );
    if (result != null && mounted) {
      setState(() => sent = result);
      ref.invalidate(reviewDueProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (sent != null) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text(
          'Thank you. Your rating helps other car owners.',
          key: Key('rate-thanks'),
          style: TextStyle(color: muted),
        ),
      );
    }
    final due = ref.watch(reviewDueProvider).value;
    if (due == null || skipped) return const SizedBox.shrink();
    return Card(
      key: const Key('rate-card'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'How did ${due.providerName} do?',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('rate-skip'),
                  onPressed: () => setState(() => skipped = true),
                  child: const Text('Not now'),
                ),
              ],
            ),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    key: Key('star-$i'),
                    tooltip: '$i ${i == 1 ? 'star' : 'stars'}',
                    onPressed: () => _rate(due, i),
                    icon: const Icon(Icons.star_border_rounded, size: 32),
                    color: forest,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RateSheet extends ConsumerStatefulWidget {
  const _RateSheet({required this.due, required this.stars});
  final ReviewDue due;
  final int stars;

  @override
  ConsumerState<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends ConsumerState<_RateSheet> {
  late int stars = widget.stars;
  final comment = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(repositoryProvider)
          .leaveReview(
            widget.due.requestId,
            stars,
            comment: comment.text.trim().isEmpty ? null : comment.text.trim(),
          );
      if (mounted) Navigator.pop(context, stars);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'That did not send. Try again in a moment.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          Text('Rate ${widget.due.providerName}', style: heading(22)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  key: Key('sheet-star-$i'),
                  onPressed: () => setState(() => stars = i),
                  icon: Icon(
                    i <= stars ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 36,
                  ),
                  color: forest,
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('rate-comment'),
            controller: comment,
            maxLength: 300,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              labelText: 'Anything to add? (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          if (error != null)
            Text(error!, style: const TextStyle(color: danger)),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('rate-send'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: busy ? null : _send,
            child: const Text('Send rating'),
          ),
        ],
      ),
    );
  }
}
