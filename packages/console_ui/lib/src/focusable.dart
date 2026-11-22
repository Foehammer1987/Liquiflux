import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
          if (v && widget.reveal) revealFocused(context);
        },
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: widget.builder(context, _hover && enabled, _focus)),
      ),
    );
  }
}

/// How the controls below scroll into view when they get focus: to the middle of their list
/// (the default, right for rows of posters), or, with [nearEdge], only once they come close to
/// the top or bottom of it, and then just far enough. A list of settings stays still under the
/// remote that way, instead of shifting on every press.
class FocusReveal extends InheritedWidget {
  const FocusReveal({super.key, this.nearEdge = true, this.margin = 96, required super.child});
  final bool nearEdge;

  /// How close to the list's top or bottom edge a focused control may sit.
  final double margin;

  static FocusReveal? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<FocusReveal>();

  @override
  bool updateShouldNotify(FocusReveal old) => old.nearEdge != nearEdge || old.margin != margin;
}

/// Scrolls the control at [context], which just got focus, into view the way the nearest
/// [FocusReveal] says (to the middle of its lists without one).
void revealFocused(BuildContext context) {
  const glide = Duration(milliseconds: 150);
  final how = FocusReveal.maybeOf(context);
  if (how == null || !how.nearEdge) {
    Scrollable.ensureVisible(context, alignment: 0.5, duration: glide);
    return;
  }
  final box = context.findRenderObject();
  final list = Scrollable.maybeOf(context);
  if (box == null || !box.attached || list == null) return;
  final view = RenderAbstractViewport.maybeOf(box);
  if (view == null) return;
  final at = list.position;
  // The scroll offsets that put the control's top, and its bottom, [margin] inside the list.
  final top = view.getOffsetToReveal(box, 0).offset - how.margin;
  final bottom = view.getOffsetToReveal(box, 1).offset + how.margin;
  final to = at.pixels > top ? top : (at.pixels < bottom ? bottom : null);
  if (to == null) return;
  final target = to.clamp(at.minScrollExtent, at.maxScrollExtent);
  if ((target - at.pixels).abs() > 0.5) at.animateTo(target, duration: glide, curve: Curves.easeOut);
}
