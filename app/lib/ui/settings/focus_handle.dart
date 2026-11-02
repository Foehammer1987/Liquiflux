import 'package:flutter/widgets.dart';

/// Moves focus onto a control that keeps its focus node to itself (a ConsoleButton, say).
/// Wrap it with [wrap] and call [focus]: the first focusable control inside takes focus
/// once the frame is built. Used on a TV, where a control that disappears or greys out
/// would otherwise leave the remote with nothing focused.
class FocusHandle {
  final _node = FocusNode(canRequestFocus: false, skipTraversal: true, debugLabel: 'FocusHandle');
  bool _gone = false;

  Widget wrap(Widget child) => Focus(focusNode: _node, child: child);

  void focus() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_gone) return;
    for (final n in _node.descendants) {
      if (n.canRequestFocus && !n.skipTraversal && n.context != null) {
        n.requestFocus();
        return;
      }
    }
  });

  void dispose() {
    _gone = true;
    _node.dispose();
  }
}
