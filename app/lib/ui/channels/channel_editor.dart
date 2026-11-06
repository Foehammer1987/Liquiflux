import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../services/channels.dart';
import '../../state/app_state.dart';
import '../../state/scope.dart';
import '../settings/settings_field.dart';

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

/// Something in Plex a channel can draw from, as a choice in a list.
typedef _Choice = ({ChannelSource source, String label});

class ChannelEditor extends StatefulWidget {
  const ChannelEditor({super.key, required this.app, this.rule});
  final AppState app;
  final ChannelRule? rule;
  @override
  State<ChannelEditor> createState() => _ChannelEditorState();
}

class _ChannelEditorState extends State<ChannelEditor> {
  late final _name = TextEditingController(text: widget.rule?.name ?? '');
  late String _kind = widget.rule?.source.kind ?? 'collection';
  late ChannelSource? _source = widget.rule?.source;
  late String _bumperKind = widget.rule?.bumpers?.kind ?? 'none';
  late ChannelSource? _bumpers = widget.rule?.bumpers;
  late int _every = widget.rule?.bumperEvery ?? 1;
  late bool _first = widget.rule?.bumperFirst ?? true;
  late bool _even = widget.rule?.evenShows ?? true;
  late Map<String, double> _weights = {...?widget.rule?.weights};

  /// Everything in Plex to pick from, by kind.
  final _choices = <String, List<_Choice>>{};
  bool _loadingChoices = true;
  String? _error;

  /// The source's shows, for their shares and weights.
  ChannelPool? _pool;
  ChannelSource? _poolFor;
  bool _loadingPool = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadChoices());
    if (_source != null) unawaited(_loadPool());
  }

  @override
  void dispose() {
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
      final shows = lib.where((i) => i.type == 'show').toList()..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      if (!mounted) return;
      int byLabel(_Choice a, _Choice b) => a.label.toLowerCase().compareTo(b.label.toLowerCase());
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
    final source = _source;
    final plex = widget.app.plex;
    if (source == null || plex == null) return;
    setState(() {
      _loadingPool = true;
      _poolFor = source;
    });
    try {
      final titles = <String, String>{};
      final shows = await loadChannelSource(plex, source, titles: titles);
      if (!mounted || _poolFor != source) return;
      setState(() {
        _pool = ChannelPool(shows: shows, titles: titles);
        _loadingPool = false;
      });
    } catch (e) {
      debugPrint('channel shows: $e');
      if (mounted && _poolFor == source) {
        setState(() {
          _pool = null;
          _loadingPool = false;
        });
      }
    }
  }

  ChannelRule? get _rule {
    final source = _source;
    if (source == null) return null;
    final name = _name.text.trim();
    return ChannelRule(
      id: widget.rule?.id ?? ChannelStore.newId(),
      name: name.isEmpty ? source.title : name,
      source: source,
      bumpers: _bumperKind == 'none' ? null : _bumpers,
      bumperEvery: _every,
      bumperFirst: _first,
      evenShows: _even,
      weights: {for (final e in _weights.entries) if (e.value != 1) e.key: e.value},
    );
  }

  void _pickSource(ChannelSource? s) {
    if (s == _source) return;
    setState(() {
      _source = s;
      _weights = {};
      _pool = null;
    });
    if (s != null) unawaited(_loadPool());
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

  Widget _picker(String kind, ChannelSource? value, ValueChanged<ChannelSource?> onPick) {
    final list = _choices[kind] ?? const [];
    if (_loadingChoices) return const LoadingNote(label: 'Reading Plex');
    if (list.isEmpty) {
      return Text(
        switch (kind) {
          'collection' => 'No collections in your Plex libraries yet.',
          'label' => 'No labels in your Plex libraries yet.',
          _ => 'Nothing to pick from.',
        },
        style: ConsoleText.small.copyWith(color: context.c.text300),
      );
    }
    final keyOf = {for (final (i, c) in list.indexed) i: c.source};
    final at = list.indexWhere((c) => c.source == value);
    return ConsoleDropdown<int>(
      width: 420,
      options: [if (at < 0) (-1, 'Pick one'), for (final (i, c) in list.indexed) (i, c.label)],
      value: at,
      onChanged: (i) => onPick(keyOf[i]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final kinds = const [('collection', 'Collection'), ('label', 'Label'), ('show', 'Show'), ('section', 'Library')];
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
                        ConsoleSegmented<String>(
                          options: kinds,
                          value: _kind,
                          autofocus: true,
                          onChanged: (k) => setState(() => _kind = k),
                        ),
                        const SizedBox(height: Space.space2),
                        _picker(_kind, _source?.kind == _kind ? _source : null, _pickSource),
                        _label('Name'),
                        SizedBox(
                          width: 420,
                          child: SettingsField(label: 'Channel name', controller: _name, hint: _source?.title ?? 'Adult Swim'),
                        ),
                        _label('Bumpers between episodes'),
                        ConsoleSegmented<String>(
                          options: const [('none', 'None'), ('show', 'Show'), ('collection', 'Collection'), ('label', 'Label')],
                          value: _bumperKind,
                          onChanged: (k) => setState(() => _bumperKind = k),
                        ),
                        if (_bumperKind != 'none') ...[
                          const SizedBox(height: Space.space2),
                          _picker(_bumperKind, _bumpers?.kind == _bumperKind ? _bumpers : null, (s) => setState(() => _bumpers = s)),
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
                          onPressed: rule == null || _source?.kind != _kind || (_bumperKind != 'none' && _bumpers?.kind != _bumperKind) ? null : () => Navigator.of(context).pop((rule: rule, deleted: false)),
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
