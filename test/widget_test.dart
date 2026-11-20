import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fundi/data/account_repository.dart';
import 'package:fundi/data/admin_repository.dart';
import 'package:fundi/data/dev_codes_repository.dart';
import 'package:fundi/data/inbox_repository.dart';
import 'package:fundi/data/parts_repository.dart';
import 'package:fundi/data/sample_directory.dart';
import 'package:fundi/data/provider_repository.dart';
import 'package:fundi/data/voice_player.dart';
import 'package:fundi/data/voice_recorder.dart';
import 'package:fundi/data/zones.dart';
import 'package:fundi/main.dart';
import 'package:fundi/models/quote.dart';
import 'package:fundi/models/service_provider.dart';
import 'package:fundi/models/trade.dart';
import 'package:fundi/state/app_state.dart';
import 'package:fundi/ui/home_screen.dart';
import 'package:fundi/ui/request_status_screen.dart';
import 'package:fundi/ui/shop_screen.dart';

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
      // Car owners never see the parts marketplace.
      expect(find.textContaining('Spare parts'), findsNothing);
      expect(find.textContaining('Order spare parts'), findsNothing);
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

    testWidgets('quote: the owner sees the lines and approves with one tap', (
      tester,
    ) async {
      await pumpApp(tester);
      await findMatch(tester);
      await tester.tap(find.byKey(const Key('request-mechanic')));
      await tester.pumpAndSettle();
      repo.mechanicAccepts();
      await tester.pump(RequestStatusScreen.checkEvery);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('owner-quote')), findsNothing);

      repo.mechanicSendsQuote(const [
        QuoteLine(
          kind: QuoteLineKind.labour,
          description: 'Replace front brake pads',
          unitPriceKes: 1200,
        ),
        QuoteLine(
          kind: QuoteLineKind.part,
          description: 'Front brake pads',
          qty: 2,
          unitPriceKes: 1700,
        ),
      ], note: 'Pads are worn to the metal');
      await tester.pump(RequestStatusScreen.checkEvery);
      await tester.pumpAndSettle();
      expect(find.text('Quote from Otieno Mobile Mechanic'), findsOneWidget);
      expect(find.text('KES 4,600'), findsOneWidget);
      expect(find.textContaining('2 × Front brake pads'), findsOneWidget);
      expect(find.text('"Pads are worn to the metal"'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('quote-approve')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quote-approve')));
      await tester.pumpAndSettle();
      expect(find.text('You approved this quote'), findsOneWidget);
      expect(find.byKey(const Key('quote-approve')), findsNothing);
      expect(
        (await repo.latestQuote((await repo.myOpenRequest())!.id))!.status,
        QuoteStatus.approved,
      );
    });

    testWidgets('job done: the owner rates the mechanic from the home screen', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.byKey(const Key('rate-card')), findsNothing);
      await findMatch(tester);
      await tester.tap(find.byKey(const Key('request-mechanic')));
      await tester.pumpAndSettle();
      repo.mechanicAccepts();
      await tester.pump(RequestStatusScreen.checkEvery);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('status-done')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('status-done')));
      await tester.pumpAndSettle();
      // Back home, asked once, gently.
      expect(find.text('How did Otieno Mobile Mechanic do?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('star-4')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('rate-comment')),
        'Came quickly',
      );
      await tester.tap(find.byKey(const Key('rate-send')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rate-thanks')), findsOneWidget);
      expect(repo.finished!.stars, 4);
      expect(repo.finished!.comment, 'Came quickly');
    });

    testWidgets('rating can be skipped and never blocks the home screen', (
      tester,
    ) async {
      await pumpApp(tester);
      await findMatch(tester);
      await tester.tap(find.byKey(const Key('request-mechanic')));
      await tester.pumpAndSettle();
      repo.mechanicAccepts();
      repo.mechanicMarksDone();
      await tester.pageBack();
      await tester.pumpAndSettle();
      ProviderScope.containerOf(tester.element(find.byType(HomeScreen)))
          .read(requestVersionProvider.notifier)
          .bump();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rate-card')), findsOneWidget);
      await tester.tap(find.byKey(const Key('rate-skip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rate-card')), findsNothing);
      expect(find.text('Find me a mechanic'), findsOneWidget);
    });

    Future<void> acceptedJob(WidgetTester tester) async {
      await findMatch(tester);
      await tester.tap(find.byKey(const Key('request-mechanic')));
      await tester.pumpAndSettle();
      repo.mechanicAccepts();
      await tester.pump(RequestStatusScreen.checkEvery);
      await tester.pumpAndSettle();
    }

    testWidgets('complaint: after a job the owner reports a problem in their '
        'own words, and money back needs an M-Pesa number', (tester) async {
      await pumpApp(tester);
      expect(find.byKey(const Key('report-last-job')), findsNothing);
      await acceptedJob(tester);
      await tester.ensureVisible(find.byKey(const Key('status-done')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('status-done')));
      await tester.pumpAndSettle();

      // Home: rating and the small report link, the main actions untouched.
      expect(find.byKey(const Key('rate-card')), findsOneWidget);
      expect(find.text('Find me a mechanic'), findsOneWidget);
      await tester.tap(find.byKey(const Key('report-last-job')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('complaint-message')),
        'The brakes still squeal',
      );
      await tester.tap(find.byKey(const Key('complaint-refund')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('complaint-send')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Kenyan mobile number'), findsOneWidget);
      expect(repo.complaints, isEmpty);

      await tester.enterText(
        find.byKey(const Key('complaint-phone')),
        '0712 345 678',
      );
      await tester.tap(find.byKey(const Key('complaint-send')));
      await tester.pumpAndSettle();
      expect(find.text('We got your report'), findsOneWidget);
      expect(find.byKey(const Key('report-last-job')), findsNothing);
      final sent = repo.complaints.values.single;
      expect(sent.message, 'The brakes still squeal');
      expect(sent.wantsRefund, isTrue);
    });

    testWidgets('complaint: can be sent from My repair while the job is under '
        'way, without asking for money back', (tester) async {
      await pumpApp(tester);
      await acceptedJob(tester);
      await tester.ensureVisible(find.byKey(const Key('status-report')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('status-report')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('complaint-message')), 'bad');
      await tester.tap(find.byKey(const Key('complaint-send')));
      await tester.pumpAndSettle();
      expect(find.text('Say in a few words what went wrong.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('complaint-message')),
        'They asked for cash before starting',
      );
      await tester.tap(find.byKey(const Key('complaint-send')));
      await tester.pumpAndSettle();
      expect(find.text('We got your report'), findsOneWidget);
      expect(find.byKey(const Key('status-report')), findsNothing);
      expect(repo.complaints.values.single.wantsRefund, isFalse);
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

    testWidgets('waiting: if the mechanic passes, the request goes on to the '
        'next free mechanic by itself', (tester) async {
      await pumpApp(tester);
      await findMatch(tester);
      await tester.tap(find.byKey(const Key('request-mechanic')));
      await tester.pumpAndSettle();
      expect(find.text('This screen updates by itself.'), findsOneWidget);
      final first = (await repo.myOpenRequest())!;

      repo.mechanicPasses();
      await tester.pump(RequestStatusScreen.checkEvery);
      await tester.pumpAndSettle();
      final second = (await repo.myOpenRequest())!;
      expect(second.providerId, isNot(first.providerId));
      expect(second.providerId, isNotNull);
      expect(second.rematchCount, 1);
      // The owner did nothing; they are told who has it now.
      expect(find.text('Waiting for confirmation'), findsOneWidget);
      expect(
        find.textContaining(
          'so we sent your request to ${second.providerName}',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('status-call')), findsOneWidget);
      await tester.tap(find.byKey(const Key('status-call')));
      expect(dialed.last, second.providerPhone);
    });

    testWidgets('waiting: no answer for 5 minutes, the request goes to the '
        'next free mechanic by itself', (tester) async {
      await pumpApp(tester);
      await findMatch(tester);
      await tester.tap(find.byKey(const Key('request-mechanic')));
      await tester.pumpAndSettle();
      final first = (await repo.myOpenRequest())!;

      // Not yet 5 minutes: nothing moves.
      await tester.pump(RequestStatusScreen.checkEvery);
      await tester.pumpAndSettle();
      expect((await repo.myOpenRequest())!.providerId, first.providerId);

      repo.ageRequest(const Duration(minutes: 6));
      await tester.pump(RequestStatusScreen.checkEvery);
      await tester.pumpAndSettle();
      final second = (await repo.myOpenRequest())!;
      expect(second.providerId, isNot(first.providerId));
      expect(second.handoff, Handoff.noAnswer);
      expect(
        find.textContaining(
          'didn\'t answer, so we sent your request to ${second.providerName}',
        ),
        findsOneWidget,
      );
      // The wait starts again for the new mechanic.
      expect(find.text('This screen updates by itself.'), findsOneWidget);
    });

    testWidgets('too many requests in a day: the owner is told plainly and '
        'can still call', (tester) async {
      await pumpApp(tester);
      for (var i = 0; i < 6; i++) {
        await repo.createRequest(
          mode: RequestMode.comeToMe,
          lat: -1.22,
          lng: 36.9,
        );
      }
      await repo.cancelRequest((await repo.myOpenRequest())!.id);
      await findMatch(tester);
      await tester.tap(find.byKey(const Key('request-mechanic')));
      await tester.pumpAndSettle();
      expect(find.textContaining('many requests today'), findsOneWidget);
      // Still on the match, with the call button.
      expect(find.byKey(const Key('request-mechanic')), findsOneWidget);
    });

    testWidgets('waiting: when nobody else is free, the owner is pointed to '
        'mechanics nearby', (tester) async {
      await pumpApp(tester);
      await findMatch(tester);
      await tester.tap(find.byKey(const Key('request-mechanic')));
      await tester.pumpAndSettle();

      // Pass until nobody is left or the request was sent on three times.
      for (var i = 0; i < 5; i++) {
        if ((await repo.myOpenRequest())!.providerId == null) break;
        repo.mechanicPasses();
      }
      expect((await repo.myOpenRequest())!.rematchCount, lessThanOrEqualTo(3));
      await tester.pump(RequestStatusScreen.checkEvery);
      await tester.pumpAndSettle();
      expect(find.text('They can\'t take it'), findsOneWidget);
      expect(find.textContaining('none is free right now'), findsOneWidget);
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

    testWidgets('trade sign-in: an unregistered number gets no way to join', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTradeArea(tester);
      expect(
        find.textContaining('Our team adds every mechanic'),
        findsOneWidget,
      );

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

      expect(find.text('This number is not registered'), findsOneWidget);
      // No listing form, no documents, no way to make themselves a mechanic.
      expect(find.byKey(const Key('listing-name')), findsNothing);
      expect(find.byKey(const Key('upload-national_id')), findsNothing);
      await tester.tap(find.byKey(const Key('not-registered-sign-out')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('phone')), findsOneWidget);
    });

    testWidgets('admin adds a mechanic, approves them, then the mechanic '
        'signs in and goes available', (tester) async {
      await pumpApp(tester);
      await openTradeArea(tester);
      await signIn(tester, '0700 000 000');
      expect(find.text('Admin'), findsOneWidget);

      await tester.tap(find.byKey(const Key('admin-add-listing')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('new-name')),
        'Baraka Mobile Mechanic',
      );
      await tester.enterText(
        find.byKey(const Key('new-owner-phone')),
        '0712 345 678',
      );
      await tester.enterText(find.byKey(const Key('new-fee')), '400');
      await tester.scrollUntilVisible(
        find.byKey(const Key('zone-0')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('zone-0')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('new-submit')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('new-submit')));
      await tester.pumpAndSettle();

      // Let the "Added" message go so it does not cover the buttons.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final added = account.directory.listings.last;
      expect(added.name, 'Baraka Mobile Mechanic');
      expect(added.status, ListingStatus.pending);
      // The number owners call defaults to the sign-in number.
      expect(added.phone, '+254712345678');
      expect(added.area, zones.first.name);

      await tester.scrollUntilVisible(
        find.byKey(Key('check-${added.id}-identity')),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(find.byKey(Key('check-${added.id}-identity')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('check-${added.id}-identity')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(Key('approve-${added.id}')),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(find.byKey(Key('approve-${added.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('approve-${added.id}')));
      await tester.pumpAndSettle();
      expect(added.status, ListingStatus.approved);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await signIn(tester, '0712 345 678');
      expect(find.text('Are you taking jobs now?'), findsOneWidget);
      expect(find.text('Owners see you as offline.'), findsOneWidget);
      expect(find.byKey(const Key('open-parts')), findsOneWidget);
      await tester.tap(find.byKey(const Key('set-available')));
      await tester.pumpAndSettle();
      expect(find.textContaining('available until'), findsOneWidget);
    });

    testWidgets('a mechanic finds a part, orders it and sees the order', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTradeArea(tester);
      await signIn(tester, '0711 000 001');
      await tester.ensureVisible(find.byKey(const Key('open-parts')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-parts')));
      await tester.pumpAndSettle();
      expect(find.text('Front brake pads'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('parts-search')),
        'alternator',
      );
      await tester.enterText(find.byKey(const Key('parts-make')), 'toyota');
      await tester.tap(find.byKey(const Key('parts-search-go')));
      await tester.pumpAndSettle();
      expect(find.text('Alternator'), findsOneWidget);
      expect(find.text('Front brake pads'), findsNothing);

      await tester.tap(find.byKey(const Key('call-shop-part2')));
      expect(dialed, [SampleDirectory.shopPhone]);

      await tester.tap(find.byKey(const Key('add-part2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-part2')));
      await tester.pumpAndSettle();
      expect(find.text('Added (2)'), findsOneWidget);
      // Only 2 in stock: no third.
      await tester.tap(find.byKey(const Key('add-part2')));
      await tester.pumpAndSettle();
      expect(find.text('Only 2 in stock.'), findsOneWidget);
      expect(find.textContaining('2 parts · KES 19,000'), findsOneWidget);
      await tester.tap(find.byKey(const Key('basket-review')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Total KES 19,000'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('order-note')),
        'Collect at 4',
      );
      await tester.tap(find.byKey(const Key('order-send')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Order sent to'), findsOneWidget);
      // Both alternators are now held for this order.
      expect(find.text('Alternator'), findsNothing);

      await tester.tap(find.byKey(const Key('parts-my-orders')));
      await tester.pumpAndSettle();
      expect(find.text('Waiting for the shop'), findsOneWidget);
      expect(find.text('2 × Alternator'), findsOneWidget);
    });

    testWidgets('a mechanic orders several parts from one shop in one order', (
      tester,
    ) async {
      await pumpApp(tester);
      final dir = account.directory;
      // A second sample shop, to check the one-shop-per-order rule.
      final other = dir.addShop(
        name: 'Sample: Industrial Area Parts',
        phone: '+254711000003',
        area: 'Industrial Area',
        ownerPhone: '+254711000003',
      );
      dir.parts.add(
        PartListing(
          id: 'part9',
          shopId: other,
          title: 'Fan belt',
          priceKes: 800,
          stockQty: 5,
        ),
      );
      await openTradeArea(tester);
      await signIn(tester, '0711 000 001');
      await tester.ensureVisible(find.byKey(const Key('open-parts')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-parts')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-part1')));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.byKey(const Key('add-part3')),
        find.byKey(const Key('parts-results')),
        const Offset(0, -150),
      );
      await tester.ensureVisible(find.byKey(const Key('add-part3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-part3')));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 parts · KES 7,600'), findsOneWidget);

      // A part from another shop asks before starting a new order.
      // The cheapest part is at the top of the list.
      await tester.dragUntilVisible(
        find.byKey(const Key('add-part9')),
        find.byKey(const Key('parts-results')),
        const Offset(0, 150),
      );
      await tester.ensureVisible(find.byKey(const Key('add-part9')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-part9')));
      await tester.pumpAndSettle();
      expect(find.text('One shop per order'), findsOneWidget);
      await tester.tap(find.byKey(const Key('basket-keep')));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 parts · KES 7,600'), findsOneWidget);

      await tester.tap(find.byKey(const Key('basket-review')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('qty-plus-part1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Total KES 11,000'), findsOneWidget);
      await tester.tap(find.byKey(const Key('order-send')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Order sent to Sample: Kirinyaga'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('basket-review')), findsNothing);

      final placed = dir.orders.single.order;
      expect(placed.items.map((i) => '${i.qty} × ${i.title}'), [
        '2 × Front brake pads',
        '1 × Engine oil 5W-30, 4 litres',
      ]);
      expect(placed.totalKes, 11000);
    });

    test('one order cannot mix shops', () async {
      final dir = SampleDirectory.seeded();
      final other = dir.addShop(
        name: 'Other',
        phone: '+254711000003',
        area: 'CBD',
        ownerPhone: '+254711000003',
      );
      dir.parts.add(
        PartListing(
          id: 'x',
          shopId: other,
          title: 'Belt',
          priceKes: 1,
          stockQty: 1,
        ),
      );
      dir.claim(SampleDirectory.mechanicPhone);
      final parts = SamplePartsRepository(
        dir,
        () => SampleDirectory.mechanicPhone,
      );
      final buyer = dir.listingOwnedBy(SampleDirectory.mechanicPhone)!;
      expect(
        () => parts.placeOrder(
          buyerId: buyer.id,
          lines: [(partId: 'part1', qty: 1), (partId: 'x', qty: 1)],
        ),
        throwsA(isA<AccountException>()),
      );
      // Nothing was held.
      expect(dir.parts.firstWhere((p) => p.id == 'part1').stockQty, 6);
    });

    testWidgets('a parts shop confirms an order and lists a new part', (
      tester,
    ) async {
      await pumpApp(tester);
      // The sample mechanic orders first, through the same rules.
      final dir = account.directory;
      final mechanicParts = SamplePartsRepository(
        dir,
        () => SampleDirectory.mechanicPhone,
      );
      dir.claim(SampleDirectory.mechanicPhone);
      final buyer = dir.listingOwnedBy(SampleDirectory.mechanicPhone)!;
      await mechanicParts.placeOrder(
        buyerId: buyer.id,
        lines: [(partId: 'part1', qty: 1)],
      );

      await openTradeArea(tester);
      await signIn(tester, '0711 000 002');
      expect(find.text('Sample: Kirinyaga Road Spares'), findsOneWidget);
      expect(find.text(buyer.name), findsOneWidget);
      expect(find.text('Orders (1 new)'), findsOneWidget);
      final order = dir.orders.single.order;
      await tester.tap(find.byKey(Key('order-next-${order.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Confirmed by the shop'), findsOneWidget);
      expect(dir.orders.single.order.status, OrderStatus.confirmed);
      expect(find.text('Orders'), findsOneWidget);

      // A new order shows up by itself while the shop has the screen open.
      await mechanicParts.placeOrder(
        buyerId: buyer.id,
        lines: [(partId: 'part3', qty: 2)],
        note: 'Collect at 5',
      );
      await tester.pump(ShopScreen.checkEvery);
      await tester.pumpAndSettle();
      expect(find.text('Orders (1 new)'), findsOneWidget);
      expect(find.text('2 × Engine oil 5W-30, 4 litres'), findsOneWidget);

      await tester.tap(find.byKey(const Key('shop-tab-parts')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-part')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('part-title')),
        'Shock absorber',
      );
      await tester.enterText(find.byKey(const Key('part-makes')), 'Nissan');
      await tester.scrollUntilVisible(
        find.byKey(const Key('part-price')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(find.byKey(const Key('part-price')), '6500');
      await tester.enterText(find.byKey(const Key('part-stock')), '4');
      await tester.scrollUntilVisible(
        find.byKey(const Key('part-save')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('part-save')));
      await tester.pumpAndSettle();
      expect(find.text('Shock absorber'), findsOneWidget);
      // The mechanic can now find it.
      final found = await mechanicParts.search(query: 'shock', make: 'nissan');
      expect(found.single.priceKes, 6500);
    });

    testWidgets('admin adds a shop worker, who signs in to the shop', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTradeArea(tester);
      await signIn(tester, '0700 000 000');
      await tester.tap(find.byKey(const Key('admin-tab-shops')));
      await tester.pumpAndSettle();
      final shop = account.directory.shops.single;
      await tester.tap(find.byKey(Key('people-${shop.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('member-name')), 'Otieno');
      await tester.enterText(
        find.byKey(const Key('member-phone')),
        '0733 000 111',
      );
      await tester.tap(find.byKey(const Key('member-add')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Not signed in yet'), findsNWidgets(2));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      await signIn(tester, '0733 000 111');
      expect(find.text(shop.name), findsOneWidget);
      expect(find.text('Our parts'), findsOneWidget);
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
    expect(
      (await admin.listings(ListingStatus.approved)).map((l) => l.id),
      contains(first.id),
    );
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
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Mwangi Mobile Mechanic'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('check-p1-identity')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('check-p1-identity')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('approve-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('approve-p1')));
      await tester.pumpAndSettle();
      expect(find.text('Mwangi Mobile Mechanic'), findsNothing);
    },
  );

  test(
    'admin: no refund on a rejected complaint, or above the job cost',
    () async {
      final admin = SampleAdminRepository();
      final c = (await admin.complaints()).single;
      expect(
        () => admin.resolveComplaint(
          c.id,
          uphold: false,
          note: 'No',
          refundKes: 500,
        ),
        throwsA(isA<AccountException>()),
      );
      expect(
        () => admin.resolveComplaint(
          c.id,
          uphold: true,
          note: 'Yes',
          refundKes: 2501,
        ),
        throwsA(isA<AccountException>()),
      );
      expect(
        () => admin.markRefundPaid(c.id, 'QX12'),
        throwsA(isA<AccountException>()),
      );
    },
  );

  testWidgets('admin console: uphold a complaint with a refund, then record '
      'the M-Pesa code', (tester) async {
    final account = SampleAccountRepository();
    await account.verifyCode(
      SampleAccountRepository.adminPhone,
      SampleAccountRepository.sampleCode,
    );
    final admin = SampleAdminRepository(account.directory);
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWithValue(account),
          adminProvider.overrideWithValue(admin),
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
    await tester.tap(find.byKey(const Key('admin-tab-complaints')));
    await tester.pumpAndSettle();

    expect(find.textContaining('brakes still squeal'), findsOneWidget);
    expect(find.textContaining('+254700000000'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('complaint-note-sample-c1')),
      'The pads were fitted badly.',
    );
    // Above the job cost: refused, nothing saved.
    await tester.enterText(
      find.byKey(const Key('complaint-refund-sample-c1')),
      '3000',
    );
    await tester.ensureVisible(
      find.byKey(const Key('complaint-uphold-sample-c1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('complaint-uphold-sample-c1')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('cannot be more than the job cost'),
      findsOneWidget,
    );
    expect(admin.sampleComplaints.single.open, isTrue);

    await tester.enterText(
      find.byKey(const Key('complaint-refund-sample-c1')),
      '2000',
    );
    // Let the error message go so it does not cover the button.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('complaint-uphold-sample-c1')));
    await tester.pumpAndSettle();
    expect(find.text('Refund due: KES 2,000 to +254700000000'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('complaint-code-sample-c1')),
      'qx12ab34',
    );
    await tester.ensureVisible(
      find.byKey(const Key('complaint-paid-sample-c1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('complaint-paid-sample-c1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('M-Pesa code QX12AB34'), findsOneWidget);
    expect(find.byKey(const Key('complaint-paid-sample-c1')), findsNothing);
  });

  group('mechanic inbox', () {
    late _LinkedInbox inbox;
    late _FakePlayer player;

    Future<void> pumpApproved(WidgetTester tester) async {
      final dir = SampleDirectory.seeded();
      final id = dir.addListing(
        type: ProviderType.mobileMechanic,
        name: 'Baraka Mobile Mechanic',
        phone: '+254722000111',
        area: 'Kasarani',
        ownerPhone: '+254712345678',
        status: ListingStatus.approved,
      );
      dir.listings.firstWhere((l) => l.id == id).checks.add(CheckKind.identity);
      final account = SampleAccountRepository(dir);
      await account.verifyCode(
        '+254712345678',
        SampleAccountRepository.sampleCode,
      );
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

    testWidgets('a mechanic sends a quote on a job they took', (tester) async {
      await pumpApproved(tester);
      await tester.tap(find.byKey(const Key('open-inbox')));
      await tester.pumpAndSettle();
      // No quote before taking the job.
      expect(find.byKey(const Key('send-quote-r1')), findsNothing);
      await tester.tap(find.byKey(const Key('accept-r1')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('send-quote-r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send-quote-r1')));
      await tester.pumpAndSettle();
      expect(find.text('Send a quote'), findsWidgets);

      // An empty line is refused.
      await tester.dragUntilVisible(
        find.byKey(const Key('quote-send')),
        find.byType(ListView).last,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quote-send')));
      await tester.pumpAndSettle();
      expect(find.text('Add at least one line.'), findsOneWidget);

      await tester.dragUntilVisible(
        find.byKey(const Key('line-0-description')),
        find.byType(ListView).last,
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('line-0-description')),
        'Replace front brake pads',
      );
      await tester.enterText(find.byKey(const Key('line-0-price')), '1200');
      await tester.enterText(
        find.byKey(const Key('line-1-description')),
        'Front brake pads',
      );
      await tester.enterText(find.byKey(const Key('line-1-qty')), '2');
      await tester.enterText(find.byKey(const Key('line-1-price')), '1700');
      await tester.pumpAndSettle();
      expect(find.text('Total KES 4,600'), findsOneWidget);
      await tester.dragUntilVisible(
        find.byKey(const Key('quote-send')),
        find.byType(ListView).last,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quote-send')));
      await tester.pumpAndSettle();

      expect(find.text('Waiting for the owner to answer.'), findsOneWidget);
      expect(find.text('Send a new quote'), findsOneWidget);
      final sent = (await inbox.latestQuote('r1'))!;
      expect(sent.totalKes, 4600);
      expect(sent.lines.map((l) => l.kind), [
        QuoteLineKind.labour,
        QuoteLineKind.part,
      ]);
    });

    testWidgets('a mechanic marks a job they took as done', (tester) async {
      await pumpApproved(tester);
      await tester.tap(find.byKey(const Key('open-inbox')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('job-done-r1')), findsNothing);
      await tester.tap(find.byKey(const Key('accept-r1')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('job-done-r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('job-done-r1')));
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsOneWidget);
      expect(find.byKey(const Key('job-done-r1')), findsNothing);
      expect(find.byKey(const Key('send-quote-r1')), findsNothing);
    });

    testWidgets('a mechanic answers a complaint about their job, once', (
      tester,
    ) async {
      await pumpApproved(tester);
      inbox.ownerComplains('r1', 'The brakes still squeal after the repair');
      await tester.tap(find.byKey(const Key('open-inbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('accept-r1')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      // Only on the job it is about.
      expect(find.byKey(const Key('complaint-r2')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('complaint-r1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('brakes still squeal'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('complaint-reply-r1')),
        'I can come back tomorrow and adjust them',
      );
      await tester.ensureVisible(
        find.byKey(const Key('complaint-reply-send-r1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('complaint-reply-send-r1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('You answered'), findsOneWidget);
      expect(find.byKey(const Key('complaint-reply-r1')), findsNothing);
      expect(
        (await inbox.complaintFor('r1'))!.providerReply,
        'I can come back tomorrow and adjust them',
      );
      expect(
        () => inbox.replyToComplaint('sc1', 'Again'),
        throwsA(isA<AccountException>()),
      );
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

  testWidgets('test codes page: opens from the link key and leads to the app', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gpsLookupProvider.overrideWithValue(() async => null),
          devCodesProvider.overrideWithValue(_FakeCodes()),
        ],
        child: const FundiApp(codesKey: 'a-long-test-key-0123456789'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test sign-in codes'), findsOneWidget);
    expect(find.text('+254712333444'), findsOneWidget);
    expect(find.text('775991'), findsOneWidget);
    expect(find.text('Text alerts'), findsOneWidget);
    expect(
      find.textContaining('New repair request near Thika'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const Key('codes-open-app')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('codes-open-app')));
    await tester.pumpAndSettle();
    expect(find.text('Find me a mechanic'), findsOneWidget);
  });

  testWidgets('test codes page: a wrong key shows no codes', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gpsLookupProvider.overrideWithValue(() async => null),
          devCodesProvider.overrideWithValue(_FakeCodes()),
        ],
        child: const FundiApp(codesKey: 'wrong'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('This link does not work'), findsOneWidget);
    expect(find.text('775991'), findsNothing);
  });

  group('trade rules in sample mode', () {
    late SampleDirectory dir;
    setUp(() => dir = SampleDirectory.seeded());

    SamplePartsRepository partsFor(String? phone) {
      if (phone != null) dir.claim(phone);
      return SamplePartsRepository(dir, () => phone);
    }

    test('strangers and signed-out people cannot see parts', () async {
      expect(
        () => partsFor('+254799000000').search(),
        throwsA(isA<AccountException>()),
      );
      expect(() => partsFor(null).search(), throwsA(isA<AccountException>()));
    });

    test('a helper at a listing still being checked cannot order', () async {
      dir.addWorker(OrgKind.provider, 'p1', '+254733000222');
      final parts = partsFor('+254733000222');
      expect(() => parts.search(), throwsA(isA<AccountException>()));
      expect(
        () =>
            parts.placeOrder(buyerId: 'p1', lines: [(partId: 'part1', qty: 1)]),
        throwsA(isA<AccountException>()),
      );
    });

    test(
      'a buyer cannot confirm their own order; cancelling gives stock back',
      () async {
        final buyerParts = partsFor(SampleDirectory.mechanicPhone);
        final buyer = dir.listingOwnedBy(SampleDirectory.mechanicPhone)!;
        final id = await buyerParts.placeOrder(
          buyerId: buyer.id,
          lines: [(partId: 'part1', qty: 2)],
        );
        expect(dir.parts.firstWhere((p) => p.id == 'part1').stockQty, 4);
        expect(
          () => buyerParts.updateOrder(id, OrderStatus.confirmed),
          throwsA(isA<AccountException>()),
        );
        await buyerParts.updateOrder(id, OrderStatus.cancelled);
        expect(dir.parts.firstWhere((p) => p.id == 'part1').stockQty, 6);
      },
    );

    test('one number cannot run two listings', () {
      expect(
        () => dir.addListing(
          type: ProviderType.garage,
          name: 'Second',
          phone: SampleDirectory.mechanicPhone,
          area: 'Kasarani',
          ownerPhone: SampleDirectory.mechanicPhone,
        ),
        throwsA(isA<AccountException>()),
      );
    });

    test('a switched-off person loses access', () async {
      final account = SampleAccountRepository(dir);
      await account.verifyCode(
        SampleDirectory.shopPhone,
        SampleAccountRepository.sampleCode,
      );
      expect((await account.access()).shops, hasLength(1));
      dir.members
              .firstWhere((m) => m.phone == SampleDirectory.shopPhone)
              .active =
          false;
      expect((await account.access()).isRegistered, isFalse);
    });

    test('fitment reads in plain words', () {
      const p = PartListing(
        id: 'x',
        shopId: 's',
        title: 'Pads',
        priceKes: 1,
        stockQty: 1,
        makes: ['Toyota'],
        models: 'Probox',
        yearFrom: 2014,
        yearTo: 2022,
      );
      expect(p.fitment, 'Toyota Probox · 2014–2022');
      const any = PartListing(
        id: 'y',
        shopId: 's',
        title: 'Oil',
        priceKes: 1,
        stockQty: 1,
      );
      expect(any.fitment, 'Fits all makes');
      expect(kes(19000), 'KES 19,000');
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

class _FakeCodes extends DevCodesRepository {
  @override
  Future<List<DevCode>> latest(String key) async {
    if (key != 'a-long-test-key-0123456789') throw Exception('Not allowed');
    return [
      (
        phone: '254712333444',
        otp: '775991',
        createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    ];
  }

  @override
  Future<List<DevMessage>> messages(String key) async => [
    (
      phone: '+254700000901',
      body:
          'New repair request near Thika: the owner wants you to come to them.',
      createdAt: DateTime.now(),
    ),
  ];
}

Future<void> openTradeArea(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('home-provider')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('home-provider')));
  await tester.pumpAndSettle();
}

/// Signs in on the trade sign-in screen with the sample code.
Future<void> signIn(WidgetTester tester, String phone) async {
  await tester.enterText(find.byKey(const Key('phone')), phone);
  await tester.tap(find.byKey(const Key('send-code')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('code')),
    SampleAccountRepository.sampleCode,
  );
  await tester.tap(find.byKey(const Key('verify-code')));
  await tester.pumpAndSettle();
}
