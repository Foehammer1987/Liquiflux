import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../state/scope.dart';
import '../nav.dart';
import '../play.dart';
import 'collections_page.dart' show SeriesBar;
import 'series_art.dart';

/// A series' showcase. Everything on it is drawn from the series itself: a moving montage
/// of its films' backdrops, colours from its poster, the films in release order as numbered
/// chapters, how each one rated, and the faces that keep coming back.
class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key, required this.franchise});
  final Franchise franchise;
  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  late Franchise _f = widget.franchise;

  /// The backdrop the hero shows while you point at a film; null lets the montage run.
  final _focus = ValueNotifier<String?>(null);
  List<({Credit credit, int films})>? _faces;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFaces());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Films requested from this page, so their buttons don't offer it twice.
  final _requested = <int>{};

  /// Missing films that can still be requested.
  List<FranchisePart> get _toRequest => [
    for (final p in _f.missing)
      if (!_requested.contains(p.tmdb!.id) && requestStateOf(p.tmdb!.mediaInfo).requestable) p,
  ];

  /// Fresh watch state after playing: re-reads just this series' films from Plex.
  Future<void> _refresh() async {
    final plex = AppScope.read(context).plex;
    if (plex == null) return;
    final f = _f;
    final fresh = await Future.wait([for (final p in f.parts) p.plex == null ? Future<PlexItem?>.value() : plex.metadata(p.plex!.ratingKey).catchError((Object _) => p.plex)]);
    if (!mounted) return;
    setState(
      () => _f = Franchise(
        name: f.name,
        overview: f.overview,
        tmdbId: f.tmdbId,
        plexKey: f.plexKey,
        tmdb: f.tmdb,
        plexCollection: f.plexCollection,
        parts: [for (final (i, p) in f.parts.indexed) FranchisePart(title: p.title, tmdb: p.tmdb, plex: fresh[i] ?? p.plex)],
      ),
    );
  }

  /// People in two or more of the films, most appearances first.
  Future<void> _loadFaces() async {
    final seerr = AppScope.read(context).seerr;
    if (seerr == null) return;
    final films = _f.released.where((p) => p.tmdb != null).take(12).toList();
    final details = await Future.wait(films.map((p) => seerr.details('movie', p.tmdb!.id).then<SeerrResult?>((d) => d).catchError((Object _) => null)));
    final count = <int, int>{};
    final first = <int, SeerrCredit>{};
    final billing = <int, int>{};
    for (final d in details.whereType<SeerrResult>()) {
      for (final (i, c) in d.cast.take(15).indexed) {
        count.update(c.id, (v) => v + 1, ifAbsent: () => 1);
        first.putIfAbsent(c.id, () => c);
        billing.update(c.id, (v) => math.min(v, i), ifAbsent: () => i);
      }
    }
    final ids = count.keys.where((id) => count[id]! >= 2).toList()..sort((a, b) => count[b] != count[a] ? count[b]!.compareTo(count[a]!) : billing[a]!.compareTo(billing[b]!));
    if (!mounted) return;
    setState(() => _faces = [for (final id in ids.take(16)) (credit: Credit(name: first[id]!.name, role: first[id]!.character, photoUrl: first[id]!.profileUrl(), tmdbId: id), films: count[id]!)]);
  }

  Future<void> _play(FranchisePart from, {bool marathon = false}) async {
    final item = from.plex;
    if (item == null) return;
    await playTitle(context, item, queue: marathon ? _f.marathonFrom(from) : const []);
    if (mounted) unawaited(_refresh());
  }

  Future<void> _requestMissing() async {
    final app = AppScope.read(context);
    final missing = _toRequest;
    if (missing.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text('Request ${missing.length} ${missing.length == 1 ? 'film' : 'films'}?'),
        content: Text(missing.map((p) => '•  ${SeriesArt.shortTitle(p.title, _f)} (${p.year ?? '?'})').join('\n')),
        actions: [
          // Cancel holds the remote's focus as the popup opens, as in the other popups.
          TextButton(autofocus: true, onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Request All')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _requesting = true);
    var failed = 0;
    for (final p in missing) {
      try {
        await app.seerr!.request('movie', p.tmdb!.id);
        _requested.add(p.tmdb!.id);
      } catch (e) {
        failed++;
        debugPrint('request ${p.title}: $e');
      }
    }
    unawaited(app.refreshRequests());
    if (!mounted) return;
    setState(() => _requesting = false);
    if (failed > 0) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Seerr turned down $failed of ${missing.length} requests. Try those again from their chapters.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final plex = app.plex;
    final f = _f;
    return ArtTint(
      url: SeriesArt.seriesPoster(f, plex),
      fallback: context.c.primary,
      builder: (context, tint) => LayoutBuilder(
        builder: (context, box) {
          final heroH = (box.maxHeight * 0.78).clamp(480.0, 760.0);
          return Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: Space.space10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: heroH,
                      child: _Hero(
                        franchise: f,
                        tint: tint,
                        urls: SeriesArt.montage(f, plex),
                        focus: _focus,
                        poster: SeriesArt.seriesPoster(f, plex),
                        requesting: _requesting,
                        canRequest: app.seerr != null && _toRequest.isNotEmpty,
                        toRequest: _toRequest.length,
                        onPlay: _play,
                        onRequest: _requestMissing,
                      ),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -Space.space8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Heading('The Saga', f.upcoming.isEmpty ? '${f.released.length} films in release order' : '${f.released.length} out so far, ${f.upcoming.length} on the way'),
                          _Timeline(franchise: f, tint: tint, focus: _focus, onOpen: _open, requested: _requested, onRequested: (id) => setState(() => _requested.add(id))),
                          if (f.released.where((p) => (p.score ?? 0) > 0).length >= 2) ...[
                            const SizedBox(height: Space.space8),
                            _Heading('How the Saga Rated', 'Audience scores, film by film'),
                            _Ratings(franchise: f, tint: tint, focus: _focus),
                          ],
                          if (_faces?.isNotEmpty ?? false) ...[
                            const SizedBox(height: Space.space8),
                            _Heading('Faces of the Saga', 'Who keeps coming back'),
                            SizedBox(
                              height: 168,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 48),
                                itemCount: _faces!.length,
                                separatorBuilder: (_, _) => const SizedBox(width: Space.space5),
                                itemBuilder: (context, i) {
                                  final (:credit, :films) = _faces![i];
                                  return SizedBox(
                                    width: 112,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        CreditAvatar(
                                          credit: credit,
                                          size: 104,
                                          onTap: () => ShellNav.of(context).push(PersonDest(name: credit.name, tmdbId: credit.tmdbId, photoUrl: credit.photoUrl)),
                                        ),
                                        Positioned(
                                          right: 2,
                                          top: 74,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Color.alphaBlend(tint.withValues(alpha: 0.35), const Color(0xEE0B0C10)),
                                              borderRadius: BorderRadius.circular(Radii.radiusFull),
                                              border: Border.all(color: tint.withValues(alpha: 0.8)),
                                            ),
                                            child: Text(
                                              '$films films',
                                              style: ConsoleText.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 40,
                top: Space.space4,
                child: _Back(tint: tint),
              ),
            ],
          );
        },
      ),
    );
  }

  void _open(FranchisePart p) {
    final nav = ShellNav.of(context);
    if (p.plex != null) {
      nav.push(ItemDest(p.plex!.ratingKey));
    } else if (p.tmdb != null && AppScope.read(context).seerr != null) {
      nav.push(SeerrDest('movie', p.tmdb!.id));
    }
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.sub);
  final String title;
  final String sub;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(48, 0, 48, Space.space4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(title, style: ConsoleText.titleLg.copyWith(fontSize: 22, color: context.c.text100)),
        const SizedBox(width: Space.space3),
        Text(sub, style: ConsoleText.small.copyWith(color: context.c.text300)),
      ],
    ),
  );
}

// ------------------------------------------------------------------ hero

class _Hero extends StatelessWidget {
  const _Hero({
    required this.franchise,
    required this.tint,
    required this.urls,
    required this.focus,
    required this.poster,
    required this.requesting,
    required this.canRequest,
    required this.toRequest,
    required this.onPlay,
    required this.onRequest,
  });
  final Franchise franchise;
  final Color tint;
  final List<String> urls;
  final ValueNotifier<String?> focus;
  final String? poster;
  final bool requesting;
  final bool canRequest;
  final int toRequest;
  final void Function(FranchisePart from, {bool marathon}) onPlay;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final f = franchise;
    final years = f.years;
    final next = f.upNext;
    final first = f.parts.where((p) => p.owned).firstOrNull;
    final score = f.averageScore;
    final marathonMins = f.marathonFrom(next ?? first).fold(0, (a, i) => a + ((i.duration ?? 0) / 60000).round());
    final facts = [
      f.upcoming.isEmpty ? '${f.total} films' : '${f.total} films, ${f.upcoming.length} on the way',
      if (years != null) years.from == years.to ? '${years.from}' : '${years.from} – ${years.to}',
      if (f.totalMinutes > 0) '${SeriesArt.hours(f.totalMinutes)} in all',
      if (score != null) '★ ${score.toStringAsFixed(1)} average',
    ];
    return Stack(
      fit: StackFit.expand,
      children: [
        // The montage fades out at the bottom into whatever is behind the page.
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) =>
              const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, Colors.white, Colors.transparent], stops: [0, 0.55, 1]).createShader(r),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRect(
                child: _Montage(urls: urls, focus: focus),
              ),
              // The series' colour washes in from the left.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color.alphaBlend(tint.withValues(alpha: 0.22), const Color(0xF2050608)), const Color(0x99050608), const Color(0x00050608)],
                    stops: const [0, 0.45, 0.8],
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 48,
          bottom: 72,
          right: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.layers, size: 16, color: tint),
                  const SizedBox(width: Space.space2),
                  Text(
                    'FILM SERIES',
                    style: ConsoleText.caption.copyWith(color: tint, letterSpacing: 2.4, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: Space.space2),
              Text(
                f.name,
                maxLines: 2,
                style: ConsoleText.display.copyWith(
                  fontSize: 64,
                  height: 1.02,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.5,
                  color: Colors.white,
                  shadows: [Shadow(color: tint.withValues(alpha: 0.55), blurRadius: 40)],
                ),
              ),
              const SizedBox(height: Space.space3),
              Wrap(
                spacing: Space.space2,
                runSpacing: Space.space2,
                children: [for (final t in facts) _Chip(t, tint: tint)],
              ),
              const SizedBox(height: Space.space4),
              SizedBox(
                width: 420,
                child: SeriesBar(franchise: f, color: tint, height: 6),
              ),
              const SizedBox(height: Space.space2),
              Text(
                f.ownedCount == 0
                    ? 'None of these are in your library yet.'
                    : f.watchedCount == 0
                    ? 'You have ${f.ownedCount} of ${f.total}${f.minutesLeft > 0 ? ', ${SeriesArt.hours(f.minutesLeft)} to watch' : ''}.'
                    : 'You have ${f.ownedCount} of ${f.total} and have seen ${f.watchedCount}${f.minutesLeft > 0 ? ', with ${SeriesArt.hours(f.minutesLeft)} left to watch' : ''}.',
                style: ConsoleText.small.copyWith(color: Colors.white.withValues(alpha: 0.7)),
              ),
              if ((f.overview ?? '').isNotEmpty) ...[
                const SizedBox(height: Space.space4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Text(
                    f.overview!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: ConsoleText.body.copyWith(fontSize: 15, height: 1.5, color: Colors.white.withValues(alpha: 0.88)),
                  ),
                ),
              ],
              const SizedBox(height: Space.space5),
              Wrap(
                spacing: Space.space3,
                runSpacing: Space.space3,
                children: [
                  if (next != null || first != null)
                    ConsoleButton(
                      label: next == null ? 'Watch Again from the Start' : (next.started || f.watchedCount > 0 ? 'Continue: ${SeriesArt.shortTitle(next.title, f)}' : 'Start the Saga'),
                      icon: LucideIcons.play,
                      kind: ButtonKind.primary,
                      size: ButtonSize.lg,
                      onPressed: () => onPlay(next ?? first!),
                    ),
                  if (f.ownedCount >= 2 && (next ?? first) != null)
                    Tooltip(
                      message: marathonMins > 0
                          ? 'Plays every film you have in order. Ends around ${SeriesArt.clockAt(DateTime.now().add(Duration(minutes: marathonMins)), context)}.'
                          : 'Plays every film you have in order',
                      child: ConsoleButton(
                        label: 'Marathon${marathonMins > 0 ? ' · ${SeriesArt.hours(marathonMins)}' : ''}',
                        icon: LucideIcons.listVideo,
                        size: ButtonSize.lg,
                        onPressed: () => onPlay(next ?? first!, marathon: true),
                      ),
                    ),
                  if (canRequest)
                    ConsoleButton(label: requesting ? 'Requesting…' : 'Request $toRequest Missing', icon: LucideIcons.download, size: ButtonSize.lg, onPressed: requesting ? null : onRequest),
                ],
              ),
            ],
          ),
        ),
        // The series' own poster, lit in its colour.
        if (poster != null)
          Positioned(
            right: 64,
            bottom: 80,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.92, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => Opacity(
                opacity: ((t - 0.92) / 0.08).clamp(0, 1),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateY(-0.18 * (1.08 - t) * 6)
                    ..scaleByDouble(t, t, 1, 1),
                  child: child,
                ),
              ),
              child: Container(
                width: 232,
                height: 348,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.radiusLg),
                  border: Border.all(color: tint.withValues(alpha: 0.6)),
                  boxShadow: [
                    BoxShadow(color: tint.withValues(alpha: 0.45), blurRadius: 60, spreadRadius: -6),
                    const BoxShadow(color: Color(0xAA000000), blurRadius: 30, offset: Offset(0, 18)),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: ArtImage(poster!, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox()),
              ),
            ),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {required this.tint});
  final String text;
  final Color tint;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Space.space3, vertical: 4),
    decoration: BoxDecoration(
      color: Color.alphaBlend(tint.withValues(alpha: 0.18), const Color(0x99000000)),
      borderRadius: BorderRadius.circular(Radii.radiusFull),
      border: Border.all(color: tint.withValues(alpha: 0.45)),
    ),
    child: Text(
      text,
      style: ConsoleText.small.copyWith(color: Colors.white, fontWeight: FontWeight.w500),
    ),
  );
}

/// The films' backdrops, slowly drifting and dissolving one into the next. Pointing at a
/// film below holds its backdrop here.
class _Montage extends StatefulWidget {
  const _Montage({required this.urls, required this.focus});
  final List<String> urls;
  final ValueNotifier<String?> focus;
  @override
  State<_Montage> createState() => _MontageState();
}

class _MontageState extends State<_Montage> {
  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (widget.focus.value == null && widget.urls.length > 1) setState(() => _i = (_i + 1) % widget.urls.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: widget.focus,
    builder: (context, focus, _) {
      final url = focus ?? (widget.urls.isEmpty ? null : widget.urls[_i % widget.urls.length]);
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 1400),
        switchInCurve: Curves.easeOut,
        child: url == null
            ? const SizedBox.expand()
            : TweenAnimationBuilder<double>(
                key: ValueKey(url),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(seconds: 9),
                builder: (context, t, child) => Transform.scale(scale: 1.04 + 0.06 * t, alignment: Alignment(0.4 - 0.8 * t, -0.2), child: child),
                child: SizedBox.expand(
                  child: ArtImage(url, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox()),
                ),
              ),
      );
    },
  );
}

// ------------------------------------------------------------------ timeline

/// The films as numbered chapters in release order, joined by a line marking the years
/// between them. Each chapter's numeral takes its own colour from its poster, kept clearly
/// apart from its neighbours.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.franchise, required this.tint, required this.focus, required this.onOpen, required this.requested, required this.onRequested});
  final Franchise franchise;
  final Color tint;
  final ValueNotifier<String?> focus;
  final ValueChanged<FranchisePart> onOpen;
  final Set<int> requested;
  final ValueChanged<int> onRequested;

  @override
  Widget build(BuildContext context) {
    final plex = AppScope.of(context).plex;
    final parts = franchise.parts;
    return DistinctTints(
      urls: [for (final p in parts) SeriesArt.poster(p, plex)],
      child: SizedBox(
        height: 440,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 48),
          itemCount: parts.length,
          itemBuilder: (context, i) {
            final p = parts[i];
            final gap = i == 0 || p.year == null || parts[i - 1].year == null ? null : p.year! - parts[i - 1].year!;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (i > 0) _Gap(years: gap, tint: tint),
                _Chapter(
                  part: p,
                  number: i + 1,
                  franchise: franchise,
                  poster: SeriesArt.poster(p, plex),
                  onHover: (on) => focus.value = on ? SeriesArt.backdrop(p, plex) : (focus.value == SeriesArt.backdrop(p, plex) ? null : focus.value),
                  onTap: () => onOpen(p),
                  requested: p.tmdb != null && requested.contains(p.tmdb!.id),
                  onRequested: onRequested,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Gap extends StatelessWidget {
  const _Gap({required this.years, required this.tint});
  final int? years;
  final Color tint;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 64,
    height: 320,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 178,
          child: Container(
            height: 2,
            decoration: BoxDecoration(gradient: LinearGradient(colors: [tint.withValues(alpha: 0.15), tint.withValues(alpha: 0.6), tint.withValues(alpha: 0.15)])),
          ),
        ),
        if (years != null && years! > 0)
          Positioned(
            top: 186,
            child: Text(
              '+$years ${years == 1 ? 'yr' : 'yrs'}',
              style: ConsoleText.caption.copyWith(color: tint.withValues(alpha: 0.9), fontWeight: FontWeight.w600),
            ),
          ),
      ],
    ),
  );
}

class _Chapter extends StatefulWidget {
  const _Chapter({required this.part, required this.number, required this.franchise, required this.poster, required this.onHover, required this.onTap, this.requested = false, this.onRequested});
  final bool requested;
  final ValueChanged<int>? onRequested;
  final FranchisePart part;
  final int number;
  final Franchise franchise;
  final String? poster;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;
  @override
  State<_Chapter> createState() => _ChapterState();
}

class _ChapterState extends State<_Chapter> {
  bool _hot = false;
  bool _busy = false;
  SeerrRequest? _made;

  Future<void> _request() async {
    final app = AppScope.read(context);
    final t = widget.part.tmdb;
    if (t == null || app.seerr == null || _busy) return;
    setState(() => _busy = true);
    try {
      final r = await app.seerr!.request('movie', t.id);
      if (mounted) setState(() => _made = r);
      widget.onRequested?.call(t.id);
      unawaited(app.refreshRequests());
    } catch (e) {
      debugPrint('request: $e');
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Couldn’t request ${widget.part.title}: ${errorText(e)}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.part;
    final c = context.c;
    final numeral = SeriesArt.roman(widget.number);
    // A missing film's request state, live from Seerr (or the request just made here).
    final req = p.owned || p.tmdb == null ? null : requestStateOf(_made?.media ?? p.tmdb!.mediaInfo, _made);
    final canRequest = req != null && req.requestable && !widget.requested && AppScope.of(context).seerr != null;
    final status = !p.released
        ? ('Coming ${p.year ?? 'soon'}', LucideIcons.calendarClock)
        : p.watched
        ? ('Watched', LucideIcons.circleCheck)
        : p.started
        ? ('In progress', LucideIcons.circlePlay)
        : p.owned
        ? ('In your library', LucideIcons.library)
        : req != null && !req.requestable
        ? (req.label, LucideIcons.hourglass)
        : widget.requested
        ? ('Requested', LucideIcons.hourglass)
        : ('Not in library', LucideIcons.cloudOff);
    return ArtTint(
      url: widget.poster,
      index: widget.number - 1,
      fallback: c.text300,
      builder: (context, color) => SizedBox(
        width: 152,
        child: Focusable(
          onTap: widget.onTap,
          semanticLabel: p.title,
          onHighlight: (on) {
            setState(() => _hot = on);
            widget.onHover(on);
          },
          builder: (context, hover, focus) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The chapter number, outlined in the film's colour.
              SizedBox(
                height: 56,
                child: Stack(
                  children: [
                    Text(
                      numeral,
                      style: ConsoleText.display.copyWith(
                        fontSize: 52,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        foreground: Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeWidth = 2
                          ..color = color.withValues(alpha: _hot ? 1 : 0.85),
                        shadows: [
                          Shadow(
                            color: color.withValues(alpha: _hot ? 0.7 : 0.3),
                            blurRadius: _hot ? 24 : 12,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.space2),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                height: 152 * 1.5,
                width: 152,
                transform: Matrix4.translationValues(0, _hot ? -6 : 0, 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.radiusMd),
                  border: Border.all(
                    color: focus ? c.primary : color.withValues(alpha: _hot ? 0.9 : 0.3),
                    width: focus ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: _hot ? 0.45 : 0.1),
                      blurRadius: _hot ? 28 : 10,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.poster != null) ArtImage(widget.poster!, fit: BoxFit.cover, alignment: Alignment.topCenter, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox()),
                    if (!p.owned) ColoredBox(color: Colors.black.withValues(alpha: p.released ? 0.45 : 0.6)),
                    if (p.started && p.plex?.watchProgress != null)
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(value: p.plex!.watchProgress, minHeight: 4, color: color, backgroundColor: Colors.black54),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Space.space3),
              Text(
                SeriesArt.shortTitle(p.title, widget.franchise),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ConsoleText.titleSm.copyWith(color: hover ? c.link : c.text100, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text([if (p.year != null) '${p.year}', if ((p.runtime ?? 0) > 0) SeriesArt.hours(p.runtime!)].join('  ·  '), style: ConsoleText.caption.copyWith(color: c.text300)),
              const SizedBox(height: Space.space1),
              Row(
                children: [
                  Icon(status.$2, size: 13, color: p.owned ? color : c.text300),
                  const SizedBox(width: 4),
                  Text(
                    status.$1,
                    style: ConsoleText.caption.copyWith(color: p.owned ? color : c.text300, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              if (canRequest) ...[
                const SizedBox(height: Space.space2),
                ConsoleButton(label: _busy ? 'Requesting…' : 'Request', icon: LucideIcons.download, size: ButtonSize.sm, onPressed: _busy ? null : _request),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ ratings

/// A bar per film, each in that film's own colour; the best rated wears a crown.
class _Ratings extends StatelessWidget {
  const _Ratings({required this.franchise, required this.tint, required this.focus});
  final Franchise franchise;
  final Color tint;
  final ValueNotifier<String?> focus;

  @override
  Widget build(BuildContext context) {
    final plex = AppScope.of(context).plex;
    final c = context.c;
    final parts = franchise.released;
    final scores = parts.map((p) => p.score ?? 0).where((v) => v > 0).toList();
    final best = scores.fold(0.0, math.max);
    // Bars start a little under the lowest score so the differences between films show.
    final floor = scores.isEmpty ? 0.0 : math.max(0.0, scores.reduce(math.min) - 1.5);
    return DistinctTints(
      urls: [for (final p in franchise.parts) SeriesArt.poster(p, plex)],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: SizedBox(
          height: 190,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final p in parts)
                ConstrainedBox(
                  constraints: BoxConstraints.tightFor(width: math.min(112, (MediaQuery.sizeOf(context).width - 96) / parts.length)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: ArtTint(
                      url: SeriesArt.poster(p, plex),
                      index: franchise.parts.indexOf(p),
                      fallback: tint,
                      builder: (context, color) {
                        final s = p.score ?? 0;
                        final top = s > 0 && s == best;
                        return MouseRegion(
                          onEnter: (_) => focus.value = SeriesArt.backdrop(p, plex),
                          onExit: (_) => focus.value = null,
                          child: Tooltip(
                            message: '${p.title}: ${s > 0 ? s.toStringAsFixed(1) : 'not rated'}',
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (top) Icon(LucideIcons.crown, size: 16, color: color),
                                Text(
                                  s > 0 ? s.toStringAsFixed(1) : '–',
                                  style: ConsoleText.small.copyWith(color: c.text100, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: s <= 0 ? 0.02 : ((s - floor) / (10 - floor)).clamp(0.05, 1)),
                                  duration: const Duration(milliseconds: 900),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, t, _) => Container(
                                    height: 120 * t,
                                    decoration: BoxDecoration(
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color, color.withValues(alpha: 0.15)]),
                                      boxShadow: [if (top) BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 18)],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  SeriesArt.roman(franchise.parts.indexOf(p) + 1),
                                  style: ConsoleText.caption.copyWith(color: color, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Back to Collections, frosted over the montage and fixed while the page scrolls.
class _Back extends StatelessWidget {
  const _Back({required this.tint});
  final Color tint;

  void _go(BuildContext context) {
    final nav = ShellNav.of(context);
    Navigator.of(context).canPop() ? nav.back() : nav.go(const CollectionsDest());
  }

  @override
  Widget build(BuildContext context) => Focusable(
    onTap: () => _go(context),
    semanticLabel: 'Back to Collections',
    builder: (context, hover, focus) => ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(12, 9, 18, 9),
          decoration: BoxDecoration(
            color: Color.alphaBlend(tint.withValues(alpha: hover || focus ? 0.28 : 0.12), Colors.black.withValues(alpha: 0.45)),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: focus ? tint : Colors.white.withValues(alpha: hover ? 0.3 : 0.14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSlide(
                duration: const Duration(milliseconds: 160),
                offset: Offset(hover ? -0.15 : 0, 0),
                child: const Icon(LucideIcons.arrowLeft, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Text('Collections', style: ConsoleText.bodyStrong.copyWith(color: Colors.white)),
            ],
          ),
        ),
      ),
    ),
  );
}
