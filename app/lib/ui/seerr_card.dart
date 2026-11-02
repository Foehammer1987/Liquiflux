import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../state/scope.dart';
import 'nav.dart';

/// A title Plex doesn't have: poster (opens the full detail page), one Request button, then live progress.
class SeerrCard extends StatefulWidget {
  const SeerrCard({super.key, required this.item, this.onRequested, this.plexKey});
  final SeerrResult item;

  /// Set when Plex already has the title (even if Seerr hasn't noticed): it opens in the library.
  final String? plexKey;
  final VoidCallback? onRequested;
  @override
  State<SeerrCard> createState() => _SeerrCardState();
}

class _SeerrCardState extends State<SeerrCard> {
  bool _busy = false;
  String? _error;
  SeerrRequest? _made;

  Future<void> _request() async {
    final app = AppScope.read(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await app.seerr!.request(widget.item.mediaType, widget.item.id);
      if (!mounted) return;
      setState(() => _made = r);
      widget.onRequested?.call();
      app.refreshRequests();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    // Fresh search data wins once Seerr reports on the new request.
    final media = it.mediaInfo ?? _made?.media;
    final state = requestStateOf(media, it.mediaInfo == null ? _made : null);
    final sub = [yearOf(it.date), it.isTv ? 'Series' : 'Movie'].where((s) => s.isNotEmpty).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PosterCard(
          title: it.displayTitle,
          subtitle: sub,
          imageUrl: it.posterUrl(),
          dimmed: state.requestable && widget.plexKey == null,
          onTap: () {
            final key = widget.plexKey ?? (media?.status == MediaStatus.available ? media?.ratingKey : null);
            ShellNav.of(context).push(key != null ? ItemDest(key) : SeerrDest(it.mediaType, it.id));
          },
        ),
        const SizedBox(height: Space.space2),
        if (widget.plexKey != null && state.requestable)
          const Align(
            alignment: Alignment.centerLeft,
            child: ConsoleBadge('In Your Library', tone: Tone.success),
          )
        else if (state.requestable)
          ConsoleButton(
            label: _busy ? 'Requesting' : (state.label == 'Partially Available' ? 'Request Rest' : 'Request'),
            icon: LucideIcons.plus,
            kind: ButtonKind.primary,
            size: ButtonSize.sm,
            expand: true,
            onPressed: _busy ? null : _request,
          )
        else
          RequestProgress(state: state, compact: true),
        if (_error != null) ...[const SizedBox(height: Space.space1), Text(_error!, style: ConsoleText.caption.copyWith(color: context.c.dangerText))],
      ],
    );
  }
}
