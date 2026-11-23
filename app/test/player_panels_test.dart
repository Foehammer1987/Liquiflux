import 'package:console_app/ui/pages/player_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The player's settings and Watch Together panels on every screen shape. On an iPhone on its
/// side the panel stopped above the control bar and showed one row of choices (the tour of a
/// real server: Quality listed only Original, with 720p out of sight).
void main() {
  test('a phone on its side: the panels take the full height', () {
    expect(playerPanelBottom(const Size(750, 382)), lessThan(40));
    expect(playerPanelBottom(const Size(593, 375)), lessThan(40), reason: 'the smallest iPhone');
  });

  test('a phone upright or a narrow iPad window: clear of the two-row bar', () {
    expect(playerPanelBottom(const Size(402, 874)), greaterThanOrEqualTo(180));
    expect(playerPanelBottom(const Size(320, 1024)), greaterThanOrEqualTo(180));
  });

  test('a tablet, a computer or a TV: clear of the one-row bar, as before', () {
    expect(playerPanelBottom(const Size(1180, 820)), 132);
    expect(playerPanelBottom(const Size(1440, 810)), 132);
  });
}
