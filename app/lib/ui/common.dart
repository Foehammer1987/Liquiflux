import 'dart:async';

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../state/scope.dart';
import 'nav.dart';

/// Runs [load] and renders loading / error / data; [pollEvery] refreshes in place.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder, this.pollEvery, this.loadingLabel = 'Loading'});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, VoidCallback reload) builder;
  final Duration? pollEvery;
  final String loadingLabel;
  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  T? _data;
  String? _error;
  bool _has = false;
  Timer? _timer;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _run();
    if (widget.pollEvery != null) _timer = Timer.periodic(widget.pollEvery!, (_) => _run());
  }

  Future<void> _run() async {
    final id = ++_seq;
    try {
      final d = await widget.load();
      if (!mounted || id != _seq) return;
      setState(() {
        _data = d;
        _has = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted || id != _seq) return;
      setState(() => _error = errorText(e));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_has) return widget.builder(context, _data as T, _run);
    if (_error != null) return ErrorNote(_error!, onRetry: _run);
    return LoadingNote(label: widget.loadingLabel);
  }
}

/// Scrolling page body with Console spacing.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth, this.padding = const EdgeInsets.all(Space.space3)});
  final List<Widget> children;
  final double? maxWidth;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    Widget col = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: Space.space3), children[i]],
      ],
    );
    if (maxWidth != null) {
      col = Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth!),
          child: col,
        ),
      );
    }
    return SingleChildScrollView(padding: padding, child: col);
  }
}

/// A Plex item as a poster (or a landscape card when [wide]).
class PlexPoster extends StatelessWidget {
  const PlexPoster({super.key, required this.item, this.wide = false, this.autofocus = false, this.onHighlight});
  final PlexItem item;

  /// Hover / focus, so Home can preview the title in its spotlight.
  final ValueChanged<bool>? onHighlight;
  final bool wide;
  final bool autofocus;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final path = wide ? (item.art ?? item.thumb) : item.posterPath;
    final spoilers = app.settings.spoilers;
    return PosterCard(
      title: item.cardTitle,
      subtitle: item.type == 'episode' ? '${item.episodeCode} · ${spoilers.titleOf(item)}' : item.cardSubtitle,
      // Wide episode cards show the episode's own still; posters show the show's.
      blur: wide && item.art == null && spoilers.hideImage(item),
      imageUrl: app.plex?.imageUrl(path, width: wide ? 480 : 240, height: wide ? 270 : 360),
      progress: item.watchProgress,
      wide: wide,
      autofocus: autofocus,
      onHighlight: onHighlight,
      onTap: () => ShellNav.of(context).push(ItemDest(item.ratingKey)),
    );
  }
}

Text muted(BuildContext context, String s) => Text(s, style: ConsoleText.small.copyWith(color: context.c.text200));
