import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/provider_repository.dart';
import '../models/service_provider.dart';
import '../state/app_state.dart';
import 'provider_card.dart';
import 'theme.dart';
import 'widgets.dart';

/// Profile: who they are, exactly what "Verified" covers, and Call.
class ProviderDetailScreen extends ConsumerStatefulWidget {
  const ProviderDetailScreen(this.provider, {super.key});
  final ServiceProvider provider;

  @override
  ConsumerState<ProviderDetailScreen> createState() => _State();
}

class _State extends ConsumerState<ProviderDetailScreen> {
  @override
  void initState() {
    super.initState();
    ref
        .read(repositoryProvider)
        .logContact(widget.provider.id, ContactKind.profileView)
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: ContentWidth(
          max: 640,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: callGreen),
            onPressed: () => callProvider(context, ref, p),
            icon: const Icon(Icons.call),
            label: Text('Call ${p.name}'),
          ),
        ),
      ),
      body: ContentWidth(
        max: 640,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Row(
              children: [
                ProviderAvatar(p, radius: 34),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${p.isMobile ? 'Mobile mechanic' : 'Garage'} · ${p.area} · ${p.distanceKm} km away',
                        style: TextStyle(color: grey),
                      ),
                      const SizedBox(height: 6),
                      AvailabilityPill(p.availability),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _Fact(
              Icons.payments_outlined,
              feeText(p.calloutFeeKes),
              'You approve any repair cost before work starts.',
            ),
            if (p.isMobile)
              _Fact(
                Icons.directions_car_outlined,
                'Comes to you within ${p.serviceRadiusKm.round()} km',
                null,
              ),
            _Fact(
              Icons.star_outline_rounded,
              p.ratingCount == 0
                  ? 'No reviews yet'
                  : '${p.ratingAvg} from ${p.ratingCount} reviews',
              'Reviews come only from jobs recorded on the platform.',
            ),
            _Fact(
              Icons.car_repair_outlined,
              p.makes.isEmpty ? 'Works on all makes' : p.makes.join(', '),
              null,
            ),
            const SizedBox(height: 20),
            const Text(
              'What we verified',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            const SizedBox(height: 8),
            for (final kind in CheckKind.values)
              if (p.checksPassed.contains(kind))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.verified, color: brandGreen),
                  title: Text(
                    kind.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(kind.explanation),
                ),
            const SizedBox(height: 8),
            Text(
              'Verification confirms who the mechanic is. It is not a guarantee of the work.',
              style: TextStyle(color: grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.title, this.note);
  final IconData icon;
  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: brandGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (note != null)
                  Text(
                    note!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
