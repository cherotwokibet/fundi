import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/account_repository.dart';
import 'data/admin_repository.dart';
import 'data/provider_repository.dart';
import 'state/app_state.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

// Supply these at build time to use the real backend:
//   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
// Without them the app runs on built-in sample data.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
          sampleModeProvider.overrideWithValue(false),
        ],
      ],
      child: const FundiApp(),
    ),
  );
}

class FundiApp extends StatelessWidget {
  const FundiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fundi',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeScreen(),
    );
  }
}
