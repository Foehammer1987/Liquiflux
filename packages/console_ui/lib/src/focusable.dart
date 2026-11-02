import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Hover, focus and activation for any tappable surface.
///
/// Activates on click, Enter, Space, and a TV remote's select button, so every control
/// works the same with a mouse, a keyboard or a D-pad.
class Focusable extends StatefulWidget {
  const Focusable({
    super.key,
    required this.builder,
    this.onTap,
    this.autofocus = false,
    this.focusNode,
    this.cursor = SystemMouseCursors.click,
    this.semanticLabel,
    this.onHighlight,
    this.reveal = true,
  });

  final Widget Function(BuildContext context, bool hovered, bool focused) builder;
  final VoidCallback? onTap;
  final bool autofocus;
  final FocusNode? focusNode;
  final MouseCursor cursor;
  final String? semanticLabel;

  /// Hovered or focused (true), or neither any more (false).
  final ValueChanged<bool>? onHighlight;

  /// Scrolls the control to the middle of the lists it's in when it gets focus. False leaves
  /// that to the page (Home's spotlight buttons scroll it back to the top instead).
  final bool reveal;

  @override
  State<Focusable> createState() => _FocusableState();
}

class _FocusableState extends State<Focusable> {
  bool _hover = false;
  bool _focus = false;

  static final _shortcuts = <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
    const SingleActivator(LogicalKeyboardKey.numpadEnter): const ActivateIntent(),
    const SingleActivator(LogicalKeyboardKey.space): const ActivateIntent(),
    const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
    const SingleActivator(LogicalKeyboardKey.gameButtonA): const ActivateIntent(),
  };

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: enabled,
        autofocus: widget.autofocus,
        focusNode: widget.focusNode,
        mouseCursor: enabled ? widget.cursor : SystemMouseCursors.basic,
        shortcuts: _shortcuts,
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap?.call())},
        onShowHoverHighlight: (v) {
          setState(() => _hover = v);
          widget.onHighlight?.call(_hover || _focus);
        },
        onShowFocusHighlight: (v) {
          setState(() => _focus = v);
          widget.onHighlight?.call(_hover || _focus);
          // Keep the focused card on screen while moving with arrows / a D-pad.
          if (v && widget.reveal) Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 150));
        },
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: widget.builder(context, _hover && enabled, _focus)),
      ),
    );
  }
}
