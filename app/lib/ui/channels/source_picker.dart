import 'dart:ui' show ImageFilter;

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../settings/settings_field.dart';

/// Something in Plex a channel can draw from, as a line in a list.
typedef SourceChoice = ({ChannelSource source, String label});

/// The icon and name for a kind of source.
(IconData, String) sourceKind(String kind) => switch (kind) {
  'show' => (LucideIcons.tv, 'Show'),
  'collection' => (LucideIcons.layers, 'Collection'),
  'label' => (LucideIcons.tag, 'Label'),
  _ => (LucideIcons.library, 'Library'),
};

/// Lets you tick any number of shows, collections, labels and libraries ([single]: pick one,
/// which closes it). [kinds] are the tabs, in order. Null when cancelled.
Future<List<ChannelSource>?> showSourcePicker(
  BuildContext context, {
  required Map<String, List<SourceChoice>> choices,
  required List<ChannelSource> chosen,
  bool single = false,
  List<String> kinds = const ['show', 'collection', 'label', 'section'],
  String title = 'Choose What Plays',
}) => showGeneralDialog<List<ChannelSource>>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close',
  barrierColor: Colors.black.withValues(alpha: 0.5),
  transitionDuration: const Duration(milliseconds: 200),
  transitionBuilder: (context, a, _, child) => BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 8 * a.value, sigmaY: 8 * a.value),
    child: FadeTransition(opacity: a, child: child),
  ),
  pageBuilder: (_, _, _) => Center(
    child: SourcePicker(choices: choices, chosen: chosen, single: single, kinds: kinds, title: title),
  ),
);

class SourcePicker extends StatefulWidget {
  const SourcePicker({super.key, required this.choices, required this.chosen, this.single = false, this.kinds = const ['show', 'collection', 'label', 'section'], this.title = 'Choose What Plays'});
  final Map<String, List<SourceChoice>> choices;
  final List<ChannelSource> chosen;
  final bool single;
  final List<String> kinds;
  final String title;
  @override
  State<SourcePicker> createState() => _SourcePickerState();
}

class _SourcePickerState extends State<SourcePicker> {
  late final List<ChannelSource> _picked = [...widget.chosen];
  late String _kind = _startKind();
  final _filter = TextEditingController();
  final _list = ScrollController();

  /// Opens on the tab of the first thing already chosen, or the first tab with anything in it.
  String _startKind() {
    final first = widget.chosen.firstOrNull?.kind;
    if (first != null && widget.kinds.contains(first)) return first;
    return widget.kinds.firstWhere((k) => widget.choices[k]?.isNotEmpty ?? false, orElse: () => widget.kinds.first);
  }

  @override
  void initState() {
    super.initState();
    _filter.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _filter.dispose();
    _list.dispose();
    super.dispose();
  }

  List<SourceChoice> get _shown {
    final q = _filter.text.trim().toLowerCase();
    final all = widget.choices[_kind] ?? const [];
    return q.isEmpty ? all : [for (final c in all) if (c.label.toLowerCase().contains(q)) c];
  }

  void _toggle(ChannelSource s) {
    if (widget.single) {
      Navigator.of(context).pop([s]);
      return;
    }
    setState(() => _picked.contains(s) ? _picked.remove(s) : _picked.add(s));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final shown = _shown;
    String tab(String k) {
      final n = widget.choices[k]?.length ?? 0;
      final name = switch (k) {
        'show' => 'Shows',
        'collection' => 'Collections',
        'label' => 'Labels',
        _ => 'Libraries',
      };
      return '$name ($n)';
    }

    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: 680,
        height: (MediaQuery.sizeOf(context).height - 80).clamp(320, 720).toDouble(),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1016),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.border200),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.space6, Space.space5, Space.space6, Space.space2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: ConsoleText.titleLg.copyWith(color: c.text100)),
                  const SizedBox(height: Space.space3),
                  ConsoleSegmented<String>(
                    options: [for (final k in widget.kinds) (k, tab(k))],
                    value: _kind,
                    autofocus: true,
                    onChanged: (k) {
                      setState(() => _kind = k);
                      if (_list.hasClients) _list.jumpTo(0);
                    },
                  ),
                  const SizedBox(height: Space.space3),
                  SizedBox(width: 360, child: SettingsField(label: 'Search', controller: _filter, hint: 'Type to narrow the list')),
                ],
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(Space.space6),
                      child: Text(
                        _filter.text.trim().isNotEmpty
                            ? 'Nothing here matches “${_filter.text.trim()}”.'
                            : switch (_kind) {
                                'collection' => 'No collections in your Plex libraries yet.',
                                'label' => 'No labels in your Plex libraries yet.',
                                _ => 'Nothing to pick from.',
                              },
                        style: ConsoleText.body.copyWith(color: c.text300),
                      ),
                    )
                  : ListView.builder(
                      controller: _list,
                      padding: const EdgeInsets.symmetric(horizontal: Space.space4, vertical: Space.space2),
                      itemCount: shown.length,
                      itemBuilder: (context, i) => _Row(
                        key: ValueKey('${shown[i].source.kind}:${shown[i].source.key}'),
                        label: shown[i].label,
                        on: _picked.contains(shown[i].source),
                        single: widget.single,
                        onTap: () => _toggle(shown[i].source),
                      ),
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(Space.space6, Space.space3, Space.space6, Space.space4),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border200))),
              child: Row(
                children: [
                  if (!widget.single) Text('${_picked.length} chosen', style: ConsoleText.small.copyWith(color: c.text200)),
                  const Spacer(),
                  ConsoleButton(label: 'Cancel', kind: ButtonKind.tertiary, onPressed: () => Navigator.of(context).pop()),
                  if (!widget.single) ...[
                    const SizedBox(width: Space.space2),
                    ConsoleButton(label: 'Done', icon: LucideIcons.check, kind: ButtonKind.primary, onPressed: () => Navigator.of(context).pop(_picked)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of the list: Select ticks it (or, picking one, picks it).
class _Row extends StatelessWidget {
  const _Row({super.key, required this.label, required this.on, required this.single, required this.onTap});
  final String label;
  final bool on;
  final bool single;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Focusable(
      onTap: onTap,
      semanticLabel: label,
      builder: (context, hover, focus) => withFocusRing(
        context,
        focused: focus,
        radius: Radii.radiusSm,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: Space.space3),
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: focus || hover ? c.surface200 : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.radiusSm),
          ),
          child: Row(
            children: [
              if (!single) ...[
                Icon(on ? LucideIcons.circleCheck : LucideIcons.circle, size: 18, color: on ? c.primary : c.text300),
                const SizedBox(width: Space.space3),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ConsoleText.body.copyWith(color: on || focus ? c.text100 : c.text200, fontWeight: on ? FontWeight.w600 : FontWeight.w400),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
