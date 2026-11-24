import 'complaint.dart';

/// Where a request stands, worked out by the database (`admin_requests`).
enum RequestStage {
  noAnswer('no_answer', 'No answer'),
  unassigned('unassigned', 'Nobody yet'),
  waiting('waiting', 'Waiting for answer'),
  taken('taken', 'Taken'),
  priceSent('price_sent', 'Price sent'),
  priceDeclined('price_declined', 'Price declined'),
  working('working', 'Working'),
  done('done', 'Done'),
  cancelled('cancelled', 'Cancelled');

  const RequestStage(this.code, this.label);
  final String code;
  final String label;

  static RequestStage fromCode(String code) =>
      values.firstWhere((s) => s.code == code, orElse: () => taken);

  /// Still open: not done and not cancelled.
  bool get open => this != done && this != cancelled;

  /// Someone should look: nobody has it, or nobody is answering.
  bool get stuck => this == noAnswer || this == unassigned;
}

/// One request as the admin sees it in Live requests.
class AdminRequest {
  const AdminRequest({
    required this.id,
    required this.createdAt,
    required this.stage,
    required this.waitingSince,
    this.area,
    this.note,
    this.carMake,
    this.comeToMe = true,
    this.providerId,
    this.providerName,
    this.providerPhone,
    this.ownerPhone,
    this.handoff = 'first',
    this.rematchCount = 0,
    this.doneAt,
    this.quoteTotalKes,
    this.hasPhoto = false,
    this.hasVoice = false,
    this.complaintStatus,
    this.refundStatus,
  });

  final String id;
  final DateTime createdAt;
  final RequestStage stage;

  /// When the current mechanic got it (or when it was sent).
  final DateTime waitingSince;
  final String? area;
  final String? note;
  final String? carMake;
  final bool comeToMe;
  final String? providerId;
  final String? providerName;
  final String? providerPhone;

  /// Only if the owner gave one. Most owners are guests with no number.
  final String? ownerPhone;

  /// Why the current mechanic has it: first, passed or no_answer.
  final String handoff;
  final int rematchCount;
  final DateTime? doneAt;
  final int? quoteTotalKes;
  final bool hasPhoto;
  final bool hasVoice;
  final ComplaintStatus? complaintStatus;
  final RefundStatus? refundStatus;

  /// Short request reference the admin can read out or search for.
  String get ref => id.replaceAll('-', '').substring(0, 6).toUpperCase();

  /// The owner's words, or a plain stand-in when they wrote nothing.
  String get problem {
    final n = note?.trim() ?? '';
    if (n.isNotEmpty) return n;
    if (hasVoice) return 'Voice note';
    if (hasPhoto) return 'Photo only';
    return 'No note';
  }

  bool get hasComplaint => complaintStatus != null;

  /// Does [query] match the reference, area, note, car or either side?
  bool matches(String query) => adminSearchMatches(
    query,
    texts: [ref, id, area, note, carMake, providerName],
    phones: [providerPhone, ownerPhone],
  );

  factory AdminRequest.fromRow(Map<String, dynamic> r) {
    DateTime? t(String k) =>
        r[k] == null ? null : DateTime.parse(r[k] as String).toLocal();
    return AdminRequest(
      id: r['id'] as String,
      createdAt: t('created_at')!,
      stage: RequestStage.fromCode(r['stage'] as String),
      waitingSince: t('waiting_since') ?? t('created_at')!,
      area: r['area'] as String?,
      note: r['note'] as String?,
      carMake: r['car_make'] as String?,
      comeToMe: r['mode'] != 'visit_garage',
      providerId: r['provider_id'] as String?,
      providerName: r['provider_name'] as String?,
      providerPhone: r['provider_phone'] as String?,
      ownerPhone: r['owner_phone'] as String?,
      handoff: r['handoff'] as String? ?? 'first',
      rematchCount: (r['rematch_count'] as num?)?.toInt() ?? 0,
      doneAt: t('done_at'),
      quoteTotalKes: (r['quote_total_kes'] as num?)?.toInt(),
      hasPhoto: r['has_photo'] as bool? ?? false,
      hasVoice: r['has_voice'] as bool? ?? false,
      complaintStatus: r['complaint_status'] == null
          ? null
          : ComplaintStatus.values.byName(r['complaint_status'] as String),
      refundStatus: r['refund_status'] == null
          ? null
          : RefundStatus.values.byName(r['refund_status'] as String),
    );
  }
}

/// The admin search: words anywhere in [texts], or at least 4 digits of a
/// number in [phones] (0712… and +254712… count as the same number).
bool adminSearchMatches(
  String query, {
  required List<String?> texts,
  List<String?> phones = const [],
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (texts.any((t) => (t ?? '').toLowerCase().contains(q))) return true;
  var digits = q.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('0')) digits = digits.substring(1);
  if (digits.startsWith('254')) digits = digits.substring(3);
  if (digits.length < 4) return false;
  return phones.any(
    (p) => (p ?? '').replaceAll(RegExp(r'\D'), '').contains(digits),
  );
}

/// "6m", "2h 10m", "3d": how long something has been going.
String shortAge(Duration d) {
  if (d.isNegative) return '0m';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) {
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours}h' : '${d.inHours}h ${m}m';
  }
  return '${d.inDays}d';
}
