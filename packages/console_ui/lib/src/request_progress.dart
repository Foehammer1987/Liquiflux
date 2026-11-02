import 'package:console_core/console_core.dart';
import 'package:flutter/material.dart';

import 'theme.dart';
import 'tokens.dart';
import 'widgets.dart';

/// Status badge, progress bar and "time left · finish time · size" line for a Seerr request.
class RequestProgress extends StatelessWidget {
  const RequestProgress({super.key, required this.state, this.compact = false});
  final RequestState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final pct = state.progress == null ? null : (state.progress! * 100).round();
    final showBar = state.progress != null && state.label != 'Available';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            ConsoleBadge(state.label, tone: state.tone),
            const Spacer(),
            if (showBar && pct != null && pct > 0)
              Text(
                '$pct%',
                style: ConsoleText.small.copyWith(color: c.chartDownload, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
          ],
        ),
        if (showBar) ...[
          const SizedBox(height: Space.space1),
          Semantics(
            label: '${state.label}${pct != null && pct > 0 ? ', $pct percent' : ''}',
            child: _Bar(progress: state.progress ?? 0, waiting: state.waiting),
          ),
        ],
        if (state.detail != null) ...[
          const SizedBox(height: Space.space1),
          Text(
            state.detail!,
            style: ConsoleText.caption.copyWith(color: c.text300),
            maxLines: compact ? 3 : 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _Bar extends StatefulWidget {
  const _Bar({required this.progress, required this.waiting});
  final double progress;
  final bool waiting;
  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Bar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.waiting && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!widget.waiting) {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.radiusFull),
      child: SizedBox(
        height: 4,
        child: LayoutBuilder(
          builder: (context, box) {
            if (widget.waiting) {
              if (reduceMotion) return ColoredBox(color: c.primary.withValues(alpha: 0.4));
              return ColoredBox(
                color: c.track,
                child: AnimatedBuilder(
                  animation: _sweep,
                  builder: (_, _) => Stack(
                    children: [
                      Positioned(
                        left: (box.maxWidth * 1.3) * _sweep.value - box.maxWidth * 0.3,
                        width: box.maxWidth * 0.3,
                        top: 0,
                        bottom: 0,
                        child: ColoredBox(color: c.primary),
                      ),
                    ],
                  ),
                ),
              );
            }
            return ColoredBox(
              color: c.track,
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOut,
                  width: box.maxWidth * widget.progress.clamp(0.01, 1.0),
                  decoration: BoxDecoration(color: c.chartDownload, borderRadius: BorderRadius.circular(Radii.radiusFull)),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
