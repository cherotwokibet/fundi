import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/provider_repository.dart';
import '../models/service_provider.dart';
import '../state/app_state.dart';
import 'browse_screen.dart';
import 'location_bar.dart';
import 'provider_card.dart';
import 'request_status_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// "Find Me a Mechanic": one choice, an optional note, then the best match.
/// The owner never picks a repair category; the mechanic diagnoses.
/// Nothing is sent to a mechanic until the owner taps "Request this mechanic".
class FindScreen extends ConsumerStatefulWidget {
  const FindScreen({super.key});

  @override
  ConsumerState<FindScreen> createState() => _State();
}

class _State extends ConsumerState<FindScreen> {
  RequestMode mode = RequestMode.comeToMe;
  final note = TextEditingController();
  Attachment? photo;
  Attachment? voice;
  bool recording = false;
  int seconds = 0;
  Timer? ticker;
  late final recorder = ref.read(voiceRecorderProvider);
  static const maxSeconds = 60;
  bool busy = false;
  bool sending = false;
  List<ServiceProvider>? matches;

  @override
  void dispose() {
    ticker?.cancel();
    if (recording) recorder.cancel();
    note.dispose();
    super.dispose();
  }

  Future<void> _addPhoto({required bool camera}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await ref.read(photoPickerProvider)(camera: camera);
      if (picked != null && mounted) setState(() => photo = picked);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not add the photo.')),
      );
    }
  }

  void _choosePhoto() {
    showModalBottomSheet<void>(
      constraints: sheetConstraints,
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('photo-camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(sheet);
                _addPhoto(camera: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(sheet);
                _addPhoto(camera: false);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleVoice() async {
    final messenger = ScaffoldMessenger.of(context);
    if (recording) {
      ticker?.cancel();
      final result = await recorder.stop();
      if (!mounted) return;
      setState(() {
        recording = false;
        voice = result;
      });
      if (result == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Nothing was recorded. Try again.')),
        );
      }
      return;
    }
    if (!await recorder.start()) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'The microphone is not available. You can type instead.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      recording = true;
      seconds = 0;
      voice = null;
    });
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => seconds++);
      if (seconds >= maxSeconds) _toggleVoice();
    });
  }

  Future<void> _find() async {
    final messenger = ScaffoldMessenger.of(context);
    if (recording) await _toggleVoice();
    if (!mounted) return;
    setState(() => busy = true);
    try {
      final all = await ref.read(nearbyProvider.future);
      final found = bestMatches(all, mode);
      if (mounted) setState(() => matches = found);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not search right now. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// The owner said yes: now the request, note, photo and voice note go to
  /// this mechanic.
  Future<void> _request(ServiceProvider p) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => sending = true);
    try {
      final loc = await ref.read(locationProvider.future);
      await ref
          .read(repositoryProvider)
          .createRequest(
            mode: mode,
            lat: loc.lat,
            lng: loc.lng,
            area: loc.label,
            note: note.text,
            photo: photo,
            voice: voice,
            providerId: p.id,
          );
      ref.read(requestVersionProvider.notifier).bump();
      navigator.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const RequestStatusScreen()),
      );
    } on RequestLimitException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not send the request. You can still call ${p.name}.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  String _willGet(ServiceProvider p) {
    final parts = [
      'your location',
      if (note.text.trim().isNotEmpty) 'your note',
      if (photo != null) '1 photo',
      if (voice != null) '1 voice note',
    ];
    final list = parts.length == 1
        ? parts.first
        : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
    return '${p.name} will get $list. Nothing is sent until you tap the button below.';
  }

  @override
  Widget build(BuildContext context) {
    final found = matches;
    return PopScope(
      // Back from the match returns to the form, not all the way home.
      canPop: found == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => matches = null);
      },
      child: Scaffold(
        appBar: AppBar(),
        body: ContentWidth(child: found != null ? _results(found) : _form()),
      ),
    );
  }

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const ScreenTitle('Where\'s the car?', subtitle: LocationBar()),
        const SizedBox(height: 8),
        _ModeTile(
          key: const Key('mode-come'),
          icon: Icons.directions_car_outlined,
          title: 'Come to me',
          subtitle: 'The car is stuck where it is',
          selected: mode == RequestMode.comeToMe,
          onTap: () => setState(() => mode = RequestMode.comeToMe),
        ),
        const SizedBox(height: 10),
        _ModeTile(
          key: const Key('mode-visit'),
          icon: Icons.garage_outlined,
          title: 'I can drive to a garage',
          subtitle: 'The car can still move',
          selected: mode == RequestMode.visitGarage,
          onTap: () => setState(() => mode = RequestMode.visitGarage),
        ),
        const SizedBox(height: 18),
        const Text.rich(
          TextSpan(
            text: 'Tell them more ',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            children: [
              TextSpan(
                text: '(optional)',
                style: TextStyle(fontWeight: FontWeight.w400, color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('note'),
          controller: note,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'What is happening? In your own words.',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFC9D0CA)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFC9D0CA)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('add-voice'),
              onPressed: busy ? null : _toggleVoice,
              icon: Icon(
                recording
                    ? Icons.stop_circle
                    : voice != null
                    ? Icons.check_circle
                    : Icons.mic_none,
                color: recording ? Colors.red : null,
              ),
              label: Text(
                recording
                    ? 'Stop (${seconds}s)'
                    : voice != null
                    ? 'Voice note added'
                    : 'Voice note',
              ),
            ),
            OutlinedButton.icon(
              key: const Key('add-photo'),
              onPressed: busy ? null : _choosePhoto,
              icon: Icon(
                photo != null
                    ? Icons.check_circle
                    : Icons.photo_camera_outlined,
              ),
              label: Text(photo != null ? 'Photo added' : 'Photo'),
            ),
            if (voice != null || photo != null)
              TextButton(
                key: const Key('clear-attachments'),
                onPressed: () => setState(() {
                  voice = null;
                  photo = null;
                }),
                child: const Text('Remove'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'You don\'t need to know what\'s wrong. The mechanic checks the car.',
          style: TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 20),
        BigButton(
          key: const Key('find-submit'),
          label: 'Find a mechanic',
          trailingIcon: Icons.arrow_forward,
          busy: busy,
          onPressed: _find,
        ),
      ],
    );
  }

  Widget _results(List<ServiceProvider> found) {
    if (found.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.schedule, size: 40, color: brandGreen),
            const SizedBox(height: 12),
            Text(
              mode == RequestMode.comeToMe
                  ? 'No mobile mechanic is free near you right now'
                  : 'No garage is open near you right now',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'We won\'t promise someone who isn\'t available. You can see every verified mechanic nearby, including busy ones, and call them directly.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            BigButton(
              label: 'See all mechanics nearby',
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(builder: (_) => const BrowseScreen()),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => matches = null),
              child: const Text('Change my request'),
            ),
          ],
        ),
      );
    }
    final p = found.first;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const ScreenTitle(
          'Your match',
          subtitle: Text('Nearest checked mechanic who is free now'),
        ),
        const SizedBox(height: 14),
        ProviderCard(p, quietCall: true),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            _willGet(p),
            key: const Key('will-get'),
            style: const TextStyle(fontSize: 14, height: 1.45),
          ),
        ),
        const SizedBox(height: 16),
        BigButton(
          key: const Key('request-mechanic'),
          label: 'Request this mechanic',
          busy: sending,
          onPressed: () => _request(p),
        ),
        TextButton(
          key: const Key('see-others'),
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => const BrowseScreen()),
          ),
          child: const Text('See other mechanics nearby'),
        ),
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFF1F5EF) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? brandGreen : hairline,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: brandGreen, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(subtitle, style: const TextStyle(color: muted)),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? brandGreen : const Color(0xFF9AA5A0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
