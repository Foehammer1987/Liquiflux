import 'dart:async';

import 'package:console_core/console_core.dart' show Tone;
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../app_info.dart';
import '../../platform.dart';
import '../../services/links.dart';
import '../../services/live_players.dart';
import '../../services/updater.dart';

/// Settings > Advanced > Updates: this version, a check against GitHub's releases, and the
/// update itself when there is one.
class UpdatesPanel extends StatefulWidget {
  const UpdatesPanel({super.key, required this.updater, this.start = false});
  final Updater updater;

  /// Opened from the update card's Update: install right away.
  final bool start;

  @override
  State<UpdatesPanel> createState() => _UpdatesPanelState();
}

class _UpdatesPanelState extends State<UpdatesPanel> {
  Updater get _u => widget.updater;

  @override
  void initState() {
    super.initState();
    unawaited(_u.load().then((_) {
      if (!mounted) return;
      if (widget.start && _u.canInstall) {
        unawaited(_install());
      } else if (_u.stage == UpdateStage.idle) {
        unawaited(_u.check());
      }
    }));
  }

  Future<void> _install() => _u.install(beforeExit: LivePlayers.releaseAll);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: _u,
      builder: (context, _) {
        final info = _u.available;
        final busy = _u.stage == UpdateStage.checking || _u.stage == UpdateStage.downloading || _u.stage == UpdateStage.installing;
        final (String status, Tone tone) = switch (_u.stage) {
          UpdateStage.idle => ('', Tone.neutral),
          UpdateStage.checking => ('Checking…', Tone.neutral),
          UpdateStage.upToDate => ('Up to date', Tone.success),
          UpdateStage.available => ('$appName ${info?.version} is available', Tone.info),
          UpdateStage.downloading => ('Downloading ${(_u.progress * 100).round()}%', Tone.info),
          UpdateStage.installing => (isTv ? 'Opening Android’s installer…' : 'Installing, Liquiflux will restart…', Tone.info),
          UpdateStage.failed => (_u.error ?? 'Something went wrong.', Tone.danger),
        };
        return ConsolePanel(
          title: 'Updates',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$appName $currentVersion', style: ConsoleText.bodyStrong.copyWith(color: c.text100)),
              if (status.isNotEmpty) ...[const SizedBox(height: Space.space2), StatusDot(status, tone: tone)],
              if (_u.stage == UpdateStage.downloading) ...[
                const SizedBox(height: Space.space2),
                LinearProgressIndicator(value: _u.progress, minHeight: 4, color: c.primary, backgroundColor: c.border100),
              ],
              const SizedBox(height: Space.space3),
              Wrap(
                spacing: Space.space3,
                runSpacing: Space.space2,
                children: [
                  if (info != null && _u.canInstall)
                    ConsoleButton(label: 'Update to ${info.version}', icon: LucideIcons.download, kind: ButtonKind.primary, onPressed: busy ? null : () => unawaited(_install())),
                  if (info != null)
                    ConsoleButton(label: _u.canInstall ? 'What’s New' : 'Get It on GitHub', icon: LucideIcons.externalLink, onPressed: () => unawaited(openExternal(info.pageUrl))),
                  ConsoleButton(label: 'Check Now', onPressed: busy ? null : () => unawaited(_u.check())),
                ],
              ),
              const SizedBox(height: Space.space4),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Check at Launch', style: ConsoleText.bodyStrong.copyWith(color: c.text100)),
                        Text(_help, style: ConsoleText.caption.copyWith(color: c.text300)),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.space4),
                  ConsoleSwitch(value: _u.auto, onChanged: (v) => unawaited(_u.setAuto(v))),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String get _help {
    if (!_u.selfUpdate) return 'Asks GitHub about new releases, at most twice a day. The app store this copy came from installs them.';
    if (isTv) return 'Asks GitHub about new releases, at most twice a day. Updates are checked, then Android asks you to confirm.';
    if (!Updater.installedWithSetup) return 'Asks GitHub about new releases, at most twice a day. This is the portable copy, so download new ones from GitHub.';
    return 'Asks GitHub about new releases, at most twice a day. Updates are checked before they install, and Liquiflux restarts.';
  }
}
