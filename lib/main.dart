import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/account_repository.dart';
import 'data/admin_repository.dart';
import 'data/dev_codes_repository.dart';
import 'data/inbox_repository.dart';
import 'data/parts_repository.dart';
import 'data/provider_repository.dart';
import 'models/portal.dart';
import 'state/app_state.dart';
import 'ui/dev_codes_screen.dart';
import 'ui/home_screen.dart';
import 'ui/provider_area.dart';
import 'ui/theme.dart';

// Supply these at build time to use the real backend:
//   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
// Without them the app runs on built-in sample data.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Real paths (/admin, /garage, /parts) instead of /#/.
  usePathUrlStrategy();
  final live = supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
  if (live) {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
  }
  runApp(
    ProviderScope(
      overrides: [
        if (live) ...[
          repositoryProvider.overrideWithValue(
            SupabaseProviderRepository(Supabase.instance.client),
          ),
          accountProvider.overrideWithValue(
            SupabaseAccountRepository(Supabase.instance.client),
          ),
          adminProvider.overrideWithValue(
            SupabaseAdminRepository(Supabase.instance.client),
          ),
          inboxRepositoryProvider.overrideWithValue(
            SupabaseInboxRepository(Supabase.instance.client),
          ),
          partsProvider.overrideWithValue(
            SupabasePartsRepository(Supabase.instance.client),
          ),
          devCodesProvider.overrideWithValue(
            SupabaseDevCodesRepository(Supabase.instance.client),
          ),
          sampleModeProvider.overrideWithValue(false),
        ],
      ],
      // Development only: <site>/?testcodes=<key> opens the test codes page.
      child: FundiApp(
        codesKey: Uri.base.queryParameters['testcodes'],
        portal: Portal.fromPath(Uri.base.path),
      ),
    ),
  );
}

class FundiApp extends StatelessWidget {
  const FundiApp({super.key, this.codesKey, this.portal = Portal.owner});

  /// When set, the app opens on the test sign-in codes page.
  final String? codesKey;

  /// Which link the app was opened on: owners, admin, garages or parts shops.
  final Portal portal;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: portal.title,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // The first screen is a named route so the address bar keeps the
      // portal's path (/admin, /garage, /parts) and a refresh stays there.
      onGenerateInitialRoutes: (_) => [_firstRoute()],
      onGenerateRoute: (_) => _firstRoute(),
    );
  }

  Route<void> _firstRoute() => MaterialPageRoute<void>(
    settings: RouteSettings(name: portal.path),
    builder: (_) => (codesKey != null && codesKey!.isNotEmpty)
        ? DevCodesScreen(codesKey!)
        : portal == Portal.owner
        ? const HomeScreen()
        : ProviderArea(portal: portal),
  );
}
