import 'dart:async';

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../services/channels.dart';
import '../../state/scope.dart';
import '../play.dart';
import 'channel_editor.dart';

/// Shuffle channels: saved rules that play random episodes from a collection, a label, a
/// show or a library, with bumpers between them if you like.
class ChannelsPage extends StatefulWidget {
  const ChannelsPage({super.key});
  @override
  State<ChannelsPage> createState() => _ChannelsPageState();
}

class _ChannelsPageState extends State<ChannelsPage> {
  ChannelStore? _store;
  String? _error;

  /// The channel being read from Plex before it plays.
  String? _starting;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final s = await AppScope.read(context).channelList();
      if (mounted) setState(() => _store = s);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _edit([ChannelRule? rule]) async {
    final store = _store;
    if (store == null) return;
    final saved = await showChannelEditor(context, rule: rule);
    if (!mounted || saved == null) return;
    if (saved.deleted) {
      store.remove(saved.rule.id);
    } else {
      store.put(saved.rule);
    }
    setState(() {});
  }

  Future<void> _play(ChannelRule rule, {bool resume = true}) async {
    final store = _store;
    final plex = AppScope.read(context).plex;
    if (store == null || plex == null || _starting != null) return;
    setState(() => _starting = rule.id);
    try {
      final run = await ChannelRun.start(plex, store, rule, resume: resume);
      if (!mounted) return;
      setState(() => _starting = null);
      if (run == null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Nothing to play in ${rule.source.title}.')));
        return;
      }
      await playChannel(context, run, resume: resume);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('channel: $e');
      if (!mounted) return;
      setState(() => _starting = null);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Couldn’t start ${rule.name}. ${errorText(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = _store;
    return ListenableBuilder(
      listenable: store ?? const AlwaysStoppedAnimation(0),
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(48, Space.space4, 48, Space.space10),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Channels',
                      style: ConsoleText.display.copyWith(fontSize: 40, height: 1.1, fontWeight: FontWeight.w800, color: c.text100),
                    ),
                    const SizedBox(height: Space.space1),
                    Text(
                      'Your own TV channels: random episodes from a collection, a label or a whole library, every show getting a fair turn, with bumpers in between if you like.',
                      style: ConsoleText.body.copyWith(color: c.text200),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.space4),
              ConsoleButton(label: 'New Channel', icon: LucideIcons.plus, kind: ButtonKind.primary, autofocus: store != null && store.rules.isEmpty, onPressed: store == null ? null : () => _edit()),
            ],
          ),
          const SizedBox(height: Space.space6),
          if (_error != null)
            ErrorNote('Couldn’t read your channels: $_error')
          else if (store == null)
            const LoadingNote(label: 'Reading your channels')
          else if (store.rules.isEmpty)
            const EmptyState(
              title: 'No channels yet',
              body:
                  'Make one from a Plex collection (say, "Adult Swim"), a label, a show or a whole library. For bumpers, keep the clips in Plex as their own show or collection and pick it as the channel’s bumpers.',
            )
          else
            Wrap(
              spacing: Space.space4,
              runSpacing: Space.space4,
              children: [
                for (final (i, r) in store.rules.indexed)
                  _ChannelCard(
                    rule: r,
                    canResume: store.canResume(r.id),
                    starting: _starting == r.id,
                    autofocus: i == 0,
                    onPlay: () => _play(r),
                    onFresh: () => _play(r, resume: false),
                    onEdit: () => _edit(r),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({required this.rule, required this.canResume, required this.starting, required this.autofocus, required this.onPlay, required this.onFresh, required this.onEdit});
  final ChannelRule rule;
  final bool canResume;
  final bool starting;
  final bool autofocus;
  final VoidCallback onPlay;
  final VoidCallback onFresh;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final b = rule.bumpers;
    final facts = [
      'From ${rule.source.title}',
      rule.evenShows ? 'Every show gets a fair turn' : 'Classic shuffle',
      if (b != null) rule.bumperEvery == 1 ? 'Bumpers from ${b.title} between episodes' : 'Bumpers from ${b.title} every ${rule.bumperEvery} episodes',
      if (rule.weights.values.any((w) => w != 1)) 'Custom show weights',
    ];
    return Container(
      width: 420,
      padding: const EdgeInsets.all(Space.space5),
      decoration: BoxDecoration(
        color: c.surface050.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(Radii.radiusLg),
        border: Border.all(color: c.border200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.radioTower, size: 20, color: c.primary),
              const SizedBox(width: Space.space2),
              Expanded(
                child: Text(rule.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ConsoleText.titleLg.copyWith(color: c.text100)),
              ),
            ],
          ),
          const SizedBox(height: Space.space2),
          for (final f in facts)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(f, maxLines: 1, overflow: TextOverflow.ellipsis, style: ConsoleText.small.copyWith(color: c.text300)),
            ),
          const SizedBox(height: Space.space4),
          Wrap(
            spacing: Space.space2,
            runSpacing: Space.space2,
            children: [
              ConsoleButton(label: starting ? 'Tuning in…' : (canResume ? 'Continue' : 'Watch'), icon: LucideIcons.play, kind: ButtonKind.primary, autofocus: autofocus, onPressed: starting ? null : onPlay),
              if (canResume) ConsoleButton(label: 'Start Fresh', icon: LucideIcons.rotateCcw, onPressed: starting ? null : onFresh),
              ConsoleButton(label: 'Edit', icon: LucideIcons.pencil, kind: ButtonKind.tertiary, onPressed: starting ? null : onEdit),
            ],
          ),
        ],
      ),
    );
  }
}
