import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/scope.dart';
import '../common.dart';
import '../tv_focus.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.sectionKey});
  final String sectionKey;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  static const _page = 120;
  static const _sorts = [('titleSort', 'Title'), ('addedAt:desc', 'Recently Added'), ('originallyAvailableAt:desc', 'Release Date'), ('audienceRating:desc', 'Rating')];
  String _sort = 'titleSort';

  /// Around the first poster, for Down from the sort buttons to land there.
  final _firstCell = FocusNode(debugLabel: 'first poster', canRequestFocus: false, skipTraversal: true);

  @override
  void dispose() {
    _firstCell.dispose();
    super.dispose();
  }

  /// Down from the sort buttons goes to the first poster. They sit at the right end of the
  /// header, so the nearest poster below them was the last one in the row (seen on a Fire TV).
  KeyEventResult _sortKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent || e.logicalKey != LogicalKeyboardKey.arrowDown) return KeyEventResult.ignored;
    final first = _firstCell.descendants.where((n) => n.canRequestFocus && !n.skipTraversal).firstOrNull;
    if (first == null) return KeyEventResult.ignored;
    _cameFrom = FocusManager.instance.primaryFocus;
    glideTo(first);
    return KeyEventResult.handled;
  }

  /// The sort button Down came from, for Up to go back to it, as everywhere else.
  FocusNode? _cameFrom;

  KeyEventResult _firstKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final back = _cameFrom;
    _cameFrom = null;
    if (e.logicalKey != LogicalKeyboardKey.arrowUp || back == null || back.context?.mounted != true) return KeyEventResult.ignored;
    glideTo(back);
    return KeyEventResult.handled;
  }
  final _items = <PlexItem>[];
  int _total = 0;
  bool _loading = false;
  String? _error;

  /// Bumped by each new load, so a slower, older one can't add its results.
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(reset: true);
    });
  }

  Future<void> _load({bool reset = false}) async {
    final plex = AppScope.read(context).plex;
    if (plex == null) return;
    if (!reset && _loading) return;
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _total = 0;
      }
    });
    try {
      final r = await plex.sectionItems(widget.sectionKey, start: _items.length, size: _page, sort: _sort);
      if (!mounted || gen != _gen) return;
      setState(() {
        _items.addAll(r.items);
        _total = r.total;
      });
    } catch (e) {
      if (mounted && gen == _gen) setState(() => _error = errorText(e));
    } finally {
      if (mounted && gen == _gen) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final section = app.sections.where((s) => s.key == widget.sectionKey).firstOrNull;
    final noun = section?.type == 'show' ? (_total == 1 ? 'Show' : 'Shows') : (_total == 1 ? 'Title' : 'Titles');
    const pad = Space.space3;
    return NotificationListener<ScrollNotification>(
      // The next page loads as you near the bottom.
      onNotification: (n) {
        if (n.metrics.extentAfter < 1200 && !_loading && _error == null && _items.isNotEmpty && _items.length < _total) _load();
        return false;
      },
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(pad, pad, pad, 0),
            sliver: SliverToBoxAdapter(
              child: ConsolePanel(
                title: section?.title ?? 'Library',
                meta: _total > 0 ? muted(context, '$_total $noun') : null,
                trailing: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _sortKey,
                  child: ConsoleSegmented<String>(
                    options: _sorts,
                    value: _sort,
                    onChanged: (v) {
                      setState(() => _sort = v);
                      _load(reset: true);
                    },
                  ),
                ),
                padding: EdgeInsets.zero,
                child: const SizedBox(height: Space.space4),
              ),
            ),
          ),
          if (_error != null && _items.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.all(pad),
              sliver: SliverToBoxAdapter(child: ErrorNote(_error!, onRetry: () => _load(reset: true))),
            )
          else if (_items.isEmpty && _loading)
            const SliverPadding(
              padding: EdgeInsets.all(pad),
              sliver: SliverToBoxAdapter(child: LoadingNote()),
            )
          else ...[
            // Only the posters on screen are built and loaded.
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(pad + Space.space4, Space.space4, pad + Space.space4, 0),
              sliver: SliverLayoutBuilder(
                builder: (context, box) {
                  const minWidth = 132.0;
                  final cols = (box.crossAxisExtent / (minWidth + Space.space3)).floor().clamp(2, 12);
                  final w = (box.crossAxisExtent - Space.space3 * (cols - 1)) / cols;
                  return SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, crossAxisSpacing: Space.space3, mainAxisSpacing: Space.space4, mainAxisExtent: w * 1.5 + 50),
                    delegate: SliverChildBuilderDelegate(
                      childCount: _items.length,
                      (context, i) {
                        final poster = PlexPoster(key: ValueKey(_items[i].ratingKey), item: _items[i], autofocus: i == 0);
                        return i == 0 ? Focus(focusNode: _firstCell, onKeyEvent: _firstKey, child: poster) : poster;
                      },
                    ),
                  );
                },
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(Space.space6),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: _error != null
                      ? ConsoleButton(label: 'Couldn’t load more. Try Again', onPressed: () => _load())
                      : _loading
                      ? const LoadingNote()
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
