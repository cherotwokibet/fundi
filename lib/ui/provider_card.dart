import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/provider_repository.dart';
import '../models/service_provider.dart';
import '../state/app_state.dart';
import 'provider_detail_screen.dart';
import 'theme.dart';

/// Logs the tap, opens the phone dialer, then asks one question afterwards.
Future<void> callProvider(
  BuildContext context,
  WidgetRef ref,
  ServiceProvider p,
) async {
  final repo = ref.read(repositoryProvider);
  final area = ref.read(locationProvider).value?.label;
  // Logging must never block or break the call.
  repo.logContact(p.id, ContactKind.callTap, area: area).catchError((_) {});
  final messenger = ScaffoldMessenger.of(context);
  bool opened;
  try {
    opened = await ref.read(dialerProvider)(p.phone);
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Could not open the dialer. Call ${p.phone}'),
        duration: const Duration(seconds: 8),
      ),
    );
    return;
  }
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 20),
      content: Text('Did ${p.name} help?'),
      action: SnackBarAction(
        label: 'YES',
        onPressed: () => repo
            .logContact(p.id, ContactKind.callHelped, area: area)
            .catchError((_) {}),
      ),
    ),
  );
}

class AvailabilityPill extends StatelessWidget {
  const AvailabilityPill(this.availability, {super.key});
  final Availability availability;

  @override
  Widget build(BuildContext context) {
    final c = availability.color;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            availability.label,
            style: TextStyle(
              color: c,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified, size: 16, color: brandGreen),
        SizedBox(width: 4),
        Text(
          'Verified',
          style: TextStyle(
            color: brandGreen,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class ProviderAvatar extends StatelessWidget {
  const ProviderAvatar(this.provider, {super.key, this.radius = 26});
  final ServiceProvider provider;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE2EFEA),
      foregroundImage: provider.photoUrl == null
          ? null
          : NetworkImage(provider.photoUrl!),
      child: Icon(
        provider.isMobile ? Icons.build_outlined : Icons.garage_outlined,
        color: brandGreen,
        size: radius,
      ),
    );
  }
}

/// Only what helps an owner choose, plus one big Call button.
class ProviderCard extends ConsumerWidget {
  const ProviderCard(this.provider, {super.key});
  final ServiceProvider provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = provider;
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => ProviderDetailScreen(p))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProviderAvatar(p),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${p.isMobile ? 'Comes to you' : 'Garage'} · ${p.area} · ${p.distanceKm} km',
                          style: TextStyle(color: grey, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            const VerifiedBadge(),
                            if (p.ratingCount > 0)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    size: 16,
                                    color: Color(0xFFE0A100),
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${p.ratingAvg} (${p.ratingCount})',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            AvailabilityPill(p.availability),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      feeText(p.calloutFeeKes),
                      style: TextStyle(color: grey, fontSize: 13),
                    ),
                  ),
                  FilledButton.icon(
                    key: Key('call-${p.id}'),
                    style: FilledButton.styleFrom(
                      backgroundColor: callGreen,
                      minimumSize: const Size(120, 48),
                    ),
                    onPressed: () => callProvider(context, ref, p),
                    icon: const Icon(Icons.call),
                    label: const Text('Call'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
