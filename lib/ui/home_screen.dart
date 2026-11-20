import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';
import 'browse_screen.dart';
import 'find_screen.dart';
import 'location_bar.dart';
import 'request_status_screen.dart';
import 'safety_sheet.dart';
import 'theme.dart';
import 'widgets.dart';
import 'complaint_ui.dart';
import 'rate_card.dart';

/// The whole product on one screen: two actions, no login, no categories.
/// Phone: one column, with the main button low, in thumb reach.
/// Wide window (desktop, tablet on its side): two columns.
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

    final header = _Header(
      hasOpenRequest: open != null,
      onMyRepair: () => go(const RequestStatusScreen()),
    );
    final banner = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3D6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'Sample data: these mechanics and numbers are examples.',
        style: TextStyle(fontSize: 13),
      ),
    );
    final hero = _Hero(onFind: () => go(const FindScreen()));
    final browse = ActionTile(
      key: const Key('home-browse'),
      icon: Icons.call_rounded,
      title: 'Browse and call',
      subtitle: 'See mechanics near you and call one',
      onTap: () => go(const BrowseScreen()),
    );
    const trust = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.verified, size: 16, color: Color(0xFF135C37)),
        SizedBox(width: 6),
        Flexible(
          child: Text(
            'Every mechanic is ID-checked. No sign-up needed.',
            style: TextStyle(fontSize: 13, color: muted),
          ),
        ),
      ],
    );
    final safety = _SafetyLink(onTap: () => showSafetySheet(context));

    if (isWide(context)) {
      return Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 12, 32, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      if (sample) ...[const SizedBox(height: 4), banner],
                      const SizedBox(height: 8),
                      const RateCard(),
                      const LastJobProblem(),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        // Tall enough to feel like a page, short enough that
                        // everything fits a laptop window without scrolling.
                        constraints: BoxConstraints(
                          minHeight: (MediaQuery.sizeOf(context).height - 250)
                              .clamp(340.0, 480.0),
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 11, child: hero),
                              const SizedBox(width: 24),
                              Expanded(
                                flex: 9,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    browse,
                                    const SizedBox(height: 24),
                                    const _HowItWorks(),
                                    const SizedBox(height: 16),
                                    const Spacer(),
                                    safety,
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      trust,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
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
                          header,
                          if (sample) ...[const SizedBox(height: 4), banner],
                          const SizedBox(height: 8),
                          const RateCard(),
                          const LastJobProblem(),
                          Expanded(child: hero),
                          const SizedBox(height: 10),
                          browse,
                          const SizedBox(height: 12),
                          trust,
                          const SizedBox(height: 12),
                          safety,
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

/// Wide layout only: three plain steps, so the page explains itself.
class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    const steps = [
      'Tell us where the car is. No need to know what\'s wrong.',
      'We match the nearest checked mechanic who is free now.',
      'Call, or send a request. You see the fee first.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'HOW IT WORKS',
          style: TextStyle(
            color: muted,
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        for (final (i, step) in steps.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: tint,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: forest,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      step,
                      style: const TextStyle(fontSize: 15, height: 1.35),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
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
                Text(
                  'Car trouble?',
                  style: heading(
                    isWide(context) ? 56 : 44,
                    color: Colors.white,
                  ),
                ),
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
                ActionTile(
                  key: const Key('home-find'),
                  primary: true,
                  icon: Icons.bolt_rounded,
                  title: 'Find me a mechanic',
                  subtitle: 'We pick the nearest one who is free',
                  onTap: onFind,
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
