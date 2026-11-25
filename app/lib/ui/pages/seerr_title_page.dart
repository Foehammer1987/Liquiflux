import 'dart:async';

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../platform.dart';
import '../../services/links.dart';
import '../../state/scope.dart';
import '../common.dart';
import '../detail/detail_view.dart';
import '../nav.dart';
import '../seerr_card.dart';

/// A title from Seerr, laid out exactly like a Plex title, with Request in place of Play.
class SeerrTitlePage extends StatefulWidget {
  const SeerrTitlePage({super.key, required this.mediaType, required this.tmdbId});
  final String mediaType;
  final int tmdbId;
  @override
  State<SeerrTitlePage> createState() => _SeerrTitlePageState();
}

class _SeerrTitlePageState extends State<SeerrTitlePage> {
  SeerrResult? _d;
  SeerrRatings? _ratings;
  List<SeerrResult> _recs = const [];
  SeerrRequest? _made;
  String? _error;
  String? _requestError;
  bool _busy = false;
  final _busySeasons = <int>{};
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final seerr = AppScope.read(context).seerr;
    if (seerr == null) {
      setState(() => _error = 'Connect Seerr in Settings to see titles that are not in Plex.');
      return;
    }
    if (_error != null) setState(() => _error = null);
    try {
      final d = await seerr.details(widget.mediaType, widget.tmdbId);
      if (!mounted) return;
      setState(() => _d = d);
      _syncPoll();
      final more = await Future.wait([seerr.ratings(widget.mediaType, widget.tmdbId), seerr.recommendations(widget.mediaType, widget.tmdbId)]);
      if (!mounted) return;
      setState(() {
        _ratings = more[0] as SeerrRatings?;
        _recs = (more[1] as List<SeerrResult>).take(20).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  /// Refresh status while a request is moving.
  Future<void> _refresh() async {
    final seerr = AppScope.read(context).seerr;
    if (seerr == null) return;
    try {
      final d = await seerr.details(widget.mediaType, widget.tmdbId);
      if (mounted) setState(() => _d = d);
      _syncPoll();
    } catch (_) {}
  }

  void _syncPoll() {
    final active = requestStateOf(_d?.mediaInfo, _d?.mediaInfo == null ? _made : null).isActive && _d?.mediaInfo != null;
    if (active && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
    } else if (!active) {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// Any request in flight: every Request button waits for it.
  bool get _anyBusy => _busy || _busySeasons.isNotEmpty;

  Future<void> _request({List<int>? seasons}) async {
    if (_anyBusy) return;
    final app = AppScope.read(context);
    setState(() {
      _requestError = null;
      if (seasons == null) {
        _busy = true;
      } else {
        _busySeasons.addAll(seasons);
      }
    });
    try {
      final r = await app.seerr!.request(widget.mediaType, widget.tmdbId, seasons: seasons);
      if (!mounted) return;
      setState(() => _made = r);
      unawaited(app.refreshRequests());
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _requestError = errorText(e));
    } finally {
      if (mounted) {
        setState(() {
          if (seasons == null) _busy = false;
          _busySeasons.removeAll(seasons ?? const <int>[]);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (_error != null) return PageBody(children: [ErrorNote(_error!, onRetry: () => _load())]);
    final d = _d;
    if (d == null) return const PageBody(children: [LoadingNote()]);

    final detail = TitleDetail.fromSeerr(d, ratings: _ratings);
    final media = d.mediaInfo ?? _made?.media;
    final state = requestStateWith(media, d.mediaInfo == null ? _made : null, d);
    final trailer = detail.extras.where((e) => e.kind == 'Trailer').firstOrNull ?? detail.extras.firstOrNull;
    final inPlex = detail.plexRatingKey;
    final seerrWeb = '${app.settings.seerrUrl.replaceAll(RegExp(r'/+$'), '')}/${widget.mediaType}/${widget.tmdbId}';

    final actions = <Widget>[
      if (inPlex != null && !state.requestable)
        ConsoleButton(label: 'Open in Library', icon: LucideIcons.play, kind: ButtonKind.primary, size: ButtonSize.lg, autofocus: true, onPressed: () => ShellNav.of(context).push(ItemDest(inPlex)))
      else if (state.requestable)
        ConsoleButton(
          label: _busy ? 'Requesting' : (state.label == 'Partially Available' ? 'Request Missing Seasons' : (d.isTv ? 'Request All Seasons' : 'Request')),
          icon: LucideIcons.plus,
          kind: ButtonKind.primary,
          size: ButtonSize.lg,
          autofocus: true,
          onPressed: _anyBusy ? null : () => _request(),
        ),
      if (inPlex != null && state.requestable) ConsoleButton(label: 'Open in Library', icon: LucideIcons.play, size: ButtonSize.lg, onPressed: () => ShellNav.of(context).push(ItemDest(inPlex))),
      if (trailer?.url != null && canOpenLinks) ConsoleButton(label: 'Watch Trailer', icon: LucideIcons.clapperboard, size: ButtonSize.lg, iconOnly: true, onPressed: () => openExternal(trailer!.url)),
      if (detail.imdbId != null && canOpenLinks)
        ConsoleButton(
          label: 'Open on IMDb',
          icon: LucideIcons.globe,
          size: ButtonSize.lg,
          iconOnly: true,
          onPressed: () => openExternal('https://www.imdb.com/title/${Uri.encodeComponent(detail.imdbId!)}/'),
        ),
      if (canOpenLinks) ConsoleButton(label: 'Open in Seerr', icon: LucideIcons.externalLink, size: ButtonSize.lg, iconOnly: true, onPressed: () => openExternal(seerrWeb)),
    ];

    final status = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // On a TV the rows have no Request button, so the page says where the title stands,
        // as the rows' In Your Library badge does.
        if (isTv && inPlex == null && state.requestable && state.label == 'Not Requested') const Align(alignment: Alignment.centerLeft, child: ConsoleBadge(notInLibrary)),
        if (!state.requestable || state.label != 'Not Requested') RequestProgress(state: state),
        if (_requestError != null) ...[const SizedBox(height: Space.space1), Text(_requestError!, style: ConsoleText.caption.copyWith(color: context.c.dangerText))],
      ],
    );

    final seasons = d.seasonDetails.where((s) => s.seasonNumber > 0).toList();
    final seasonPanel = d.isTv && seasons.isNotEmpty
        ? ConsolePanel(
            title: 'Seasons',
            meta: muted(context, '${seasons.length}'),
            child: Column(
              children: [
                for (final (i, s) in seasons.indexed) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: context.fx.glass ? context.fx.panelBorder : context.c.border100),
                  _SeasonRow(
                    season: s,
                    status: media?.seasonStatus[s.seasonNumber] ?? MediaStatus.unknown,
                    busy: _busySeasons.contains(s.seasonNumber),
                    onRequest: _anyBusy ? null : () => _request(seasons: [s.seasonNumber]),
                  ),
                ],
              ],
            ),
          )
        : null;

    return TitleDetailView(
      detail: detail,
      actions: actions,
      status: status,
      sections: [?seasonPanel],
      moreSections: [
        if (_recs.isNotEmpty)
          ConsolePanel(
            title: 'More Like This',
            padding: const EdgeInsets.fromLTRB(Space.space2, Space.space2, Space.space2, Space.space3),
            child: PosterRow(
              children: [for (final r in _recs) SeerrCard(key: ValueKey('${r.mediaType}:${r.id}'), item: r)],
            ),
          ),
      ],
    );
  }
}

class _SeasonRow extends StatelessWidget {
  const _SeasonRow({required this.season, required this.status, required this.busy, required this.onRequest});
  final SeerrSeason season;
  final int status;
  final bool busy;
  final VoidCallback? onRequest;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (label, tone) = switch (status) {
      MediaStatus.available => ('Available', Tone.success),
      MediaStatus.partiallyAvailable => ('Partially Available', Tone.success),
      MediaStatus.processing => ('Requested', Tone.info),
      MediaStatus.pending => ('Pending Approval', Tone.warning),
      _ => ('Not Requested', Tone.neutral),
    };
    final meta = [if (season.episodeCount != null) '${season.episodeCount} ${season.episodeCount == 1 ? 'Episode' : 'Episodes'}', yearOf(season.airDate)].where((s) => s.isNotEmpty).join('  ·  ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.space1, vertical: Space.space2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(season.name, style: ConsoleText.titleSm.copyWith(color: c.text100)),
                if (meta.isNotEmpty) Text(meta, style: ConsoleText.caption.copyWith(color: c.text300)),
              ],
            ),
          ),
          ConsoleBadge(label, tone: tone),
          const SizedBox(width: Space.space3),
          SizedBox(
            width: 104,
            child: status == MediaStatus.unknown
                ? ConsoleButton(label: busy ? 'Requesting' : 'Request', icon: LucideIcons.plus, size: ButtonSize.sm, expand: true, onPressed: busy ? null : onRequest)
                : const SizedBox(),
          ),
        ],
      ),
    );
  }
}
