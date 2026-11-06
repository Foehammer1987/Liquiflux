import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/network_watch.dart';

/// Samsung's exit confirmation: Return on the app's home page asks before the app closes,
/// and only "Yes" closes it. "No", Return, or Exit's own handling close the popup. True for Yes.
Future<bool> confirmExit(BuildContext context) async {
  final yes = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder: (context) => const ExitPopup(),
  );
  return yes ?? false;
}

class ExitPopup extends StatelessWidget {
  const ExitPopup({super.key});

  @override
  Widget build(BuildContext context) => _Popup(
    icon: LucideIcons.logOut,
    title: 'Exit $appName?',
    body: null,
    actions: [
      // No is focused first, so a second press of OK doesn't close the app by surprise.
      ConsoleButton(label: 'No', autofocus: true, kind: ButtonKind.secondary, onPressed: () => Navigator.pop(context, false)),
      ConsoleButton(label: 'Yes', kind: ButtonKind.primary, onPressed: () => Navigator.pop(context, true)),
    ],
  );
}

/// The network-lost message (Samsung CO-CN-02). It closes itself once the TV is back on
/// the network; Return closes it sooner, and the app keeps watching either way.
Future<void> showNetworkLost(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: 0.7),
  builder: (context) => const NetworkLostPopup(),
);

class NetworkLostPopup extends StatefulWidget {
  const NetworkLostPopup({super.key});

  @override
  State<NetworkLostPopup> createState() => _NetworkLostPopupState();
}

class _NetworkLostPopupState extends State<NetworkLostPopup> {
  final _online = NetworkWatch.instance.online;

  @override
  void initState() {
    super.initState();
    _online.addListener(_changed);
  }

  void _changed() {
    if (_online.value && mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _online.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Popup(
    icon: LucideIcons.wifiOff,
    title: 'No network connection',
    body: 'Your TV is not connected to the network, so $appName can’t reach your server. Check the network in your TV’s settings. '
        'This message closes by itself when the connection is back.',
    actions: [ConsoleButton(label: 'OK', autofocus: true, kind: ButtonKind.primary, onPressed: () => Navigator.pop(context))],
  );
}

class _Popup extends StatelessWidget {
  const _Popup({required this.icon, required this.title, required this.body, required this.actions});
  final IconData icon;
  final String title;
  final String? body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          color: c.surface100,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(Space.space6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 22, color: c.text100),
                    const SizedBox(width: Space.space3),
                    Expanded(child: Text(title, style: ConsoleText.titleLg.copyWith(color: c.text100))),
                  ],
                ),
                if (body != null) ...[
                  const SizedBox(height: Space.space3),
                  Text(body!, style: ConsoleText.body.copyWith(color: c.text200)),
                ],
                const SizedBox(height: Space.space5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (final (i, a) in actions.indexed) ...[if (i > 0) const SizedBox(width: Space.space2), a],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
