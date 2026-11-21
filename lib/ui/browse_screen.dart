import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/service_provider.dart';
import '../state/app_state.dart';
import 'location_bar.dart';
import 'provider_card.dart';
import 'theme.dart';
import 'widgets.dart';

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
      appBar: AppBar(),
      body: ContentWidth(
        max: 1040,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: ScreenTitle('Mechanics nearby', subtitle: LocationBar()),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  for (final (f, label) in const [
                    (_Filter.all, 'All'),
                    (_Filter.mobile, 'Comes to you'),
                    (_Filter.garage, 'Garages'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterChip(
                        label: label,
                        selected: filter == f,
                        onTap: () => setState(() => filter = f),
                      ),
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
                          _Filter.mobile =>
                            p.type == ProviderType.mobileMechanic,
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
                    // One column on a phone, two side by side on a wide window.
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final columns = box.maxWidth >= 760 ? 2 : 1;
                        final rows = (list.length / columns).ceil();
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: rows,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, r) {
                            if (columns == 1) return ProviderCard(list[r]);
                            final left = list[r * 2];
                            final right = r * 2 + 1 < list.length
                                ? list[r * 2 + 1]
                                : null;
                            return IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: ProviderCard(left)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: right == null
                                        ? const SizedBox()
                                        : ProviderCard(right),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? forest : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? forest : hairline),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : ink,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
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
