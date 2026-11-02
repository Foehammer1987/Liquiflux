import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../state/scope.dart';
import '../nav.dart';
import '../play.dart';

/// The filters last used, so Shuffle opens the way you left it.
ShuffleFilter _last = const ShuffleFilter();

/// Shuffle Play: a slot machine of your posters that lands on something to watch.
Future<void> showShuffle(BuildContext context) {
  final app = AppScope.read(context);
  final nav = ShellNav.of(context);
  final host = context;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close Shuffle',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 260),
    transitionBuilder: (context, a, _, child) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 14 * a.value, sigmaY: 14 * a.value),
      child: FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ),
    pageBuilder: (context, _, _) => Center(
      child: _Shuffle(app: app, nav: nav, host: host),
    ),
  );
}

class _Shuffle extends StatefulWidget {
  const _Shuffle({required this.app, required this.nav, required this.host});
  final AppState app;
  final ShellNav nav;

  /// The page that opened Shuffle; it starts the player once the dialog is gone.
  final BuildContext host;
  @override
  State<_Shuffle> createState() => _ShuffleState();
}

class _ShuffleState extends State<_Shuffle> {
  final _rng = Random();
  ShuffleFilter _filter = _last;
  List<PlexItem> _pool = const [];
  List<String> _genres = const [];
  PlexItem? _pick;

  /// The poster on the reel while it spins.
  PlexItem? _reel;
  bool _spinning = false;
  bool _loading = true;

  /// The library couldn't be read, so there's nothing to pick from.
  bool _failed = false;
  final _recent = <String>{};
  int _spin = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final lib = await widget.app.library();
      final pool = [for (final l in lib.bySection) ...l];
      final count = <String, int>{};
      for (final i in pool) {
        for (final g in i.genres) {
          count.update(g, (v) => v + 1, ifAbsent: () => 1);
        }
      }
      if (!mounted) return;
      setState(() {
        _pool = pool;
        _genres = (count.keys.toList()..sort((a, b) => count[b]!.compareTo(count[a]!))).take(14).toList()..sort();
        _loading = false;
      });
      await _shuffle();
    } catch (e) {
      debugPrint('shuffle: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  int get _matches => shuffleCandidates(_pool, _filter).length;

  /// Spins the reel through random matches, slowing down, then lands on the pick.
  Future<void> _shuffle() async {
    final pick = pickShuffle(_pool, _filter, random: _rng, avoid: _recent);
    final id = ++_spin;
    _last = _filter;
    if (pick == null) {
      setState(() {
        _pick = null;
        _reel = null;
      });
      return;
    }
    _recent.add(pick.ratingKey);
    final reel = shuffleCandidates(_pool, _filter);
    setState(() {
      _spinning = true;
      _pick = null;
    });
    for (var k = 0; k < 14 && reel.length > 1; k++) {
      await Future<void>.delayed(Duration(milliseconds: 45 + k * k * 2));
      if (!mounted || id != _spin) return;
      setState(() => _reel = reel[_rng.nextInt(reel.length)]);
    }
    if (!mounted || id != _spin) return;
    setState(() {
      _reel = pick;
      _pick = pick;
      _spinning = false;
    });
  }

  void _set(ShuffleFilter f) {
    setState(() => _filter = f);
    _recent.clear();
    unawaited(_shuffle());
  }

  Future<void> _play() async {
    final p = _pick;
    if (p == null) return;
    Navigator.of(context).pop();
    if (widget.host.mounted) await playTitle(widget.host, p);
  }

  void _details() {
    final p = _pick;
    if (p == null) return;
    Navigator.of(context).pop();
    widget.nav.push(ItemDest(p.ratingKey));
  }

  @override
  Widget build(BuildContext context) {
    final plex = widget.app.plex;
    final shown = _reel;
    final poster = plex?.imageUrl(shown?.thumb, width: 360, height: 540);
    final art = plex?.imageUrl(_pick?.art, width: 1280, height: 720);
    return Theme(
      data: ConsoleTheme.dark(glass: widget.app.settings.glass),
      child: Builder(
        builder: (context) {
          final c = context.c;
          return ArtTint(
            url: plex?.imageUrl(_pick?.thumb, width: 240, height: 360),
            fallback: c.primary,
            builder: (context, tint) => Material(
              type: MaterialType.transparency,
              child: Container(
                width: 860,
                height: 540,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: const Color(0xFF07080B),
                  border: Border.all(color: tint.withValues(alpha: 0.45)),
                  boxShadow: [BoxShadow(color: tint.withValues(alpha: 0.3), blurRadius: 80, spreadRadius: -10)],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // The pick's backdrop, softly blurred behind everything.
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 700),
                      child: art == null
                          ? const SizedBox.expand()
                          : ImageFiltered(
                              key: ValueKey(art),
                              imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                              child: Opacity(
                                opacity: 0.45,
                                child: ArtImage(art, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox()),
                              ),
                            ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(center: const Alignment(-0.6, -0.2), radius: 1.3, colors: [tint.withValues(alpha: 0.25), const Color(0xCC07080B)]),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(Space.space8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Reel(poster: poster, spinning: _spinning, tint: tint, landed: _pick != null),
                          const SizedBox(width: Space.space8),
                          Expanded(child: _side(context, tint)),
                        ],
                      ),
                    ),
                    Positioned(
                      right: Space.space3,
                      top: Space.space3,
                      child: ConsoleButton(label: 'Close', icon: LucideIcons.x, iconOnly: true, kind: ButtonKind.tertiary, onPressed: () => Navigator.of(context).pop()),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _side(BuildContext context, Color tint) {
    final c = context.c;
    final p = _pick;
    final mins = p?.duration == null ? null : (p!.duration! / 60000).round();
    final facts = p == null
        ? const <String>[]
        : [
            if (p.year != null) '${p.year}',
            if (p.type == 'show') p.cardSubtitle,
            if (mins != null) p.type == 'show' ? '${mins}m episodes' : '${mins ~/ 60}h ${mins % 60}m',
            if (scoreOf(p) > 0) '★ ${scoreOf(p).toStringAsFixed(1)}',
            ...p.genres.take(2),
          ];
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(bottom: Space.space1),
      child: Text(
        t.toUpperCase(),
        style: ConsoleText.caption.copyWith(color: c.text300, letterSpacing: 1.4, fontWeight: FontWeight.w600),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.shuffle, size: 18, color: tint),
            const SizedBox(width: Space.space2),
            Text('Shuffle Play', style: ConsoleText.titleLg.copyWith(color: c.text100)),
            const SizedBox(width: Space.space3),
            if (!_loading) Text('$_matches to pick from', style: ConsoleText.small.copyWith(color: c.text300)),
          ],
        ),
        const SizedBox(height: Space.space4),
        label('Pick from'),
        ConsoleSegmented<String>(
          options: const [('any', 'Anything'), ('movie', 'Movies'), ('show', 'Shows')],
          value: _filter.kind,
          onChanged: (v) => _set(_filter.copyWith(kind: v)),
        ),
        const SizedBox(height: Space.space3),
        label('How long have you got'),
        ConsoleSegmented<int>(
          options: const [(0, 'Any length'), (30, 'Under 30m'), (60, 'Under 1h'), (90, 'Under 90m'), (120, 'Under 2h')],
          value: _filter.maxMinutes ?? 0,
          onChanged: (v) => _set(_filter.copyWith(maxMinutes: () => v == 0 ? null : v)),
        ),
        const SizedBox(height: Space.space3),
        Row(
          children: [
            ConsoleDropdown<String>(
              width: 200,
              options: [('', 'Any genre'), for (final g in _genres) (g, g)],
              value: _filter.genre ?? '',
              onChanged: (v) => _set(_filter.copyWith(genre: () => v.isEmpty ? null : v)),
            ),
            const SizedBox(width: Space.space4),
            ConsoleSwitch(
              value: _filter.unwatched,
              onChanged: (v) => _set(_filter.copyWith(unwatched: v)),
              color: tint,
              semanticLabel: 'Only unwatched',
            ),
            const SizedBox(width: Space.space2),
            Text('Only things I haven’t finished', style: ConsoleText.body.copyWith(color: c.text200)),
          ],
        ),
        const Spacer(),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(a),
              child: child,
            ),
          ),
          child: _loading
              ? const LoadingNote(label: 'Reading your library')
              : p == null
              ? (_spinning
                    ? const SizedBox(height: 120)
                    : Text(
                        _failed ? 'Couldn’t read your Plex library. Check the connection and try again.' : 'Nothing matches. Try a longer time or another genre.',
                        key: const ValueKey('none'),
                        style: ConsoleText.body.copyWith(color: c.text200),
                      ))
              : Column(
                  key: ValueKey(p.ratingKey),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ConsoleText.display.copyWith(fontSize: 34, height: 1.1, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    const SizedBox(height: Space.space2),
                    Text(
                      facts.join('  ·  '),
                      style: ConsoleText.small.copyWith(color: tint, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: Space.space2),
                    Text(
                      p.summary ?? '',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: ConsoleText.body.copyWith(color: c.text200, height: 1.5),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: Space.space5),
        Row(
          children: [
            ConsoleButton(label: 'Play', icon: LucideIcons.play, kind: ButtonKind.primary, size: ButtonSize.lg, onPressed: p == null || _spinning ? null : _play),
            const SizedBox(width: Space.space3),
            ConsoleButton(label: 'Shuffle Again', icon: LucideIcons.shuffle, size: ButtonSize.lg, onPressed: _loading || _spinning ? null : _shuffle),
            const SizedBox(width: Space.space3),
            ConsoleButton(label: 'Details', icon: LucideIcons.info, kind: ButtonKind.tertiary, size: ButtonSize.lg, onPressed: p == null || _spinning ? null : _details),
          ],
        ),
      ],
    );
  }
}

/// The spinning poster: flicks through titles, then settles on the pick with a bounce.
class _Reel extends StatelessWidget {
  const _Reel({required this.poster, required this.spinning, required this.tint, required this.landed});
  final String? poster;
  final bool spinning;
  final bool landed;
  final Color tint;

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: landed ? 1 : 0.95,
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeOutBack,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 300,
      height: 450,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.radiusLg),
        border: Border.all(color: tint.withValues(alpha: landed ? 0.8 : 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: landed ? 0.5 : 0.15),
            blurRadius: landed ? 48 : 16,
          ),
        ],
        color: const Color(0xFF111318),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSwitcher(
        duration: Duration(milliseconds: spinning ? 60 : 260),
        transitionBuilder: (child, a) => SlideTransition(
          position: Tween(begin: const Offset(0, -0.12), end: Offset.zero).animate(a),
          child: FadeTransition(opacity: a, child: child),
        ),
        child: poster == null
            ? Center(
                key: const ValueKey('empty'),
                child: Icon(LucideIcons.shuffle, size: 48, color: tint.withValues(alpha: 0.5)),
              )
            : ArtImage(poster!, key: ValueKey(poster), fit: BoxFit.cover, width: 300, height: 450, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox()),
      ),
    ),
  );
}
