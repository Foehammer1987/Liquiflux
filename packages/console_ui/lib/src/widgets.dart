import 'package:console_core/console_core.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'focusable.dart';
import 'glass.dart';
import 'theme.dart';
import 'tokens.dart';

const _fast = Duration(milliseconds: 150);

/// 2px primary ring, 2px offset — the Console focus style.
BoxDecoration focusRing(BuildContext context, double radius) => BoxDecoration(
  borderRadius: BorderRadius.circular(radius + 2),
  border: Border.all(color: context.c.primary, width: 2),
);

/// Draws the ring outside [child] without changing layout.
Widget withFocusRing(BuildContext context, {required bool focused, required double radius, required Widget child}) => Stack(
  clipBehavior: Clip.none,
  children: [
    child,
    if (focused)
      Positioned(
        left: -4,
        top: -4,
        right: -4,
        bottom: -4,
        child: IgnorePointer(child: DecoratedBox(decoration: focusRing(context, radius))),
      ),
  ],
);

enum LogoInk { white, navy, blue }

/// The brand mark. [ink] defaults to white on dark and navy on light.
class ConsoleLogo extends StatelessWidget {
  const ConsoleLogo({super.key, this.height = 24, this.ink});
  final double height;
  final LogoInk? ink;

  @override
  Widget build(BuildContext context) {
    final i = ink ?? (Theme.of(context).brightness == Brightness.dark ? LogoInk.white : LogoInk.navy);
    return Image.asset('assets/logos/mark-${i.name}.png', package: 'console_ui', height: height, filterQuality: FilterQuality.medium, semanticLabel: 'Console');
  }
}

enum ButtonKind { primary, secondary, tertiary, danger }

enum ButtonSize { sm, md, lg }

class ConsoleButton extends StatelessWidget {
  const ConsoleButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.kind = ButtonKind.secondary,
    this.size = ButtonSize.md,
    this.autofocus = false,
    this.expand = false,
    this.iconOnly = false,
  });
  final String label;

  /// Square button showing only [icon]; [label] becomes its tooltip.
  final bool iconOnly;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ButtonKind kind;
  final ButtonSize size;
  final bool autofocus;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final h = switch (size) {
      ButtonSize.sm => Sizes.controlSm,
      ButtonSize.md => Sizes.controlMd,
      ButtonSize.lg => Sizes.controlLg,
    };
    final padX = switch (size) {
      ButtonSize.sm => Space.space3,
      ButtonSize.md => Space.space4,
      ButtonSize.lg => Space.space6,
    };
    final disabled = onPressed == null;
    return Focusable(
      onTap: onPressed,
      autofocus: autofocus,
      semanticLabel: label,
      builder: (context, hover, focus) {
        Color bg, fg, border = Colors.transparent;
        switch (kind) {
          case ButtonKind.primary:
            bg = hover ? c.primaryFillHover : c.primaryFill;
            fg = c.onPrimary;
          case ButtonKind.secondary:
            final fx = context.fx;
            bg = fx.glass ? (hover ? fx.controlFill.withValues(alpha: fx.controlFill.a * 1.8) : fx.controlFill) : c.surface200;
            fg = c.text100;
            border = hover ? c.border300 : fx.controlBorder;
          case ButtonKind.tertiary:
            bg = hover ? c.surface200 : Colors.transparent;
            fg = c.link;
          case ButtonKind.danger:
            bg = c.dangerFill;
            fg = c.onPrimary;
        }
        if (disabled) {
          bg = c.surface200;
          fg = c.textDisabled;
          border = Colors.transparent;
        }
        final style = (kind == ButtonKind.tertiary ? ConsoleText.bodyStrong : ConsoleText.titleSm).copyWith(color: fg);
        if (iconOnly) {
          return Tooltip(
            message: label,
            child: withFocusRing(
              context,
              focused: focus,
              radius: Radii.radiusFull,
              child: AnimatedContainer(
                duration: _fast,
                width: h,
                height: h,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                  border: Border.all(color: border),
                ),
                child: Icon(icon, size: h * 0.45, color: fg),
              ),
            ),
          );
        }
        return withFocusRing(
          context,
          focused: focus,
          radius: Radii.radiusSm,
          child: AnimatedContainer(
            duration: _fast,
            curve: Curves.easeOut,
            height: h,
            padding: EdgeInsets.symmetric(horizontal: kind == ButtonKind.tertiary ? Space.space2 : padX),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(Radii.radiusSm),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: Space.space1)],
                Flexible(
                  child: Text(label, style: style, overflow: TextOverflow.ellipsis, maxLines: 1),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Text action in `link` blue ("See All", "Open in Plex").
class ConsoleLink extends StatelessWidget {
  const ConsoleLink({super.key, required this.label, this.onTap, this.trailingChevron = false, this.style});
  final String label;
  final VoidCallback? onTap;
  final bool trailingChevron;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Focusable(
    onTap: onTap,
    semanticLabel: label,
    builder: (context, hover, focus) => withFocusRing(
      context,
      focused: focus,
      radius: Radii.radiusSm,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: (style ?? ConsoleText.small).copyWith(color: context.c.link, decoration: hover ? TextDecoration.underline : null, decorationColor: context.c.link),
          ),
          if (trailingChevron) Icon(LucideIcons.chevronRight, size: 14, color: context.c.text300),
        ],
      ),
    ),
  );
}

/// Dashboard container. Flat: surface-100 drawn by a border-200 hairline. Glass: a floating frosted panel.
class ConsolePanel extends StatelessWidget {
  const ConsolePanel({super.key, this.title, this.meta, this.trailing, this.onSeeAll, required this.child, this.padding = const EdgeInsets.all(Space.space4)});
  final String? title;
  final Widget? meta;
  final Widget? trailing;
  final VoidCallback? onSeeAll;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GlassSurface(
      radius: context.fx.glass ? Radii.radiusLg : Radii.radiusMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.space4, Space.space4, Space.space4, 0),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                spacing: Space.space3,
                runSpacing: Space.space2,
                children: [
                  Text(title!, style: ConsoleText.titleSm.copyWith(color: c.text100)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ?meta,
                      if (meta != null && (trailing != null || onSeeAll != null)) const SizedBox(width: Space.space3),
                      ?trailing,
                      if (onSeeAll != null) ConsoleLink(label: 'See All', onTap: onSeeAll, trailingChevron: true),
                    ],
                  ),
                ],
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

Color toneText(BuildContext context, Tone t) => switch (t) {
  Tone.success => context.c.successText,
  Tone.warning => context.c.warningText,
  Tone.danger => context.c.dangerText,
  Tone.info => context.c.link,
  Tone.neutral => context.c.text200,
};

Color toneTint(BuildContext context, Tone t) => switch (t) {
  Tone.success => context.c.successTint,
  Tone.warning => context.c.warningTint,
  Tone.danger => context.c.dangerTint,
  Tone.info => context.c.primaryTint,
  Tone.neutral => context.c.surface300,
};

Color toneDot(BuildContext context, Tone t) => switch (t) {
  Tone.success => context.c.success,
  Tone.warning => context.c.warning,
  Tone.danger => context.c.danger,
  Tone.info => context.c.chartDownload,
  Tone.neutral => context.c.neutralDot,
};

class ConsoleBadge extends StatelessWidget {
  const ConsoleBadge(this.text, {super.key, this.tone = Tone.neutral});
  final String text;
  final Tone tone;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Space.space2, vertical: 2),
    decoration: BoxDecoration(color: toneTint(context, tone), borderRadius: BorderRadius.circular(Radii.radiusSm)),
    child: Text(
      text,
      style: ConsoleText.caption.copyWith(fontWeight: FontWeight.w500, color: toneText(context, tone)),
    ),
  );
}

/// 8px dot beside a word. The word is required: a dot never carries meaning alone.
class StatusDot extends StatelessWidget {
  const StatusDot(this.text, {super.key, this.tone = Tone.neutral, this.style});
  final String text;
  final Tone tone;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: toneDot(context, tone), shape: BoxShape.circle),
      ),
      const SizedBox(width: Space.space2),
      Flexible(
        child: Text(
          text,
          style: (style ?? ConsoleText.body).copyWith(color: context.c.text100),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

/// Pill segmented control (All / Download / Upload style).
class ConsoleSegmented<T> extends StatelessWidget {
  const ConsoleSegmented({super.key, required this.options, required this.value, required this.onChanged, this.autofocus = false});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// The chosen option takes focus when it first shows (a dialog's first control on a TV).
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Wrap(
      spacing: Space.space1,
      runSpacing: Space.space1,
      children: [
        for (final (v, label) in options)
          Focusable(
            onTap: () => onChanged(v),
            semanticLabel: label,
            autofocus: autofocus && v == value,
            builder: (context, hover, focus) {
              final on = v == value;
              return withFocusRing(
                context,
                focused: focus,
                radius: Radii.radiusFull,
                child: AnimatedContainer(
                  duration: _fast,
                  height: Sizes.controlSm,
                  padding: const EdgeInsets.symmetric(horizontal: Space.space3),
                  decoration: BoxDecoration(color: on ? c.primaryFill : Colors.transparent, borderRadius: BorderRadius.circular(Radii.radiusFull)),
                  child: Align(
                    widthFactor: 1,
                    child: Text(
                      label,
                      style: ConsoleText.small.copyWith(color: on ? c.onPrimary : (hover ? c.text100 : c.text200), fontWeight: on ? FontWeight.w600 : FontWeight.w400),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Labelled single-line field.
class ConsoleField extends StatelessWidget {
  const ConsoleField({
    super.key,
    required this.label,
    required this.controller,
    this.help,
    this.error,
    this.hint,
    this.obscure = false,
    this.mono = false,
    this.onSubmitted,
    this.autofocus = false,
    this.lines = 1,
  });
  final String label;
  final TextEditingController controller;

  /// More than 1 makes a multi-line box.
  final int lines;
  final String? help;
  final String? error;
  final String? hint;
  final bool obscure;
  final bool mono;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    OutlineInputBorder b(Color col) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.radiusSm),
      borderSide: BorderSide(color: col),
    );
    final style = (mono ? ConsoleText.data.copyWith(fontSize: 13) : ConsoleText.body).copyWith(color: c.text100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: ConsoleText.caption.copyWith(color: c.text200)),
        const SizedBox(height: Space.space1),
        SizedBox(
          height: lines > 1 ? null : Sizes.controlMd,
          child: TextField(
            controller: controller,
            maxLines: lines,
            minLines: lines,
            obscureText: obscure,
            autofocus: autofocus,
            onSubmitted: onSubmitted,
            style: style,
            cursorColor: c.primary,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: c.surface200,
              hintText: hint,
              hintStyle: style.copyWith(color: c.text300),
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.space3, vertical: 6),
              border: b(c.border200),
              enabledBorder: b(error != null ? c.danger : c.border200),
              hoverColor: Colors.transparent,
              focusedBorder: b(c.primary),
            ),
          ),
        ),
        if (error != null || help != null) ...[const SizedBox(height: Space.space1), Text(error ?? help!, style: ConsoleText.caption.copyWith(color: error != null ? c.dangerText : c.text300))],
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.body, this.action});
  final String title;
  final String? body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.space6),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: ConsoleText.bodyStrong.copyWith(color: context.c.text100),
          textAlign: TextAlign.center,
        ),
        if (body != null) ...[
          const SizedBox(height: Space.space1),
          Text(
            body!,
            style: ConsoleText.caption.copyWith(color: context.c.text300),
            textAlign: TextAlign.center,
          ),
        ],
        if (action != null) ...[const SizedBox(height: Space.space3), action!],
      ],
    ),
  );
}

class ErrorNote extends StatelessWidget {
  const ErrorNote(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Space.space3, vertical: Space.space2),
    decoration: BoxDecoration(color: context.c.dangerTint, borderRadius: BorderRadius.circular(Radii.radiusSm)),
    child: Row(
      children: [
        Expanded(
          child: Text(redactSecrets(message), style: ConsoleText.body.copyWith(color: context.c.dangerText)),
        ),
        if (onRetry != null) ConsoleButton(label: 'Retry', size: ButtonSize.sm, kind: ButtonKind.tertiary, onPressed: onRetry),
      ],
    ),
  );
}

class LoadingNote extends StatelessWidget {
  const LoadingNote({super.key, this.label = 'Loading'});
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.space4),
    child: Text('$label…', style: ConsoleText.caption.copyWith(color: context.c.text300)),
  );
}

/// Label-left / value-right row of the info column.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key});
  final String label;
  final Widget value;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(label, style: ConsoleText.body.copyWith(color: context.c.text100)),
      ),
      DefaultTextStyle.merge(
        style: ConsoleText.body.copyWith(color: context.c.text200),
        child: value,
      ),
    ],
  );
}

/// On/off pill. [color] tints the track when on (defaults to primary).
class ConsoleSwitch extends StatelessWidget {
  const ConsoleSwitch({super.key, required this.value, required this.onChanged, this.color, this.semanticLabel});
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final on = color ?? c.primaryFill;
    return Focusable(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      semanticLabel: semanticLabel,
      builder: (context, hover, focus) => withFocusRing(
        context,
        focused: focus,
        radius: Radii.radiusFull,
        child: AnimatedContainer(
          duration: _fast,
          width: 36,
          height: 20,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: value ? on : (hover ? c.border300 : c.track), borderRadius: BorderRadius.circular(Radii.radiusFull)),
          child: AnimatedAlign(
            duration: _fast,
            curve: Curves.easeOutCubic,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 3, offset: const Offset(0, 1))],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact select: shows the current choice and opens a menu of [options].
class ConsoleDropdown<T> extends StatelessWidget {
  const ConsoleDropdown({super.key, required this.options, required this.value, required this.onChanged, this.width = 220});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final double width;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset(0, box.size.height + 4), ancestor: overlay);
    final c = context.c;
    final picked = await showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, overlay.size.width - at.dx - box.size.width, 0),
      constraints: BoxConstraints(minWidth: box.size.width, maxWidth: box.size.width, maxHeight: 360),
      color: c.surface100,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.radiusMd),
        side: BorderSide(color: c.border200),
      ),
      items: [
        for (final (v, label) in options)
          PopupMenuItem<T>(
            value: v,
            height: 32,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: ConsoleText.body.copyWith(color: v == value ? c.text100 : c.text200, fontWeight: v == value ? FontWeight.w600 : FontWeight.w400),
                  ),
                ),
                if (v == value) Icon(LucideIcons.check, size: 14, color: c.primary),
              ],
            ),
          ),
      ],
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final label = options.where((o) => o.$1 == value).map((o) => o.$2).firstOrNull ?? '';
    return Builder(
      builder: (context) => Focusable(
        onTap: () => _open(context),
        semanticLabel: label,
        builder: (context, hover, focus) => withFocusRing(
          context,
          focused: focus,
          radius: Radii.radiusMd,
          child: AnimatedContainer(
            duration: _fast,
            width: width,
            height: Sizes.controlMd,
            padding: const EdgeInsets.symmetric(horizontal: Space.space3),
            decoration: BoxDecoration(
              color: c.surface050.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(Radii.radiusMd),
              border: Border.all(color: hover ? c.border300 : c.border200),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ConsoleText.body.copyWith(color: c.text100),
                  ),
                ),
                Icon(LucideIcons.chevronDown, size: 14, color: c.text200),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
