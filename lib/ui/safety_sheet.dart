import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Emergency numbers in Kenya. 999 and 112 reach police and general
/// emergency; 1199 is the Kenya Red Cross.
const emergencyNumbers = [
  (
    number: '999',
    title: 'Police and emergency',
    note: 'Police and general emergencies',
  ),
  (number: '112', title: 'Emergency', note: 'Same help, other number'),
  (
    number: '1199',
    title: 'Kenya Red Cross',
    note: 'Disaster and emergency response',
  ),
];

/// "Accident or unsafe location?" Safety first, mechanic second.
void showSafetySheet(BuildContext context) {
  showModalBottomSheet<void>(
    constraints: sheetConstraints,
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: page,
    builder: (_) => const _SafetySheet(),
  );
}

class _SafetySheet extends ConsumerWidget {
  const _SafetySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Are you safe?', style: heading(28)),
            const SizedBox(height: 10),
            const Text(
              '1. Move people away from traffic if you can.\n'
              '2. Turn on hazard lights; put out a warning triangle.\n'
              '3. If anyone is hurt or in danger, call now.',
              style: TextStyle(fontSize: 15, height: 1.6),
            ),
            const SizedBox(height: 14),
            for (final e in emergencyNumbers) ...[
              Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: hairline),
                ),
                child: InkWell(
                  key: Key('sos-${e.number}'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => ref.read(dialerProvider)(e.number),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 60),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  e.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  e.note,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.call, color: danger, size: 20),
                          const SizedBox(width: 8),
                          Text(e.number, style: heading(24, color: danger)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('When you\'re safe, find a mechanic'),
            ),
          ],
        ),
      ),
    );
  }
}
