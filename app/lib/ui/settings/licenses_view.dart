import 'dart:async';

import 'package:console_ui/console_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Settings > Advanced > Open-Source Licenses: every package Liquiflux is built from (the
/// Dart packages and Flutter's engine, which Flutter registers, and the player's native
/// libraries from services/native_licenses.dart), then one package's license text.
Future<void> showLicenses(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: 0.7),
  builder: (context) => const LicensesView(),
);

/// A package and its license texts, as LicenseRegistry hands them out.
typedef LicensedPackage = ({String name, List<String> texts});

/// The registry's entries by package, sorted by name (a package can have several).
Future<List<LicensedPackage>> loadLicenses() async {
  final byName = <String, List<String>>{};
  await for (final entry in LicenseRegistry.licenses) {
    final text = entry.paragraphs.map((p) => '${'    ' * p.indent.clamp(0, 8)}${p.text}').join('\n\n');
    for (final name in entry.packages) {
      byName.putIfAbsent(name, () => []).add(text);
    }
  }
  final names = byName.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [for (final n in names) (name: n, texts: byName[n]!)];
}

class LicensesView extends StatefulWidget {
  const LicensesView({super.key});

  @override
  State<LicensesView> createState() => _LicensesViewState();
}

class _LicensesViewState extends State<LicensesView> {
  late final Future<List<LicensedPackage>> _packages = loadLicenses();

  /// The package being read; null for the list.
  LicensedPackage? _open;

  /// The list row to put focus back on when a package is closed.
  int _from = 0;

  void _close() {
    if (_open == null) return Navigator.pop(context);
    setState(() => _open = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final size = MediaQuery.sizeOf(context);
    final open = _open;
    return PopScope(
      // Back or Escape on a package goes back to the list first.
      canPop: open == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _open = null);
      },
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 860, maxHeight: size.height * 0.85),
          child: Material(
            color: c.surface100,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(Space.space6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.scrollText, size: 22, color: c.text100),
                      const SizedBox(width: Space.space3),
                      Expanded(
                        child: Text(open?.name ?? 'Open-Source Licenses', style: ConsoleText.titleLg.copyWith(color: c.text100), overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: Space.space3),
                      ConsoleButton(label: open == null ? 'Close' : 'Back', icon: open == null ? LucideIcons.x : LucideIcons.arrowLeft, kind: ButtonKind.secondary, onPressed: _close),
                    ],
                  ),
                  const SizedBox(height: Space.space4),
                  Flexible(
                    child: FutureBuilder<List<LicensedPackage>>(
                      future: _packages,
                      builder: (context, snap) {
                        final list = snap.data;
                        if (list == null) return const LoadingNote(label: 'Reading the licenses');
                        if (open != null) return _LicenseText(key: ValueKey(open.name), text: open.texts.join('\n\n${'─' * 24}\n\n'));
                        return _PackageList(
                          packages: list,
                          focusIndex: _from,
                          onOpen: (i) => setState(() {
                            _from = i;
                            _open = list[i];
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PackageList extends StatelessWidget {
  const _PackageList({required this.packages, required this.focusIndex, required this.onOpen});
  final List<LicensedPackage> packages;
  final int focusIndex;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${packages.length} packages. Choose one to read its license.', style: ConsoleText.caption.copyWith(color: c.text300)),
        const SizedBox(height: Space.space3),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: packages.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: Space.space1),
              child: ConsoleButton(
                label: packages[i].name,
                kind: ButtonKind.tertiary,
                expand: true,
                autofocus: i == focusIndex,
                onPressed: () => onOpen(i),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A license's text. It takes focus so a remote's Up and Down (and Page Up and Down) scroll
/// it; a mouse or a finger scrolls it as usual.
class _LicenseText extends StatefulWidget {
  const _LicenseText({super.key, required this.text});
  final String text;

  @override
  State<_LicenseText> createState() => _LicenseTextState();
}

class _LicenseTextState extends State<_LicenseText> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent || !_scroll.hasClients) return KeyEventResult.ignored;
    final page = _scroll.position.viewportDimension * 0.85;
    final by = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowDown => 80.0,
      LogicalKeyboardKey.arrowUp => -80.0,
      LogicalKeyboardKey.pageDown || LogicalKeyboardKey.space => page,
      LogicalKeyboardKey.pageUp => -page,
      _ => null,
    };
    if (by == null) return KeyEventResult.ignored;
    final p = _scroll.position;
    final to = (_scroll.offset + by).clamp(p.minScrollExtent, p.maxScrollExtent);
    // At the top, Up leaves for the Back button instead.
    if (by < 0 && _scroll.offset <= p.minScrollExtent) return KeyEventResult.ignored;
    unawaited(_scroll.animateTo(to, duration: const Duration(milliseconds: 120), curve: Curves.easeOut));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Focus(
      autofocus: true,
      onKeyEvent: _key,
      child: Builder(
        builder: (context) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.radiusMd),
            border: Border.all(color: Focus.of(context).hasFocus ? c.text300 : c.border100),
          ),
          child: Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.all(Space.space4),
              child: Text(widget.text, style: ConsoleText.data.copyWith(color: c.text200, height: 1.45)),
            ),
          ),
        ),
      ),
    );
  }
}
