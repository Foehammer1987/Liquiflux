import 'package:flutter/material.dart';

import 'player_session.dart';

/// Text subtitles drawn by the app, for direct video output, where mpv draws nothing over
/// the picture. Follows the same size, height, colour and background settings as mpv's
/// own subtitles, and moves up while the control bar shows.
class AppSubtitles extends StatelessWidget {
  const AppSubtitles({super.key, required this.session});

  final PlayerSession session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    return StreamBuilder<List<String>>(
      stream: s.player.stream.subtitle,
      initialData: s.player.state.subtitle,
      builder: (context, snap) {
        final text = subtitleText(snap.data ?? const []);
        if (text.isEmpty) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, box) {
            final h = box.maxHeight;
            final look = subtitleLook(height: h, size: s.subtitleSize, raise: s.subtitleRaise, controlsShown: s.controlsShown);
            final style = TextStyle(fontSize: look.fontSize, height: 1.25, color: s.subtitleSwatch, fontWeight: FontWeight.w500);
            final Widget words = switch (s.subtitleBackground) {
              'box' => DecoratedBox(
                decoration: BoxDecoration(color: const Color(0xB0000000), borderRadius: BorderRadius.circular(look.fontSize * 0.15)),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: look.fontSize * 0.3, vertical: look.fontSize * 0.08),
                  child: Text(text, textAlign: TextAlign.center, style: style),
                ),
              ),
              'shadow' => Text(
                text,
                textAlign: TextAlign.center,
                style: style.copyWith(
                  shadows: [Shadow(color: const Color(0xC0000000), offset: Offset(look.fontSize * 0.05, look.fontSize * 0.05), blurRadius: look.fontSize * 0.08)],
                ),
              ),
              // Outline: a stroked copy underneath the filled text.
              _ => Stack(
                children: [
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: style.copyWith(
                      color: null,
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = look.fontSize * 0.1
                        ..strokeJoin = StrokeJoin.round
                        ..color = Colors.black,
                    ),
                  ),
                  Text(text, textAlign: TextAlign.center, style: style),
                ],
              ),
            };
            return Padding(
              padding: EdgeInsets.fromLTRB(box.maxWidth * 0.06, 0, box.maxWidth * 0.06, look.bottom),
              child: Align(alignment: Alignment.bottomCenter, child: words),
            );
          },
        );
      },
    );
  }
}

/// mpv's `sub-text` lines (main and secondary), trimmed, without empty ones.
String subtitleText(List<String> lines) => [
  for (final l in lines.take(1))
    for (final part in l.split('\n'))
      if (part.trim().isNotEmpty) part.trim(),
].join('\n');

/// Font size and gap below, matched to mpv's: its default font is about 5.8% of the picture
/// height at 100%, and `sub-pos` counts the raise (plus 12 while the bar shows) in percent.
({double fontSize, double bottom}) subtitleLook({required double height, required int size, required int raise, required bool controlsShown}) => (
  fontSize: height * 0.058 * size / 100,
  bottom: height * (0.03 + (raise + (controlsShown ? 12 : 0)) / 100),
);
