import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const orange = Color(0xFFE08A3C), rust = Color(0xFFD9743A), amber = Color(0xFFE0A040), blue = Color(0xFF3C8AE0);

  test('neighbouring ranks get clearly different colours', () {
    // Five posters that are all warm orange, like a row of action films.
    final out = ArtColor.distinct([
      [orange],
      [rust],
      [amber],
      [blue],
      [orange],
      [rust, blue],
    ]);
    for (var i = 1; i < out.length; i++) {
      expect(ArtColor.hueDistance(out[i], out[i - 1]), greaterThanOrEqualTo(60), reason: 'rank ${i + 1} vs $i');
      if (i > 1) expect(ArtColor.hueDistance(out[i], out[i - 2]), greaterThanOrEqualTo(60), reason: 'rank ${i + 1} vs ${i - 1}');
    }
    expect(out.first, orange, reason: 'the first keeps its own artwork colour');
    expect(out[3], blue, reason: 'a colour that already stands apart is kept');
  });

  test('grey artwork still gets a colour', () {
    final out = ArtColor.distinct([const [], const [], const []]);
    expect(out, hasLength(3));
    expect(ArtColor.hueDistance(out[0], out[1]), greaterThanOrEqualTo(60));
  });

  test('palette lists separate colours strongest first', () {
    final px = <int>[
      for (var i = 0; i < 300; i++) ...[220, 60, 40, 255],
      for (var i = 0; i < 100; i++) ...[40, 90, 220, 255],
    ];
    final p = ArtColor.palette(px);
    expect(p, hasLength(2));
    expect(HSLColor.fromColor(p.first).hue, lessThan(30));
    expect(ArtColor.accent(p, p.first), p[1]);
  });
}
