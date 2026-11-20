import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account_repository.dart';
import '../models/quote.dart';
import '../models/trade.dart' show kes;
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// The lines of a quote and its total, as both sides see it.
class QuoteLines extends StatelessWidget {
  const QuoteLines(this.quote, {super.key});
  final Quote quote;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in quote.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: l.text),
                        TextSpan(
                          text: '  ${l.kind.label}',
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(kes(l.totalKes)),
              ],
            ),
          ),
        const Divider(),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Total',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            Text(
              quote.totalText,
              key: const Key('quote-total'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ],
        ),
        if (quote.note != null) ...[
          const SizedBox(height: 6),
          Text(
            '"${quote.note}"',
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }
}

class _LineDraft {
  _LineDraft({this.kind = QuoteLineKind.labour});
  QuoteLineKind kind;
  final description = TextEditingController();
  final qty = TextEditingController(text: '1');
  final price = TextEditingController();

  void dispose() {
    description.dispose();
    qty.dispose();
    price.dispose();
  }

  int get qtyValue => int.tryParse(qty.text.trim()) ?? 0;
  int get priceValue => int.tryParse(price.text.trim()) ?? -1;
}

/// The mechanic writes a quote: a few lines of labour and parts, and a total.
class QuoteFormScreen extends ConsumerStatefulWidget {
  const QuoteFormScreen({super.key, required this.requestId});
  final String requestId;

  @override
  ConsumerState<QuoteFormScreen> createState() => _QuoteFormState();
}

class _QuoteFormState extends ConsumerState<QuoteFormScreen> {
  final lines = [_LineDraft(), _LineDraft(kind: QuoteLineKind.part)];
  final note = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    for (final l in lines) {
      l.dispose();
    }
    note.dispose();
    super.dispose();
  }

  /// Lines with something typed in them.
  List<_LineDraft> get _filled => [
    for (final l in lines)
      if (l.description.text.trim().isNotEmpty ||
          l.price.text.trim().isNotEmpty)
        l,
  ];

  int get _total => _filled.fold(
    0,
    (sum, l) => sum + (l.priceValue < 0 ? 0 : l.priceValue * l.qtyValue),
  );

  Future<void> _send() async {
    final filled = _filled;
    String? problem;
    if (filled.isEmpty) problem = 'Add at least one line.';
    for (final l in filled) {
      if (l.description.text.trim().length < 2) {
        problem = 'Say what each line is for.';
      } else if (l.qtyValue < 1 || l.qtyValue > 100) {
        problem = 'Quantities go from 1 to 100.';
      } else if (l.priceValue < 0) {
        problem = 'Enter a price for each line (0 is fine).';
      }
    }
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(inboxRepositoryProvider).sendQuote(widget.requestId, [
        for (final l in filled)
          QuoteLine(
            kind: l.kind,
            description: l.description.text.trim(),
            qty: l.qtyValue,
            unitPriceKes: l.priceValue,
          ),
      ], note: note.text.trim().isEmpty ? null : note.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is AccountException
              ? e.message
              : 'The quote did not send. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Scaffold(
      appBar: AppBar(title: const Text('Send a quote')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const Text(
              'List the work and parts with prices. The owner sees the total and taps '
              'Approve or Decline. Sending a new quote replaces one they have not answered.',
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < lines.length; i++)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final k in QuoteLineKind.values)
                            ChoiceChip(
                              key: Key('line-$i-kind-${k.name}'),
                              label: Text(k.label),
                              selected: lines[i].kind == k,
                              onSelected: (_) =>
                                  setState(() => lines[i].kind = k),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: Key('line-$i-description'),
                        controller: lines[i].description,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: lines[i].kind == QuoteLineKind.part
                              ? 'Part'
                              : 'What you will do',
                          hintText: lines[i].kind == QuoteLineKind.part
                              ? 'Front brake pads'
                              : 'Replace front brake pads',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          SizedBox(
                            width: 90,
                            child: TextField(
                              key: Key('line-$i-qty'),
                              controller: lines[i].qty,
                              keyboardType: TextInputType.number,
                              inputFormatters: digits,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'How many',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              key: Key('line-$i-price'),
                              controller: lines[i].price,
                              keyboardType: TextInputType.number,
                              inputFormatters: digits,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Price each, KES',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          if (lines.length > 1)
                            IconButton(
                              key: Key('line-$i-remove'),
                              tooltip: 'Remove line',
                              onPressed: () =>
                                  setState(() => lines.removeAt(i).dispose()),
                              icon: const Icon(Icons.close),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (lines.length < 20)
              OutlinedButton.icon(
                key: const Key('line-add'),
                onPressed: () => setState(() => lines.add(_LineDraft())),
                icon: const Icon(Icons.add),
                label: const Text('Add a line'),
              ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('quote-note'),
              controller: note,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Note to the owner (optional)',
                hintText: 'The pads are worn down to the metal',
                border: OutlineInputBorder(),
              ),
            ),
            Text(
              'Total ${kes(_total)}',
              key: const Key('quote-form-total'),
              style: heading(22),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: danger)),
              ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('quote-send'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: busy ? null : _send,
              child: const Text('Send the quote'),
            ),
          ],
        ),
      ),
    );
  }
}
