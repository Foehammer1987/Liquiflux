import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import '../state/scope.dart';

/// "Who's watching?": the Plex Home's users, and a PIN pad for the ones that have a PIN.
/// True when another user is now in use. [atStart] (the launch prompt) closes by itself
/// when the Home has fewer than two users or plex.tv can't be reached.
Future<bool> showProfiles(BuildContext context, {bool atStart = false}) async {
  final app = AppScope.read(context);
  final switched = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close profiles',
    barrierColor: Colors.black.withValues(alpha: atStart ? 0.92 : 0.7),
    transitionDuration: const Duration(milliseconds: 240),
    transitionBuilder: (context, a, _, child) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16 * a.value, sigmaY: 16 * a.value),
      child: FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child),
      ),
    ),
    pageBuilder: (context, _, _) => ProfilePicker(app: app, atStart: atStart),
  );
  return switched ?? false;
}

class ProfilePicker extends StatefulWidget {
  const ProfilePicker({super.key, required this.app, this.atStart = false});
  final AppState app;
  final bool atStart;
  @override
  State<ProfilePicker> createState() => _ProfilePickerState();
}

class _ProfilePickerState extends State<ProfilePicker> {
  List<PlexHomeUser>? _users;
  String? _error;

  /// The user whose PIN is being typed, if any.
  PlexHomeUser? _pinFor;
  String _pin = '';
  String? _pinError;
  bool _busy = false;
  int _shake = 0;

  // Where the remote goes as the PIN pad comes and goes (autofocus can't: the old view is
  // still fading out, holding the focus, when the new one appears).
  final _firstKey = FocusNode(debugLabel: 'pin 1');
  final _tiles = <String, FocusNode>{};
  FocusNode _tile(PlexHomeUser u) => _tiles.putIfAbsent(u.uuid, () => FocusNode(debugLabel: 'profile ${u.uuid}'));

  void _focusSoon(FocusNode n) => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) n.requestFocus();
  });

  @override
  void dispose() {
    _firstKey.dispose();
    for (final n in _tiles.values) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Shows the Home as last listed straight away, and asks plex.tv again behind it (someone
  /// may have been added since). Failing that, what was listed before stays.
  Future<void> _load() async {
    final had = widget.app.homeList;
    setState(() {
      _error = null;
      _users = had != null && had.length > 1 ? had : null;
    });
    if (_users != null) _focusCurrent();
    try {
      final list = await widget.app.homeUsers(fresh: !widget.atStart || had == null);
      if (!mounted) return;
      if (widget.atStart && list.length < 2) return _close(false);
      final first = _users == null;
      setState(() => _users = list);
      if (first) _focusCurrent();
    } catch (e) {
      if (!mounted || _users != null) return;
      if (widget.atStart) return _close(false);
      setState(() => _error = errorText(e));
    }
  }

  /// The remote starts on whoever's watching, else the first person.
  void _focusCurrent() {
    final list = _users;
    if (list == null || list.isEmpty || _pinFor != null) return;
    _focusSoon(_tile(list.firstWhere(_isCurrent, orElse: () => list.first)));
  }

  void _close(bool switched) {
    if (mounted) Navigator.of(context).pop(switched);
  }

  bool _isCurrent(PlexHomeUser u) => widget.app.profile?.uuid == u.uuid;

  void _pick(PlexHomeUser u) {
    if (_busy) return;
    if (_isCurrent(u)) return _close(false);
    if (u.protected) {
      setState(() {
        _pinFor = u;
        _pin = '';
        _pinError = null;
      });
      _focusSoon(_firstKey);
      return;
    }
    unawaited(_switch(u, null));
  }

  Future<void> _switch(PlexHomeUser u, String? pin) async {
    setState(() {
      _busy = true;
      _pinError = null;
      _error = null;
    });
    try {
      await widget.app.switchProfile(u, pin: pin);
      _close(true);
    } on PlexPinRejected {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pin = '';
        _pinError = 'That PIN is not right. Try again.';
        _shake++;
        // plex.tv thinks this user has a PIN after all.
        if (_pinFor == null) _focusSoon(_firstKey);
        _pinFor ??= u;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pin = '';
        if (_pinFor != null) {
          _pinError = errorText(e);
        } else {
          _error = errorText(e);
        }
      });
    }
  }

  void _digit(String d) {
    if (_busy || _pin.length >= 4) return;
    setState(() {
      _pin += d;
      _pinError = null;
    });
    if (_pin.length == 4) unawaited(_switch(_pinFor!, _pin));
  }

  void _erase() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _leavePin() {
    final u = _pinFor;
    setState(() {
      _pinFor = null;
      _pin = '';
      _pinError = null;
    });
    if (u != null) _focusSoon(_tile(u));
  }

  /// Number keys, the keypad and Backspace type the PIN; Back leaves the PIN pad first.
  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (_pinFor == null || e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    for (var i = 0; i <= 9; i++) {
      if (k == LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + i) || k == LogicalKeyboardKey(LogicalKeyboardKey.numpad0.keyId + i)) {
        _digit('$i');
        return KeyEventResult.handled;
      }
    }
    if (k == LogicalKeyboardKey.backspace || k == LogicalKeyboardKey.delete) {
      _erase();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ConsoleTheme.dark(glass: widget.app.settings.glass),
      child: Builder(
        builder: (context) {
          final c = context.c;
          return PopScope(
            canPop: _pinFor == null,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && _pinFor != null) _leavePin();
            },
            child: Material(
              type: MaterialType.transparency,
              child: Focus(
                // Only hears the keys of the controls inside; never takes the focus itself.
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _key,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(Space.space6),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _pinFor != null ? _pinPad(context, c, _pinFor!) : _list(context, c),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _list(BuildContext context, ConsoleColors c) {
    final users = _users;
    return Column(
      key: const ValueKey('list'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("Who's watching?", style: ConsoleText.display.copyWith(color: c.text100, fontSize: 40, fontWeight: FontWeight.w800)),
        const SizedBox(height: Space.space8),
        if (_error != null) ...[
          SizedBox(width: 520, child: ErrorNote(_error!)),
          const SizedBox(height: Space.space4),
          ConsoleButton(label: 'Try Again', icon: LucideIcons.refreshCw, autofocus: true, onPressed: _load),
        ] else if (users == null)
          const LoadingNote(label: 'Asking Plex who is in your Home')
        else if (users.length < 2)
          SizedBox(
            width: 520,
            child: Text(
              'This Plex account has no other Home users. Add some at plex.tv under Plex Home, then they show up here.',
              textAlign: TextAlign.center,
              style: ConsoleText.body.copyWith(color: c.text200),
            ),
          )
        else
          FocusTraversalGroup(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: Space.space6,
              runSpacing: Space.space6,
              children: [
                for (final u in users)
                  ProfileTile(
                    user: u,
                    focusNode: _tile(u),
                    current: _isCurrent(u),
                    busy: _busy,
                    onTap: () => _pick(u),
                  ),
              ],
            ),
          ),
        if (_busy && _pinFor == null) ...[const SizedBox(height: Space.space6), const LoadingNote(label: 'Switching')],
      ],
    );
  }

  Widget _pinPad(BuildContext context, ConsoleColors c, PlexHomeUser u) {
    Widget key(String label, {IconData? icon, VoidCallback? onTap, FocusNode? focusNode}) => Padding(
      padding: const EdgeInsets.all(Space.space2),
      child: Focusable(
        onTap: onTap,
        focusNode: focusNode,
        semanticLabel: label,
        builder: (context, hover, focus) => withFocusRing(
          context,
          focused: focus,
          radius: Radii.radiusFull,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: focus || hover ? Colors.white.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.07),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Center(
              child: icon != null ? Icon(icon, color: c.text100, size: 26) : Text(label, style: ConsoleText.display.copyWith(fontSize: 28, color: c.text100)),
            ),
          ),
        ),
      ),
    );
    return Column(
      key: ValueKey('pin:${u.uuid}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        ProfileAvatar(user: u, size: 96),
        const SizedBox(height: Space.space3),
        Text('Enter ${u.name}’s PIN', style: ConsoleText.titleLg.copyWith(color: c.text100)),
        const SizedBox(height: Space.space5),
        TweenAnimationBuilder<double>(
          key: ValueKey(_shake),
          tween: Tween(begin: _shake == 0 ? 0 : 1, end: 0),
          duration: const Duration(milliseconds: 420),
          builder: (context, t, child) => Transform.translate(offset: Offset(12 * t * (((t * 10).floor().isEven) ? 1 : -1), 0), child: child),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 4; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  margin: const EdgeInsets.symmetric(horizontal: Space.space2),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? c.text100 : Colors.transparent,
                    border: Border.all(color: _pinError != null ? c.danger : c.text200, width: 2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.space2),
        SizedBox(
          height: 22,
          child: _busy
              ? Text('Checking', style: ConsoleText.small.copyWith(color: c.text200))
              : _pinError != null
              ? Text(_pinError!, style: ConsoleText.small.copyWith(color: c.danger))
              : null,
        ),
        const SizedBox(height: Space.space3),
        FocusTraversalGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final row in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
              ])
                Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) key(d, onTap: () => _digit(d), focusNode: d == '1' ? _firstKey : null)]),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  key('Back to profiles', icon: LucideIcons.arrowLeft, onTap: _leavePin),
                  key('0', onTap: () => _digit('0')),
                  key('Delete', icon: LucideIcons.delete, onTap: _erase),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One Home user: a round avatar and their name.
class ProfileTile extends StatelessWidget {
  const ProfileTile({super.key, required this.user, required this.onTap, this.current = false, this.busy = false, this.autofocus = false, this.focusNode});
  final PlexHomeUser user;
  final FocusNode? focusNode;
  final VoidCallback onTap;
  final bool current;
  final bool busy;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Focusable(
      onTap: onTap,
      autofocus: autofocus,
      focusNode: focusNode,
      semanticLabel: '${user.name}${user.protected ? ', has a PIN' : ''}${current ? ', in use' : ''}',
      builder: (context, hover, focus) => SizedBox(
        width: 148,
        child: Column(
          children: [
            AnimatedScale(
              scale: focus || hover ? 1.08 : 1,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: focus ? c.primary : (current ? Colors.white.withValues(alpha: 0.5) : Colors.transparent), width: 3),
                  boxShadow: [if (focus) BoxShadow(color: c.primary.withValues(alpha: 0.45), blurRadius: 24)],
                ),
                child: Opacity(opacity: busy ? 0.5 : 1, child: ProfileAvatar(user: user, size: 112)),
              ),
            ),
            const SizedBox(height: Space.space3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (user.protected) ...[Icon(LucideIcons.lock, size: 14, color: c.text200), const SizedBox(width: Space.space1)],
                Flexible(
                  child: Text(
                    user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ConsoleText.titleSm.copyWith(color: focus || current ? c.text100 : c.text200),
                  ),
                ),
              ],
            ),
            if (current) Text('Watching now', style: ConsoleText.caption.copyWith(color: c.text300)),
          ],
        ),
      ),
    );
  }
}

/// A Home user's plex.tv picture in a circle, or their initials on a color of their own.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, this.user, this.thumb = '', this.name = '', required this.size});
  final PlexHomeUser? user;
  final String thumb;
  final String name;
  final double size;

  static const _palette = [Color(0xFF3D7BF7), Color(0xFFE5484D), Color(0xFF30A46C), Color(0xFFF5A524), Color(0xFF8E4EC6), Color(0xFF12A594)];

  @override
  Widget build(BuildContext context) {
    final who = user ?? PlexHomeUser(uuid: 'x', title: name, thumb: thumb);
    final color = _palette[who.name.codeUnits.fold<int>(0, (a, b) => a + b) % _palette.length];
    final initials = Center(
      child: Text(who.initials, style: ConsoleText.display.copyWith(fontSize: size * 0.38, color: Colors.white, fontWeight: FontWeight.w700)),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      clipBehavior: Clip.antiAlias,
      child: who.thumb.isEmpty
          ? initials
          : ArtImage(who.thumb, fit: BoxFit.cover, width: size, height: size, decodeWidth: (size * 2).round(), errorBuilder: (_, _, _) => initials),
    );
  }
}
