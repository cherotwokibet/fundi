import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/zones.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Shows where we are searching and lets the owner change it in one tap.
class LocationBar extends ConsumerWidget {
  const LocationBar({super.key, this.onDark = false});

  /// True inside the dark hero card on the home screen.
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(locationProvider);
    final label = loc.when(
      data: (l) => 'Near ${l.label}',
      loading: () => 'Finding your location…',
      error: (_, _) => 'Choose your area',
    );
    final text = onDark ? Colors.white : muted;
    final accent = onDark ? lime : forest;
    return Material(
      color: onDark ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        key: const Key('location-bar'),
        borderRadius: BorderRadius.circular(24),
        onTap: () => _pick(context, ref),
        child: ConstrainedBox(
          // A full-height tap target, even though the text is small.
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: 8,
              horizontal: onDark ? 14 : 0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.place_outlined, size: 18, color: accent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '$label · ',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: text, fontSize: 15),
                  ),
                ),
                Text(
                  'Change',
                  style: TextStyle(
                    color: accent,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _pick(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      constraints: sheetConstraints,
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
