import 'package:flutter/widgets.dart';

/// A QR code that opens https://plex.tv/link, so a phone's camera can take the user
/// straight to where a TV's link code goes. The address never changes, so the code is
/// drawn from these fixed modules (version 2, medium error correction) instead of
/// pulling in an encoder.
class PlexLinkQr extends StatelessWidget {
  const PlexLinkQr({super.key, this.size = 168});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'QR code for plex.tv/link',
    child: CustomPaint(size: Size.square(size), painter: const _QrPainter()),
  );
}

/// Dark modules on white with the four-module quiet zone scanners expect, whatever the theme.
class _QrPainter extends CustomPainter {
  const _QrPainter();

  static const _quiet = 4;
  static const _rows = [
    '#######.#..###..#.#######',
    '#.....#.#.#...#...#.....#',
    '#.###.#..######...#.###.#',
    '#.###.#.###.###...#.###.#',
    '#.###.#..#.######.#.###.#',
    '#.....#...#.#.#...#.....#',
    '#######.#.#.#.#.#.#######',
    '........##.#..###........',
    '#.##.###.####.###.#..#.##',
    '####...#.#..##.....#...#.',
    '..##.##..##..##...#.#....',
    '.#.##..#.#...###...#.##..',
    '#..#.###.##.#..######.###',
    '.#.##..#.####.#######...#',
    '.#..#.##..##.#..##..#.##.',
    '#.#.##..#.##...######...#',
    '......##..#.#.#.#########',
    '........###....##...#.#.#',
    '#######.##...##.#.#.#.###',
    '#.....#.#..#.####...#..#.',
    '#.###.#..##..##.######.#.',
    '#.###.#.##.....####.#####',
    '#.###.#.###...###.#.#.##.',
    '#.....#....####...#.#.#..',
    '#######.#..#...#..#######',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cells = _rows.length + 2 * _quiet;
    final m = size.shortestSide / cells;
    canvas.drawRect(Offset.zero & Size.square(m * cells), Paint()..color = const Color(0xFFFFFFFF));
    final ink = Paint()..color = const Color(0xFF000000);
    for (var y = 0; y < _rows.length; y++) {
      for (var x = 0; x < _rows[y].length; x++) {
        // A hair of overlap so no seams show between neighbouring modules.
        if (_rows[y][x] == '#') canvas.drawRect(Rect.fromLTWH((x + _quiet) * m, (y + _quiet) * m, m + 0.5, m + 0.5), ink);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => false;
}
