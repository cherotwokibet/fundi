import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';
import 'browse_screen.dart';
import 'find_screen.dart';
import 'location_bar.dart';
import 'provider_area.dart';
import 'theme.dart';

/// The whole product on one screen: two buttons, no login, no categories.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Start loading nearby mechanics now so the next screen opens instantly.
    ref.watch(nearbyProvider);
    final sample = ref.watch(sampleModeProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (sample)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3D6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Sample data: these mechanics and numbers are examples.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  const Spacer(),
                  const Text(
                    'Car problem?',
                    style: TextStyle(
                      fontSize: 34,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Get a verified mechanic to sort it out. You don\'t need to know what\'s wrong.',
                    style: TextStyle(fontSize: 17, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: LocationBar(),
                  ),
                  const Spacer(),
                  _BigAction(
                    key: const Key('home-find'),
                    filled: true,
                    icon: Icons.bolt,
                    title: 'Find me a mechanic',
                    subtitle: 'We pick the nearest one who is free',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const FindScreen()),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _BigAction(
                    key: const Key('home-browse'),
                    filled: false,
                    icon: Icons.call,
                    title: 'Browse and call',
                    subtitle: 'See mechanics near you and call one',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const BrowseScreen()),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified, size: 16, color: brandGreen),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Every mechanic is ID-checked. No sign-up needed.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    key: const Key('home-provider'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProviderArea()),
                    ),
                    child: const Text('I\'m a mechanic or garage'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BigAction extends StatelessWidget {
  const _BigAction({
    super.key,
    required this.filled,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final bool filled;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : brandGreen;
    return Material(
      color: filled ? brandGreen : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: brandGreen, width: filled ? 0 : 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          child: Row(
            children: [
              Icon(icon, color: fg, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: fg,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: filled
                            ? Colors.white.withValues(alpha: 0.9)
                            : ink,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}
