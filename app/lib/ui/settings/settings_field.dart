import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../platform.dart';

/// A labelled text field for Settings: a [ConsoleField] on a desktop, and on a TV one that
/// works with the remote.
///
/// On a TV the arrows move past the field like any other control, and focusing it doesn't
/// pop up the on-screen keyboard. Select opens the keyboard; its Done key submits
/// ([onSubmitted]) and its Next key moves on to the next control. Back, or an arrow off a
/// one-line field, stops editing and keeps what was typed.
class SettingsField extends StatefulWidget {
  const SettingsField({super.key, required this.label, required this.controller, this.help, this.hint, this.obscure = false, this.mono = false, this.lines = 1, this.onSubmitted, this.tv});
  final String label;
  final TextEditingController controller;
  final String? help;
  final String? hint;
  final bool obscure;
  final bool mono;

  /// More than 1 makes a multi-line box.
  final int lines;
  final ValueChanged<String>? onSubmitted;

  /// The TV behaviour; [isTv] when not given (tests set it).
  final bool? tv;

  @override
  State<SettingsField> createState() => _SettingsFieldState();
}

class _SettingsFieldState extends State<SettingsField> {
  final _node = FocusNode(debugLabel: 'SettingsField');
  bool _editing = false;

  bool get _tv => widget.tv ?? isTv;

  @override
  void initState() {
    super.initState();
    _node.addListener(_focusChanged);
  }

  @override
  void dispose() {
    _node
      ..removeListener(_focusChanged)
      ..dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (!_node.hasFocus && _editing) {
      setState(() => _editing = false);
    } else if (_node.hasFocus && !_editing && _tv) {
      final ctx = _node.context;
      if (ctx != null) revealFocused(ctx);
    }
  }

  void _edit() {
    setState(() => _editing = true);
    _node.requestFocus();
  }

  void _stop() {
    if (_editing) setState(() => _editing = false);
  }

  /// The keyboard's Done or Next key.
  void _submitted(String value) {
    _stop();
    final submit = widget.onSubmitted;
    if (submit != null) {
      submit(value);
    } else {
      _node.nextFocus();
    }
  }

  static final _select = {LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter, LogicalKeyboardKey.gameButtonA};
  static final _arrows = {
    LogicalKeyboardKey.arrowUp: TraversalDirection.up,
    LogicalKeyboardKey.arrowDown: TraversalDirection.down,
    LogicalKeyboardKey.arrowLeft: TraversalDirection.left,
    LogicalKeyboardKey.arrowRight: TraversalDirection.right,
  };

  /// Keys the remote sends while the field is focused but the keyboard isn't up (on a TV,
  /// keys typed on the on-screen keyboard never come through here).
  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final key = e.logicalKey;
    if (!_editing) {
      if (_select.contains(key)) {
        if (e is KeyDownEvent) _edit();
        return KeyEventResult.handled;
      }
      final dir = _arrows[key];
      if (dir == null) return KeyEventResult.ignored;
      // Through the shell's D-pad action, so Left from the edge opens the rail like anywhere else.
      Actions.maybeInvoke(context, DirectionalFocusIntent(dir, ignoreTextFields: false));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      _stop();
      return KeyEventResult.handled;
    }
    // Back closed the keyboard but the field is still being edited: Select brings it back.
    if (key == LogicalKeyboardKey.select) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      return KeyEventResult.handled;
    }
    final dir = _arrows[key];
    if (widget.lines == 1 && (dir == TraversalDirection.up || dir == TraversalDirection.down)) {
      _stop();
      _node.focusInDirection(dir!);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (!_tv) {
      return ConsoleField(
        label: widget.label,
        controller: widget.controller,
        help: widget.help,
        hint: widget.hint,
        obscure: widget.obscure,
        mono: widget.mono,
        lines: widget.lines,
        onSubmitted: widget.onSubmitted,
      );
    }
    final c = context.c;
    OutlineInputBorder b(Color col, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.radiusSm),
      borderSide: BorderSide(color: col, width: width),
    );
    final style = (widget.mono ? ConsoleText.data.copyWith(fontSize: 13) : ConsoleText.body).copyWith(color: c.text100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.label, style: ConsoleText.caption.copyWith(color: c.text200)),
        const SizedBox(height: Space.space1),
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _key,
          child: SizedBox(
            height: widget.lines > 1 ? null : Sizes.controlMd,
            child: TextField(
              controller: widget.controller,
              focusNode: _node,
              // Read-only until Select, so landing on the field doesn't open the keyboard.
              readOnly: !_editing,
              showCursor: _editing,
              maxLines: widget.lines,
              minLines: widget.lines,
              obscureText: widget.obscure,
              textInputAction: widget.lines > 1 ? TextInputAction.newline : (widget.onSubmitted != null ? TextInputAction.done : TextInputAction.next),
              // Done and Next are handled in _submitted, which also leaves editing.
              onEditingComplete: () {},
              onSubmitted: _submitted,
              onTap: _edit,
              style: style,
              cursorColor: c.primary,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: c.surface200,
                hintText: widget.hint,
                hintStyle: style.copyWith(color: c.text300),
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.space3, vertical: 6),
                border: b(c.border200),
                enabledBorder: b(c.border200),
                hoverColor: Colors.transparent,
                // Thicker than on a desktop so it reads from the sofa.
                focusedBorder: b(c.primary, 2),
              ),
            ),
          ),
        ),
        if (widget.help != null) ...[const SizedBox(height: Space.space1), Text(widget.help!, style: ConsoleText.caption.copyWith(color: c.text300))],
      ],
    );
  }
}
