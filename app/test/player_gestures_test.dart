// The player's touch gestures (phones and tablets): volume, brightness, seek, pinch, and how
// they live with the player's own taps and double taps and the screen's edge swipes.
import 'package:console_app/services/screen_brightness.dart';
import 'package:console_app/ui/player/player_gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBrightness extends ScreenBrightness {
  double value = 0.5;
  @override
  Future<double> get() async => value;
  @override
  Future<void> set(double v) async => value = v;
  @override
  Future<void> reset() async => value = 0.5;
}

void main() {
  const screen = Size(800, 400);

  late double volume;
  late Duration? seekedTo;
  late bool fill;
  late int taps;
  late int doubleTaps;
  late _FakeBrightness brightness;

  Future<void> pump(WidgetTester t, {bool enabled = true}) async {
    t.view.physicalSize = screen;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    volume = 50;
    seekedTo = null;
    fill = false;
    taps = 0;
    doubleTaps = 0;
    brightness = _FakeBrightness();
    await t.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => PlayerGestures(
            enabled: enabled,
            position: () => const Duration(minutes: 10),
            duration: () => const Duration(hours: 2),
            volume: () => volume,
            onVolume: (v) => volume = v,
            onSeek: (d) => seekedTo = d,
            fill: fill,
            onFill: (f) => setState(() => fill = f),
            brightness: brightness,
            // The player's own taps, as on the picture.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              onDoubleTap: () => doubleTaps++,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> drag(WidgetTester t, Offset from, Offset by) async {
    final g = await t.startGesture(from);
    for (var i = 1; i <= 10; i++) {
      await g.moveBy(by / 10);
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await t.pump();
  }

  testWidgets('up on the right half turns the volume up, down turns it down', (t) async {
    await pump(t);
    await drag(t, const Offset(600, 300), const Offset(0, -150));
    expect(volume, greaterThan(90));
    await drag(t, const Offset(600, 100), const Offset(0, 200));
    expect(volume, lessThan(40));
    expect(seekedTo, isNull);
  });

  testWidgets('up and down on the left half change the brightness', (t) async {
    await pump(t);
    await drag(t, const Offset(200, 300), const Offset(0, -150));
    expect(brightness.value, greaterThan(0.9));
    expect(volume, 50, reason: 'the volume is the right half\'s');
  });

  testWidgets('sideways seeks on release, by the distance dragged', (t) async {
    await pump(t);
    // A quarter of the width is a quarter of two minutes.
    await drag(t, const Offset(300, 200), const Offset(200, 0));
    expect(seekedTo, isNotNull);
    expect(seekedTo!.inSeconds, closeTo(const Duration(minutes: 10, seconds: 30).inSeconds, 3));
  });

  testWidgets('a seek dragged back to where it started is cancelled', (t) async {
    await pump(t);
    final g = await t.startGesture(const Offset(300, 200));
    for (final dx in <double>[40, 40, 40, -40, -40, -39]) {
      await g.moveBy(Offset(dx, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await t.pump();
    expect(seekedTo, isNull);
  });

  testWidgets('the seek shows where it would go while dragging', (t) async {
    await pump(t);
    final g = await t.startGesture(const Offset(300, 200));
    for (var i = 0; i < 5; i++) {
      await g.moveBy(const Offset(40, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('10:30'), findsOneWidget);
    expect(find.text('+0:30'), findsOneWidget);
    await g.up();
    await t.pump();
  });

  testWidgets('two fingers apart fill the screen, together fit it again', (t) async {
    await pump(t);
    Future<void> pinch(double from, double to) async {
      final a = await t.startGesture(Offset(400 - from, 200), pointer: 1);
      final b = await t.startGesture(Offset(400 + from, 200), pointer: 2);
      for (var i = 1; i <= 8; i++) {
        final d = from + (to - from) * i / 8;
        await a.moveTo(Offset(400 - d, 200));
        await b.moveTo(Offset(400 + d, 200));
        await t.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await t.pump();
    }

    await pinch(60, 140);
    expect(fill, isTrue);
    await pinch(140, 60);
    expect(fill, isFalse);
  });

  testWidgets('taps and double taps still reach the player', (t) async {
    await pump(t);
    await t.tapAt(const Offset(400, 200));
    await t.pump(const Duration(milliseconds: 400));
    expect(taps, 1);
    await t.tapAt(const Offset(700, 200));
    await t.pump(const Duration(milliseconds: 50));
    await t.tapAt(const Offset(700, 200));
    await t.pump(const Duration(milliseconds: 400));
    expect(doubleTaps, 1);
    expect(volume, 50);
    expect(seekedTo, isNull);
  });

  testWidgets('a swipe from a screen edge is the system\'s', (t) async {
    await pump(t);
    // The left edge (iOS back), the bottom (home indicator), the top (Control Center).
    await drag(t, const Offset(8, 200), const Offset(300, 0));
    await drag(t, const Offset(600, 396), const Offset(0, -200));
    await drag(t, const Offset(600, 6), const Offset(0, 200));
    expect(seekedTo, isNull);
    expect(volume, 50);
  });

  testWidgets('off (a panel open, or turned off in Settings): nothing changes', (t) async {
    await pump(t, enabled: false);
    await drag(t, const Offset(600, 300), const Offset(0, -150));
    await drag(t, const Offset(300, 200), const Offset(200, 0));
    expect(volume, 50);
    expect(seekedTo, isNull);
    await t.tapAt(const Offset(400, 200));
    await t.pump(const Duration(milliseconds: 400));
    expect(taps, 1, reason: 'taps still work');
  });
}
