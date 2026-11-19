import 'package:console_app/platform.dart';
import 'package:console_app/ui/touch.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the phone/tablet build is the mobile form on Android, or any iPhone or iPad', () {
    expect(touchBuild(android: true, ios: false, flavor: 'mobile', env: const {}), isTrue);
    expect(touchBuild(android: true, ios: false, flavor: '', env: const {}), isFalse, reason: 'the TV build');
    expect(touchBuild(android: false, ios: true, flavor: '', env: const {}), isTrue);
    expect(touchBuild(android: false, ios: false, flavor: '', env: const {'CONSOLE_TOUCH': '1'}), isTrue);
    expect(touchBuild(android: false, ios: false, flavor: '', env: const {}), isFalse, reason: 'a desktop');
  });

  Future<bool> compactAt(WidgetTester t, Size size, {required bool touch}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    late bool compact;
    await t.pumpWidget(
      MaterialApp(
        home: TouchDensity(
          touch: touch,
          child: Builder(
            builder: (context) {
              compact = ConsoleDensity.compactOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return compact;
  }

  testWidgets('phones get the compact layout either way up; tablets and non-touch builds never do', (t) async {
    expect(await compactAt(t, const Size(384, 832), touch: true), isTrue);
    expect(await compactAt(t, const Size(832, 384), touch: true), isTrue, reason: 'a phone on its side');
    expect(await compactAt(t, const Size(800, 1280), touch: true), isFalse, reason: 'a tablet');
    expect(await compactAt(t, const Size(1280, 800), touch: true), isFalse);
    expect(await compactAt(t, const Size(384, 832), touch: false), isFalse, reason: 'a narrow desktop window');
  });

  test('a desktop test run is neither TV nor touch', () {
    expect(isTouch, isFalse);
    expect(isAndroidTv, isFalse);
  }, skip: isTv || isTouch);
}
