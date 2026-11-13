import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/account_repository.dart';
import '../data/admin_repository.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Admin console: check each application, then approve or pause it.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _State();
}

class _State extends ConsumerState<AdminScreen> {
  ListingStatus tab = ListingStatus.pending;
  late Future<List<AdminListing>> rows = _load();

  Future<List<AdminListing>> _load() => ref.read(adminProvider).listings(tab);

  void _reload() {
    final next = _load();
    setState(() {
      rows = next;
    });
  }

  Future<void> _do(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      // Owners see approvals at once.
      ref.invalidate(nearbyProvider);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is AccountException ? e.message : 'That did not save. Try again.',
          ),
        ),
      );
    }
    if (mounted) _reload();
  }

  Future<void> _view(String path) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await ref.read(adminProvider).documentUrl(path);
      if (url.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Sample mode: there is no real file to open.'),
          ),
        );
        return;
      }
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the document.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification'),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(accountProvider).signOut();
              ref.read(accountVersionProvider.notifier).bump();
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: ContentWidth(
        max: 900,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SegmentedButton<ListingStatus>(
                segments: const [
                  ButtonSegment(
                    value: ListingStatus.pending,
                    label: Text('Waiting'),
                  ),
                  ButtonSegment(
                    value: ListingStatus.approved,
                    label: Text('Live'),
                  ),
                  ButtonSegment(
                    value: ListingStatus.suspended,
                    label: Text('Paused'),
                  ),
                ],
                selected: {tab},
                onSelectionChanged: (s) {
                  tab = s.first;
                  _reload();
                },
              ),
            ),
            Expanded(
              child: FutureBuilder<List<AdminListing>>(
                future: rows,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Could not load applications.'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _reload,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    );
                  }
                  final list = snap.data!;
                  if (list.isEmpty) {
                    return Center(
                      child: Text(switch (tab) {
                        ListingStatus.pending => 'No applications are waiting.',
                        ListingStatus.approved => 'No providers are live yet.',
                        ListingStatus.suspended => 'No providers are paused.',
                      }),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _card(list[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(AdminListing l) {
    final admin = ref.read(adminProvider);
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              '${l.type.name == 'garage' ? 'Garage' : 'Mobile mechanic'} · ${l.area} · ${l.phone}',
              style: TextStyle(color: grey, fontSize: 13),
            ),
            const SizedBox(height: 10),
            const Text(
              'Documents',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            if (l.documents.isEmpty)
              Text('Nothing uploaded yet.', style: TextStyle(color: grey)),
            Wrap(
              spacing: 8,
              children: [
                for (final d in l.documents.entries)
                  ActionChip(
                    avatar: const Icon(Icons.description_outlined, size: 18),
                    label: Text(d.key.label),
                    onPressed: () => _view(d.value),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Checks', style: TextStyle(fontWeight: FontWeight.w600)),
            for (final k in l.applicableChecks)
              CheckboxListTile(
                key: Key('check-${l.id}-${k.name}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(k.title),
                subtitle: Text(k.explanation),
                value: l.checksPassed.contains(k),
                onChanged: (v) =>
                    _do(() => admin.setCheck(l.id, k, v ?? false)),
              ),
            const SizedBox(height: 8),
            if (l.status != ListingStatus.approved) ...[
              FilledButton(
                key: Key('approve-${l.id}'),
                onPressed: l.canApprove
                    ? () => _do(
                        () => admin.setStatus(l.id, ListingStatus.approved),
                      )
                    : null,
                child: const Text('Approve and go live'),
              ),
              if (!l.canApprove)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Pass the identity check first.',
                    style: TextStyle(color: grey, fontSize: 13),
                  ),
                ),
            ] else
              OutlinedButton(
                key: Key('pause-${l.id}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () =>
                    _do(() => admin.setStatus(l.id, ListingStatus.suspended)),
                child: const Text('Pause this listing'),
              ),
            if (l.status == ListingStatus.suspended)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Paused listings are hidden from owners.',
                  style: TextStyle(fontSize: 13, color: brandGreen),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
