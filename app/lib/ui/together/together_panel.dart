import 'dart:ui' show ImageFilter;

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:openwatchparty/openwatchparty.dart' as owp;

import '../../platform.dart';
import '../../services/open_party.dart';
import '../../services/watch_together.dart';
import '../settings/settings_field.dart';
import '../../state/scope.dart';
import '../play.dart';
import '../player/remote.dart';

/// Start a room for [item] and pick who to ask, or, once in one, see who's there.
/// Lives in the player's side panel, and in a dialog from a title's page.
class TogetherPanel extends StatefulWidget {
  const TogetherPanel({super.key, required this.item, required this.tint, this.onClose, this.onStarted, this.focusOnOpen = false});
  final PlexItem item;
  final Color tint;
  final VoidCallback? onClose;

  /// Put focus on the first thing in the panel once it's up, for the D-pad.
  final bool focusOnOpen;

  /// The room is up (from a title's page this starts playback).
  final VoidCallback? onStarted;

  @override
  State<TogetherPanel> createState() => _TogetherPanelState();
}

class _TogetherPanelState extends State<TogetherPanel> {
  late final Future<List<PlexFriend>> _friends = AppScope.read(context).watchTogether.loadFriends();
  final _picked = <int>{};
  bool _inviting = false;
  final _list = FocusNode(debugLabel: 'together list');
  final _close = FocusNode(debugLabel: 'together close');

  WatchTogether get _wt => AppScope.read(context).watchTogether;
  OpenParty get _party => AppScope.read(context).openParty;
  final _code = TextEditingController();
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusOnOpen) WidgetsBinding.instance.addPostFrameCallback((_) => _focusFirst());
  }

  /// The first friend or button in the list, or Close when there's nothing to press yet.
  void _focusFirst() {
    if (!mounted) return;
    final first = _list.traversalDescendants.firstOrNull ?? (_close.context == null ? null : _close);
    first?.requestFocus();
  }

  @override
  void dispose() {
    _list.dispose();
    _close.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final started = await _wt.start(widget.item, _picked.toList());
    if (started && mounted) widget.onStarted?.call();
  }

  /// A room by code: the player opens on its own once the room has the title.
  Future<void> _startCode() async {
    final started = await _party.start(widget.item);
    if (started && mounted) widget.onClose?.call();
  }

  Future<void> _joinCode() async {
    final joined = await _party.join(_code.text);
    if (joined && mounted) widget.onClose?.call();
  }

  Future<void> _invite() async {
    final sent = await _wt.invite(_picked.toList());
    if (sent && mounted) {
      setState(() {
        _picked.clear();
        _inviting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final wt = app.watchTogether, party = app.openParty;
    return ListenableBuilder(
      listenable: Listenable.merge([wt, party]),
      builder: (context, _) {
        final inRoom = wt.inRoomFor(widget.item.ratingKey);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.space4, Space.space3, Space.space2, 0),
              child: Row(
                children: [
                  Icon(LucideIcons.usersRound, color: widget.tint, size: 20),
                  const SizedBox(width: Space.space2),
                  Expanded(
                    child: Text('Watch Together', style: ConsoleText.titleLg.copyWith(color: Colors.white)),
                  ),
                  if (widget.onClose != null)
                    Focusable(
                      onTap: widget.onClose!,
                      focusNode: _close,
                      semanticLabel: 'Close',
                      builder: (_, hover, focus) => Container(
                        padding: const EdgeInsets.all(8),
                        foregroundDecoration: tvRing(focus, circle: true),
                        child: Icon(LucideIcons.x, size: 18, color: Colors.white.withValues(alpha: hover ? 1 : 0.7)),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Focus(
                focusNode: _list,
                canRequestFocus: false,
                skipTraversal: true,
                child: ListView(padding: const EdgeInsets.fromLTRB(Space.space4, Space.space2, Space.space4, Space.space4), children: party.inRoom ? _codeRoom(party) : (inRoom ? _room(wt) : _setup(wt, party))),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _note(String text) => Text(text, style: ConsoleText.small.copyWith(color: Colors.white.withValues(alpha: 0.7), height: 1.45));

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: Space.space4, bottom: Space.space2),
    child: Text(
      text,
      style: ConsoleText.caption.copyWith(color: Colors.white.withValues(alpha: 0.55), letterSpacing: 1.6, fontWeight: FontWeight.w600),
    ),
  );

  Widget _error(WatchTogether wt) => wt.error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: Space.space3),
          child: Text(wt.error!, style: ConsoleText.small.copyWith(color: const Color(0xFFFF8A80))),
        );

  List<Widget> _setup(WatchTogether wt, OpenParty party) {
    final title = widget.item.type == 'episode' ? (widget.item.grandparentTitle ?? widget.item.title) : widget.item.title;
    return [
      _note('Watch $title in step with friends: play, pause and jumps happen for everyone.'),
      _heading('WITH A ROOM CODE'),
      _note('Get a code to share. Friends join from Liquiflux or Plezy, each playing their own copy from their own Plex server.'),
      const SizedBox(height: Space.space3),
      if (roomKind(widget.item))
        TvRing(
          radius: Radii.radiusSm,
          child: ConsoleButton(label: party.busy && !_joining ? 'Opening…' : 'Start a Room', icon: LucideIcons.play, kind: ButtonKind.primary, onPressed: party.busy ? null : _startCode),
        ),
      const SizedBox(height: Space.space2),
      if (_joining) ...[
        SettingsField(label: 'Room code', controller: _code, hint: 'K7M-Q2X', mono: true, onSubmitted: (_) => _joinCode()),
        const SizedBox(height: Space.space2),
        TvRing(
          radius: Radii.radiusSm,
          child: ConsoleButton(label: party.busy ? 'Joining…' : 'Join', icon: LucideIcons.logIn, kind: ButtonKind.primary, onPressed: party.busy ? null : _joinCode),
        ),
      ] else
        TvRing(
          radius: Radii.radiusSm,
          child: ConsoleButton(label: 'Join with a Code', icon: LucideIcons.keyRound, onPressed: () => setState(() => _joining = true)),
        ),
      if (party.error != null)
        Padding(
          padding: const EdgeInsets.only(top: Space.space3),
          child: Text(party.error!, style: ConsoleText.small.copyWith(color: const Color(0xFFFF8A80))),
        ),
      _heading('WITH PLEX FRIENDS'),
      _note('A Plex Watch Together room. Friends join from Liquiflux or Plex Web.'),
      const SizedBox(height: Space.space2),
      _friendPicker(exclude: const {}),
      const SizedBox(height: Space.space4),
      TvRing(
        radius: Radii.radiusSm,
        child: ConsoleButton(
          label: wt.busy ? 'Starting…' : (_picked.isEmpty ? 'Start a Plex Room' : 'Start a Plex Room with ${_picked.length}'),
          icon: LucideIcons.play,
          kind: ButtonKind.primary,
          onPressed: wt.busy ? null : _start,
        ),
      ),
      _error(wt),
    ];
  }

  /// In a room by code: its code, who's there, and the way out.
  List<Widget> _codeRoom(OpenParty party) {
    final me = party.state.peerId;
    final room = party.state.room;
    final match = party.state.match?.state;
    return [
      _note('Share this code. Friends join from Liquiflux or Plezy, and play, pause and jumps happen for everyone.'),
      _heading('ROOM CODE'),
      Text(party.code ?? '…', style: ConsoleText.titleLg.copyWith(color: Colors.white, fontSize: 34, letterSpacing: 4, fontWeight: FontWeight.w700)),
      if (match == owp.MatchState.searching) ...[const SizedBox(height: Space.space2), _note('Looking for this title on your Plex server…')],
      if (match == owp.MatchState.unavailable) ...[const SizedBox(height: Space.space2), _note('This title isn’t on your Plex server, so you can’t play along.')],
      if (party.state.mismatch != null) ...[
        const SizedBox(height: Space.space2),
        _note('Your copy is ${_minutes(party.state.mismatch!.deltaMs)} different from the host’s, so it may drift out of step.'),
        const SizedBox(height: Space.space2),
        TvRing(radius: Radii.radiusSm, child: ConsoleButton(label: 'Play Mine Anyway', icon: LucideIcons.play, kind: ButtonKind.primary, onPressed: party.acceptMismatch)),
      ],
      _heading('IN THE ROOM'),
      for (final p in room?.participants ?? const <owp.Participant>[])
        _Person(
          name: cleanLabel(p.name, max: 32, fallback: 'Guest'),
          you: p.peerId == me,
          detail: [if (p.host) 'Host', ?_client(p.client)].join(' · ').ifEmpty,
          state: !p.connected ? 'Reconnecting' : switch (p.player) { owp.PlayerState.ready => 'Watching', owp.PlayerState.buffering => 'Buffering', owp.PlayerState.loading => 'Joining', owp.PlayerState.idle => 'Not playing' },
          on: p.connected,
          tint: widget.tint,
        ),
      if (room == null) _note('Connecting…'),
      const SizedBox(height: Space.space4),
      TvRing(
        radius: Radii.radiusSm,
        child: ConsoleButton(label: 'Leave Room', icon: LucideIcons.logOut, kind: ButtonKind.danger, onPressed: party.leave),
      ),
      if (party.isHost) ...[
        const SizedBox(height: Space.space2),
        TvRing(
          radius: Radii.radiusSm,
          child: ConsoleButton(label: 'End Room for Everyone', icon: LucideIcons.circleStop, onPressed: party.end),
        ),
      ],
    ];
  }

  static String _minutes(int ms) {
    final m = (ms.abs() / 60000).round();
    return m < 1 ? 'a few seconds' : (m == 1 ? 'a minute' : '$m minutes');
  }

  /// "Plezy/1.4.0" → "Plezy".
  static String? _client(String c) => cleanLabel(c.split('/').first, max: 20).ifEmpty;

  List<Widget> _room(WatchTogether wt) {
    final room = wt.room!;
    final here = {for (final p in wt.peers) p.userId};
    final invited = [
      for (final u in room.users)
        if (!here.contains(u.id) && u.id != wt.account?.id) u,
    ];
    return [
      _note('Play, pause and jumps are shared with everyone here. The room closes three hours after it opened.'),
      _heading('IN THE ROOM'),
      for (final p in wt.peers)
        _Person(name: p.name, you: p.me, detail: p.device.isNotEmpty && p.device != p.name ? p.device : null, state: p.ready ? 'Watching' : 'Joining', on: true, tint: widget.tint),
      if (wt.peers.isEmpty) _note('Connecting…'),
      if (invited.isNotEmpty) ...[_heading('INVITED'), for (final u in invited) _Person(name: u.title, thumb: u.thumb, state: 'Not here yet', on: false, tint: widget.tint)],
      const SizedBox(height: Space.space4),
      if (_inviting) ...[
        _friendPicker(exclude: {for (final u in room.users) u.id}),
        const SizedBox(height: Space.space3),
        TvRing(
          radius: Radii.radiusSm,
          child: ConsoleButton(label: wt.busy ? 'Inviting…' : 'Send Invites', icon: LucideIcons.send, kind: ButtonKind.primary, onPressed: wt.busy || _picked.isEmpty ? null : _invite),
        ),
      ] else
        TvRing(
          radius: Radii.radiusSm,
          child: ConsoleButton(label: 'Invite More', icon: LucideIcons.userPlus, onPressed: () => setState(() => _inviting = true)),
        ),
      const SizedBox(height: Space.space2),
      TvRing(
        radius: Radii.radiusSm,
        child: ConsoleButton(label: 'Leave Room', icon: LucideIcons.logOut, kind: ButtonKind.danger, onPressed: wt.leave),
      ),
      _error(wt),
    ];
  }

  Widget _friendPicker({required Set<int> exclude}) => FutureBuilder<List<PlexFriend>>(
    future: _friends,
    builder: (context, snap) {
      if (snap.hasError) return _note(WatchTogether.explain(snap.error!));
      if (!snap.hasData) return _note('Finding your Plex friends…');
      final list = snap.data!.where((f) => !exclude.contains(f.id)).toList();
      if (list.isEmpty) return _note('No Plex friends to invite yet. Add friends at plex.tv, or start a room and share it from Plex Web.');
      return Column(
        children: [
          for (final f in list)
            Focusable(
              onTap: () => setState(() => _picked.contains(f.id) ? _picked.remove(f.id) : _picked.add(f.id)),
              semanticLabel: 'Invite ${f.title}',
              builder: (_, hover, focus) => _Person(
                name: f.title,
                detail: f.username != null && f.username != f.title ? f.username : null,
                thumb: f.thumb,
                tint: widget.tint,
                on: _picked.contains(f.id),
                hover: hover || focus,
                focused: focus,
                trailing: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _picked.contains(f.id) ? widget.tint : Colors.transparent,
                    border: Border.all(color: _picked.contains(f.id) ? widget.tint : Colors.white.withValues(alpha: 0.4), width: 1.5),
                  ),
                  child: _picked.contains(f.id) ? const Icon(LucideIcons.check, size: 14, color: Colors.black) : null,
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _Person extends StatelessWidget {
  const _Person({required this.name, required this.tint, this.you = false, this.detail, this.thumb, this.state, this.on = false, this.hover = false, this.focused = false, this.trailing});
  final String name;
  final bool you;
  final String? detail;
  final String? thumb;
  final String? state;
  final Color tint;
  final bool on;
  final bool hover;
  final bool focused;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();
    final face = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.lerp(Colors.black, tint, on ? 0.55 : 0.25),
        border: Border.all(color: on ? tint : Colors.white.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: thumb != null && thumb!.startsWith('http')
          ? ArtImage(
              thumb!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Center(
                child: Text(initials, style: ConsoleText.bodyStrong.copyWith(color: Colors.white)),
              ),
            )
          : Center(
              child: Text(initials, style: ConsoleText.bodyStrong.copyWith(color: Colors.white)),
            ),
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: Space.space2, vertical: 6),
      foregroundDecoration: tvRing(focused, radius: Radii.radiusMd),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: hover ? 0.08 : 0),
        borderRadius: BorderRadius.circular(Radii.radiusMd),
      ),
      child: Row(
        children: [
          face,
          const SizedBox(width: Space.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  you ? '$name (you)' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ConsoleText.bodyStrong.copyWith(color: Colors.white),
                ),
                if (detail != null || state != null)
                  Text(
                    [?state, ?detail].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ConsoleText.caption.copyWith(color: state == 'Watching' ? tint : Colors.white.withValues(alpha: 0.55)),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Watch Together from a title's page: pick friends, then playback starts in the room.
Future<void> showTogether(BuildContext context, PlexItem item) async {
  final host = context;
  final c = context.c;
  var started = false;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.radiusLg + 4),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            width: 420,
            height: 560,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(Radii.radiusLg + 4),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: TogetherPanel(
                item: item,
                tint: c.primary,
                focusOnOpen: isTv,
                onClose: () => Navigator.of(context).pop(),
                onStarted: () {
                  started = true;
                  Navigator.of(context).pop();
                },
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(
        scale: Tween(begin: 0.96, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
  if (started && host.mounted) await playTitle(host, item);
}

extension on String {
  String? get ifEmpty => isEmpty ? null : this;
}
