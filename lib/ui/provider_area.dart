import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account_repository.dart';
import '../models/portal.dart';
import '../models/service_provider.dart';
import '../models/trade.dart';
import '../state/app_state.dart';
import 'admin_screen.dart';
import 'garage_screen.dart';
import 'parts_screen.dart';
import 'shop_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// The admin, garage and parts shop portals, each on its own link. Nobody
/// joins here: our team adds every business and the numbers of the people
/// who work there. Signing in opens only what this portal is for; a number
/// that belongs to another portal is pointed there.
class ProviderArea extends ConsumerWidget {
  const ProviderArea({super.key, this.portal = Portal.garage});
  final Portal portal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider);
    // Rebuilt when sign-in state or the listing changes.
    ref.watch(accountVersionProvider);
    if (!account.isSignedIn) return _SignInScreen(portal);
    return ref
        .watch(accessProvider)
        .when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => _RetryScreen(
            message: 'Could not load your account.',
            onRetry: () => ref.invalidate(accessProvider),
          ),
          data: (access) {
            if (!access.isRegistered) return const _NotRegisteredScreen();
            if (portal == Portal.admin) {
              return access.isAdmin
                  ? const AdminScreen()
                  : _WrongPortalScreen(portal, access);
            }
            final mine = [
              for (final m in access.memberships)
                if (portalFor(m) == portal) m,
            ];
            if (mine.isEmpty) return _WrongPortalScreen(portal, access);
            if (mine.length > 1) return _ChooserScreen(access, mine);
            return _destination(access, mine.single);
          },
        );
  }
}

/// The portal a membership is used from.
Portal portalFor(Membership m) =>
    m.kind == OrgKind.shop ? Portal.parts : Portal.garage;

/// Every portal this person can use.
List<Portal> portalsOf(TradeAccess access) => [
  if (access.isAdmin) Portal.admin,
  for (final p in [Portal.garage, Portal.parts])
    if (access.memberships.any((m) => portalFor(m) == p)) p,
];

String _portalName(Portal p) => switch (p) {
  Portal.admin => 'admin portal',
  Portal.garage => 'portal for mechanics and garages',
  Portal.parts => 'portal for parts shops',
  Portal.owner => 'car owner app',
};

/// Opens another portal: a new address on the web, a new screen in the app.
void openPortal(BuildContext context, Portal p) {
  Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(
      settings: RouteSettings(name: p.path),
      builder: (_) => ProviderArea(portal: p),
    ),
  );
}

/// Signed in on the wrong link: say which portal is theirs.
class _WrongPortalScreen extends ConsumerWidget {
  const _WrongPortalScreen(this.portal, this.access);
  final Portal portal;
  final TradeAccess access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theirs = portalsOf(access);
    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton(
            onPressed: () => _signOut(ref),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _StatusNote(
              icon: Icons.alt_route,
              title: 'This number is not for the ${_portalName(portal)}',
              body: 'Use the link for your work below. Save it on your phone.',
            ),
            const SizedBox(height: 20),
            for (final p in theirs)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FilledButton(
                  key: Key('go-portal-${p.name}'),
                  onPressed: () => openPortal(context, p),
                  child: Text('Open the ${_portalName(p)}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Where one membership leads.
Widget _destination(TradeAccess access, Membership m) {
  if (m.kind == OrgKind.shop) {
    return m.isLive
        ? ShopScreen(shopId: m.orgId, shopName: m.orgName)
        : const _PausedScreen(
            title: 'Your shop is paused',
            body: 'Garages and mechanics cannot see your parts right now. Contact our team.',
          );
  }
  if (m.role == MemberRole.owner) return const _ListingFlow();
  return m.isLive
      ? PartsMarketScreen(access: access)
      : _PausedScreen(
          title: m.orgStatus == 'pending'
              ? '${m.orgName} is still being checked'
              : '${m.orgName} is paused',
          body: 'You can order spare parts once it is live.',
        );
}

/// The listing owner's screens: status, documents, availability and inbox.
class _ListingFlow extends ConsumerWidget {
  const _ListingFlow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listing = ref.watch(myListingProvider);
    return listing.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => _RetryScreen(
        message: 'Could not load your listing.',
        onRetry: () => ref.invalidate(myListingProvider),
      ),
      data: (l) => l == null
          ? const _PausedScreen(
              title: 'Your listing is not linked to this number',
              body: 'Contact our team.',
            )
          : _ManageScreen(l),
    );
  }
}

class _RetryScreen extends StatelessWidget {
  const _RetryScreen({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

Future<void> _signOut(WidgetRef ref) async {
  await ref.read(accountProvider).signOut();
  ref.read(accountVersionProvider.notifier).bump();
}

/// Signed in, but no admin has added this number.
class _NotRegisteredScreen extends ConsumerWidget {
  const _NotRegisteredScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(),
    body: ContentWidth(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const _StatusNote(
            icon: Icons.person_search_outlined,
            title: 'This number is not registered',
            body:
                'Our team adds every mechanic, garage and parts shop after visiting and checking them. '
                'If we added you, sign in with the number you gave us. '
                'Not added yet? Ask our team to visit you.',
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('not-registered-sign-out'),
            onPressed: () => _signOut(ref),
            child: const Text('Use a different number'),
          ),
        ],
      ),
    ),
  );
}

class _PausedScreen extends ConsumerWidget {
  const _PausedScreen({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      actions: [
        TextButton(
          onPressed: () => _signOut(ref),
          child: const Text('Sign out'),
        ),
      ],
    ),
    body: ContentWidth(
      child: _StatusNote(icon: Icons.hourglass_top, title: title, body: body),
    ),
  );
}

/// For someone added to more than one business.
class _ChooserScreen extends ConsumerWidget {
  const _ChooserScreen(this.access, this.memberships);
  final TradeAccess access;
  final List<Membership> memberships;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your work'),
        actions: [
          TextButton(
            onPressed: () => _signOut(ref),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            for (final m in memberships)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  key: Key('choose-${m.orgId}'),
                  leading: Icon(
                    m.kind == OrgKind.shop
                        ? Icons.storefront_outlined
                        : Icons.build_outlined,
                  ),
                  title: Text(m.orgName),
                  subtitle: Text(
                    m.kind == OrgKind.shop
                        ? 'Parts shop'
                        : m.role == MemberRole.owner
                        ? 'Your listing'
                        : 'You order parts for this garage',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _destination(access, m),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _friendly(Object e) => e is AccountException
    ? e.message
    : 'Something went wrong. Check your connection and try again.';

String _signInTitle(Portal p) => switch (p) {
  Portal.admin => 'Fundi admin',
  Portal.parts => 'Parts shops',
  _ => 'Mechanics and garages',
};

String _sampleNumber(Portal p) => switch (p) {
  Portal.admin => 'Sample admin: 0700 000 000.',
  Portal.parts => 'Sample parts shop: 0711 000 002.',
  _ => 'Sample mechanic: 0711 000 001.',
};

// ---------------------------------------------------------------------------
// Sign in with a phone number and a code
// ---------------------------------------------------------------------------
class _SignInScreen extends ConsumerStatefulWidget {
  const _SignInScreen(this.portal);
  final Portal portal;

  @override
  ConsumerState<_SignInScreen> createState() => _SignInState();
}

/// What each portal's sign-in says about it, on the forest panel.
({String badge, String headline, List<(IconData, String)> points}) _pitch(
  Portal p,
) => switch (p) {
  Portal.admin => (
    badge: 'Admin',
    headline: 'Run the Fundi network.',
    points: [
      (
        Icons.verified_user_outlined,
        'Check and approve mechanics, garages and parts shops',
      ),
      (Icons.forum_outlined, 'See every request as it happens'),
      (Icons.flag_outlined, 'Decide complaints and refunds'),
    ],
  ),
  Portal.parts => (
    badge: 'Parts',
    headline: 'Sell parts to checked mechanics.',
    points: [
      (
        Icons.storefront_outlined,
        'Orders come only from approved garages and mechanics',
      ),
      (Icons.inventory_2_outlined, 'Confirm, get it ready, hand it over'),
      (Icons.notifications_none, 'New orders show at once, with a count'),
    ],
  ),
  _ => (
    badge: 'Garages',
    headline: 'Jobs from car owners near you.',
    points: [
      (Icons.mic_none, "Requests with the owner's note, photo and voice note"),
      (
        Icons.receipt_long_outlined,
        'Send your price, the owner approves in one tap',
      ),
      (Icons.build_outlined, 'Order spare parts from checked shops'),
    ],
  ),
};

/// +254712345678 → +254 712 345 678
String _spaced(String phone) {
  final d = phone.replaceAll(RegExp(r'\D'), '');
  if (d.length != 12) return phone;
  return '+${d.substring(0, 3)} ${d.substring(3, 6)} ${d.substring(6, 9)} ${d.substring(9)}';
}

class _SignInState extends ConsumerState<_SignInScreen> {
  static const resendAfter = 30;

  final phone = TextEditingController();
  final code = TextEditingController();
  final codeFocus = FocusNode();
  String? sentTo;
  String? phoneError;
  String? codeError;
  String? notice;
  bool busy = false;
  int wait = 0;
  Timer? ticker;

  @override
  void dispose() {
    ticker?.cancel();
    phone.dispose();
    code.dispose();
    codeFocus.dispose();
    super.dispose();
  }

  void _startWait() {
    ticker?.cancel();
    wait = resendAfter;
    ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => wait--);
      if (wait <= 0) t.cancel();
    });
  }

  Future<void> _send({bool again = false}) async {
    final normal = normalizeKenyanPhone(phone.text);
    if (normal == null) {
      setState(
        () => phoneError =
            'Enter a Kenyan mobile number, for example 0712 345 678.',
      );
      return;
    }
    setState(() {
      busy = true;
      phoneError = null;
      codeError = null;
      notice = null;
    });
    try {
      await ref.read(accountProvider).sendCode(normal);
      if (!mounted) return;
      setState(() {
        sentTo = normal;
        code.clear();
        if (again) notice = 'New code sent.';
      });
      _startWait();
      codeFocus.requestFocus();
    } catch (e) {
      if (mounted) {
        setState(() {
          if (sentTo == null) {
            phoneError = _friendly(e);
          } else {
            codeError = _friendly(e);
          }
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _verify() async {
    if (busy) return;
    final entered = code.text.trim();
    if (entered.length != 6) {
      setState(() => codeError = 'Enter all 6 digits of the code.');
      return;
    }
    setState(() {
      busy = true;
      codeError = null;
      notice = null;
    });
    try {
      await ref.read(accountProvider).verifyCode(sentTo!, entered);
      ref.read(accountVersionProvider.notifier).bump();
    } catch (e) {
      if (mounted) setState(() => codeError = _friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _changeNumber() {
    ticker?.cancel();
    setState(() {
      sentTo = null;
      code.clear();
      codeError = null;
      notice = null;
      wait = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final form = Padding(
      padding: EdgeInsets.fromLTRB(24, wide ? 40 : 28, 24, 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: AutofillGroup(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: sentTo == null ? _phoneStep() : _codeStep(),
          ),
        ),
      ),
    );
    if (wide) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 5, child: _Panel(widget.portal)),
            Expanded(
              flex: 6,
              child: Center(child: SingleChildScrollView(child: form)),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _Panel(widget.portal, compact: true),
            Center(child: form),
          ],
        ),
      ),
    );
  }

  static InputDecoration _box({String? hint, String? error, Widget? prefix}) =>
      InputDecoration(
        hintText: hint,
        errorText: error,
        errorMaxLines: 3,
        counterText: '',
        prefixIcon: prefix,
        filled: true,
        fillColor: const Color(0xFFF7F8F5),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: forest, width: 2),
        ),
      );

  Widget _button(Key key, String label, VoidCallback onPressed) => SizedBox(
    height: 54,
    child: FilledButton(
      key: key,
      style: FilledButton.styleFrom(
        backgroundColor: forest,
        disabledBackgroundColor: forest.withValues(alpha: 0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          : Text(label),
    ),
  );

  static const _label = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: ink,
  );

  Widget _phoneStep() {
    return Column(
      key: const ValueKey('phone-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _signInTitle(widget.portal),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: Color(0xFF135C37),
          ),
        ),
        const SizedBox(height: 6),
        Text('Sign in', style: heading(32)),
        const SizedBox(height: 10),
        Text(
          widget.portal == Portal.admin
              ? 'For the Fundi team only. Sign in with your team number.'
              : 'Our team adds every mechanic, garage and parts shop after checking them. '
                    'Sign in with the number you gave our team.',
          style: const TextStyle(fontSize: 15, color: muted, height: 1.45),
        ),
        const SizedBox(height: 28),
        const Text('Phone number', style: _label),
        const SizedBox(height: 8),
        TextField(
          key: const Key('phone'),
          controller: phone,
          autofocus: true,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.go,
          autofillHints: const [AutofillHints.telephoneNumber],
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
            LengthLimitingTextInputFormatter(16),
          ],
          style: const TextStyle(fontSize: 18, letterSpacing: 0.5),
          onChanged: (_) {
            if (phoneError != null) setState(() => phoneError = null);
          },
          onSubmitted: (_) => _send(),
          decoration: _box(
            hint: '712 345 678',
            error: phoneError,
            prefix: Container(
              margin: const EdgeInsets.only(left: 6, right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: hairline)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'KE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                  SizedBox(width: 6),
                  Text('+254', style: TextStyle(fontSize: 18, color: ink)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '0712…, 712… and +254712… all work.',
          style: TextStyle(fontSize: 13, color: muted),
        ),
        const SizedBox(height: 22),
        _button(const Key('send-code'), 'Send me a code', _send),
        const SizedBox(height: 22),
        const _Assurance(),
      ],
    );
  }

  Widget _codeStep() {
    final sample = ref.watch(sampleModeProvider);
    return Column(
      key: const ValueKey('code-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('change-number'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(0, 40),
            ),
            onPressed: busy ? null : _changeNumber,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Use a different number'),
          ),
        ),
        const SizedBox(height: 8),
        Text('Check your phone', style: heading(32)),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            text: 'We sent a 6-digit code to ',
            children: [
              TextSpan(
                text: _spaced(sentTo!),
                style: const TextStyle(fontWeight: FontWeight.w700, color: ink),
              ),
              const TextSpan(text: '.'),
            ],
          ),
          style: const TextStyle(fontSize: 15, color: muted, height: 1.45),
        ),
        if (sample) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: warnFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: warnLine),
            ),
            child: Text(
              'Sample mode: no SMS is sent. Use 123456. '
              '${_sampleNumber(widget.portal)}',
              style: const TextStyle(fontSize: 13, color: warnInk),
            ),
          ),
        ],
        const SizedBox(height: 26),
        const Text('Code', style: _label),
        const SizedBox(height: 8),
        TextField(
          key: const Key('code'),
          controller: code,
          focusNode: codeFocus,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          maxLength: 6,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofillHints: const [AutofillHints.oneTimeCode],
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: 14,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          onChanged: (v) {
            if (codeError != null) setState(() => codeError = null);
            // Pasted or filled in from the text: sign in at once.
            if (v.length == 6) _verify();
          },
          onSubmitted: (_) => _verify(),
          decoration: _box(hint: '······', error: codeError),
        ),
        if (notice != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.check_circle,
                size: 16,
                color: Color(0xFF135C37),
              ),
              const SizedBox(width: 6),
              Text(
                notice!,
                style: const TextStyle(fontSize: 13, color: Color(0xFF135C37)),
              ),
            ],
          ),
        ],
        const SizedBox(height: 22),
        _button(const Key('verify-code'), 'Sign in', _verify),
        const SizedBox(height: 14),
        Center(
          child: wait > 0
              ? Text(
                  "Didn't get it? You can ask for a new code in ${wait}s.",
                  key: const Key('resend-wait'),
                  style: const TextStyle(fontSize: 13, color: muted),
                )
              : TextButton(
                  key: const Key('resend-code'),
                  onPressed: busy ? null : () => _send(again: true),
                  child: const Text("Didn't get it? Send a new code"),
                ),
        ),
      ],
    );
  }
}

/// The forest side: whose portal this is and what it is for.
class _Panel extends StatelessWidget {
  const _Panel(this.portal, {this.compact = false});
  final Portal portal;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = _pitch(portal);
    final brand = Row(
      children: [
        Text('fundi', style: heading(compact ? 22 : 26, color: Colors.white)),
        const SizedBox(width: 10),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: lime.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              p.badge,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: lime,
              ),
            ),
          ),
        ),
      ],
    );
    if (compact) {
      return Container(
        color: forest,
        padding: EdgeInsets.fromLTRB(
          24,
          MediaQuery.paddingOf(context).top + 20,
          24,
          24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            brand,
            const SizedBox(height: 18),
            Text(p.headline, style: heading(24, color: Colors.white)),
          ],
        ),
      );
    }
    return Container(
      color: forest,
      padding: const EdgeInsets.fromLTRB(48, 40, 48, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          brand,
          const Spacer(),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(p.headline, style: heading(44, color: Colors.white)),
          ),
          const SizedBox(height: 28),
          for (final (icon, text) in p.points)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: lime),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFFDCE6E0),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Spacer(),
          const Text(
            'Only people the Fundi team has checked and added can sign in.',
            style: TextStyle(fontSize: 13, color: Color(0xFF8FA59A)),
          ),
        ],
      ),
    );
  }
}

class _Assurance extends StatelessWidget {
  const _Assurance();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F6EC),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline, size: 18, color: forest),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'We text you a 6-digit code, so there is no password to remember. '
            'Fundi never asks for your M-Pesa PIN.',
            style: TextStyle(fontSize: 13, color: ink, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Manage: checks while pending, then the garage portal's Today screen
// ---------------------------------------------------------------------------
class _ManageScreen extends ConsumerWidget {
  const _ManageScreen(this.listing);
  final MyListing listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = listing;
    if (l.status == ListingStatus.approved) {
      return GarageToday(
        listing: l,
        onSignOut: () => _signOut(ref),
        parts: const _PartsEntry(),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l.name),
        actions: [
          TextButton(
            onPressed: () => _signOut(ref),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: l.status == ListingStatus.suspended
              ? const [
                  _StatusNote(
                    icon: Icons.block,
                    title: 'Your listing is paused',
                    body: 'Owners cannot see you right now. Contact support.',
                  ),
                ]
              : [
                  const Text(
                    'Our team is checking your listing',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Owners will see you once the checks are done. If our team asked for a document, '
                    'you can add it here. Only our verification team can open them.',
                  ),
                  const SizedBox(height: 12),
                  _Documents(l.type),
                ],
        ),
      ),
    );
  }
}

class _StatusNote extends StatelessWidget {
  const _StatusNote({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Icon(icon, size: 44, color: brandGreen),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// The document checklist with an upload button per document.
class _Documents extends ConsumerStatefulWidget {
  const _Documents(this.type);
  final ProviderType type;

  @override
  ConsumerState<_Documents> createState() => _DocumentsState();
}

class _DocumentsState extends ConsumerState<_Documents> {
  DocumentKind? uploading;

  Future<void> _upload(DocumentKind kind, {required bool camera}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final photo = await ref.read(photoPickerProvider)(camera: camera);
      if (photo == null) return;
      setState(() => uploading = kind);
      await ref
          .read(accountProvider)
          .uploadDocument(kind, photo.bytes, photo.mime);
      ref.invalidate(myDocumentsProvider);
      ref.invalidate(myListingProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendly(e))));
    } finally {
      if (mounted) setState(() => uploading = null);
    }
  }

  void _choose(DocumentKind kind) {
    showModalBottomSheet<void>(
      constraints: sheetConstraints,
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('doc-camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(sheet);
                _upload(kind, camera: true);
              },
            ),
            ListTile(
              key: const Key('doc-gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(sheet);
                _upload(kind, camera: false);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final done = ref.watch(myDocumentsProvider).value ?? const {};
    final wanted = DocumentKind.forType(widget.type);
    final allRequired = done.containsAll({
      DocumentKind.nationalId,
      DocumentKind.selfie,
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, kind) in wanted.indexed)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: Icon(
                done.contains(kind)
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: done.contains(kind) ? callGreen : null,
              ),
              title: Text(kind.label),
              subtitle: Text(
                i < 2 ? 'Required' : 'Optional, speeds up approval',
              ),
              trailing: uploading == kind
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : TextButton(
                      key: Key('upload-${kind.code}'),
                      onPressed: uploading == null ? () => _choose(kind) : null,
                      child: Text(done.contains(kind) ? 'Replace' : 'Upload'),
                    ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          allRequired
              ? 'Thank you. We are checking your documents and will call you if we need anything.'
              : 'Upload the two required documents to start verification.',
        ),
      ],
    );
  }
}

/// Opens the spare parts marketplace from an approved listing.
class _PartsEntry extends ConsumerWidget {
  const _PartsEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(accessProvider).value;
    if (access == null || access.buyers.isEmpty) return const SizedBox.shrink();
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: hairline),
      ),
      child: ListTile(
        key: const Key('open-parts'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.inventory_2_outlined, color: forest),
        ),
        title: const Text(
          'Order spare parts',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text('From verified parts shops near you.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PartsMarketScreen(access: access),
          ),
        ),
      ),
    );
  }
}
