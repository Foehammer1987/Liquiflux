import 'dart:ui' show ImageFilter;

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import 'player_session.dart';

/// Shown before a title you stopped part-way through starts: carry on from where you were,
/// or start again. The title's own artwork sits softened behind, in its colours.
class ResumePrompt extends StatefulWidget {
  const ResumePrompt({super.key, required this.session, required this.at, required this.tint, required this.accent, required this.onBack});
  final PlayerSession session;
  final VoidCallback onBack;
  final Duration at;
  final Color tint;
  final Color accent;

  @override
  State<ResumePrompt> createState() => _ResumePromptState();
}

class _ResumePromptState extends State<ResumePrompt> {
  /// Around the two buttons. The player already holds the focus when the prompt appears, so
  /// the Resume button's autofocus did nothing: on a TV neither button was focused and Select
  /// did nothing until an arrow was pressed (seen on the Shield). Resume takes it here.
  final _buttons = FocusNode(debugLabel: 'resume buttons', canRequestFocus: false, skipTraversal: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final inside = FocusManager.instance.primaryFocus;
      if (inside != null && inside.ancestors.contains(_buttons)) return;
      _buttons.descendants.where((n) => n.canRequestFocus && !n.skipTraversal).firstOrNull?.requestFocus();
    });
  }

  @override
  void dispose() {
    _buttons.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final at = widget.at;
    final tint = widget.tint;
    final accent = widget.accent;
    final onBack = widget.onBack;
    final it = session.item;
    final plex = session.plex;
    final art = plex.imageUrl(it.art ?? it.thumb, width: 1280, height: 720);
    final total = it.duration != null && it.duration! > 0 ? Duration(milliseconds: it.duration!) : null;
    final progress = total == null ? null : (at.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final episode = it.type == 'episode';
    final left = total == null ? null : total - at;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (art != null)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24, tileMode: TileMode.decal),
            // Blurred this much, a 480-wide copy looks the same and takes a seventh of the memory.
            child: ArtImage(art, decodeWidth: 480, fit: BoxFit.cover, headers: plex.headersFor(art), gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox()),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.2),
              radius: 1.2,
              colors: [playerShade(tint, 0.55), playerShade(tint, 0.9)],
            ),
          ),
        ),
        Positioned(
          left: Space.space4,
          top: Space.space4,
          child: ConsoleButton(label: 'Back', icon: LucideIcons.arrowLeft, iconOnly: true, onPressed: onBack),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(Space.space5),
              child: GlassSurface(
                radius: Radii.radiusLg + 4,
                elevation: 2,
                fill: playerShade(tint, 0.62),
                padding: const EdgeInsets.all(Space.space6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PICK UP WHERE YOU LEFT OFF?', style: ConsoleText.caption.copyWith(color: accent, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
                    const SizedBox(height: Space.space2),
                    Text(
                      episode ? (it.grandparentTitle ?? it.title) : it.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ConsoleText.display.copyWith(fontSize: 26, height: 1.2, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    if (episode) ...[
                      const SizedBox(height: 2),
                      Text('${it.episodeCode} · ${it.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ConsoleText.body.copyWith(color: Colors.white.withValues(alpha: 0.8))),
                    ],
                    if (progress != null) ...[
                      const SizedBox(height: Space.space4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.radiusFull),
                        child: SizedBox(
                          height: 4,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ColoredBox(color: Colors.white.withValues(alpha: 0.18)),
                              FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: progress,
                                child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [tint, accent]))),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.space2),
                    Text(
                      [
                        'Stopped at ${clock(at)}',
                        if (left != null && left > Duration.zero) '${formatDuration(left.inMilliseconds)} left',
                      ].join('  ·  '),
                      style: ConsoleText.small.copyWith(color: Colors.white.withValues(alpha: 0.7)),
                    ),
                    const SizedBox(height: Space.space5),
                    Focus(
                      focusNode: _buttons,
                      child: Wrap(
                      spacing: Space.space3,
                      runSpacing: Space.space3,
                      children: [
                        ConsoleButton(
                          label: 'Resume from ${clock(at)}',
                          icon: LucideIcons.play,
                          kind: ButtonKind.primary,
                          size: ButtonSize.lg,
                          autofocus: true,
                          onPressed: () => session.chooseStart(resume: true),
                        ),
                        ConsoleButton(
                          label: 'Start from the Beginning',
                          icon: LucideIcons.rotateCcw,
                          size: ButtonSize.lg,
                          onPressed: () => session.chooseStart(resume: false),
                        ),
                      ],
                    ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
