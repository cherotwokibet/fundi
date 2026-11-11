import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/service_provider.dart';
import '../state/app_state.dart';
import 'location_bar.dart';
import 'provider_card.dart';

enum _Filter { all, mobile, garage }

/// "Browse and Call": nearby verified mechanics, one tap to call. No sign-up.
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _State();
}

class _State extends ConsumerState<BrowseScreen> {
  _Filter filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final nearby = ref.watch(nearbyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mechanics near you')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: LocationBar(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (f, label) in const [
                  (_Filter.all, 'All'),
                  (_Filter.mobile, 'Comes to you'),
                  (_Filter.garage, 'Garages'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: filter == f,
                    onSelected: (_) => setState(() => filter = f),
                  ),
              ],
            ),
          ),
          Expanded(
            child: nearby.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _Message(
                icon: Icons.wifi_off,
                title: 'Could not load mechanics',
                body: 'Check your connection and try again.',
                action: FilledButton(
                  onPressed: () => ref.invalidate(nearbyProvider),
                  child: const Text('Try again'),
                ),
              ),
              data: (all) {
                final list = all
                    .where(
                      (p) => switch (filter) {
                        _Filter.all => true,
                        _Filter.mobile => p.type == ProviderType.mobileMechanic,
                        _Filter.garage => p.type == ProviderType.garage,
                      },
                    )
                    .toList();
                if (list.isEmpty) {
                  return const _Message(
                    icon: Icons.search_off,
                    title: 'No verified mechanics here yet',
                    body: 'We only show mechanics we have verified. Try another area using Change above.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(nearbyProvider.future),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => ProviderCard(list[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
