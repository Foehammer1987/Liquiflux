import 'dart:async';

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../state/scope.dart';
import '../common.dart';
import '../nav.dart';
import '../seerr_card.dart';

/// An actor or crew member: their titles in Plex, then the rest of their work to request.
class PersonPage extends StatefulWidget {
  const PersonPage({super.key, required this.person});
  final PersonDest person;
  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  List<PlexItem>? _library;
  SeerrPerson? _bio;
  List<SeerrResult>? _credits;
  String? _seerrError;
  BackdropController? _backdrop;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _backdrop = BackdropScope.maybeOf(context);
      if (widget.person.photoUrl != null) _backdrop?.set(this, widget.person.photoUrl);
      _loadPlex();
      _loadSeerr();
    });
  }

  @override
  void dispose() {
    final b = _backdrop;
    scheduleMicrotask(() => b?.clear(this));
    super.dispose();
  }

  Future<void> _loadPlex() async {
    final app = AppScope.read(context);
    final tag = widget.person.plexTagId;
    if (app.plex == null || tag == null) return;
    try {
      final lists = await Future.wait([for (final s in app.sections.where((s) => s.isVideo)) app.plex!.withActor(s.key, tag)]);
      if (mounted) setState(() => _library = [for (final l in lists) ...l]);
    } catch (_) {
      if (mounted) setState(() => _library = const []);
    }
  }

  Future<void> _loadSeerr() async {
    final app = AppScope.read(context);
    final seerr = app.seerr;
    if (seerr == null || app.seerrConn != Conn.ok) {
      if (widget.person.plexTagId == null) setState(() => _library = const []);
      return;
    }
    try {
      var id = widget.person.tmdbId;
      if (id == null) {
        final hits = await seerr.searchPeople(widget.person.name);
        id = (hits.where((p) => p.name.toLowerCase() == widget.person.name.toLowerCase()).firstOrNull ?? hits.firstOrNull)?.id;
      }
      if (id == null) {
        if (mounted) setState(() => _credits = const []);
        return;
      }
      final results = await Future.wait([seerr.person(id), seerr.personCredits(id)]);
      if (!mounted) return;
      final bio = results[0] as SeerrPerson;
      setState(() {
        _bio = bio;
        _credits = results[1] as List<SeerrResult>;
      });
      if (widget.person.photoUrl == null && bio.profileUrl() != null) _backdrop?.set(this, bio.profileUrl());
      // No Plex tag (the title came from Seerr): find their library titles through Seerr's matches.
      if (widget.person.plexTagId != null || app.plex == null) return;
      final keys = _credits!.where((c) => c.mediaInfo?.status == MediaStatus.available && c.mediaInfo?.ratingKey != null).map((c) => c.mediaInfo!.ratingKey!).take(40);
      final items = await Future.wait(keys.map((k) => app.plex!.metadata(k).catchError((Object _) => null)));
      if (mounted) setState(() => _library = items.whereType<PlexItem>().toList());
    } catch (e) {
      if (mounted) setState(() => _seerrError = errorText(e));
    } finally {
      // Without a Plex tag the library panel waits on this: never leave it spinning.
      if (mounted && widget.person.plexTagId == null && _library == null) setState(() => _library = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    final p = widget.person;
    final bio = _bio;
    final photo = p.photoUrl ?? bio?.profileUrl();
    final born = DateTime.tryParse(bio?.birthday ?? '');
    final died = DateTime.tryParse(bio?.deathday ?? '');
    final facts = <(String, Widget)>[
      if (bio?.knownFor != null) ('Known for', Text(bio!.knownFor!)),
      if (born != null) ('Born', Text([formatDate(born), if (died == null) '(age ${_age(born)})', if ((bio?.placeOfBirth ?? '').isNotEmpty) 'in ${bio!.placeOfBirth}'].join(' '))),
      if (died != null) ('Died', Text(formatDate(died))),
    ];
    final library = _library ?? const <PlexItem>[];
    final haveTmdb = {for (final i in library) ?i.tmdbId};
    final requestable = (_credits ?? const <SeerrResult>[]).where((r) => r.mediaInfo?.status != MediaStatus.available && !haveTmdb.contains(r.id)).take(40).toList();
    final initials = Credit(name: p.name).initials;
    final seerrOn = app.seerrConn == Conn.ok;

    return PageBody(
      padding: const EdgeInsets.fromLTRB(Space.space6, Space.space3, Space.space6, Space.space8),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ConsoleButton(label: 'Back', icon: LucideIcons.chevronLeft, kind: ButtonKind.tertiary, onPressed: ShellNav.of(context).back),
        ),
        GlassSurface(
          padding: const EdgeInsets.all(Space.space6),
          elevation: 1.5,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 168,
                height: 168,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.surface300,
                  border: Border.all(color: context.fx.panelBorder),
                  boxShadow: context.fx.glass ? [BoxShadow(color: context.fx.shadow, blurRadius: 28, offset: const Offset(0, 12), spreadRadius: -6)] : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: photo != null
                    ? ArtImage(
                        photo,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Center(
                          child: Text(initials, style: ConsoleText.display.copyWith(color: c.text300)),
                        ),
                      )
                    : Center(
                        child: Text(initials, style: ConsoleText.display.copyWith(fontSize: 44, color: c.text300)),
                      ),
              ),
              const SizedBox(width: Space.space8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: ConsoleText.display.copyWith(fontSize: 30, height: 1.2, color: c.text100)),
                    const SizedBox(height: Space.space2),
                    Wrap(
                      spacing: Space.space2,
                      children: [
                        if (_library != null) ConsoleBadge('${library.length} in Your Library', tone: library.isEmpty ? Tone.neutral : Tone.success),
                        if (_credits != null) ConsoleBadge('${_credits!.length} ${_credits!.length == 1 ? 'Credit' : 'Credits'}'),
                      ],
                    ),
                    if (facts.isNotEmpty) ...[const SizedBox(height: Space.space4), FactTable(rows: facts)],
                    if ((bio?.biography ?? '').isNotEmpty) ...[
                      const SizedBox(height: Space.space3),
                      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: ExpandableText(bio!.biography!, maxLines: 5)),
                    ],
                    if (!seerrOn && bio == null) ...[const SizedBox(height: Space.space3), muted(context, 'Connect Seerr in Settings to see their biography and everything else they have been in.')],
                  ],
                ),
              ),
            ],
          ),
        ),
        ConsolePanel(
          title: 'In Your Library',
          meta: _library != null ? muted(context, '${library.length}') : null,
          child: _library == null
              ? (p.plexTagId == null && !seerrOn ? const EmptyState(title: 'Nothing to show') : const LoadingNote(label: 'Looking through Plex'))
              : library.isEmpty
              ? EmptyState(title: 'Nothing with ${p.name} in Plex yet', body: requestable.isNotEmpty ? 'Request something below.' : null)
              : PosterGrid(children: [for (final i in library) PlexPoster(item: i)]),
        ),
        if (seerrOn)
          ConsolePanel(
            title: 'More With ${p.name}',
            meta: _credits != null ? muted(context, '${requestable.length} to Request') : null,
            child: _seerrError != null
                ? ErrorNote(_seerrError!)
                : _credits == null
                ? const LoadingNote(label: 'Asking Seerr')
                : requestable.isEmpty
                ? const EmptyState(title: 'You have everything', body: 'Every title Seerr lists for them is already in Plex.')
                : PosterGrid(
                    children: [for (final r in requestable) SeerrCard(key: ValueKey('${r.mediaType}:${r.id}'), item: r)],
                  ),
          ),
      ],
    );
  }

  static int _age(DateTime born) {
    final n = DateTime.now();
    return n.year - born.year - ((n.month < born.month || (n.month == born.month && n.day < born.day)) ? 1 : 0);
  }
}
