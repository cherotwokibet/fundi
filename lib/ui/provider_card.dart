import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/provider_repository.dart';
import '../models/service_provider.dart';
import '../state/app_state.dart';
import 'provider_detail_screen.dart';
import 'theme.dart';
import 'widgets.dart';

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

/// Kept for the profile screen: the status pill without freshness.
class AvailabilityPill extends StatelessWidget {
  const AvailabilityPill(this.availability, {super.key});
  final Availability availability;

  @override
  Widget build(BuildContext context) => StatusPill(availability);
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

/// Only what helps an owner choose, plus Call. Calling is never blocked,
/// whatever the mechanic's status.
class ProviderCard extends ConsumerWidget {
  const ProviderCard(this.provider, {super.key, this.quietCall = false});
  final ServiceProvider provider;

  /// True when another button on the screen is the main action.
  final bool quietCall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = provider;
    final fee = feeParts(p);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ProviderDetailScreen(p)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusPill(p.availability, setAt: p.availabilitySetAt),
              const SizedBox(height: 10),
              Text(p.name, style: heading(20)),
              const SizedBox(height: 3),
              Text(
                '${p.isMobile ? 'Comes to you' : 'Garage'} · ${p.area} · ${p.distanceKm} km',
                style: const TextStyle(color: muted, fontSize: 14),
              ),
              const SizedBox(height: 10),
              CheckedLine(p),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: hairline),
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fee.amount,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        Text(
                          fee.covers,
                          style: const TextStyle(color: muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    key: Key('call-${p.id}'),
                    style: FilledButton.styleFrom(
                      backgroundColor: quietCall ? Colors.white : forest,
                      foregroundColor: quietCall ? forest : Colors.white,
                      minimumSize: const Size(104, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: quietCall
                            ? const BorderSide(color: forest, width: 1.5)
                            : BorderSide.none,
                      ),
                    ),
                    onPressed: () => callProvider(context, ref, p),
                    icon: const Icon(Icons.call, size: 20),
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
