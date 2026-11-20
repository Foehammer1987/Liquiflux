import 'dart:ui' show ImageFilter;

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../platform.dart';
import 'player_session.dart';
import 'riptide.dart';

/// Shown after a few seconds paused, the way Netflix and Prime do: the title (its logo when
/// Plex has one), the synopsis and who's in it, over a softened picture in the title's colours.
class PauseScreen extends StatefulWidget {
  const PauseScreen({super.key, required this.session, required this.riptide, required this.tint, required this.accent});
  final PlayerSession session;
  final Riptide riptide;
  final Color tint;
  final Color accent;

  @override
  State<PauseScreen> createState() => _PauseScreenState();
}

class _PauseScreenState extends State<PauseScreen> {
  /// Always through Plex's resizer, web addresses too: a cast photo from the web can be a
  /// full-size headshot, and decoding a few of those over a playing video got the app
  /// killed on the 2 GB Shield.
  String? _photo(String? thumb) => widget.session.plex.imageUrl(thumb, width: 112, height: 112);

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final show = widget.riptide.show;
    final it = s.item;
    final tint = widget.tint, accent = widget.accent;
    final episode = it.type == 'episode';
    final logo = episode ? show?.clearLogo : it.clearLogo;
    final logoUrl = logo == null ? null : s.plex.imageUrl(logo, width: 900, height: 360);
    final title = episode ? (it.grandparentTitle ?? it.title) : it.title;
    final mins = it.duration == null ? null : (it.duration! / 60000).round();
    final left = s.duration - s.position;
    final facts = [
      if (episode) 'Season ${it.parentIndex ?? 0}, Episode ${it.index ?? 0}',
      if (it.year != null && !episode) '${it.year}',
      if (it.contentRating != null) it.contentRating!,
      if (mins != null && mins > 0) mins >= 60 ? '${mins ~/ 60}h ${mins % 60}m' : '${mins}m',
      if (left.inMinutes > 0) '${left.inMinutes}m left',
    ];
    // Who's in this scene when the Riptide scanner has been over the title, else top billing.
    final scene = widget.riptide.inScene(s.position);
    final cast = (scene.isNotEmpty ? scene : widget.riptide.cast).take(6).toList();
    final director = (it.directors.isNotEmpty ? it.directors : (show?.directors ?? const <PlexTag>[])).map((d) => d.tag).take(2).join(', ');

    return Stack(
      fit: StackFit.expand,
      children: [
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [playerShade(tint, 0.94), playerShade(tint, 0.7), Colors.black.withValues(alpha: 0.2)], stops: const [0, 0.5, 1]),
            ),
          ),
        ),
        // A slow glow in the title's colours behind the text.
        Positioned(
          left: -200,
          top: -100,
          bottom: -100,
          width: 900,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(colors: [tint.withValues(alpha: 0.22), accent.withValues(alpha: 0.06), Colors.transparent], stops: const [0, 0.5, 1]),
              ),
            ),
          ),
        ),
        Positioned(
          left: 72,
          top: 0,
          bottom: 0,
          width: 620,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "YOU'RE WATCHING",
                style: ConsoleText.caption.copyWith(color: accent, letterSpacing: 2.6, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: Space.space3),
              if (logoUrl != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440, maxHeight: 150),
                  child: ArtImage(logoUrl, fit: BoxFit.contain, alignment: Alignment.centerLeft, errorBuilder: (_, _, _) => _Title(title, tint)),
                )
              else
                _Title(title, tint),
              if (episode) ...[const SizedBox(height: Space.space3), Text(it.title, style: ConsoleText.titleLg.copyWith(fontSize: 24, color: Colors.white))],
              const SizedBox(height: Space.space2),
              Text(
                facts.join('   ·   '),
                style: ConsoleText.body.copyWith(color: tint, fontWeight: FontWeight.w600),
              ),
              if ((it.summary ?? '').isNotEmpty) ...[
                const SizedBox(height: Space.space4),
                Text(
                  it.summary!,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: ConsoleText.body.copyWith(fontSize: 16, height: 1.55, color: Colors.white.withValues(alpha: 0.88)),
                ),
              ],
              if (cast.isNotEmpty) ...[
                const SizedBox(height: Space.space6),
                Text(
                  scene.isNotEmpty ? 'IN THIS SCENE' : 'STARRING',
                  style: ConsoleText.caption.copyWith(color: Colors.white.withValues(alpha: 0.55), letterSpacing: 2, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: Space.space3),
                Wrap(
                  spacing: Space.space4,
                  runSpacing: Space.space3,
                  children: [for (final r in cast) _Face(name: r.tag, role: r.role, photo: _photo(r.thumb), tint: tint)],
                ),
                const SizedBox(height: Space.space3),
                Text(
                  isTv ? 'Press Down for Riptide: the whole cast and their other titles' : 'Press R for Riptide: the whole cast and their other titles',
                  style: ConsoleText.caption.copyWith(color: Colors.white.withValues(alpha: 0.55)),
                ),
              ],
              if (director.isNotEmpty) ...[
                const SizedBox(height: Space.space4),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Directed by  ',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
                      ),
                      TextSpan(
                        text: director,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                  style: ConsoleText.body,
                ),
              ],
            ],
          ),
        ),
        Positioned(right: 56, bottom: 56, child: _Paused(tint: tint)),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text, this.tint);
  final String text;
  final Color tint;
  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 2,
    style: ConsoleText.display.copyWith(
      fontSize: 56,
      height: 1.05,
      fontWeight: FontWeight.w900,
      letterSpacing: -1.2,
      color: Colors.white,
      shadows: [Shadow(color: tint.withValues(alpha: 0.5), blurRadius: 36)],
    ),
  );
}

class _Face extends StatelessWidget {
  const _Face({required this.name, required this.role, required this.photo, required this.tint});
  final String name;
  final String? role;
  final String? photo;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join();
    return SizedBox(
      width: 88,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: playerShade(tint, 0.9),
              border: Border.all(color: tint.withValues(alpha: 0.6)),
            ),
            clipBehavior: Clip.antiAlias,
            child: photo == null
                ? Center(
                    child: Text(initials, style: ConsoleText.titleMd.copyWith(color: Colors.white70)),
                  )
                : ArtImage(
                    photo!,
                    fit: BoxFit.cover,
                    decodeWidth: 112,
                    errorBuilder: (_, _, _) => Center(
                      child: Text(initials, style: ConsoleText.titleMd.copyWith(color: Colors.white70)),
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: ConsoleText.small.copyWith(color: Colors.white, fontWeight: FontWeight.w500),
          ),
          if (role != null && role!.isNotEmpty)
            Text(
              role!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: ConsoleText.caption.copyWith(color: Colors.white.withValues(alpha: 0.6)),
            ),
        ],
      ),
    );
  }
}

/// "Paused", breathing gently in the title's colour.
class _Paused extends StatefulWidget {
  const _Paused({required this.tint});
  final Color tint;
  @override
  State<_Paused> createState() => _PausedState();
}

class _PausedState extends State<_Paused> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: widget.tint.withValues(alpha: 0.5 + 0.4 * _c.value), width: 2),
            boxShadow: [
              BoxShadow(
                color: widget.tint.withValues(alpha: 0.15 + 0.3 * _c.value),
                blurRadius: 12 + 14 * _c.value,
              ),
            ],
          ),
          child: const Icon(LucideIcons.play, color: Colors.white, size: 20),
        ),
        const SizedBox(width: Space.space3),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Paused', style: ConsoleText.titleMd.copyWith(color: Colors.white)),
            Text(isTv ? 'Press Select to carry on' : 'Click or press Space to carry on', style: ConsoleText.caption.copyWith(color: Colors.white.withValues(alpha: 0.6))),
          ],
        ),
      ],
    ),
  );
}
