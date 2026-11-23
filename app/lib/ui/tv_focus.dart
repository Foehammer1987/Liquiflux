import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// D-pad focus movement for the whole app.
///
/// Left and Right only move along the row the focused control is in: a control counts when it
/// overlaps that control's height. Flutter's policy, with nothing left in the row, falls back
/// to the nearest control anywhere in that direction, usually in another row, so Left at the
/// start of a Home row climbed to the row above (whose scrolled-away cards sit off the left
/// edge) instead of reaching the edge and opening the rail. Here the row's end is an edge: the
/// move fails, and the shell opens the rail on Left.
///
/// Up and Down go to the nearest line of controls above or below and never pass one over
/// ([verticalTarget]), and Up straight after a Down (or the other way round) goes back to the
/// control it came from. Flutter only does
/// that within one scrolling list, and every Home row is its own list, so Down then Up landed
/// on a different card than the one you left.
///
/// Never a stop, in any direction:
/// - a control nobody can see (faded out to nothing, offstage) or with no size (a collapsed
///   slider). A "Because You Watched" card's thumbs-up sat invisible in its corner, and Left
///   from the next card went there: the page jumped to centre it and nothing looked focused;
/// - a control inside another card (that thumbs-up again), unless you're already inside one.
///   From the card itself, Left or Right reaches a control inside it that lies that way, such
///   as an episode row's play thumbnail.
///
/// The control that gets focus glides to the middle of the screen ([glideTo]).
class TvTraversalPolicy extends ReadingOrderTraversalPolicy {
  TvTraversalPolicy({TraversalRequestFocusCallback? requestFocusCallback}) : super(requestFocusCallback: requestFocusCallback ?? glideTo);

  /// The last Up / Down move in each scope, so the opposite move can retrace it.
  final _trail = Expando<_Move>('tv focus trail');

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final scope = currentNode.nearestScope;
    final from = scope?.focusedChild;
    if (scope == null || from == null || from.context == null) return super.inDirection(currentNode, direction);
    // Flutter's own Up / Down trail isn't used here; keep it from steering a later move.
    invalidateScopeData(scope);
    final vertical = direction == TraversalDirection.up || direction == TraversalDirection.down;
    if (!vertical) {
      // A sideways move ends the trail.
      _trail[scope] = null;
      final next = sidewaysTarget(from, scope.traversalDescendants, direction);
      if (next == null) return false;
      requestFocusCallback(
        next,
        alignmentPolicy: direction == TraversalDirection.left ? ScrollPositionAlignmentPolicy.keepVisibleAtStart : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      return true;
    }
    final last = _trail[scope];
    final back = last != null && last.to == from && last.direction == _opposite(direction) && _fair(last.from) && last.from.nearestScope == scope ? last.from : null;
    // A run of Up / Down moves keeps the column it started in.
    final column = last != null && last.to == from ? last.column : null;
    final next = back ?? verticalTarget(from, scope.traversalDescendants, direction, column: column);
    if (next == null) return false;
    _trail[scope] = _Move(from, next, direction, column ?? from.rect.center.dx);
    requestFocusCallback(
      next,
      alignmentPolicy: direction == TraversalDirection.up ? ScrollPositionAlignmentPolicy.keepVisibleAtStart : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
    return true;
  }
}

/// Focuses [node] and glides it to the middle of its lists, the way [Focusable] scrolls a
/// control that gets focus. Flutter's own callback first jumped the list just far enough to
/// show the control, and the control then glided on to the middle: a snap, then a slide.
void glideTo(FocusNode node, {ScrollPositionAlignmentPolicy? alignmentPolicy, double? alignment, Duration? duration, Curve? curve}) {
  node.requestFocus();
  final ctx = node.context;
  if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 150));
}

class _Move {
  _Move(this.from, this.to, this.direction, this.column);

  /// The x the run of Up / Down moves this one belongs to started from.
  final double column;
  final FocusNode from;
  final FocusNode to;
  final TraversalDirection direction;
}

TraversalDirection _opposite(TraversalDirection d) => switch (d) {
  TraversalDirection.up => TraversalDirection.down,
  TraversalDirection.down => TraversalDirection.up,
  TraversalDirection.left => TraversalDirection.right,
  TraversalDirection.right => TraversalDirection.left,
};

/// The control Left or Right from [from] goes to among [nodes], or null at the end of its row.
FocusNode? sidewaysTarget(FocusNode from, Iterable<FocusNode> nodes, TraversalDirection direction) {
  assert(direction == TraversalDirection.left || direction == TraversalDirection.right);
  final r = from.rect;
  final left = direction == TraversalDirection.left;
  final candidates = [
    for (final s in _stops(from, r, nodes))
      if (_sideways(r, s.rect, left) || (s.node.ancestors.contains(from) && (left ? s.rect.center.dx < r.center.dx : s.rect.center.dx > r.center.dx))) s,
  ];
  if (candidates.isEmpty) return null;
  // Inside a scrolling row, a card further along that row beats anything else level with it.
  final row = Scrollable.maybeOf(from.context!, axis: Axis.horizontal);
  if (row != null) {
    final same = candidates.where((s) => Scrollable.maybeOf(s.node.context!, axis: Axis.horizontal) == row).toList();
    if (same.isNotEmpty) return _nearest(r.center, same).node;
  }
  return _nearest(r.center, candidates).node;
}

/// The control Up or Down from [from] goes to among [nodes], or null at the top or bottom.
///
/// Rows first: the move goes to the nearest line of controls above or below, whatever is on
/// it, and never passes one over. (It used to prefer a control straight above or below, however
/// far: Down from Settings' tabs, on the left, jumped six settings to the first one whose
/// control reached that far left, past the dropdowns and switches on the right.) Controls in
/// [from]'s own vertical list come before any outside it.
///
/// On that line it takes the control under [column] (the x a run of Up / Down moves started
/// from, when this move carries one on), then one overlapping [from]'s width, then the
/// nearest across. A short or offset line so doesn't drag the rest of the trip sideways.
FocusNode? verticalTarget(FocusNode from, Iterable<FocusNode> nodes, TraversalDirection direction, {double? column}) {
  assert(direction == TraversalDirection.up || direction == TraversalDirection.down);
  final r = from.rect;
  final up = direction == TraversalDirection.up;
  var eligible = [
    for (final s in _stops(from, r, nodes))
      if (up ? s.rect.center.dy <= r.top : s.rect.center.dy >= r.bottom) s,
  ];
  if (eligible.isEmpty) return null;
  final list = Scrollable.maybeOf(from.context!, axis: Axis.vertical);
  if (list != null) {
    final same = eligible.where((s) => Scrollable.maybeOf(s.node.context!, axis: Axis.vertical) == list).toList();
    if (same.isNotEmpty) eligible = same;
  }
  // The nearest line: the control whose near edge is closest, and all that are level with it.
  double gap(_Stop s) => up ? r.top - s.rect.bottom : s.rect.top - r.bottom;
  final first = eligible.reduce((a, b) => gap(b) < gap(a) ? b : a);
  final line = [
    for (final s in eligible)
      if (_level(first.rect, s.rect)) s,
  ];
  final x = column ?? r.center.dx;
  if (column != null) {
    final under = line.where((s) => s.rect.left <= x && s.rect.right >= x).toList();
    if (under.isNotEmpty) return _nearest(Offset(x, r.center.dy), under).node;
  }
  final inBand = line.where((s) => s.rect.left < r.right && s.rect.right > r.left).toList();
  if (inBand.isNotEmpty) return _nearestVertically(r, inBand).node;
  // Nothing straight above or below on it: the one whose nearer side is closest across.
  _Stop? best;
  var bestX = double.infinity;
  for (final s in line) {
    final d = math.min((s.rect.left - x).abs(), (s.rect.right - x).abs());
    if (d < bestX) {
      best = s;
      bestX = d;
    }
  }
  return best?.node;
}

/// [a] and [b] are on one line: they share more than half of the shorter one's height (so one
/// lying wholly within the other's height counts).
bool _level(Rect a, Rect b) {
  if (identical(a, b)) return true;
  final shared = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  return shared > math.min(a.height, b.height) / 2;
}

/// A control that may take focus, with where it is on screen (worked out once per move:
/// [FocusNode.rect] walks the whole render tree each time it's asked).
typedef _Stop = ({FocusNode node, Rect rect});

/// The controls among [nodes] that may take focus from [from] (at [at]): shown, with a size,
/// and not tucked inside another card unless [from] is inside one too.
List<_Stop> _stops(FocusNode from, Rect at, Iterable<FocusNode> nodes) {
  // A nested scope's own controls are listed too; the scope itself is no stop (and no card).
  final fair = <_Stop>[
    for (final n in nodes)
      if (n != from && n is! FocusScopeNode && _fair(n))
        if (_shownPart(n, n.rect, from) case final rect?) (node: n, rect: rect),
  ];
  if (fair.any((c) => _holds(c.rect, at))) return fair;
  bool tucked(_Stop s) => fair.any((c) => !identical(c, s) && _holds(c.rect, s.rect));
  return [
    for (final s in fair)
      if (!tucked(s) || s.node.ancestors.contains(from)) s,
  ];
}

/// Where [n] (at [rect]) can be seen, for a move from [from]: when it's in a scrolling list
/// [from] isn't in, only the part inside the list's window counts, and none at all when it's
/// scrolled out of it (a row built just past the bottom of a list, under the buttons below
/// it, isn't beside those buttons). Within its own list the whole of it counts, so a move
/// still reaches the next row along, which scrolls the list.
Rect? _shownPart(FocusNode n, Rect rect, FocusNode from) {
  final list = Scrollable.maybeOf(n.context!);
  if (list == null) return rect;
  final fromCtx = from.context;
  if (fromCtx != null && fromCtx.mounted) {
    for (ScrollableState? s = Scrollable.maybeOf(fromCtx); s != null; s = Scrollable.maybeOf(s.context)) {
      if (s == list) return rect;
    }
  }
  final box = list.context.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) return rect;
  // The same space as FocusNode.rect (through the TV canvas's scaling).
  final shown = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size).intersect(rect);
  return shown.width > 0 && shown.height > 0 ? shown : null;
}

/// [outer] holds all of [inner] and is bigger.
bool _holds(Rect outer, Rect inner) =>
    outer.left <= inner.left + 0.5 && outer.top <= inner.top + 0.5 && outer.right >= inner.right - 0.5 && outer.bottom >= inner.bottom - 0.5 && outer.width * outer.height > inner.width * inner.height + 1;

/// On screen in principle: mounted, with a size, and not faded out to nothing or offstage.
bool _fair(FocusNode n) {
  final ctx = n.context;
  if (ctx == null || !ctx.mounted) return false;
  final box = ctx.findRenderObject();
  if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return false;
  for (RenderObject? r = box; r != null; r = r.parent) {
    if (r is RenderOpacity && r.opacity == 0) return false;
    if (r is RenderAnimatedOpacity && r.opacity.value == 0) return false;
    if (r is RenderOffstage && r.offstage) return false;
  }
  return true;
}

bool _sideways(Rect from, Rect to, bool left) {
  if (left ? to.center.dx > from.left : to.center.dx < from.right) return false;
  return to.bottom > from.top && to.top < from.bottom;
}

_Stop _nearest(Offset c, List<_Stop> stops) {
  _Stop? best;
  var bestX = double.infinity, bestY = double.infinity;
  for (final s in stops) {
    final x = (s.rect.center.dx - c.dx).abs(), y = (s.rect.center.dy - c.dy).abs();
    if (x < bestX || (x == bestX && y < bestY)) {
      best = s;
      bestX = x;
      bestY = y;
    }
  }
  return best!;
}

/// The nearest of [stops] above or below [from]: the closest line of them, and on it the one
/// nearest across. When several on that line fit within [from]'s width (Play and More Info
/// above a wide Continue Watching card), the first of them.
_Stop _nearestVertically(Rect from, List<_Stop> stops) {
  final c = from.center;
  final dy = stops.map((s) => (s.rect.center.dy - c.dy).abs()).reduce(math.min);
  final line = [
    for (final s in stops)
      if ((s.rect.center.dy - c.dy).abs() <= dy + 4) s,
  ];
  final under = [
    for (final s in line)
      if (s.rect.left >= from.left - 0.5 && s.rect.right <= from.right + 0.5) s,
  ];
  if (under.length > 1) return under.reduce((a, b) => b.rect.left < a.rect.left ? b : a);
  return _nearest(c, line);
}

/// Keeps the D-pad inside a panel such as the sidebar: a move with nowhere to go inside it stays
/// put, rather than jumping to whatever lies that way on the page behind. [onEdge] gets the
/// direction of such a move, to send focus somewhere on purpose.
class FocusPanel extends StatelessWidget {
  const FocusPanel({super.key, required this.child, this.onEdge});
  final Widget child;
  final void Function(TraversalDirection direction)? onEdge;

  @override
  Widget build(BuildContext context) => FocusScope(
    // A panel's own scope stops at its edges (Flutter's default for a scope); the shell's
    // scope, which also holds the page, doesn't.
    child: Actions(actions: {DirectionalFocusIntent: _PanelAction(onEdge)}, child: child),
  );
}

class _PanelAction extends DirectionalFocusAction {
  _PanelAction(this.onEdge);
  final void Function(TraversalDirection direction)? onEdge;

  @override
  void invoke(DirectionalFocusIntent intent) {
    final node = FocusManager.instance.primaryFocus;
    if (node == null) return;
    if (intent.ignoreTextFields && node.context?.widget is EditableText) return;
    if (!node.focusInDirection(intent.direction)) onEdge?.call(intent.direction);
  }
}
