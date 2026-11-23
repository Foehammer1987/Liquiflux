import 'dart:ui' show Rect;

import 'package:console_app/services/window_fullscreen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('on a Mac the window goes back where it was after full screen', () async {
    var bounds = const Rect.fromLTWH(15, 33, 1440, 833);
    final calls = <String>[];
    final w = WindowFullscreen(
      mac: true,
      getBounds: () async => bounds,
      setBounds: (r) async {
        calls.add('bounds');
        bounds = r;
      },
      setFull: (on) async {
        calls.add('full $on');
        // macOS put it back somewhere else.
        if (!on) bounds = const Rect.fromLTWH(0, 122, 1440, 833);
      },
    );
    await w.set(true);
    await w.set(false);
    expect(calls, ['full true', 'full false', 'bounds']);
    expect(bounds, const Rect.fromLTWH(15, 33, 1440, 833));
  });

  test('elsewhere it only switches full screen', () async {
    final calls = <String>[];
    final w = WindowFullscreen(mac: false, getBounds: () async => Rect.zero, setBounds: (_) async => calls.add('bounds'), setFull: (on) async => calls.add('full $on'));
    await w.set(true);
    await w.set(false);
    expect(calls, ['full true', 'full false']);
  });
}
