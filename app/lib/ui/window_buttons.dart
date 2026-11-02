import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Minimise, maximise and close for the frameless Windows window.
class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key, this.height = 44});
  final double height;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget btn(IconData icon, String label, VoidCallback onTap, {bool close = false}) => Focusable(
      onTap: onTap,
      semanticLabel: label,
      builder: (context, hover, _) => Container(
        width: 46,
        height: height,
        color: hover ? (close ? c.dangerFill : Colors.white.withValues(alpha: 0.12)) : Colors.transparent,
        child: Icon(icon, size: 16, color: Colors.white.withValues(alpha: hover ? 1 : 0.8)),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(LucideIcons.minus, 'Minimize', () => windowManager.minimize()),
        btn(LucideIcons.square, 'Maximize', () async => await windowManager.isMaximized() ? windowManager.unmaximize() : windowManager.maximize()),
        btn(LucideIcons.x, 'Close', () => windowManager.close(), close: true),
      ],
    );
  }
}
