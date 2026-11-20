import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/account_repository.dart';
import '../data/admin_repository.dart';
import '../data/dev_codes_repository.dart';
import '../data/inbox_repository.dart';
import '../data/parts_repository.dart';
import '../data/sample_directory.dart';
import '../data/provider_repository.dart';
import '../data/voice_player.dart';
import '../data/voice_recorder.dart';
import '../data/zones.dart';
import '../models/complaint.dart';
import '../models/quote.dart';
import '../models/service_provider.dart';
import '../models/trade.dart';

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

/// What the signed-in person was added to by an admin (and whether they are
/// an admin). Loading it also links a newly signed-in person to their invites.
final accessProvider = FutureProvider<TradeAccess>((ref) {
  ref.watch(accountVersionProvider);
  final account = ref.watch(accountProvider);
  return account.isSignedIn
      ? account.access()
      : Future.value(const TradeAccess());
});

/// Sample repositories share the account's sample data, so what an admin
/// adds in sample mode is there when that person signs in.
SampleDirectory _sampleDirectory(Ref ref) {
  final account = ref.watch(accountProvider);
  return account is SampleAccountRepository
      ? account.directory
      : SampleDirectory.seeded();
}

/// The trade-only spare parts marketplace.
final partsProvider = Provider<PartsRepository>((ref) {
  final account = ref.watch(accountProvider);
  return SamplePartsRepository(
    _sampleDirectory(ref),
    () => account is SampleAccountRepository ? account.phone : null,
  );
});

/// Requests sent to the signed-in mechanic or garage.
final inboxRepositoryProvider = Provider<InboxRepository>(
  (ref) => SampleInboxRepository(),
);

final inboxProvider = FutureProvider<List<IncomingRequest>>((ref) {
  ref.watch(accountVersionProvider);
  return ref.watch(inboxRepositoryProvider).myRequests();
});

/// Plays voice notes in the inbox. Overridden in tests.
final voicePlayerProvider = Provider<VoicePlayer>((ref) => DeviceVoicePlayer());

/// Development only: the mock sign-in codes page.
final devCodesProvider = Provider<DevCodesRepository>(
  (ref) => SampleDevCodesRepository(),
);

final adminProvider = Provider<AdminRepository>(
  (ref) => SampleAdminRepository(_sampleDirectory(ref)),
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

/// The owner's open request, if any. Bump [requestVersionProvider] to reload.
final requestVersionProvider = NotifierProvider<VersionNotifier, int>(
  VersionNotifier.new,
);

final openRequestProvider = FutureProvider<OwnerRequest?>((ref) {
  ref.watch(requestVersionProvider);
  return ref.watch(repositoryProvider).myOpenRequest();
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

/// The latest quote on the owner's request (My repair).
final quoteProvider = FutureProvider.family<Quote?, String>(
  (ref, requestId) => ref.watch(repositoryProvider).latestQuote(requestId),
);

/// The latest quote on a job in the mechanic's inbox.
final inboxQuoteProvider = FutureProvider.family<Quote?, String>(
  (ref, requestId) => ref.watch(inboxRepositoryProvider).latestQuote(requestId),
);

/// A finished job the owner has not rated yet, for the home screen.
final reviewDueProvider = FutureProvider<ReviewDue?>((ref) {
  ref.watch(requestVersionProvider);
  return ref.watch(repositoryProvider).reviewDue();
});

/// The owner's latest finished job, for "Report a problem" on the home screen.
final lastJobProvider = FutureProvider<LastJob?>((ref) {
  ref.watch(requestVersionProvider);
  return ref.watch(repositoryProvider).lastJob();
});

/// The owner's complaint about a job, or null.
final complaintProvider = FutureProvider.family<Complaint?, String>((
  ref,
  requestId,
) {
  ref.watch(requestVersionProvider);
  return ref.watch(repositoryProvider).complaintFor(requestId);
});

/// The owner's complaint about a job in the mechanic's inbox, or null.
final inboxComplaintProvider = FutureProvider.family<Complaint?, String>(
  (ref, requestId) =>
      ref.watch(inboxRepositoryProvider).complaintFor(requestId),
);
