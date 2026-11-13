import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fundi/data/account_repository.dart';
import 'package:fundi/data/admin_repository.dart';
import 'package:fundi/data/inbox_repository.dart';
import 'package:fundi/data/provider_repository.dart';
import 'package:fundi/data/voice_player.dart';
import 'package:fundi/data/voice_recorder.dart';
import 'package:fundi/data/zones.dart';
import 'package:fundi/main.dart';
import 'package:fundi/models/service_provider.dart';
import 'package:fundi/state/app_state.dart';
import 'package:fundi/ui/request_status_screen.dart';

void main() {
  final kasarani = zones.first;

  group('ranking', () {
    final repo = SampleProviderRepository();

    test(
      'nearby: really available first, then nearest; far ones excluded',
      () async {
        final list = await repo.nearby(lat: kasarani.lat, lng: kasarani.lng);
        expect(list, isNotEmpty);
        expect(list.first.availability, Availability.available);
        // Kilimani is ~13 km from Kasarani, outside the default 10 km.
        expect(list.any((p) => p.area == 'Kilimani'), isFalse);
        final ranks = list.map((p) => p.availability.index).toList();
        expect(ranks, [...ranks]..sort());
      },
    );

    test('bestMatches never offers a busy or offline provider', () async {
      final list = await repo.nearby(lat: kasarani.lat, lng: kasarani.lng);
      for (final mode in RequestMode.values) {
        for (final p in bestMatches(list, mode)) {
          expect(p.availability, isNot(Availability.busy));
          expect(p.availability, isNot(Availability.offline));
        }
      }
    });

    test(
      'come-to-me matches mobile mechanics; visit matches garages',
      () async {
        final list = await repo.nearby(lat: kasarani.lat, lng: kasarani.lng);
        expect(
          bestMatches(list, RequestMode.comeToMe).every((p) => p.isMobile),
          isTrue,
        );
        expect(
          bestMatches(list, RequestMode.visitGarage).every((p) => !p.isMobile),
          isTrue,
        );
      },
    );

    test('fromRow maps a database row, including stale availability', () {
      final p = ServiceProvider.fromRow({
        'id': 'x',
        'type': 'garage',
        'display_name': 'G',
        'business_phone': '+254700000000',
        'area': 'A',
        'lat': -1.2,
        'lng': 36.8,
        'distance_km': 1.3,
        'availability': 'unconfirmed',
        'checks_passed': ['identity', 'business'],
        'callout_fee_kes': 300,
        'makes': <dynamic>[],
        'rating_avg': 4.5,
        'rating_count': 10,
        'service_radius_km': 0,
      });
      expect(p.type, ProviderType.garage);
      expect(p.availability, Availability.unconfirmed);
      expect(p.checksPassed, {CheckKind.identity, CheckKind.business});
    });
  });

  group('owner journeys', () {
    late SampleProviderRepository repo;
    late SampleAccountRepository account;
    late List<String> dialed;

    Future<void> pumpApp(WidgetTester tester) async {
      // The sample mechanic only answers when a test tells it to.
      repo = SampleProviderRepository(acceptAfter: null);
      account = SampleAccountRepository();
      dialed = [];
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            accountProvider.overrideWithValue(account),
            voiceRecorderProvider.overrideWithValue(_FakeRecorder()),
            photoPickerProvider.overrideWithValue(
              ({required bool camera}) async =>
                  (bytes: Uint8List.fromList([1, 2, 3]), mime: 'image/jpeg'),
            ),
            gpsLookupProvider.overrideWithValue(() async => null),
            dialerProvider.overrideWithValue((phone) async {
              dialed.add(phone);
              return true;
            }),
          ],
          child: const FundiApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('home shows the two actions and no login', (tester) async {
      await pumpApp(tester);
      expect(find.text('Find me a mechanic'), findsOneWidget);
      expect(find.text('Browse and call'), findsOneWidget);
      expect(find.textContaining('Sign in'), findsNothing);
      // No open request, so no My repair button.
      expect(find.byKey(const Key('home-my-repair')), findsNothing);
    });

    testWidgets('browse then call: two taps open the dialer and log the tap', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.byKey(const Key('home-browse')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('call-s1')));
      await tester.pump();
      expect(dialed, ['+254700000001']);
      expect(repo.loggedContacts.single.kind, ContactKind.callTap);
      expect(
        find.textContaining('Did Otieno Mobile Mechanic help?'),
        findsOneWidget,
      );
    });

    Future<void> findMatch(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('home-find')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('find-submit')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('find-submit')));
      await tester.pumpAndSettle();
    }

    testWidgets('find me: no category needed; nothing is sent before the '
        'owner confirms', (tester) async {
      await pumpApp(tester);
      await findMatch(tester);
      expect(find.text('Your match'), findsOneWidget);
      expect(find.text('Otieno Mobile Mechanic'), findsOneWidget);
      expect(
        find.textContaining('Nothing is sent until you tap'),
        findsOneWidget,
      );
      // Seeing the match sends nothing.
      expect(repo.requests, isEmpty);
      // Calling is still one tap from here.
      await tester.tap(find.byKey(const Key('call-s1')));
      await tester.pump();
      expect(dialed, ['+254700000001']);
      expect(repo.requests, isEmpty);
    });

    testWidgets('find me: confirm sends the request and shows the wait', (
      tester,
    ) async {
      await pumpApp(tester);
      await findMatch(tester);
      await tester.tap(find.byKey(const Key('request-mechanic')));
      await tester.pumpAndSettle();
      expect(repo.requests, [RequestMode.comeToMe]);
      expect(find.text('Waiting for confirmation'), findsOneWidget);
      expect(
        find.text('Otieno Mobile Mechanic has your request.'),
        findsOneWidget,
      );

      // The mechanic takes the job; the screen finds out on its next check.
      repo.mechanicAccepts();
      await tester.pump(RequestStatusScreen.checkEvery);
      await tester.pumpAndSettle();
      expect(find.text('Request accepted'), findsOneWidget);
      await tester.tap(find.byKey(const Key('status-call')));
      await tester.pump();
      expect(dialed, ['+254700000001']);
    });

    testWidgets('find me: a photo and a voice note travel with the request', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.byKey(const Key('home-find')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-voice')));
      await tester.pump();
      expect(find.textContaining('Stop ('), findsOneWidget);
      await tester.tap(find.byKey(const Key('add-voice')));
      await tester.pump();
      expect(find.text('Voice note added'), findsOneWidget);

      await tester.tap(find.byKey(const Key('add-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('photo-camera')));
      await tester.pumpAndSettle();
      expect(find.text('Photo added'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('find-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('find-submit')));
      await tester.pumpAndSettle();
      // The owner is told exactly what will be shared.
      expect(
        find.textContaining('your location, 1 photo and 1 voice note'),
        findsOneWidget,
      );
      expect(repo.lastAttachments, isNull);
      await tester.tap(find.byKey(const Key('request-mechanic')));
      await tester.pumpAndSettle();
      expect(repo.lastAttachments, (photo: true, voice: true));
    });

    testWidgets('my repair: get back to the request from home, then cancel', (
      tester,
    ) async {
      await pumpApp(tester);
      await findMatch(tester);
      await tester.tap(find.byKey(const Key('request-mechanic')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('home-my-repair')));
      await tester.pumpAndSettle();
      expect(find.text('Waiting for confirmation'), findsOneWidget);

      await tester.tap(find.byKey(const Key('cancel-request')));
      await tester.pumpAndSettle();
      expect(find.text('Find me a mechanic'), findsOneWidget);
      expect(find.byKey(const Key('home-my-repair')), findsNothing);
      expect(await repo.myOpenRequest(), isNull);
    });

    testWidgets('waiting: after 5 minutes, or if the mechanic passes, the '
        'owner is pointed to someone else', (tester) async {
      await pumpApp(tester);
      await findMatch(tester);
      await tester.tap(find.byKey(const Key('request-mechanic')));
      await tester.pumpAndSettle();
      expect(find.text('This screen updates by itself.'), findsOneWidget);

      repo.mechanicPasses();
      await tester.pump(RequestStatusScreen.checkEvery);
      await tester.pumpAndSettle();
      expect(find.text('They can\'t take it'), findsOneWidget);
      await tester.tap(find.byKey(const Key('status-others')));
      await tester.pumpAndSettle();
      expect(find.text('Mechanics nearby'), findsOneWidget);
    });

    testWidgets('safety: emergency numbers are two taps from home', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.ensureVisible(find.byKey(const Key('home-safety')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-safety')));
      await tester.pumpAndSettle();
      expect(find.text('Are you safe?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sos-999')));
      await tester.pump();
      expect(dialed, ['999']);
    });

    testWidgets('browse card: freshness, checks in words, fee and what it '
        'covers', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byKey(const Key('home-browse')));
      await tester.pumpAndSettle();
      expect(find.text('Available · Updated 4 min ago'), findsOneWidget);
      expect(find.text('ID, location and experience checked'), findsWidgets);
      expect(find.text('KES 500'), findsWidgets);
      expect(find.text('Visit and inspection'), findsWidgets);
    });

    for (final size in const [Size(320, 568), Size(360, 640), Size(390, 844)]) {
      testWidgets('layout holds at ${size.width.round()} px wide with text '
          'at 1.5 times size', (tester) async {
        await pumpApp(tester);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        // Any overflow is thrown as an error by the test framework.
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const Key('home-browse')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('home-browse')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('home-find')));
        await tester.pumpAndSettle();
        await findMatch(tester);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byKey(const Key('request-mechanic')),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('request-mechanic')));
        await tester.pumpAndSettle();
        expect(find.text('Waiting for confirmation'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('desktop: home shows everything without scrolling, in two '
        'columns', (tester) async {
      await pumpApp(tester);
      // A laptop window. (The test font is wider than the real one.)
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final findBox = tester.getRect(find.byKey(const Key('home-find')));
      final browseBox = tester.getRect(find.byKey(const Key('home-browse')));
      // Side by side, not stacked, and both on screen.
      expect(browseBox.left, greaterThan(findBox.right));
      for (final key in [
        'home-find',
        'home-browse',
        'home-safety',
        'home-provider',
      ]) {
        final box = tester.getRect(find.byKey(Key(key)));
        expect(box.bottom, lessThanOrEqualTo(720), reason: key);
      }
      expect(find.text('HOW IT WORKS'), findsOneWidget);
    });

    testWidgets('desktop: browse shows two cards per row; forms stay narrow', (
      tester,
    ) async {
      await pumpApp(tester);
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-browse')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final first = tester.getRect(find.byKey(const Key('call-s1')));
      final second = tester.getRect(find.byKey(const Key('call-s2')));
      expect(second.left, greaterThan(first.right));
      await tester.pageBack();
      await tester.pumpAndSettle();

      await findMatch(tester);
      expect(tester.takeException(), isNull);
      final button = tester.getRect(find.byKey(const Key('request-mechanic')));
      expect(button.width, lessThanOrEqualTo(560));
      // Centred, not stuck to the left edge.
      expect((button.center.dx - 683).abs(), lessThan(2));
    });

    testWidgets('phone: home stays one column', (tester) async {
      await pumpApp(tester);
      final findBox = tester.getRect(find.byKey(const Key('home-find')));
      final browseBox = tester.getRect(find.byKey(const Key('home-browse')));
      expect(browseBox.top, greaterThan(findBox.bottom));
      expect(find.text('HOW IT WORKS'), findsNothing);
    });

    testWidgets('every tappable thing on home is at least 48 px tall', (
      tester,
    ) async {
      await pumpApp(tester);
      for (final key in [
        'home-find',
        'home-browse',
        'home-safety',
        'home-provider',
        'location-bar',
      ]) {
        final box = tester.getSize(find.byKey(Key(key)));
        expect(box.height, greaterThanOrEqualTo(48), reason: key);
      }
    });

    testWidgets('stale availability is never shown as available', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.byKey(const Key('home-browse')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Wanjiru Auto Electrics'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Availability not confirmed'), findsOneWidget);
    });

    testWidgets('mechanic: sign in, apply, then switch to available', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.ensureVisible(find.byKey(const Key('home-provider')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-provider')));
      await tester.pumpAndSettle();

      // A bad number is rejected before any code is sent.
      await tester.enterText(find.byKey(const Key('phone')), '12345');
      await tester.tap(find.byKey(const Key('send-code')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Enter a Kenyan mobile number'),
        findsOneWidget,
      );

      await tester.enterText(find.byKey(const Key('phone')), '0712 345 678');
      await tester.tap(find.byKey(const Key('send-code')));
      await tester.pumpAndSettle();
      expect(find.textContaining('+254712345678'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('code')), '000000');
      await tester.tap(find.byKey(const Key('verify-code')));
      await tester.pumpAndSettle();
      expect(find.text('That code is not correct.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('code')), '123456');
      await tester.tap(find.byKey(const Key('verify-code')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('listing-name')),
        'Baraka Mobile Mechanic',
      );
      await tester.enterText(
        find.byKey(const Key('listing-phone')),
        '0722000111',
      );
      await tester.enterText(find.byKey(const Key('listing-fee')), '400');
      await tester.scrollUntilVisible(
        find.byKey(const Key('listing-submit')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('listing-submit')));
      await tester.pumpAndSettle();

      final sent = account.lastApplication!;
      expect(sent.businessPhone, '+254722000111');
      expect(sent.calloutFeeKes, 400);
      expect(sent.area, zones.first.name);

      // Pending until both required documents are uploaded.
      expect(find.text('One more step: your documents'), findsOneWidget);
      expect(find.text('Are you taking jobs now?'), findsNothing);
      for (final kind in ['national_id', 'selfie']) {
        await tester.tap(find.byKey(Key('upload-$kind')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('doc-camera')));
        await tester.pumpAndSettle();
      }

      expect(find.text('Are you taking jobs now?'), findsOneWidget);
      expect(find.text('Owners see you as offline.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('set-available')));
      await tester.pumpAndSettle();
      expect(find.textContaining('available until'), findsOneWidget);
    });
  });

  test('admin: cannot approve before identity is checked', () async {
    final admin = SampleAdminRepository();
    var waiting = await admin.listings(ListingStatus.pending);
    final first = waiting.firstWhere((l) => !l.canApprove);
    expect(
      () => admin.setStatus(first.id, ListingStatus.approved),
      throwsA(isA<AccountException>()),
    );
    await admin.setCheck(first.id, CheckKind.identity, true);
    await admin.setStatus(first.id, ListingStatus.approved);
    waiting = await admin.listings(ListingStatus.pending);
    expect(waiting.any((l) => l.id == first.id), isFalse);
    expect((await admin.listings(ListingStatus.approved)).single.id, first.id);
  });

  testWidgets(
    'admin console: tick identity, approve, listing leaves the queue',
    (tester) async {
      final account = SampleAccountRepository();
      await account.verifyCode(
        SampleAccountRepository.adminPhone,
        SampleAccountRepository.sampleCode,
      );
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountProvider.overrideWithValue(account),
            gpsLookupProvider.overrideWithValue(() async => null),
          ],
          child: const FundiApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('home-provider')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-provider')));
      await tester.pumpAndSettle();
      expect(find.text('Verification'), findsOneWidget);
      expect(find.text('Mwangi Mobile Mechanic'), findsOneWidget);
      await tester.tap(find.byKey(const Key('check-p1-identity')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('approve-p1')));
      await tester.pumpAndSettle();
      expect(find.text('Mwangi Mobile Mechanic'), findsNothing);
    },
  );

  group('mechanic inbox', () {
    late _LinkedInbox inbox;
    late _FakePlayer player;

    Future<void> pumpApproved(WidgetTester tester) async {
      final account = SampleAccountRepository();
      await account.verifyCode(
        '+254712345678',
        SampleAccountRepository.sampleCode,
      );
      await account.apply(
        const ListingApplication(
          type: ProviderType.mobileMechanic,
          name: 'Baraka Mobile Mechanic',
          businessPhone: '+254722000111',
          area: 'Kasarani',
          lat: -1.22,
          lng: 36.9,
          serviceRadiusKm: 5,
        ),
      );
      final bytes = Uint8List.fromList([1]);
      await account.uploadDocument(
        DocumentKind.nationalId,
        bytes,
        'image/jpeg',
      );
      await account.uploadDocument(DocumentKind.selfie, bytes, 'image/jpeg');
      inbox = _LinkedInbox();
      player = _FakePlayer();
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountProvider.overrideWithValue(account),
            inboxRepositoryProvider.overrideWithValue(inbox),
            voicePlayerProvider.overrideWithValue(player),
            gpsLookupProvider.overrideWithValue(() async => null),
          ],
          child: const FundiApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('home-provider')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-provider')));
      await tester.pumpAndSettle();
    }

    testWidgets('shows waiting requests with note and voice note', (
      tester,
    ) async {
      await pumpApproved(tester);
      expect(find.text('2 owners are waiting for an answer'), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-inbox')));
      await tester.pumpAndSettle();

      expect(find.textContaining('clicking sound'), findsOneWidget);
      expect(
        find.text('No note. The owner wants you to look at the car.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('voice-r1')));
      await tester.pumpAndSettle();
      expect(player.played, ['https://files.test/sample/voice']);
    });

    testWidgets('take one request and pass on another', (tester) async {
      await pumpApproved(tester);
      await tester.tap(find.byKey(const Key('open-inbox')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('accept-r1')));
      await tester.pumpAndSettle();
      expect(find.text('You took this'), findsOneWidget);
      expect(find.byKey(const Key('accept-r1')), findsNothing);
      // Let the confirmation message clear before the next tap.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('decline-r2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('decline-r2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('request-r2')), findsNothing);

      // Back on the manage screen nothing is waiting any more.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('No new requests'), findsOneWidget);
    });

    test('a request can only be answered once', () async {
      final repo = SampleInboxRepository();
      await repo.respond('r1', accept: true);
      expect(
        () => repo.respond('r1', accept: false),
        throwsA(isA<AccountException>()),
      );
    });

    test('fromRow maps an inbox row', () {
      final r = IncomingRequest.fromRow({
        'id': 'x',
        'mode': 'visit_garage',
        'created_at': '2026-11-11T08:00:00Z',
        'status': 'accepted',
        'note': null,
        'voice_path': 'u/1/voice',
        'distance_km': 2,
      });
      expect(r.mode, RequestMode.visitGarage);
      expect(r.status, RequestStatus.accepted);
      expect(r.waiting, isFalse);
      expect(r.voicePath, 'u/1/voice');
      expect(r.distanceKm, 2.0);
    });
  });

  test('normalizeKenyanPhone accepts common formats and rejects others', () {
    expect(normalizeKenyanPhone('0712 345 678'), '+254712345678');
    expect(normalizeKenyanPhone('712345678'), '+254712345678');
    expect(normalizeKenyanPhone('+254 112 345 678'), '+254112345678');
    expect(normalizeKenyanPhone('254712345678'), '+254712345678');
    expect(normalizeKenyanPhone('0812345678'), isNull);
    expect(normalizeKenyanPhone('07123'), isNull);
    expect(normalizeKenyanPhone(''), isNull);
  });
}

class _FakeRecorder implements VoiceRecorder {
  @override
  Future<bool> start() async => true;

  @override
  Future<Recording?> stop() async =>
      (bytes: Uint8List.fromList([9, 9]), mime: 'audio/mp4');

  @override
  Future<void> cancel() async {}
}

/// Sample inbox that hands out a link, so playback can be checked.
class _LinkedInbox extends SampleInboxRepository {
  @override
  Future<String> fileUrl(String path) async => 'https://files.test/$path';
}

class _FakePlayer implements VoicePlayer {
  final List<String> played = [];

  @override
  Future<void> play(String url) async => played.add(url);

  @override
  Future<void> stop() async {}
}
