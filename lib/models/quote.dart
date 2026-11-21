/// An itemised quote a mechanic sends on a job they took.
library;

import 'trade.dart' show kes;

enum QuoteStatus {
  sent,
  approved,
  declined,
  withdrawn;

  static QuoteStatus fromName(String? n) =>
      values.firstWhere((v) => v.name == n, orElse: () => sent);
}

enum QuoteLineKind {
  labour('Labour'),
  part('Part'),
  other('Other');

  const QuoteLineKind(this.label);
  final String label;

  static QuoteLineKind fromName(String? n) =>
      values.firstWhere((v) => v.name == n, orElse: () => other);
}

class QuoteLine {
  const QuoteLine({
    required this.kind,
    required this.description,
    required this.unitPriceKes,
    this.qty = 1,
  });
  final QuoteLineKind kind;
  final String description;
  final int qty;
  final int unitPriceKes;

  int get totalKes => qty * unitPriceKes;

  /// "2 × Front brake pads" or "Replace brake pads".
  String get text => qty == 1 ? description : '$qty × $description';

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'description': description,
    'qty': qty,
    'unit_price_kes': unitPriceKes,
  };

  factory QuoteLine.fromRow(Map<String, dynamic> r) => QuoteLine(
    kind: QuoteLineKind.fromName(r['kind'] as String?),
    description: r['description'] as String,
    qty: (r['qty'] as num).toInt(),
    unitPriceKes: (r['unit_price_kes'] as num).toInt(),
  );
}

class Quote {
  const Quote({
    required this.id,
    required this.requestId,
    required this.status,
    required this.totalKes,
    required this.createdAt,
    required this.lines,
    this.note,
  });
  final String id;
  final String requestId;
  final QuoteStatus status;
  final int totalKes;
  final DateTime createdAt;
  final List<QuoteLine> lines;
  final String? note;

  bool get waiting => status == QuoteStatus.sent;

  String get totalText => kes(totalKes);

  Quote withStatus(QuoteStatus s) => Quote(
    id: id,
    requestId: requestId,
    status: s,
    totalKes: totalKes,
    createdAt: createdAt,
    lines: lines,
    note: note,
  );

  /// Columns to select from `quotes` (with its lines) for [Quote.fromRow].
  static const columns =
      'id, request_id, status, note, total_kes, created_at, '
      'quote_lines(position, kind, description, qty, unit_price_kes)';

  factory Quote.fromRow(Map<String, dynamic> r) {
    final lines = [...(r['quote_lines'] as List? ?? const [])]
      ..sort((a, b) => (a['position'] as num).compareTo(b['position'] as num));
    return Quote(
      id: r['id'] as String,
      requestId: r['request_id'] as String,
      status: QuoteStatus.fromName(r['status'] as String?),
      totalKes: (r['total_kes'] as num).toInt(),
      note: r['note'] as String?,
      createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      lines: [
        for (final l in lines) QuoteLine.fromRow(l as Map<String, dynamic>),
      ],
    );
  }

  /// Builds a quote in sample mode, the way the database would.
  factory Quote.draft({
    required String id,
    required String requestId,
    required List<QuoteLine> lines,
    String? note,
  }) => Quote(
    id: id,
    requestId: requestId,
    status: QuoteStatus.sent,
    totalKes: lines.fold(0, (sum, l) => sum + l.totalKes),
    createdAt: DateTime.now(),
    lines: lines,
    note: (note == null || note.trim().isEmpty) ? null : note.trim(),
  );
}
