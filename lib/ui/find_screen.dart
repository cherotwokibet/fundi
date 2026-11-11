import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/provider_repository.dart';
import '../models/service_provider.dart';
import '../state/app_state.dart';
import 'browse_screen.dart';
import 'location_bar.dart';
import 'provider_card.dart';
import 'theme.dart';

/// "Find Me a Mechanic": one choice, an optional note, then the best match.
/// The owner never picks a repair category; the mechanic diagnoses.
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
      final loc = await ref.read(locationProvider.future);
      final all = await ref.read(nearbyProvider.future);
      final found = bestMatches(all, mode);
      // Saving the request must not stop the owner from seeing a mechanic.
      ref
          .read(repositoryProvider)
          .createRequest(
            mode: mode,
            lat: loc.lat,
            lng: loc.lng,
            area: loc.label,
            note: note.text,
            photo: photo,
            voice: voice,
            providerId: found.isEmpty ? null : found.first.id,
          )
          .catchError((_) {});
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

  @override
  Widget build(BuildContext context) {
    final found = matches;
    return Scaffold(
      appBar: AppBar(title: const Text('Find me a mechanic')),
      body: found != null ? _results(found) : _form(),
    );
  }

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const LocationBar(),
        const SizedBox(height: 12),
        const Text(
          'Where should the mechanic help you?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        _ModeTile(
          key: const Key('mode-come'),
          icon: Icons.directions_car_outlined,
          title: 'Come to me',
          subtitle: 'A mobile mechanic comes to where the car is',
          selected: mode == RequestMode.comeToMe,
          onTap: () => setState(() => mode = RequestMode.comeToMe),
        ),
        const SizedBox(height: 10),
        _ModeTile(
          key: const Key('mode-visit'),
          icon: Icons.garage_outlined,
          title: 'I can go to a garage',
          subtitle: 'The car can still move',
          selected: mode == RequestMode.visitGarage,
          onTap: () => setState(() => mode = RequestMode.visitGarage),
        ),
        const SizedBox(height: 20),
        TextField(
          key: const Key('note'),
          controller: note,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What is happening? (optional)',
            hintText: 'In your own words, e.g. "It won\'t start"',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
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
                    : 'Say it instead',
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
              label: Text(photo != null ? 'Photo added' : 'Add a photo'),
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
        Text(
          'All optional. You don\'t need to know what is wrong; the mechanic will check the car.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('find-submit'),
          onPressed: busy ? null : _find,
          child: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Find a mechanic'),
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
            FilledButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const BrowseScreen()),
              ),
              child: const Text('See all mechanics nearby'),
            ),
            TextButton(
              onPressed: () => setState(() => matches = null),
              child: const Text('Change my request'),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        const Text(
          'Your best match',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text('Verified and nearest to you. Call to get help now.'),
        const SizedBox(height: 12),
        ProviderCard(found.first),
        if (found.length > 1) ...[
          const SizedBox(height: 20),
          const Text(
            'If they don\'t pick up',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          for (final p in found.skip(1)) ...[
            ProviderCard(p),
            const SizedBox(height: 12),
          ],
        ],
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
      color: selected ? const Color(0xFFE2EFEA) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? brandGreen : const Color(0xFFD5DBD6),
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
                    Text(subtitle),
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
