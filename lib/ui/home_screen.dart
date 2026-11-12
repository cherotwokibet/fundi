import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';
import 'browse_screen.dart';
import 'find_screen.dart';
import 'location_bar.dart';
import 'provider_area.dart';
import 'request_status_screen.dart';
import 'safety_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

/// The whole product on one screen: two actions, no login, no categories.
/// The main button sits low, where a thumb reaches it one-handed.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Start loading nearby mechanics now so the next screen opens instantly.
    ref.watch(nearbyProvider);
    final sample = ref.watch(sampleModeProvider);
    final open = ref.watch(openRequestProvider).value;
    void go(Widget screen) =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => screen));

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            // Fills the screen when there is room; scrolls when the text is
            // large or the phone is small.
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Header(
                            hasOpenRequest: open != null,
                            onMyRepair: () => go(const RequestStatusScreen()),
                          ),
                          if (sample) ...[
                            const SizedBox(height: 4),
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
                          ],
                          const SizedBox(height: 8),
                          Expanded(
                            child: _Hero(onFind: () => go(const FindScreen())),
                          ),
                          const SizedBox(height: 10),
                          BigButton(
                            key: const Key('home-browse'),
                            kind: ButtonKind.tint,
                            icon: Icons.call_outlined,
                            label: 'Browse and call a mechanic',
                            onPressed: () => go(const BrowseScreen()),
                          ),
                          const SizedBox(height: 12),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.verified,
                                size: 16,
                                color: Color(0xFF135C37),
                              ),
                              SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Every mechanic is ID-checked. No sign-up needed.',
                                  style: TextStyle(fontSize: 13, color: muted),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _SafetyLink(onTap: () => showSafetySheet(context)),
                          TextButton(
                            key: const Key('home-provider'),
                            onPressed: () => go(const ProviderArea()),
                            child: const Text('I\'m a mechanic or garage'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.hasOpenRequest, required this.onMyRepair});
  final bool hasOpenRequest;
  final VoidCallback onMyRepair;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: forest,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.build_rounded, size: 18, color: lime),
          ),
          const SizedBox(width: 10),
          // Working name. The brand is not chosen yet.
          Text('fundi', style: heading(22, color: forest)),
          const Spacer(),
          // Only shown when this phone has an open request.
          if (hasOpenRequest)
            Material(
              color: Colors.white,
              shape: const StadiumBorder(side: BorderSide(color: hairline)),
              child: InkWell(
                key: const Key('home-my-repair'),
                customBorder: const StadiumBorder(),
                onTap: onMyRepair,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF1F9D55),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'My repair',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onFind});
  final VoidCallback onFind;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: forest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Quiet decoration only; it carries no meaning.
          Positioned(
            right: -70,
            bottom: 70,
            child: IgnorePointer(
              child: Icon(
                Icons.build_rounded,
                size: 220,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'VERIFIED MECHANICS · NAIROBI',
                  style: TextStyle(
                    color: lime,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                Text('Car trouble?', style: heading(44, color: Colors.white)),
                const SizedBox(height: 10),
                const Text(
                  'A checked mechanic nearby will sort it out. You don\'t need to know what\'s wrong.',
                  style: TextStyle(
                    color: Color(0xFFE4EBE6),
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                const LocationBar(onDark: true),
                const Spacer(),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: BigButton(
                    key: const Key('home-find'),
                    label: 'Find me a mechanic',
                    trailingIcon: Icons.arrow_forward,
                    onPressed: onFind,
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

class _SafetyLink extends StatelessWidget {
  const _SafetyLink({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: warnFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: warnLine),
      ),
      child: InkWell(
        key: const Key('home-safety'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: warnInk),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Accident or unsafe location?',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                Icon(Icons.chevron_right, color: warnInk),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
