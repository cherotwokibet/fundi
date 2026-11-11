import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/zones.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// Shows where we are searching and lets the owner change it in one tap.
class LocationBar extends ConsumerWidget {
  const LocationBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(locationProvider);
    final label = loc.when(
      data: (l) => 'Near ${l.label}',
      loading: () => 'Finding your location…',
      error: (_, _) => 'Choose your area',
    );
    return InkWell(
      key: const Key('location-bar'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => _pick(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.place_outlined, size: 18, color: brandGreen),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              'Change',
              style: TextStyle(
                color: brandGreen,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pick(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.my_location),
              title: const Text('Use my current location'),
              onTap: () {
                Navigator.pop(sheet);
                ref.read(locationProvider.notifier).useGps();
              },
            ),
            for (final z in zones)
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(z.name),
                onTap: () {
                  Navigator.pop(sheet);
                  ref.read(locationProvider.notifier).pickZone(z);
                },
              ),
          ],
        ),
      ),
    );
  }
}
