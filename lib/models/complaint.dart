enum ComplaintStatus { open, upheld, rejected }

enum RefundStatus { none, due, paid }

/// An owner's report that something went wrong with a job, and what Fundi
/// decided. The rules (who can raise, reply, decide, and the refund cap) are
/// in the database.
class Complaint {
  const Complaint({
    required this.id,
    required this.requestId,
    required this.message,
    required this.createdAt,
    this.wantsRefund = false,
    this.refundPhone,
    this.status = ComplaintStatus.open,
    this.providerReply,
    this.adminNote,
    this.refundKes = 0,
    this.refundStatus = RefundStatus.none,
    this.refundReference,
    this.providerName,
    this.providerPhone,
    this.jobCostKes,
  });

  final String id;
  final String requestId;
  final String message;
  final DateTime createdAt;
  final bool wantsRefund;

  /// Where the refund goes (2547XXXXXXXX). Only in the admin's list.
  final String? refundPhone;
  final ComplaintStatus status;
  final String? providerReply;
  final String? adminNote;
  final int refundKes;
  final RefundStatus refundStatus;
  final String? refundReference;

  /// Only in the admin's list.
  final String? providerName;
  final String? providerPhone;

  /// What the job cost: the most a refund can be. Admin's list only.
  final int? jobCostKes;

  bool get open => status == ComplaintStatus.open;

  /// Still needs an admin: to decide, or to pay back the refund.
  bool get needsAdmin => open || refundStatus == RefundStatus.due;

  static const columns =
      'id, request_id, message, wants_refund, provider_reply, status, '
      'admin_note, refund_kes, refund_status, refund_reference, created_at';

  factory Complaint.fromRow(Map<String, dynamic> r) => Complaint(
    id: r['id'] as String,
    requestId: r['request_id'] as String,
    message: r['message'] as String,
    createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
    wantsRefund: r['wants_refund'] as bool? ?? false,
    refundPhone: r['refund_phone'] as String?,
    status: ComplaintStatus.values.byName(r['status'] as String),
    providerReply: r['provider_reply'] as String?,
    adminNote: r['admin_note'] as String?,
    refundKes: (r['refund_kes'] as num?)?.toInt() ?? 0,
    refundStatus: RefundStatus.values.byName(r['refund_status'] as String),
    refundReference: r['refund_reference'] as String?,
    providerName: r['provider_name'] as String?,
    providerPhone: r['provider_phone'] as String?,
    jobCostKes: (r['job_cost_kes'] as num?)?.toInt(),
  );

  Complaint copyWith({
    ComplaintStatus? status,
    String? providerReply,
    String? adminNote,
    int? refundKes,
    RefundStatus? refundStatus,
    String? refundReference,
  }) => Complaint(
    id: id,
    requestId: requestId,
    message: message,
    createdAt: createdAt,
    wantsRefund: wantsRefund,
    refundPhone: refundPhone,
    status: status ?? this.status,
    providerReply: providerReply ?? this.providerReply,
    adminNote: adminNote ?? this.adminNote,
    refundKes: refundKes ?? this.refundKes,
    refundStatus: refundStatus ?? this.refundStatus,
    refundReference: refundReference ?? this.refundReference,
    providerName: providerName,
    providerPhone: providerPhone,
    jobCostKes: jobCostKes,
  );
}

/// The owner's latest finished job, for "Report a problem" on the home screen.
typedef LastJob = ({String requestId, String providerName, DateTime doneAt});
