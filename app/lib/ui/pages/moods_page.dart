import 'dart:math';

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../state/scope.dart';
import '../common.dart';

/// Netflix-style browsing of your own library: every mood that has enough titles
/// ("Feel-Good Comedies", "Dark Sci-Fi", "Waiting on Your Shelf"…), then every Plex genre.
/// Home shows a few of the moods; this page has them all.
class MoodsPage extends StatefulWidget {
  const MoodsPage({super.key});
  @override
  State<MoodsPage> createState() => _MoodsPageState();
}

class _MoodsPageState extends State<MoodsPage> {
  List<PlexItem>? _all;
  String? _error;
  String _kind = 'all';
  List<MoodRow> _moods = const [];
  List<MoodRow> _genres = const [];
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = AppScope.read(context);
    try {
      final lib = await app.library();
      if (!mounted) return;
      _all = [for (final l in lib.bySection) ...l];
      _fill();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  void _fill() {
    final all = _all;
    if (all == null) return;
    setState(() {
      _moods = moodRows(all, kind: _kind, perRow: 24, random: _rng);
      _genres = genreRows(all, kind: _kind, perRow: 24, random: _rng);
    });
  }

  Widget _heading(String title, String note) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, Space.space10, 48, Space.space4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: ConsoleText.display.copyWith(fontSize: 26, fontWeight: FontWeight.w800, color: c.text100),
          ),
          const SizedBox(width: Space.space3),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(note, style: ConsoleText.caption.copyWith(color: c.text300)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shelf(MoodRow row) => Shelf(
    key: ValueKey('${row.name}:$_kind'),
    title: row.name,
    inset: 48,
    children: [for (final i in row.items) PlexPoster(item: i)],
  );

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget gap() => const SizedBox(height: Space.space8);
    // A lazy list: rows below the fold (and their posters) load as you scroll to them.
    return ListView(
      padding: const EdgeInsets.only(bottom: Space.space10),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(48, Space.space4, 48, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Moods',
                      style: ConsoleText.display.copyWith(fontSize: 40, height: 1.1, fontWeight: FontWeight.w800, color: c.text100),
                    ),
                    const SizedBox(height: Space.space1),
                    Text('Your library by mood and genre. Each visit shows a different mix.', style: ConsoleText.body.copyWith(color: c.text200)),
                  ],
                ),
              ),
              ConsoleSegmented<String>(
                options: const [('all', 'All'), ('movie', 'Movies'), ('show', 'Series')],
                value: _kind,
                onChanged: (k) {
                  _kind = k;
                  _fill();
                },
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(48), child: ErrorNote('Couldn’t read your Plex library: $_error'))
        else if (_all == null)
          const Padding(padding: EdgeInsets.only(top: Space.space10), child: LoadingNote(label: 'Reading your library'))
        else if (_moods.isEmpty && _genres.isEmpty)
          const Padding(padding: EdgeInsets.all(48), child: ErrorNote('Not enough titles here for mood rows yet.'))
        else ...[
          if (_moods.isNotEmpty) ...[
            _heading('By Mood', 'Built from Plex genres, years, length, ratings and what you’ve watched.'),
            for (final (i, m) in _moods.indexed) ...[if (i > 0) gap(), _shelf(m)],
          ],
          if (_genres.isNotEmpty) ...[
            _heading('By Genre', 'Every genre with at least 8 titles, biggest first.'),
            for (final (i, g) in _genres.indexed) ...[if (i > 0) gap(), _shelf(g)],
          ],
        ],
      ],
    );
  }
}
