import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'art_image.dart';
import 'draw_probe.dart';
import 'theme.dart';
import 'tokens.dart';

/// Frosted-glass surface settings. With [glass] off, surfaces fall back to flat Console panels.
@immutable
class ConsoleEffects extends ThemeExtension<ConsoleEffects> {
  const ConsoleEffects({
    required this.glass,
    required this.panelFill,
    required this.panelBorder,
    required this.panelHighlight,
    required this.chromeFill,
    required this.controlFill,
    required this.controlBorder,
    required this.shadow,
    required this.glowA,
    required this.glowB,
    required this.backdropTint,
    this.blur = 28,
  });

  final bool glass;

  /// Panel fill over the blurred backdrop.
  final Color panelFill;
  final Color panelBorder;

  /// Lighter top edge that catches the "light".
  final Color panelHighlight;

  /// App bar and rail.
  final Color chromeFill;

  /// Secondary buttons, chips, the search box.
  final Color controlFill;
  final Color controlBorder;
  final Color shadow;

  /// Ambient colour washes behind everything.
  final Color glowA;
  final Color glowB;

  /// Laid over title art so text stays readable.
  final Color backdropTint;
  final double blur;

  static ConsoleEffects darkFor(ConsoleColors c, {bool glass = true}) => ConsoleEffects(
    glass: glass,
    panelFill: glass ? const Color(0xFF1B1C20).withValues(alpha: 0.58) : c.surface100,
    panelBorder: glass ? Colors.white.withValues(alpha: 0.09) : c.border200,
    panelHighlight: glass ? Colors.white.withValues(alpha: 0.14) : c.border200,
    chromeFill: glass ? const Color(0xFF141518).withValues(alpha: 0.62) : c.surface200,
    controlFill: glass ? Colors.white.withValues(alpha: 0.07) : c.surface200,
    controlBorder: glass ? Colors.white.withValues(alpha: 0.12) : c.border200,
    shadow: Colors.black.withValues(alpha: glass ? 0.45 : 0),
    glowA: const Color(0xFF006FFF).withValues(alpha: 0.20),
    glowB: const Color(0xFF7A3FD1).withValues(alpha: 0.12),
    backdropTint: const Color(0xFF0C0C0C).withValues(alpha: 0.62),
  );

  static ConsoleEffects lightFor(ConsoleColors c, {bool glass = true}) => ConsoleEffects(
    glass: glass,
    panelFill: glass ? Colors.white.withValues(alpha: 0.62) : c.surface100,
    panelBorder: glass ? Colors.white.withValues(alpha: 0.75) : c.border200,
    panelHighlight: glass ? Colors.white : c.border200,
    chromeFill: glass ? Colors.white.withValues(alpha: 0.6) : c.surface200,
    controlFill: glass ? Colors.white.withValues(alpha: 0.55) : c.surface200,
    controlBorder: glass ? const Color(0xFF212327).withValues(alpha: 0.10) : c.border200,
    shadow: const Color(0xFF212327).withValues(alpha: glass ? 0.12 : 0),
    glowA: const Color(0xFF006FFF).withValues(alpha: 0.14),
    glowB: const Color(0xFF7A3FD1).withValues(alpha: 0.10),
    backdropTint: const Color(0xFFF4F5F6).withValues(alpha: 0.7),
  );

  @override
  ConsoleEffects copyWith({bool? glass}) => ConsoleEffects(
    glass: glass ?? this.glass,
    panelFill: panelFill,
    panelBorder: panelBorder,
    panelHighlight: panelHighlight,
    chromeFill: chromeFill,
    controlFill: controlFill,
    controlBorder: controlBorder,
    shadow: shadow,
    glowA: glowA,
    glowB: glowB,
    backdropTint: backdropTint,
    blur: blur,
  );

  @override
  ConsoleEffects lerp(ConsoleEffects? o, double t) {
    if (o == null) return this;
    return ConsoleEffects(
      glass: t < 0.5 ? glass : o.glass,
      panelFill: Color.lerp(panelFill, o.panelFill, t)!,
      panelBorder: Color.lerp(panelBorder, o.panelBorder, t)!,
      panelHighlight: Color.lerp(panelHighlight, o.panelHighlight, t)!,
      chromeFill: Color.lerp(chromeFill, o.chromeFill, t)!,
      controlFill: Color.lerp(controlFill, o.controlFill, t)!,
      controlBorder: Color.lerp(controlBorder, o.controlBorder, t)!,
      shadow: Color.lerp(shadow, o.shadow, t)!,
      glowA: Color.lerp(glowA, o.glowA, t)!,
      glowB: Color.lerp(glowB, o.glowB, t)!,
      backdropTint: Color.lerp(backdropTint, o.backdropTint, t)!,
      blur: blur + (o.blur - blur) * t,
    );
  }
}

extension ConsoleEffectsContext on BuildContext {
  ConsoleEffects get fx => Theme.of(this).extension<ConsoleEffects>() ?? ConsoleEffects.darkFor(ConsoleColors.dark);
}

/// A floating frosted panel: blurs what's behind it, soft shadow, hairline with a lit top edge.
class GlassSurface extends StatelessWidget {
  const GlassSurface({super.key, required this.child, this.radius = Radii.radiusLg, this.padding = EdgeInsets.zero, this.fill, this.elevation = 1});
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final Color? fill;

  /// 0 = no shadow, 1 = panel, 2 = popover.
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    final r = BorderRadius.circular(radius);
    final body = DecoratedBox(
      decoration: BoxDecoration(
        color: fill ?? fx.panelFill,
        borderRadius: r,
        border: Border.all(color: fx.panelBorder),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: fx.glass
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    fx.panelHighlight.withValues(alpha: fx.panelHighlight.a * 0.3),
                    fx.panelHighlight.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.4],
                )
              : null,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
    if (!fx.glass) return body;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: elevation <= 0 ? null : [BoxShadow(color: fx.shadow, blurRadius: 24 * elevation, offset: Offset(0, 8 * elevation), spreadRadius: -4)],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter.grouped(
          filter: ImageFilter.blur(sigmaX: fx.blur, sigmaY: fx.blur),
          child: body,
        ),
      ),
    );
  }
}

/// The window background: soft colour washes, or a title's art blurred and tinted.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key, this.imageUrl});
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fx = context.fx;
    final glows = Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: c.surface000),
        if (fx.glass) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(center: const Alignment(-0.9, -1.1), radius: 1.1, colors: [fx.glowA, fx.glowA.withValues(alpha: 0)]),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(center: const Alignment(1.1, 1.0), radius: 1.0, colors: [fx.glowB, fx.glowB.withValues(alpha: 0)]),
            ),
          ),
        ],
      ],
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        glows,
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          child: imageUrl == null ? const SizedBox.expand(key: ValueKey('none')) : _ArtWash(key: ValueKey(imageUrl), url: imageUrl!),
        ),
      ],
    );
  }
}

class _ArtWash extends StatelessWidget {
  const _ArtWash({super.key, required this.url});
  final String url;
  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    final base = context.c.surface000;
    // Blurred this much, a 480-wide copy looks the same as the full art and takes a tenth of the memory.
    final art = ArtImage(url, decodeWidth: 480, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox());
    return Stack(
      fit: StackFit.expand,
      children: [
        DrawProbe.noBlur ? art : ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48, tileMode: TileMode.clamp), child: art),
        ColoredBox(color: fx.backdropTint),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [base.withValues(alpha: 0), base.withValues(alpha: 0.85)], stops: const [0.35, 1]),
          ),
        ),
      ],
    );
  }
}

/// Lets a page put its art behind the whole window; the latest page to ask wins.
class BackdropController extends ChangeNotifier {
  final _stack = <(Object, String)>[];
  String? get url => _stack.isEmpty ? null : _stack.last.$2;

  void set(Object owner, String? url) {
    _stack.removeWhere((e) => e.$1 == owner);
    if (url != null) _stack.add((owner, url));
    notifyListeners();
  }

  void clear(Object owner) => set(owner, null);
}

class BackdropScope extends InheritedWidget {
  const BackdropScope({super.key, required this.controller, required super.child});
  final BackdropController controller;
  static BackdropController? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<BackdropScope>()?.controller;
  @override
  bool updateShouldNotify(BackdropScope old) => old.controller != controller;
}

/// [child] softly blurred when [on], with edges kept crisp (for hiding spoilers in a picture).
Widget blurred(bool on, Widget child) => on ? ClipRect(child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18, tileMode: TileMode.decal), child: child)) : child;
