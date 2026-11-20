import 'package:flutter/material.dart';

import '../models/service_provider.dart';

// Palette: two greens and a lime on a warm off-white page. Every text pair
// below is at least 4.5:1 (see docs/DESIGN.md for the measured numbers).
const forest = Color(0xFF17392C);
const lime = Color(0xFFD8F27E);
const page = Color(0xFFF8F6F1);
const ink = Color(0xFF14211D);
const muted = Color(0xFF55625D);
const tint = Color(0xFFE6ECE4);
const hairline = Color(0xFFDEE3DC);
const danger = Color(0xFFB3261E);
const warnInk = Color(0xFF7A4B00);
const warnFill = Color(0xFFFFF8E8);
const warnLine = Color(0xFFF1D9A6);

// Waiting on someone else (quote sent, checks to do): 7.9:1.
const infoInk = Color(0xFF1D4E89);
const infoFill = Color(0xFFE3ECF8);
// Complaints and things gone wrong: 7.0:1.
const alertInk = Color(0xFF9E2318);
const alertFill = Color(0xFFFBE9E7);
// Work consoles (admin, garage board, shop orders) sit on a slightly darker page.
const consolePage = Color(0xFFF4F3EE);

// Older names, still used by the mechanic and admin screens.
const brandGreen = forest;
const callGreen = forest;

/// Heading style: Inter Tight ExtraBold, tight letter spacing.
TextStyle heading(double size, {Color color = ink}) => TextStyle(
  fontFamily: 'InterTight',
  fontWeight: FontWeight.w800,
  fontSize: size,
  height: 1.05,
  letterSpacing: -size * 0.03,
  color: color,
);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: forest,
    primary: forest,
    surface: page,
    onSurface: ink,
    onSurfaceVariant: muted,
    error: danger,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: page,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      backgroundColor: page,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: hairline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 56),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: forest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: forest,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    ),
  );
}

/// One place for how availability reads and looks.
extension AvailabilityLook on Availability {
  String get label => switch (this) {
    Availability.available => 'Available',
    Availability.unconfirmed => 'Availability not confirmed',
    Availability.busy => 'Busy',
    Availability.offline => 'Offline',
  };

  /// Strong colour, for the mechanic's own availability buttons.
  Color get color => switch (this) {
    Availability.available => const Color(0xFF135C37),
    Availability.unconfirmed => const Color(0xFF4A524F),
    Availability.busy => warnInk,
    Availability.offline => const Color(0xFF4A524F),
  };

  /// Pill text and fill. Each pair is at least 6:1.
  Color get pillText => color;
  Color get pillFill => switch (this) {
    Availability.available => const Color(0xFFDCEFE2),
    Availability.busy => const Color(0xFFFCEBC7),
    _ => const Color(0xFFECEDEA),
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

/// The fee as a big amount and a small line saying what it covers.
({String amount, String covers}) feeParts(ServiceProvider p) {
  final covers = p.isMobile ? 'Visit and inspection' : 'Inspection';
  final kes = p.calloutFeeKes;
  if (kes == null) return (amount: 'Ask for the fee', covers: covers);
  if (kes == 0) return (amount: 'Free', covers: covers);
  return (amount: 'KES $kes', covers: covers);
}

/// What we checked, in plain words: "ID and experience checked".
String checkedText(ServiceProvider p) {
  final parts = [
    if (p.checksPassed.contains(CheckKind.identity)) 'ID',
    if (p.checksPassed.contains(CheckKind.location))
      p.isMobile ? 'location' : 'workshop',
    if (p.checksPassed.contains(CheckKind.experience)) 'experience',
    if (p.checksPassed.contains(CheckKind.business)) 'business',
  ];
  if (parts.isEmpty) return 'Checks in progress';
  if (parts.length == 1) return '${parts.first} checked';
  return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last} checked';
}

/// "4 min ago", "2 h ago". Empty when unknown.
String agoText(DateTime? t, {DateTime? now}) {
  if (t == null) return '';
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// 12:04
String clockText(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
