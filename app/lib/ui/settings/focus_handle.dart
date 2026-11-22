import 'package:flutter/widgets.dart';

/// Moves focus onto a control that keeps its focus node to itself (a ConsoleButton, say).
/// Wrap it with [wrap] and call [focus]: the first focusable control inside takes focus
/// once the frame is built. Used on a TV, where a control that disappears or greys out
/// would otherwise leave the remote with nothing focused.
class FocusHandle {
  final _node = FocusNode(canRequestFocus: false, skipTraversal: true, debugLabel: 'FocusHandle');
  bool _gone = false;

  Widget wrap(Widget child) => Focus(focusNode: _node, child: child);

  void focus() => WidgetsBinding.instance.addPostFrameCallback((_) => focusNow());

  /// As [focus], but at once: for controls that are already on screen. ([focus] waits for the
  /// next frame, and when nothing on screen is changing there may not be one until the next
  /// key press.)
  void focusNow() {
    if (_gone) return;
    // The one highest up (then furthest left): the nodes come in the order they were made,
    // which isn't the order on screen once a list has changed its rows.
    FocusNode? first;
    for (final n in _node.descendants) {
      if (!n.canRequestFocus || n.skipTraversal || n.context == null || n is FocusScopeNode) continue;
      final a = n.rect, b = first?.rect;
      if (b == null || a.top < b.top - 1 || ((a.top - b.top).abs() <= 1 && a.left < b.left)) first = n;
    }
    first?.requestFocus();
  }

  /// Whether [node] is one of the controls inside.
  bool holds(FocusNode node) => node.context != null && node.ancestors.contains(_node);

  void dispose() {
    _gone = true;
    _node.dispose();
  }
}
