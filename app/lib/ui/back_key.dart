import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// One press of a TV remote's Back button does one thing.
///
/// Android tracks every Back press and, when Flutter leaves the key-up unhandled, also turns
/// it into a system Back (a route pop). Widgets that act on the key-down (the shell's Back
/// shortcut, a text field that stops editing, a player panel) therefore got the press twice:
/// Back on a title page went to Home and then straight out of the app.
///
/// Sitting above every page, this sees a Back key-down only when nothing below handled it.
/// If the key-down was handled, the matching key-up is swallowed so no system Back follows;
/// if it wasn't, the key-up goes on to Android and the system Back does the job once.
class BackKeyGuard extends StatefulWidget {
  const BackKeyGuard({super.key, required this.child});
  final Widget child;

  @override
  State<BackKeyGuard> createState() => _BackKeyGuardState();
}

class _BackKeyGuardState extends State<BackKeyGuard> {
  /// The last Back key-down reached here unhandled.
  bool _downUnhandled = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e.logicalKey != LogicalKeyboardKey.goBack) return KeyEventResult.ignored;
    if (e is KeyDownEvent) {
      _downUnhandled = true;
      return KeyEventResult.ignored;
    }
    if (e is KeyUpEvent) {
      final pass = _downUnhandled;
      _downUnhandled = false;
      return pass ? KeyEventResult.ignored : KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: _onKey, child: widget.child);
}
