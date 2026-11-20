import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account_repository.dart';
import '../models/service_provider.dart';
import '../state/app_state.dart';
import 'admin_screen.dart';
import 'inbox_screen.dart';
import 'location_bar.dart';
import 'theme.dart';

/// Entry for mechanics and garages: sign in, then apply, then manage.
class ProviderArea extends ConsumerWidget {
  const ProviderArea({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider);
    // Rebuilt when sign-in state or the listing changes.
    ref.watch(accountVersionProvider);
    if (!account.isSignedIn) return const _SignInScreen();
    if (ref.watch(isAdminProvider).value ?? false) return const AdminScreen();
    final listing = ref.watch(myListingProvider);
    return listing.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load your listing.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(myListingProvider),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
      data: (l) => l == null ? const _ApplyScreen() : _ManageScreen(l),
    );
  }
}

String _friendly(Object e) => e is AccountException
    ? e.message
    : 'Something went wrong. Check your connection and try again.';

// ---------------------------------------------------------------------------
// Sign in with a phone number and a code
// ---------------------------------------------------------------------------
class _SignInScreen extends ConsumerStatefulWidget {
  const _SignInScreen();

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
      appBar: AppBar(title: const Text('For mechanics and garages')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const Text(
            'Get calls from car owners near you',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Join free. We verify your ID first, then owners can find and call you.',
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
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Sample mode: no SMS is sent. Use 123456. Sign in as 0700 000 000 to see the admin console.',
                  style: TextStyle(fontSize: 13),
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
    );
  }
}

// ---------------------------------------------------------------------------
// Apply: the listing details
// ---------------------------------------------------------------------------
class _ApplyScreen extends ConsumerStatefulWidget {
  const _ApplyScreen();

  @override
  ConsumerState<_ApplyScreen> createState() => _ApplyState();
}

class _ApplyState extends ConsumerState<_ApplyScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final phone = TextEditingController();
  final fee = TextEditingController();
  final makes = TextEditingController();
  ProviderType type = ProviderType.mobileMechanic;
  double radius = 5;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    for (final c in [name, phone, fee, makes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final loc = await ref.read(locationProvider.future);
      await ref
          .read(accountProvider)
          .apply(
            ListingApplication(
              type: type,
              name: name.text.trim(),
              businessPhone: normalizeKenyanPhone(phone.text)!,
              area: loc.label,
              lat: loc.lat,
              lng: loc.lng,
              serviceRadiusKm: radius,
              calloutFeeKes: int.tryParse(fee.text.trim()),
              makes: [
                for (final m in makes.text.split(','))
                  if (m.trim().isNotEmpty) m.trim(),
              ],
            ),
          );
      ref.invalidate(myListingProvider);
    } catch (e) {
      if (mounted) setState(() => error = _friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final garage = type == ProviderType.garage;
    return Scaffold(
      appBar: AppBar(title: const Text('Your listing')),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            SegmentedButton<ProviderType>(
              segments: const [
                ButtonSegment(
                  value: ProviderType.mobileMechanic,
                  label: Text('I go to the car'),
                  icon: Icon(Icons.build_outlined),
                ),
                ButtonSegment(
                  value: ProviderType.garage,
                  label: Text('I have a garage'),
                  icon: Icon(Icons.garage_outlined),
                ),
              ],
              selected: {type},
              onSelectionChanged: (s) => setState(() => type = s.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('listing-name'),
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: garage
                    ? 'Garage name'
                    : 'Your name or business name',
                border: const OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? 'Enter the name owners will see'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('listing-phone'),
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Number owners will call',
                hintText: '0712 345 678',
                border: OutlineInputBorder(),
              ),
              validator: (v) => normalizeKenyanPhone(v ?? '') == null
                  ? 'Enter a Kenyan mobile number'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('listing-fee'),
              controller: fee,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Inspection or call-out fee in KES (optional)',
                helperText: 'Owners see this before they call. 0 means free.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: makes,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Car makes you work on (optional)',
                hintText: 'Toyota, Nissan, Subaru',
                helperText: 'Leave empty if you work on all makes.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Where you work from',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const LocationBar(),
            if (!garage) ...[
              const SizedBox(height: 8),
              Text(
                'How far you travel: ${radius.round()} km',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Slider(
                value: radius,
                min: 2,
                max: 20,
                divisions: 18,
                label: '${radius.round()} km',
                onChanged: (v) => setState(() => radius = v),
              ),
            ],
            const SizedBox(height: 12),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              key: const Key('listing-submit'),
              onPressed: busy ? null : _submit,
              child: const Text('Send for verification'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Manage: status and the availability switch
// ---------------------------------------------------------------------------
class _ManageScreen extends ConsumerStatefulWidget {
  const _ManageScreen(this.listing);
  final MyListing listing;

  @override
  ConsumerState<_ManageScreen> createState() => _ManageState();
}

class _ManageState extends ConsumerState<_ManageScreen> {
  bool busy = false;

  Future<void> _set(Availability a) async {
    setState(() => busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(accountProvider).setAvailability(a);
      ref.invalidate(myListingProvider);
      ref.invalidate(nearbyProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendly(e))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.listing;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.name),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(accountProvider).signOut();
              ref.read(accountVersionProvider.notifier).bump();
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: switch (l.status) {
          ListingStatus.pending => [
            const Text(
              'One more step: your documents',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'We check these before owners can see you. Only our verification team can open them.',
            ),
            const SizedBox(height: 12),
            _Documents(l.type),
          ],
          ListingStatus.suspended => const [
            _StatusNote(
              icon: Icons.block,
              title: 'Your listing is paused',
              body: 'Owners cannot see you right now. Contact support.',
            ),
          ],
          ListingStatus.approved => [
            const InboxEntry(),
            const SizedBox(height: 20),
            const Text(
              'Are you taking jobs now?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(_statusLine(context, l)),
            const SizedBox(height: 16),
            for (final (a, label, hint) in const [
              (Availability.available, 'Available', 'Owners can call you now'),
              (
                Availability.busy,
                'Busy',
                'Shown, but owners know you are on a job',
              ),
              (Availability.offline, 'Offline', 'Not taking jobs'),
            ]) ...[
              _AvailabilityButton(
                key: Key('set-${a.name}'),
                label: label,
                hint: hint,
                color: a.color,
                selected: l.availability == a,
                onTap: busy ? null : () => _set(a),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            const Text(
              '"Available" lasts 4 hours. Tap it again to stay available, so owners never call a number that will not be answered.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        },
      ),
    );
  }

  String _statusLine(BuildContext context, MyListing l) {
    final until = l.availableUntil;
    return switch (l.availability) {
      Availability.available when until != null =>
        'Owners see you as available until ${TimeOfDay.fromDateTime(until).format(context)}.',
      Availability.unconfirmed =>
        'Your "Available" has expired. Tap Available to show up first again.',
      Availability.busy => 'Owners see you as busy.',
      _ => 'Owners see you as offline.',
    };
  }
}

class _AvailabilityButton extends StatelessWidget {
  const _AvailabilityButton({
    super.key,
    required this.label,
    required this.hint,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String hint;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color.withValues(alpha: 0.12) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? color : const Color(0xFFD5DBD6),
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(hint),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle, color: color),
            ],
          ),
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
