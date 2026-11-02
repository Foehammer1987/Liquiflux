import 'package:flutter/widgets.dart';
import 'package:qr/qr.dart';

/// A QR code for [data] (an address for a phone's camera), dark on white with the quiet
/// zone scanners expect, whatever the theme.
class QrView extends StatelessWidget {
  const QrView(this.data, {super.key, this.size = 168, this.label});
  final String data;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: label ?? 'QR code',
    child: CustomPaint(size: Size.square(size), painter: _QrPainter(QrImage(QrCode(payload: QrPayload.fromString(data))))),
  );
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);
  final QrImage image;
  static const _quiet = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final n = image.moduleCount;
    final cells = n + 2 * _quiet;
    final m = size.shortestSide / cells;
    canvas.drawRect(Offset.zero & Size.square(m * cells), Paint()..color = const Color(0xFFFFFFFF));
    final ink = Paint()..color = const Color(0xFF000000);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (image.isDark(y, x)) canvas.drawRect(Rect.fromLTWH((x + _quiet) * m, (y + _quiet) * m, m + 0.5, m + 0.5), ink);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => !identical(old.image, image);
}
