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

class _SignInState extends ConsumerState<_SignInScreen> {
  final phone = TextEditingController();
  final code = TextEditingController();
  String? sentTo;
  String? error;
  bool busy = false;

  @override
  void dispose() {
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = _friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _send() => _run(() async {
    final normal = normalizeKenyanPhone(phone.text);
    if (normal == null) {
      throw AccountException(
        'Enter a Kenyan mobile number, for example 0712 345 678.',
      );
    }
    await ref.read(accountProvider).sendCode(normal);
    if (mounted) setState(() => sentTo = normal);
  });

  Future<void> _verify() => _run(() async {
    await ref.read(accountProvider).verifyCode(sentTo!, code.text.trim());
    ref.read(accountVersionProvider.notifier).bump();
  });

  @override
  Widget build(BuildContext context) {
    final sample = ref.watch(sampleModeProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_signInTitle(widget.portal))),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const Text(
              'Sign in to your work account',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              widget.portal == Portal.admin
                  ? 'For the Fundi team only. Sign in with your team number.'
                  : 'Our team adds every mechanic, garage and parts shop after checking them. '
                        'Sign in with the number you gave our team.',
            ),
            const SizedBox(height: 20),
            if (sentTo == null) ...[
              TextField(
                key: const Key('phone'),
                controller: phone,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: const InputDecoration(
                  labelText: 'Your phone number',
                  hintText: '0712 345 678',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('send-code'),
                onPressed: busy ? null : _send,
                child: const Text('Send me a code'),
              ),
            ] else ...[
              Text('Enter the 6-digit code sent to $sentTo'),
              if (sample)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Sample mode: no SMS is sent. Use 123456. '
                    '${_sampleNumber(widget.portal)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('code'),
                controller: code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autofillHints: const [AutofillHints.oneTimeCode],
                decoration: const InputDecoration(
                  labelText: 'Code',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('verify-code'),
                onPressed: busy ? null : _verify,
                child: const Text('Continue'),
              ),
              TextButton(
                onPressed: busy ? null : () => setState(() => sentTo = null),
                child: const Text('Use a different number'),
              ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
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
