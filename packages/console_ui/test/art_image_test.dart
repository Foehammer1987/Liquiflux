import 'dart:async';

import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _art({required bool onstage}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: TickerMode(
      enabled: onstage,
      child: ArtImage('http://plex.test/art.jpg', width: 120, height: 80, errorBuilder: (_, _, _) => const SizedBox()),
    ),
  ),
);

void main() {
  tearDown(() {
    ArtMemory.releaseCovered.value = false;
    ArtMemory.releaseAll.value = false;
    ArtMemory.maxDecodeWidth = null;
    DrawProbe.noArt = false;
  });

  testWidgets('measuring without artwork shows none, at the same size', (tester) async {
    DrawProbe.noArt = true;
    await tester.pumpWidget(_art(onstage: true));
    expect(find.byType(Image), findsNothing);
    expect(tester.getSize(find.byType(ArtImage)), const Size(120, 80));
  });

  group('decode width', () {
    test('the narrower of the asked width and the cap', () {
      expect(ArtImage.decodeWidthFor(null, null), isNull);
      expect(ArtImage.decodeWidthFor(480, null), 480);
      expect(ArtImage.decodeWidthFor(null, 1280), 1280);
      expect(ArtImage.decodeWidthFor(480, 1280), 480);
      expect(ArtImage.decodeWidthFor(1920, 1280), 1280);
    });

    testWidgets('capped artwork decodes through ResizeImage', (tester) async {
      ArtMemory.maxDecodeWidth = 1280;
      await tester.pumpWidget(_art(onstage: true));
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<ResizeImage>());
      expect((image.image as ResizeImage).width, 1280);
    });
  });

  group('covered pages', () {
    testWidgets('keep their artwork until asked to let go', (tester) async {
      await tester.pumpWidget(_art(onstage: false));
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('let go of it while a 4K video plays, and get it back once uncovered', (tester) async {
      await tester.pumpWidget(_art(onstage: false));
      ArtMemory.releaseCovered.value = true;
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      // Same size, so nothing behind moves.
      expect(tester.getSize(find.byType(ArtImage)), const Size(120, 80));
      // The video ends, but this page is still covered (Home behind the title page).
      ArtMemory.releaseCovered.value = false;
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(_art(onstage: true));
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('the page on top keeps its artwork', (tester) async {
      ArtMemory.releaseCovered.value = true;
      await tester.pumpWidget(_art(onstage: true));
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('the page under a pushed route lets go, and gets it back on Back', (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: Center(child: ArtImage('http://plex.test/art.jpg', width: 120, height: 80, errorBuilder: (_, _, _) => const SizedBox())),
        ),
      );
      ArtMemory.releaseCovered.value = true;
      await tester.pump();
      expect(find.byType(Image, skipOffstage: false), findsOneWidget);
      unawaited(nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const ColoredBox(color: Colors.black))));
      await tester.pumpAndSettle();
      expect(find.byType(Image, skipOffstage: false), findsNothing);
      nav.currentState!.pop();
      await tester.pump();
      // Back as soon as the page starts to show again.
      expect(find.byType(Image, skipOffstage: false), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('all artwork lets go while the hidden pages are drawn again, and comes back after', (tester) async {
      await tester.pumpWidget(_art(onstage: true));
      ArtMemory.releaseAll.value = true;
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(tester.getSize(find.byType(ArtImage)), const Size(120, 80));
      ArtMemory.releaseAll.value = false;
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('a page uncovered gets its artwork back', (tester) async {
      ArtMemory.releaseCovered.value = true;
      await tester.pumpWidget(_art(onstage: false));
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(_art(onstage: true));
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
