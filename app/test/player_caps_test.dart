import 'package:console_app/platform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mpv\'s settings are offered wherever the player is mpv: not on a Samsung TV or an Apple TV', () {
    expect(playerIsMpv, !isTizen && !isTvOS);
    // This machine runs the tests with mpv.
    expect(playerIsMpv, isTrue);
  });
}
