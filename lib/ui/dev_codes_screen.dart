import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dev_codes_repository.dart';
import '../state/app_state.dart';
import 'home_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// DEVELOPMENT ONLY. Opened with `?testcodes=KEY` in the web address.
/// Shows the latest mock sign-in codes so a tester can sign in from any
/// phone or computer. Refreshes by itself.
class DevCodesScreen extends ConsumerStatefulWidget {
  const DevCodesScreen(this.codesKey, {super.key});
  final String codesKey;

  static const refreshEvery = Duration(seconds: 5);

  @override
  ConsumerState<DevCodesScreen> createState() => _State();
}

class _State extends ConsumerState<DevCodesScreen> {
  Timer? timer;
  List<DevCode>? codes;
  bool refused = false;

  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(DevCodesScreen.refreshEvery, (_) => _load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(devCodesProvider).latest(widget.codesKey);
      if (mounted) {
        setState(() {
          codes = list;
          refused = false;
        });
      }
    } catch (_) {
      // Wrong key, link switched off, or no connection. Keep any codes
      // already shown; say so only if there is nothing to show.
      if (mounted) setState(() => refused = codes == null);
    }
  }

  void _copy(String otp) {
    Clipboard.setData(ClipboardData(text: otp));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Copied $otp')));
  }

  @override
  Widget build(BuildContext context) {
    final list = codes;
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              const ScreenTitle(
                'Test sign-in codes',
                subtitle: Text(
                  'Codes from the last 15 minutes. This page updates by itself.',
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: warnFill,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: warnLine),
                ),
                child: const Text(
                  'For testing only. Anyone with this link can sign in as any number. Do not share it publicly.',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
              const SizedBox(height: 16),
              if (refused)
                const Text(
                  'This link does not work. The key may be wrong, or the link was switched off.',
                )
              else if (list == null)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (list.isEmpty)
                const Text(
                  'No codes yet. In the app, enter a phone number and tap "Send me a code". It shows here within 5 seconds.',
                  style: TextStyle(fontSize: 15, height: 1.4),
                )
              else
                for (final c in list) ...[
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: Key('code-${c.otp}'),
                      onTap: () => _copy(c.otp),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.phone.startsWith('254')
                                        ? '+${c.phone}'
                                        : c.phone,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${agoText(c.createdAt)} · tap to copy',
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(c.otp, style: heading(30, color: forest)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 12),
              BigButton(
                key: const Key('codes-open-app'),
                kind: ButtonKind.tint,
                label: 'Open the app',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
