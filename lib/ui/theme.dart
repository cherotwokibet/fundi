import 'package:flutter/material.dart';

import '../models/service_provider.dart';

const brandGreen = Color(0xFF0B6B53);
const callGreen = Color(0xFF12824A);
const ink = Color(0xFF14211D);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: brandGreen,
    primary: brandGreen,
    surface: const Color(0xFFF7F8F6),
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    useMaterial3: true,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE3E7E3)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

/// One place for how availability reads and looks.
extension AvailabilityLook on Availability {
  String get label => switch (this) {
    Availability.available => 'Available now',
    Availability.unconfirmed => 'Availability not confirmed',
    Availability.busy => 'Busy',
    Availability.offline => 'Offline',
  };

  Color get color => switch (this) {
    Availability.available => callGreen,
    Availability.unconfirmed => const Color(0xFF9A6A00),
    Availability.busy => const Color(0xFFB4541A),
    Availability.offline => const Color(0xFF6B7672),
  };
}

extension CheckKindLook on CheckKind {
  String get title => switch (this) {
    CheckKind.identity => 'Identity',
    CheckKind.location => 'Location',
    CheckKind.experience => 'Experience',
    CheckKind.business => 'Business',
  };

  String get explanation => switch (this) {
    CheckKind.identity =>
      'National ID checked and matched to the person and their M-Pesa name.',
    CheckKind.location =>
      'Where they work from was confirmed by a visit or video call.',
    CheckKind.experience =>
      'Trade certificate or a reference from a garage was checked.',
    CheckKind.business =>
      'Business registration and county permit were checked.',
  };
}

String feeText(int? kes) {
  if (kes == null) return 'Ask for the inspection fee';
  if (kes == 0) return 'Free inspection';
  return 'Inspection fee KES $kes';
}
