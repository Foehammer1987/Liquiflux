import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../services/channels.dart';
import '../../state/app_state.dart';
import '../../state/scope.dart';
import '../settings/settings_field.dart';
import 'source_picker.dart';

/// What the editor closed with: a rule to save, or one to delete.
typedef ChannelEdit = ({ChannelRule rule, bool deleted});

/// Makes a new channel, or changes [rule]. Null when cancelled.
Future<ChannelEdit?> showChannelEditor(BuildContext context, {ChannelRule? rule}) {
  final app = AppScope.read(context);
  return showGeneralDialog<ChannelEdit>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (context, a, _, child) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12 * a.value, sigmaY: 12 * a.value),
      child: FadeTransition(opacity: a, child: child),
    ),
    pageBuilder: (context, _, _) => Center(child: ChannelEditor(app: app, rule: rule)),
  );
}


class ChannelEditor extends StatefulWidget {
  const ChannelEditor({super.key, required this.app, this.rule});
  final AppState app;
  final ChannelRule? rule;
  @override
  State<ChannelEditor> createState() => _ChannelEditorState();
}

class _ChannelEditorState extends State<ChannelEditor> {
  late final _name = TextEditingController(text: widget.rule?.name ?? '');
  late List<ChannelSource> _sources = [...?widget.rule?.sources];
  final _addButton = FocusNode();
  late ChannelSource? _bumpers = widget.rule?.bumpers;
  final _bumperButton = FocusNode();
  late int _every = widget.rule?.bumperEvery ?? 1;
  late bool _first = widget.rule?.bumperFirst ?? true;
  late bool _even = widget.rule?.evenShows ?? true;
  late final Map<String, double> _weights = {...?widget.rule?.weights};

  /// Everything in Plex to pick from, by kind.
  final _choices = <String, List<SourceChoice>>{};
  bool _loadingChoices = true;
  String? _error;

  /// The source's shows, for their shares and weights.
  ChannelPool? _pool;
  List<ChannelSource>? _poolFor;
  bool _loadingPool = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadChoices());
    if (_sources.isNotEmpty) unawaited(_loadPool());
  }

  @override
  void dispose() {
    _addButton.dispose();
    _bumperButton.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadChoices() async {
    final app = widget.app;
    final plex = app.plex;
    if (plex == null) {
      setState(() {
        _loadingChoices = false;
        _error = 'Plex isn’t connected.';
      });
      return;
    }
    final sections = app.sections;
    final many = sections.length > 1;
    String where(PlexSection s, String title) => many ? '$title (${s.title})' : title;
    try {
      final per = await Future.wait([
        for (final s in sections)
          Future.wait([
            plex.collections(s.key),
            plex.labels(s.key),
          ]).then((r) => (section: s, collections: r[0] as List<PlexItem>, labels: r[1] as List<({String key, String title})>)),
      ]);
      final lib = await app.library().then<List<PlexItem>>((l) => [for (final x in l.bySection) ...x], onError: (Object _) => const <PlexItem>[]);
      // TV networks and blocks you own at least one show from.
      final packs = await app.tvCollections().then<List<TvShelf>>((t) => tvShelves(t.pack, t.shows), onError: (Object _) => const <TvShelf>[]);
      final shows = lib.where((i) => i.type == 'show').toList()..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      if (!mounted) return;
      int byLabel(SourceChoice a, SourceChoice b) => a.label.toLowerCase().compareTo(b.label.toLowerCase());
      setState(() {
        _choices['collection'] = [
          for (final p in per)
            for (final c in p.collections) (source: ChannelSource(kind: 'collection', key: c.ratingKey, title: c.title), label: where(p.section, c.title)),
        ]..sort(byLabel);
        _choices['label'] = [
          for (final p in per)
            for (final l in p.labels) (source: ChannelSource(kind: 'label', key: l.key, title: l.title, section: p.section.key), label: where(p.section, l.title)),
        ]..sort(byLabel);
        _choices['show'] = [for (final s in shows) (source: ChannelSource(kind: 'show', key: s.ratingKey, title: s.title), label: s.year == null ? s.title : '${s.title} (${s.year})')];
        _choices['pack'] = [
          for (final p in packs)
            if (p.owned.isNotEmpty)
              (
                source: ChannelSource(kind: 'pack', key: p.collection.id, title: p.collection.name),
                label: '${p.collection.name} (${p.collection.isBlock ? 'block' : 'network'}, ${p.owned.length} ${p.owned.length == 1 ? 'show' : 'shows'})',
              ),
        ];
        _choices['section'] = [for (final s in sections) (source: ChannelSource(kind: 'section', key: s.key, title: s.title), label: s.title)];
        _loadingChoices = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingChoices = false;
          _error = errorText(e);
        });
      }
    }
  }

  Future<void> _loadPool() async {
    final sources = _sources;
    final plex = widget.app.plex;
    if (sources.isEmpty || plex == null) {
      setState(() {
        _pool = null;
        _poolFor = null;
        _loadingPool = false;
      });
      return;
    }
    setState(() {
      _loadingPool = true;
      _poolFor = sources;
    });
    try {
      final titles = <String, String>{};
      final shows = await loadChannelSources(plex, sources, titles: titles, packShows: widget.app.packShows);
      if (!mounted || !identical(_poolFor, sources)) return;
      setState(() {
        _pool = ChannelPool(shows: shows, titles: titles);
        _loadingPool = false;
      });
    } catch (e) {
      debugPrint('channel shows: $e');
      if (mounted && identical(_poolFor, sources)) {
        setState(() {
          _pool = null;
          _loadingPool = false;
        });
      }
    }
  }

  ChannelRule? get _rule {
    if (_sources.isEmpty) return null;
    final name = _name.text.trim();
    return ChannelRule(
      id: _id,
      name: name.isEmpty ? _sources.first.title : name,
      sources: _sources,
      bumpers: _bumpers,
      bumperEvery: _every,
      bumperFirst: _first,
      evenShows: _even,
      // Only shows still in the channel keep a weight (once its shows are known).
      weights: {for (final e in _weights.entries) if (e.value != 1 && (_pool?.shows.containsKey(e.key) ?? true)) e.key: e.value},
    );
  }

  late final String _id = widget.rule?.id ?? ChannelStore.newId();

  void _setSources(List<ChannelSource> next) {
    if (listEquals(next, _sources)) return;
    setState(() => _sources = next);
    unawaited(_loadPool());
  }

  /// Opens the picker; focus comes back to the Add button after.
  Future<void> _add() async {
    final picked = await showSourcePicker(context, choices: _choices, chosen: _sources);
    if (!mounted) return;
    if (picked != null) _setSources(picked);
    _addButton.requestFocus();
  }

  void _remove(ChannelSource s) {
    _setSources([for (final x in _sources) if (x != s) x]);
    // The Remove button pressed has gone: focus goes to Add rather than nowhere.
    _addButton.requestFocus();
  }

  void _step(String show, int by) {
    const steps = ChannelRule.weightSteps;
    final now = _weights[show] ?? 1;
    var i = steps.indexWhere((w) => w >= now);
    if (i < 0) i = steps.length - 1;
    final next = steps[(i + by).clamp(0, steps.length - 1)];
    setState(() => _weights[show] = next);
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: Space.space1, top: Space.space4),
    child: Text(
      t.toUpperCase(),
      style: ConsoleText.caption.copyWith(color: context.c.text300, letterSpacing: 1.4, fontWeight: FontWeight.w600),
    ),
  );

  Future<void> _chooseBumpers() async {
    final picked = await showSourcePicker(
      context,
      choices: _choices,
      chosen: [?_bumpers],
      single: true,
      kinds: const ['show', 'collection', 'label'],
      title: 'Choose Bumpers',
    );
    if (!mounted) return;
    if (picked != null && picked.isNotEmpty) setState(() => _bumpers = picked.first);
    _bumperButton.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Theme(
      data: ConsoleTheme.dark(glass: app.settings.glass),
      child: Builder(
        builder: (context) {
          final c = context.c;
          final rule = _rule;
          final pool = _pool;
          final shares = rule != null && pool != null ? channelShares(rule, pool) : const <String, double>{};
          final shows = pool == null ? const <String>[] : (pool.shows.keys.toList()..sort((a, b) => (pool.titles[a] ?? a).toLowerCase().compareTo((pool.titles[b] ?? b).toLowerCase())));
          return Material(
            type: MaterialType.transparency,
            child: Container(
              width: 820,
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height - 80),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0D12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: c.border200),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(Space.space8, Space.space6, Space.space8, Space.space4),
                      children: [
                        Row(
                          children: [
                            Icon(LucideIcons.radioTower, size: 20, color: c.primary),
                            const SizedBox(width: Space.space2),
                            Text(widget.rule == null ? 'New Channel' : 'Edit Channel', style: ConsoleText.titleLg.copyWith(color: c.text100)),
                          ],
                        ),
                        if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.space3), child: ErrorNote('Couldn’t read Plex: $_error')),
                        _label('Episodes from'),
                        for (final src in _sources) _sourceRow(context, src),
                        if (_sources.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Space.space2),
                            child: Text('Pick as many shows, collections, labels or libraries as you like. They play as one channel.', style: ConsoleText.small.copyWith(color: c.text300)),
                          ),
                        const SizedBox(height: Space.space1),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _loadingChoices
                              ? const LoadingNote(label: 'Reading Plex')
                              : ConsoleButton(focusNode: _addButton, autofocus: true, label: _sources.isEmpty ? 'Add Shows and Collections' : 'Add or Remove', icon: LucideIcons.plus, onPressed: _add),
                        ),
                        _label('Name'),
                        SizedBox(
                          width: 420,
                          child: SettingsField(label: 'Channel name', controller: _name, hint: _sources.firstOrNull?.title ?? 'Adult Swim'),
                        ),
                        _label('Bumpers between episodes'),
                        if (_bumpers case final b?) _bumperRow(context, b),
                        if (_bumpers == null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Space.space2),
                            child: Text('None. Pick a show, collection or label that holds short clips.', style: ConsoleText.small.copyWith(color: c.text300)),
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _loadingChoices
                              ? const SizedBox()
                              : ConsoleButton(focusNode: _bumperButton, label: _bumpers == null ? 'Choose Bumpers' : 'Change Bumpers', icon: LucideIcons.clapperboard, onPressed: _chooseBumpers),
                        ),
                        if (_bumpers != null) ...[
                          const SizedBox(height: Space.space3),
                          ConsoleSegmented<int>(
                            options: const [(1, 'After every episode'), (2, 'Every 2'), (3, 'Every 3'), (4, 'Every 4')],
                            value: _every,
                            onChanged: (v) => setState(() => _every = v),
                          ),
                          const SizedBox(height: Space.space3),
                          _switchRow(context, _first, (v) => setState(() => _first = v), 'Start with a bumper'),
                          const SizedBox(height: Space.space1),
                          Text(
                            'Bumpers always play from the start. They don’t show Skip Intro or Up Next, and they’re never marked watched or sent to Trakt or AniList.',
                            style: ConsoleText.small.copyWith(color: c.text300),
                          ),
                        ],
                        _label('Shuffle'),
                        _switchRow(context, _even, (v) => setState(() => _even = v), 'Give every show an equal turn'),
                        const SizedBox(height: Space.space1),
                        Text(
                          _even
                              ? 'Picks a show, then one of its episodes, so a show with 800 episodes doesn’t crowd out one with 50. Set a show higher or lower below.'
                              : 'Classic shuffle: every episode is equally likely, so long-running shows come up most.',
                          style: ConsoleText.small.copyWith(color: c.text300),
                        ),
                        if (_loadingPool) const Padding(padding: EdgeInsets.only(top: Space.space3), child: LoadingNote(label: 'Reading the shows')),
                        if (pool != null && shows.isNotEmpty) ...[
                          const SizedBox(height: Space.space3),
                          Text('${shows.length} ${shows.length == 1 ? 'show' : 'shows'}, ${pool.episodeCount} episodes', style: ConsoleText.small.copyWith(color: c.text200)),
                          const SizedBox(height: Space.space2),
                          for (final s in shows) _weightRow(context, pool.titles[s] ?? s, pool.shows[s]!.length, _weights[s] ?? 1, shares[s] ?? 0, () => _step(s, -1), () => _step(s, 1)),
                        ],
                        if (pool != null && shows.isEmpty) Padding(padding: const EdgeInsets.only(top: Space.space3), child: Text('No episodes found there.', style: ConsoleText.small.copyWith(color: c.text300))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(Space.space8, Space.space3, Space.space8, Space.space5),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border200))),
                    child: Row(
                      children: [
                        if (widget.rule != null) ConsoleButton(label: 'Delete', icon: LucideIcons.trash2, kind: ButtonKind.danger, onPressed: () => Navigator.of(context).pop((rule: widget.rule!, deleted: true))),
                        const Spacer(),
                        ConsoleButton(label: 'Cancel', kind: ButtonKind.tertiary, onPressed: () => Navigator.of(context).pop()),
                        const SizedBox(width: Space.space2),
                        ConsoleButton(
                          label: 'Save',
                          icon: LucideIcons.check,
                          kind: ButtonKind.primary,
                          onPressed: rule == null ? null : () => Navigator.of(context).pop((rule: rule, deleted: false)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _bumperRow(BuildContext context, ChannelSource b) {
    final c = context.c;
    final (icon, kind) = sourceKind(b.kind);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.space2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c.text300),
          const SizedBox(width: Space.space2),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: b.title, style: ConsoleText.body.copyWith(color: c.text100)),
                  TextSpan(text: '  $kind', style: ConsoleText.small.copyWith(color: c.text300)),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ConsoleButton(
            label: 'No Bumpers',
            icon: LucideIcons.x,
            iconOnly: true,
            size: ButtonSize.sm,
            kind: ButtonKind.tertiary,
            onPressed: () {
              setState(() => _bumpers = null);
              _bumperButton.requestFocus();
            },
          ),
        ],
      ),
    );
  }

  Widget _sourceRow(BuildContext context, ChannelSource src) {
    final c = context.c;
    final (icon, kind) = sourceKind(src.kind);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c.text300),
          const SizedBox(width: Space.space2),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: src.title, style: ConsoleText.body.copyWith(color: c.text100)),
                  TextSpan(text: '  $kind', style: ConsoleText.small.copyWith(color: c.text300)),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ConsoleButton(label: 'Remove ${src.title}', icon: LucideIcons.x, iconOnly: true, size: ButtonSize.sm, kind: ButtonKind.tertiary, onPressed: () => _remove(src)),
        ],
      ),
    );
  }

  Widget _switchRow(BuildContext context, bool value, ValueChanged<bool> onChanged, String label) => Row(
    children: [
      ConsoleSwitch(value: value, onChanged: onChanged, semanticLabel: label),
      const SizedBox(width: Space.space2),
      Text(label, style: ConsoleText.body.copyWith(color: context.c.text200)),
    ],
  );

  Widget _weightRow(BuildContext context, String title, int episodes, double weight, double share, VoidCallback less, VoidCallback more) {
    final c = context.c;
    final off = weight <= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: title, style: ConsoleText.body.copyWith(color: off ? c.text300 : c.text100)),
                  TextSpan(text: '  $episodes ep', style: ConsoleText.small.copyWith(color: c.text300)),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ConsoleButton(label: 'Less of $title', icon: LucideIcons.minus, iconOnly: true, size: ButtonSize.sm, kind: ButtonKind.tertiary, onPressed: off ? null : less),
          SizedBox(
            width: 92,
            child: Text(
              off ? 'Off' : '${(share * 100).toStringAsFixed(share < 0.1 ? 1 : 0)}%${weight == 1 ? '' : ' (×${_trim(weight)})'}',
              textAlign: TextAlign.center,
              style: ConsoleText.small.copyWith(color: off ? c.text300 : c.text100, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          ConsoleButton(label: 'More of $title', icon: LucideIcons.plus, iconOnly: true, size: ButtonSize.sm, kind: ButtonKind.tertiary, onPressed: weight >= ChannelRule.maxWeight ? null : more),
        ],
      ),
    );
  }

  static String _trim(double w) => w == w.roundToDouble() ? w.toStringAsFixed(0) : w.toString();
}
