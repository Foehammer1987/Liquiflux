import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import 'plex_link_qr.dart';

/// Signing in to Plex on a TV, which may have no browser: a big code to type at
/// plex.tv/link on a phone or computer, a QR code that opens that page, how long the code
/// has left, and buttons for a new code or to give up.
class PlexLinkCode extends StatelessWidget {
  const PlexLinkCode({super.key, required this.code, required this.left, required this.expired, required this.onNewCode, required this.onCancel});

  /// Null while a code is being fetched.
  final String? code;

  /// Time until the code stops working, when plex.tv said.
  final Duration? left;
  final bool expired;
  final VoidCallback onNewCode;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final shown = code ?? '····';
    final status = switch ((code, expired, left)) {
      (null, _, _) => 'Getting a code',
      (_, true, _) => 'This code has expired. Get a new one to try again.',
      (_, _, final Duration l) => 'Waiting for you to enter it. The code expires in ${_clock(l)}.',
      _ => 'Waiting for you to enter it.',
    };
    return Wrap(
      spacing: Space.space6,
      runSpacing: Space.space4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(Radii.radiusSm), child: const PlexLinkQr()),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Go to plex.tv/link on your phone or computer and enter this code', style: ConsoleText.titleLg.copyWith(color: c.text100)),
              const SizedBox(height: Space.space1),
              Text('Or scan the QR code with your phone to open the page.', style: ConsoleText.caption.copyWith(color: c.text300)),
              const SizedBox(height: Space.space3),
              Semantics(
                label: code == null ? 'Getting a code' : 'Code ${shown.split('').join(' ')}',
                excludeSemantics: true,
                child: Text(
                  shown,
                  style: ConsoleText.data.copyWith(
                    fontSize: 72,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 12,
                    color: expired ? c.text300 : c.text100,
                    decoration: expired ? TextDecoration.lineThrough : null,
                    decorationColor: c.text300,
                  ),
                ),
              ),
              const SizedBox(height: Space.space2),
              Text(status, style: ConsoleText.body.copyWith(color: expired ? c.warningText : c.text200)),
              const SizedBox(height: Space.space4),
              Wrap(
                spacing: Space.space2,
                runSpacing: Space.space2,
                children: [
                  ConsoleButton(label: 'Get a New Code', icon: LucideIcons.refreshCw, kind: expired ? ButtonKind.primary : ButtonKind.secondary, onPressed: onNewCode),
                  ConsoleButton(label: 'Cancel', onPressed: onCancel),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 14:05, or 0:09.
  static String _clock(Duration d) {
    final s = d.isNegative ? 0 : d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}
