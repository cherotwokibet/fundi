import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/provider_repository.dart';
import '../models/complaint.dart';
import '../models/trade.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// "Report a problem": the owner says what went wrong in their own words and
/// can ask for their money back. Nothing else to fill in, no sign-up.
/// True when the report was sent.
Future<bool> showReportProblem(
  BuildContext context, {
  required String requestId,
  required String mechanic,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReportSheet(requestId: requestId, mechanic: mechanic),
  );
  return sent == true;
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.requestId, required this.mechanic});
  final String requestId;
  final String mechanic;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final message = TextEditingController();
  final phone = TextEditingController();
  bool refund = false;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    message.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = message.text.trim();
    if (text.length < 10) {
      setState(() => error = 'Say in a few words what went wrong.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(repositoryProvider)
          .raiseComplaint(
            widget.requestId,
            text,
            wantsRefund: refund,
            refundPhone: refund ? phone.text.trim() : null,
          );
      ref.invalidate(complaintProvider(widget.requestId));
      if (mounted) Navigator.pop(context, true);
    } on ComplaintException catch (e) {
      if (mounted) setState(() => error = e.message);
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Report a problem', style: heading(22)),
            const SizedBox(height: 4),
            Text(
              'Tell us what went wrong with the work by ${widget.mechanic}. '
              'They can answer, then Fundi decides.',
              style: const TextStyle(color: muted, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('complaint-message'),
              controller: message,
              maxLength: 500,
              maxLines: 4,
              minLines: 2,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'What went wrong?',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              key: const Key('complaint-refund'),
              contentPadding: EdgeInsets.zero,
              title: const Text('I want my money back'),
              value: refund,
              onChanged: (v) => setState(() => refund = v),
            ),
            if (refund)
              TextField(
                key: const Key('complaint-phone'),
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'M-Pesa number for the refund',
                  hintText: '0712 345 678',
                  helperText: 'Only Fundi sees this number.',
                  border: OutlineInputBorder(),
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: danger)),
              ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('complaint-send'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: busy ? null : _send,
              child: const Text('Send report'),
            ),
          ],
        ),
      ),
    );
  }
}

/// What happened to the owner's report, in plain words.
class OwnerComplaintCard extends StatelessWidget {
  const OwnerComplaintCard(this.complaint, {super.key, required this.mechanic});
  final Complaint complaint;
  final String mechanic;

  @override
  Widget build(BuildContext context) {
    final c = complaint;
    final (title, body) = switch (c.status) {
      ComplaintStatus.open => (
        'We got your report',
        c.providerReply == null
            ? '$mechanic can answer, then Fundi decides. The outcome shows here.'
            : '$mechanic answered: "${c.providerReply}". Fundi will decide and the outcome shows here.',
      ),
      ComplaintStatus.upheld => (
        'Fundi agreed with you',
        switch (c.refundStatus) {
          RefundStatus.due =>
            'You get ${kes(c.refundKes)} back by M-Pesa. ${c.adminNote ?? ''}',
          RefundStatus.paid =>
            '${kes(c.refundKes)} was sent to you by M-Pesa (code ${c.refundReference}). ${c.adminNote ?? ''}',
          RefundStatus.none => c.adminNote ?? '',
        },
      ),
      ComplaintStatus.rejected => (
        'Fundi looked at your report',
        c.adminNote ?? '',
      ),
    };
    return Card(
      key: const Key('owner-complaint'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              body.trim(),
              style: const TextStyle(color: muted, fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// On the home screen, for the owner's last finished job: their report's
/// outcome if they sent one, or a small "Problem with the work?" link for
/// 14 days. Never in the way of the two main actions.
class LastJobProblem extends ConsumerWidget {
  const LastJobProblem({super.key});

  static const reportWithin = Duration(days: 14);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(lastJobProvider).value;
    if (job == null) return const SizedBox.shrink();
    final complaint = ref.watch(complaintProvider(job.requestId));
    if (!complaint.hasValue) return const SizedBox.shrink();
    final c = complaint.value;
    if (c != null) return OwnerComplaintCard(c, mechanic: job.providerName);
    if (DateTime.now().difference(job.doneAt) > reportWithin) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const Key('report-last-job'),
        style: TextButton.styleFrom(foregroundColor: muted),
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          final sent = await showReportProblem(
            context,
            requestId: job.requestId,
            mechanic: job.providerName,
          );
          if (sent) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Report sent. The outcome will show here.'),
              ),
            );
          }
        },
        icon: const Icon(Icons.flag_outlined, size: 18),
        label: Text('Problem with the work by ${job.providerName}?'),
      ),
    );
  }
}
