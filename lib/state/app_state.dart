import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/account_repository.dart';
import '../data/admin_repository.dart';
import '../data/provider_repository.dart';
import '../data/voice_recorder.dart';
import '../data/zones.dart';
import '../models/service_provider.dart';

/// Overridden in main.dart with the Supabase repository when keys are set.
final repositoryProvider = Provider<ProviderRepository>(
  (ref) => SampleProviderRepository(),
);

/// Sign-in and listing management for mechanics and garages.
final accountProvider = Provider<AccountRepository>(
  (ref) => SampleAccountRepository(),
);

/// Bumped when sign-in state changes, so screens that depend on it rebuild.
class VersionNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final accountVersionProvider = NotifierProvider<VersionNotifier, int>(
  VersionNotifier.new,
);

/// The signed-in provider's own listing, or null if they have not applied.
final myListingProvider = FutureProvider<MyListing?>((ref) {
  ref.watch(accountVersionProvider);
  return ref.watch(accountProvider).myListing();
});

/// Documents the signed-in provider has uploaded.
final myDocumentsProvider = FutureProvider<Set<DocumentKind>>((ref) {
  ref.watch(accountVersionProvider);
  return ref.watch(accountProvider).myDocuments();
});

/// Whether the signed-in user may open the admin console.
final isAdminProvider = FutureProvider<bool>((ref) {
  ref.watch(accountVersionProvider);
  final account = ref.watch(accountProvider);
  return account.isSignedIn ? account.isAdmin() : Future.value(false);
});

final adminProvider = Provider<AdminRepository>(
  (ref) => SampleAdminRepository(),
);

typedef PickedPhoto = ({Uint8List bytes, String mime});

/// Takes a photo with the camera, or picks one. Null if cancelled.
/// Overridden in tests.
final photoPickerProvider =
    Provider<Future<PickedPhoto?> Function({required bool camera})>((ref) {
      return ({required bool camera}) async {
        final file = await ImagePicker().pickImage(
          source: camera ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 1600,
          imageQuality: 80,
        );
        if (file == null) return null;
        return (
          bytes: await file.readAsBytes(),
          mime: file.mimeType ?? 'image/jpeg',
        );
      };
    });

/// Microphone recorder for voice notes. Overridden in tests.
final voiceRecorderProvider = Provider<VoiceRecorder>(
  (ref) => DeviceVoiceRecorder(),
);

/// True while the app runs on built-in sample data.
final sampleModeProvider = Provider<bool>((ref) => true);

/// Opens the phone dialer. Overridden in tests.
final dialerProvider = Provider<Future<bool> Function(String phone)>(
  (ref) =>
      (phone) => launchUrl(Uri(scheme: 'tel', path: phone)),
);

/// Where the owner is: from GPS, or a zone they picked.
class OwnerLocation {
  const OwnerLocation(this.lat, this.lng, this.label, {this.fromGps = false});
  final double lat;
  final double lng;
  final String label;
  final bool fromGps;
}

/// Asks the device for a position. Returns null if it is off or denied.
final gpsLookupProvider = Provider<Future<OwnerLocation?> Function()>((ref) {
  return () async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return OwnerLocation(
        p.latitude,
        p.longitude,
        'your location',
        fromGps: true,
      );
    } catch (_) {
      return null;
    }
  };
});

class LocationNotifier extends AsyncNotifier<OwnerLocation> {
  @override
  Future<OwnerLocation> build() async {
    final gps = await ref.read(gpsLookupProvider)();
    return gps ?? _fromZone(zones.first);
  }

  OwnerLocation _fromZone(Zone z) => OwnerLocation(z.lat, z.lng, z.name);

  void pickZone(Zone z) => state = AsyncData(_fromZone(z));

  Future<void> useGps() async {
    final gps = await ref.read(gpsLookupProvider)();
    if (gps != null) state = AsyncData(gps);
  }
}

final locationProvider = AsyncNotifierProvider<LocationNotifier, OwnerLocation>(
  LocationNotifier.new,
);

/// Verified providers near the owner, ready for both home-screen journeys.
final nearbyProvider = FutureProvider<List<ServiceProvider>>((ref) async {
  final loc = await ref.watch(locationProvider.future);
  return ref.watch(repositoryProvider).nearby(lat: loc.lat, lng: loc.lng);
});

/// Best matches for "Find Me a Mechanic": only providers that can actually
/// take the job now, in ranked order. Busy and offline providers never match.
List<ServiceProvider> bestMatches(
  List<ServiceProvider> all,
  RequestMode mode, {
  int limit = 3,
}) {
  final fits = all.where((p) {
    if (p.availability == Availability.busy ||
        p.availability == Availability.offline) {
      return false;
    }
    return mode == RequestMode.comeToMe ? p.canComeToOwner : !p.isMobile;
  }).toList()..sort(compareProviders);
  return fits.take(limit).toList();
}
