import 'dart:async';

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../platform.dart';
import '../../services/tv_sleep.dart';
import 'player_session.dart';
import 'remote.dart';
import 'riptide.dart';

enum SheetTab {
  audio('Audio', LucideIcons.audioLines),
  subtitles('Subtitles', LucideIcons.captions),
  video('Video', LucideIcons.monitorPlay),
  playback('Playback', LucideIcons.gauge),
  chapters('Chapters', LucideIcons.listVideo),

  /// Who's in it; a panel of its own, opened from the bar or Down on the pause screen.
  riptide('Riptide', LucideIcons.users);

  const SheetTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The frosted panel on the right of the player with every in-playback setting.
class PlayerSheet extends StatelessWidget {
  const PlayerSheet({super.key, required this.session, required this.tint, required this.accent, required this.tab, required this.onTab, required this.onClose, required this.imageUrl, this.tabFocus, this.riptide, this.onPerson});
  final PlayerSession session;
  final SheetTab tab;
  final ValueChanged<SheetTab> onTab;
  final VoidCallback onClose;
  final String? Function(String? path, int w, int h) imageUrl;

  /// Focus for each tab's button, so the player can put the D-pad on the open tab.
  final Map<SheetTab, FocusNode>? tabFocus;

  /// The cast for the Riptide panel, and what picking someone does (opens their page).
  final Riptide? riptide;
  final ValueChanged<PlexTag>? onPerson;

  final Color tint;
  final Color accent;
  Color get _tint => tint;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      for (final t in SheetTab.values)
        if (t != SheetTab.riptide && (t != SheetTab.chapters || session.chapters.isNotEmpty)) t,
    ];
    return GlassSurface(
      radius: Radii.radiusLg + 4,
      elevation: 2,
      fill: playerShade(tint, 0.62),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.space4, Space.space3, Space.space2, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(tab.label, style: ConsoleText.titleLg.copyWith(color: Colors.white)),
                ),
                _IconBtn(icon: LucideIcons.x, label: 'Close', onTap: onClose),
              ],
            ),
          ),
          if (tab != SheetTab.riptide)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.space3, Space.space2, Space.space3, Space.space2),
            child: Row(
              children: [
                for (final t in tabs)
                  Expanded(
                    child: _TabButton(tab: t, on: t == tab, tint: _tint, focusNode: tabFocus?[t], onTap: () => onTab(t)),
                  ),
              ],
            ),
          ),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Space.space3, Space.space3, Space.space3, Space.space5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: switch (tab) {
                  SheetTab.audio => _audio(context),
                  SheetTab.subtitles => _subtitles(context),
                  SheetTab.video => _video(context),
                  SheetTab.playback => _playback(context),
                  SheetTab.chapters => _chapters(context),
                  SheetTab.riptide => _riptide(context),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _audio(BuildContext context) {
    final s = session;
    final plexTracks = s.audioStreams;
    return [
      _Heading('Track', color: accent),
      if (plexTracks.isNotEmpty)
        for (final a in plexTracks) _Choice(label: a.label, detail: _audioDetail(a), on: a.id == s.audio?.id, tint: _tint, onTap: () => s.selectAudio(a))
      else
        for (final a in s.mpvAudio)
          _Choice(label: a.title ?? a.language ?? 'Track ${a.id}', detail: a.codec, on: s.player.state.track.audio.id == a.id, tint: _tint, onTap: () => s.player.setAudioTrack(a)),
      // Only mpv has audio delay, sound filters and an output choice (not Samsung's player).
      if (playerIsMpv) ...[
      _Heading('Sync', color: accent),
      _Stepper(
        label: 'Audio Delay',
        value: _ms(s.audioDelayMs),
        help: 'Move the sound earlier or later if voices and lips drift apart.',
        onMinus: () => s.setAudioDelay(s.audioDelayMs - 50),
        onPlus: () => s.setAudioDelay(s.audioDelayMs + 50),
        onReset: s.audioDelayMs == 0 ? null : () => s.setAudioDelay(0),
      ),
      _Heading('Sound', color: accent),
      _SwitchRow(label: 'Night Mode', help: 'Evens out loud effects and quiet dialogue.', value: s.prefs.nightMode, tint: _tint, onChanged: s.setNightMode),
      _SwitchRow(label: 'Volume Boost', help: 'Lets the volume go up to 200% for quiet mixes.', value: s.prefs.volumeBoost, tint: _tint, onChanged: s.setVolumeBoost),
      if (s.audioDevices.length > 1) ...[
        _Heading('Output', color: accent),
        for (final d in s.audioDevices) _Choice(label: d.name == 'auto' ? 'System Default' : d.description, on: d.name == s.audioDevice, tint: _tint, onTap: () => s.setAudioDevice(d)),
      ],
      ],
    ];
  }

  String? _audioDetail(PlexStream a) {
    final bits = [if (a.codec != null) a.codec!.toUpperCase(), if (a.channels != null) _channels(a.channels!), if (a.bitrate != null) '${a.bitrate} kbps'];
    return bits.isEmpty ? null : bits.join(' · ');
  }

  static String _channels(int n) => switch (n) {
    1 => 'Mono',
    2 => 'Stereo',
    6 => '5.1',
    8 => '7.1',
    _ => '$n ch',
  };
  static String _ms(int ms) => ms == 0 ? '0 ms' : '${ms > 0 ? '+' : ''}$ms ms';

  /// Plex's own subtitle search: pick a language, then a result to add it to the title.
  List<Widget> _online(PlayerSession s) {
    final results = s.onlineResults;
    return [
      _Heading('Find Online', color: accent),
      _Labelled(
        'Language',
        _Chips<String>(options: [for (final l in s.onlineLanguages) (l, _languageName(l))], value: s.onlineLanguage, tint: _tint, onChanged: (l) => s.searchOnline(l)),
      ),
      if (s.onlineSearching)
        const _Note('Searching…')
      else if (results == null)
        _Action(label: 'Search for Subtitles', icon: LucideIcons.search, tint: _tint, onTap: () => s.searchOnline()),
      for (final r in (results ?? const <OnlineSubtitle>[]).take(30))
        _Choice(
          label: r.label,
          detail: s.onlineFetching?.key == r.key
              ? 'Adding it to the title…'
              : [
                  if (r.perfectMatch) 'Made for this file',
                  if (r.score > 0) '${r.score}% match',
                  if (r.hearingImpaired) 'SDH',
                  if (r.forced) 'Forced',
                  if (r.downloaded) 'Already on the server',
                  if (r.provider.isNotEmpty) r.provider,
                ].join(' · '),
          on: false,
          tint: _tint,
          onTap: () => s.fetchOnline(r),
        ),
      if (s.onlineNote != null) _Note(s.onlineNote!),
      if (results != null && results.isNotEmpty)
        _Note(isTizen ? 'Found by your Plex server. Names closest to your file’s line up best.' : 'Found by your Plex server. Names closest to your file’s line up best; Subtitle Delay fixes the rest.'),
    ];
  }

  static String _languageName(String two) => playbackLanguages.where((l) => twoLetterLanguage(l.$1) == two).firstOrNull?.$2 ?? two.toUpperCase();

  List<Widget> _subtitles(BuildContext context) {
    final s = session;
    final subs = s.subtitleStreams;
    final image = s.subtitle?.isImageSubtitle ?? false;
    return [
      _Heading('Track', color: accent),
      _Choice(label: 'Off', on: s.subtitle == null, tint: _tint, onTap: () => s.selectSubtitle(null)),
      if (subs.isNotEmpty)
        for (final t in subs)
          _Choice(
            label: t.label,
            detail: [
              if (t.forced) 'Forced',
              if (t.hearingImpaired) 'SDH',
              if (t.isExternal) 'Sidecar file',
              if (t.codec != null && !t.label.toUpperCase().contains(t.codec!.toUpperCase())) t.codec!.toUpperCase(),
            ].join(' · '),
            on: t.id == s.subtitle?.id,
            tint: _tint,
            onTap: () => s.selectSubtitle(t),
          )
      else
        for (final t in s.mpvSubtitles) _Choice(label: t.title ?? t.language ?? 'Track ${t.id}', on: s.player.state.track.subtitle.id == t.id, tint: _tint, onTap: () => s.player.setSubtitleTrack(t)),
      if (s.transcoding && s.subtitle != null) const _Note('The server is burning these subtitles into the picture, so the style below applies when playing the original.'),
      // Burned in by the server (the note above), they are part of the picture: nothing here changes them.
      if (image && !s.transcoding) const _Note('Picture-based subtitles (PGS, VobSub) keep their own look. Size and height still apply.'),
      if (s.canSearchOnline) ..._online(s),
      if (playerIsMpv) ...[
      _Heading('Sync', color: accent),
      _Stepper(
        label: 'Subtitle Delay',
        value: _ms(s.subtitleDelayMs),
        help: 'Show lines earlier or later when they are out of step.',
        onMinus: () => s.setSubtitleDelay(s.subtitleDelayMs - 100),
        onPlus: () => s.setSubtitleDelay(s.subtitleDelayMs + 100),
        onReset: s.subtitleDelayMs == 0 ? null : () => s.setSubtitleDelay(0),
      ),
      ],
      _Heading('Style', color: accent),
      _Labelled(
        'Size',
        _Chips<int>(
          options: const [(75, 'Small'), (100, 'Normal'), (125, 'Large'), (150, 'Huge')],
          value: s.subtitleSize,
          tint: _tint,
          onChanged: (v) => s.setSubtitleLook(size: v),
        ),
      ),
      _Stepper(
        label: 'Height',
        value: s.subtitleRaise == 0 ? 'Bottom' : '+${s.subtitleRaise}%',
        onMinus: s.subtitleRaise <= 0 ? null : () => s.setSubtitleLook(raise: s.subtitleRaise - 2),
        onPlus: s.subtitleRaise >= 40 ? null : () => s.setSubtitleLook(raise: s.subtitleRaise + 2),
        onReset: s.subtitleRaise == 0 ? null : () => s.setSubtitleLook(raise: 0),
      ),
      _Labelled(
        'Colour',
        Wrap(
          spacing: Space.space2,
          runSpacing: Space.space2,
          children: [
            for (final (key, color) in [...PlayerSession.subtitleColors.entries.map((e) => (e.key, e.value)), ('art', s.tint ?? Colors.white)])
              _Swatch(
                color: color,
                on: s.subtitleColor == key,
                art: key == 'art',
                onTap: () => s.setSubtitleLook(color: key),
              ),
          ],
        ),
      ),
      _Labelled(
        'Background',
        _Chips<String>(
          options: const [('outline', 'Outline'), ('shadow', 'Shadow'), ('box', 'Box')],
          value: s.subtitleBackground,
          tint: _tint,
          onChanged: (v) => s.setSubtitleLook(background: v),
        ),
      ),
      _Preview(session: s),
    ];
  }

  List<Widget> _video(BuildContext context) {
    final s = session;
    final m = s.media;
    final fileKbps = m?.bitrate ?? 0;
    return [
      _Heading('Quality', color: accent),
      for (final q in streamingQualities)
        if (q.isOriginal || fileKbps == 0 || q.kbps < fileKbps)
          _Choice(
            label: q.isOriginal ? 'Original' : q.label,
            detail: q.isOriginal
                ? [m?.resolutionLabel, m?.videoCodec?.toUpperCase(), if (fileKbps > 0) '${(fileKbps / 1000).toStringAsFixed(1)} Mbps', 'Direct Play'].whereType<String>().join(' · ')
                : 'Converted by the server',
            on: s.quality == q.kbps,
            tint: _tint,
            onTap: () => s.setQuality(q.kbps),
          ),
      if (s.item.media.length > 1) ...[
        _Heading('Version', color: accent),
        for (final (i, v) in s.item.media.indexed)
          _Choice(
            label: [v.resolutionLabel, v.videoCodec?.toUpperCase()].whereType<String>().join(' ').ifEmpty('Version ${i + 1}'),
            detail: [v.container?.toUpperCase(), if (v.bitrate != null) '${(v.bitrate! / 1000).toStringAsFixed(1)} Mbps', v.audioCodec?.toUpperCase()].whereType<String>().join(' · '),
            on: i == s.mediaIndex,
            tint: _tint,
            onTap: () => s.setVersion(i),
          ),
      ],
      _Heading('Picture', color: accent),
      _Labelled('Aspect', _Chips<String>(options: const [('fit', 'Fit'), ('fill', 'Fill'), ('stretch', 'Stretch')], value: s.aspect, tint: _tint, onChanged: s.setAspect)),
      if (playerIsMpv) _SwitchRow(label: 'Deinterlace', help: 'For old TV recordings with combing on motion.', value: s.deinterlace, tint: _tint, onChanged: s.setDeinterlace),
    ];
  }

  List<Widget> _playback(BuildContext context) {
    final s = session;
    final sleep = s.sleep;
    final left = sleep.left;
    final titles = sleep.titles;
    // Counting episodes only means something with one to go on to.
    final series = s.isEpisode || s.queue.length > 1;
    return [
      _Heading('Speed', color: accent),
      _Chips<double>(options: const [(0.5, '0.5×'), (0.75, '0.75×'), (1.0, 'Normal'), (1.25, '1.25×'), (1.5, '1.5×'), (1.75, '1.75×'), (2.0, '2×')], value: s.rate, tint: _tint, onChanged: s.setRate),
      if (playerIsMpv) const _Note('Pitch stays natural at every speed.'),
      _Heading('Sleep Timer', color: accent),
      _Chips<String>(
        options: [
          ('off', 'Off'),
          ('15', '15 min'),
          ('30', '30 min'),
          ('45', '45 min'),
          ('60', '1 hour'),
          ('90', '90 min'),
          ('e1', 'End of This'),
          if (series) ...[('e2', '2 Episodes'), ('e3', '3 Episodes')],
        ],
        value: titles != null ? 'e$titles' : (sleep.minutes == null ? 'off' : '${sleep.minutes}'),
        tint: _tint,
        onChanged: (v) => v == 'off'
            ? s.setSleep()
            : v.startsWith('e')
            ? s.setSleep(titles: int.parse(v.substring(1)))
            : s.setSleep(minutes: int.parse(v)),
      ),
      if (left != null) _Note('Stopping in ${clock(left)}. Volume fades over the last minute; any button keeps you watching.'),
      if (titles != null && titles > 1) _Note('Stopping when ${titles == 2 ? 'the next episode' : 'the episode after next'} ends. Carries on through Up Next.'),
      if (titles == 1) _Note('Stopping when this ends. The credits play out with no countdown to the next one.'),
      if (TvSleep.supported)
        ValueListenableBuilder<bool?>(
          valueListenable: TvSleep.allowed,
          builder: (context, allowed, _) => allowed == true
              ? const _Note('When it stops, the TV goes to sleep (and turns off, if HDMI-CEC is on).')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Note('To turn the TV off when it stops, switch on "Liquiflux sleep timer" once in Android\'s Accessibility settings. It only puts the TV to sleep. Without it the player just closes and the TV\'s own sleep setting takes over.'),
                    _Choice(label: 'Allow Turning the TV Off', detail: 'Settings > Device Preferences > Accessibility', on: false, tint: _tint, onTap: () => unawaited(TvSleep.ask())),
                  ],
                ),
        ),
    ];
  }

  List<Widget> _riptide(BuildContext context) {
    final x = riptide;
    if (x == null) return const [];
    final scene = x.inScene(session.position);
    final first = tabFocus?[SheetTab.riptide];
    Widget row(PlexTag r, int i) => _PersonRow(
      name: r.tag,
      role: r.role,
      // Small and always through Plex's resizer (see PauseScreen._photo).
      photo: imageUrl(r.thumb, 88, 88),
      tint: _tint,
      // The player puts the D-pad on the panel's first person.
      focusNode: i == 0 ? first : null,
      onTap: onPerson == null ? null : () => onPerson!(r),
    );
    final cast = x.cast;
    var i = 0;
    return [
      if (scene.isNotEmpty) ...[_Heading('In This Scene', color: accent), for (final r in scene) row(r, i++)],
      _Heading(scene.isEmpty ? 'Cast' : 'Full Cast', color: accent),
      if (cast.isEmpty) const _Note('Plex has no cast for this title.') else for (final r in cast) row(r, i++),
      if (!x.scanned && cast.isNotEmpty && (x.server.isNotEmpty || isAnimated(session.item))) _Note(isAnimated(session.item) ? 'Animated titles show the whole cast.' : 'Who’s in each scene shows here once the Riptide scanner has been over this title.'),
    ];
  }

  List<Widget> _chapters(BuildContext context) {
    final s = session;
    final now = s.chapterAt(s.position);
    return [
      for (final c in s.chapters)
        _ChapterRow(
          chapter: c,
          on: identical(c, now),
          tint: _tint,
          thumb: imageUrl(c.thumb, 192, 108),
          headers: s.plex.headers,
          onTap: () => s.seekTo(Duration(milliseconds: c.startMs)),
        ),
    ];
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.tab, required this.on, required this.tint, required this.onTap, this.focusNode});
  final SheetTab tab;
  final bool on;
  final Color tint;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  @override
  Widget build(BuildContext context) => Focusable(
    onTap: onTap,
    focusNode: focusNode,
    semanticLabel: tab.label,
    builder: (context, hover, focus) => AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      foregroundDecoration: tvRing(focus, radius: Radii.radiusMd),
      padding: const EdgeInsets.symmetric(vertical: Space.space2),
      decoration: BoxDecoration(
        color: on ? tint.withValues(alpha: 0.2) : (hover || focus ? Colors.white.withValues(alpha: 0.08) : Colors.transparent),
        borderRadius: BorderRadius.circular(Radii.radiusMd),
        border: Border.all(color: on ? tint.withValues(alpha: 0.6) : (focus ? Colors.white.withValues(alpha: 0.6) : Colors.transparent)),
      ),
      child: Column(
        children: [
          Icon(tab.icon, size: 18, color: on ? Colors.white : Colors.white.withValues(alpha: 0.7)),
          const SizedBox(height: 2),
          Text(
            tab.label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: ConsoleText.caption.copyWith(color: on ? Colors.white : Colors.white.withValues(alpha: 0.7)),
          ),
        ],
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.space2, Space.space4, Space.space2, Space.space2),
    child: Text(
      text.toUpperCase(),
      style: ConsoleText.caption.copyWith(color: color.withValues(alpha: 0.9), letterSpacing: 0.8, fontWeight: FontWeight.w700),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.space2, Space.space2, Space.space2, 0),
    child: Text(text, style: ConsoleText.caption.copyWith(color: Colors.white.withValues(alpha: 0.6))),
  );
}

/// Someone in the cast: their photo, name and character. Picking them opens their page.
class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.name, required this.role, required this.photo, required this.tint, required this.onTap, this.focusNode});
  final String name;
  final String? role;
  final String? photo;
  final Color tint;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  @override
  Widget build(BuildContext context) {
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join();
    final fallback = Center(child: Text(initials, style: ConsoleText.small.copyWith(color: Colors.white70)));
    return Focusable(
      onTap: onTap,
      focusNode: focusNode,
      semanticLabel: role == null ? name : '$name as $role',
      builder: (context, hover, focus) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: Space.space2, vertical: 6),
        foregroundDecoration: tvRing(focus, radius: Radii.radiusMd),
        decoration: BoxDecoration(
          color: hover || focus ? Colors.white.withValues(alpha: 0.07) : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.radiusMd),
          border: focus ? Border.all(color: Colors.white.withValues(alpha: 0.7)) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(shape: BoxShape.circle, color: playerShade(tint, 0.9), border: Border.all(color: tint.withValues(alpha: 0.5))),
              clipBehavior: Clip.antiAlias,
              child: photo == null ? fallback : ArtImage(photo!, fit: BoxFit.cover, decodeWidth: 88, errorBuilder: (_, _, _) => fallback),
            ),
            const SizedBox(width: Space.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ConsoleText.body.copyWith(color: Colors.white, fontWeight: FontWeight.w500)),
                  if (role != null && role!.isNotEmpty) Text(role!, maxLines: 1, overflow: TextOverflow.ellipsis, style: ConsoleText.caption.copyWith(color: Colors.white.withValues(alpha: 0.55))),
                ],
              ),
            ),
            if (onTap != null) Icon(LucideIcons.chevronRight, size: 16, color: Colors.white.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, this.detail, required this.on, required this.tint, required this.onTap});
  final String label;
  final String? detail;
  final bool on;
  final Color tint;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Focusable(
    onTap: onTap,
    semanticLabel: label,
    builder: (context, hover, focus) => AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: Space.space2, vertical: Space.space2),
      foregroundDecoration: tvRing(focus, radius: Radii.radiusMd),
      decoration: BoxDecoration(
        color: on ? tint.withValues(alpha: 0.16) : (hover || focus ? Colors.white.withValues(alpha: 0.07) : Colors.transparent),
        borderRadius: BorderRadius.circular(Radii.radiusMd),
        border: focus ? Border.all(color: Colors.white.withValues(alpha: 0.7)) : null,
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? tint : Colors.transparent,
              border: Border.all(color: on ? tint : Colors.white.withValues(alpha: 0.35), width: 1.5),
            ),
            child: on ? const Icon(LucideIcons.check, size: 12, color: Colors.black) : null,
          ),
          const SizedBox(width: Space.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: ConsoleText.body.copyWith(color: Colors.white, fontWeight: on ? FontWeight.w600 : FontWeight.w400),
                ),
                if (detail != null && detail!.isNotEmpty) Text(detail!, style: ConsoleText.caption.copyWith(color: Colors.white.withValues(alpha: 0.55))),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// A row that does something (rather than picking one of several).
class _Action extends StatelessWidget {
  const _Action({required this.label, required this.icon, required this.tint, required this.onTap});
  final String label;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Focusable(
    onTap: onTap,
    semanticLabel: label,
    builder: (context, hover, focus) => AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: Space.space2, vertical: Space.space2),
      foregroundDecoration: tvRing(focus, radius: Radii.radiusMd),
      decoration: BoxDecoration(
        color: hover || focus ? tint.withValues(alpha: 0.22) : tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.radiusMd),
        border: focus ? Border.all(color: Colors.white.withValues(alpha: 0.7)) : null,
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: Space.space3),
          Text(label, style: ConsoleText.body.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    ),
  );
}

class _Labelled extends StatelessWidget {
  const _Labelled(this.label, this.child);
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.space2, Space.space1, Space.space2, Space.space3),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: ConsoleText.body.copyWith(color: Colors.white)),
        const SizedBox(height: Space.space2),
        child,
      ],
    ),
  );
}

class _Chips<T> extends StatelessWidget {
  const _Chips({required this.options, required this.value, required this.tint, required this.onChanged});
  final List<(T, String)> options;
  final T value;
  final Color tint;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Space.space1 + 2,
    runSpacing: Space.space1 + 2,
    children: [
      for (final (v, label) in options)
        Focusable(
          onTap: () => onChanged(v),
          semanticLabel: label,
          builder: (context, hover, focus) {
            final on = v == value;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: Space.space3),
              foregroundDecoration: tvRing(focus, radius: Radii.radiusFull),
              decoration: BoxDecoration(
                color: on ? tint : (hover ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.07)),
                borderRadius: BorderRadius.circular(Radii.radiusFull),
                border: Border.all(color: focus ? Colors.white : Colors.transparent),
              ),
              child: Align(
                widthFactor: 1,
                child: Text(
                  label,
                  style: ConsoleText.small.copyWith(color: on ? Colors.black : Colors.white, fontWeight: on ? FontWeight.w600 : FontWeight.w400),
                ),
              ),
            );
          },
        ),
    ],
  );
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.value, this.help, this.onMinus, this.onPlus, this.onReset});
  final String label;
  final String value;
  final String? help;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final VoidCallback? onReset;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.space2, Space.space1, Space.space1, Space.space3),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: ConsoleText.body.copyWith(color: Colors.white)),
            ),
            if (onReset != null) _IconBtn(icon: LucideIcons.rotateCcw, label: 'Reset', size: 14, onTap: onReset!),
            _IconBtn(icon: LucideIcons.minus, label: 'Less', onTap: onMinus),
            SizedBox(
              width: 72,
              child: Text(
                value,
                textAlign: TextAlign.center,
                style: ConsoleText.bodyStrong.copyWith(color: Colors.white, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            _IconBtn(icon: LucideIcons.plus, label: 'More', onTap: onPlus),
          ],
        ),
        if (help != null) Text(help!, style: ConsoleText.caption.copyWith(color: Colors.white.withValues(alpha: 0.55))),
      ],
    ),
  );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.label, this.help, required this.value, required this.tint, required this.onChanged});
  final String label;
  final String? help;
  final bool value;
  final Color tint;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.space2, Space.space1, Space.space2, Space.space3),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: ConsoleText.body.copyWith(color: Colors.white)),
              if (help != null) Text(help!, style: ConsoleText.caption.copyWith(color: Colors.white.withValues(alpha: 0.55))),
            ],
          ),
        ),
        const SizedBox(width: Space.space3),
        TvRing(
          radius: Radii.radiusFull,
          child: ConsoleSwitch(value: value, color: tint, semanticLabel: label, onChanged: onChanged),
        ),
      ],
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.on, required this.onTap, this.art = false});
  final Color color;
  final bool on;
  final bool art;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Focusable(
    onTap: onTap,
    semanticLabel: art ? "The title's colour" : 'Colour',
    builder: (context, hover, focus) => AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 30,
      height: 30,
      padding: const EdgeInsets.all(3),
      foregroundDecoration: tvRing(focus, circle: true),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: on || focus ? Colors.white : Colors.white.withValues(alpha: hover ? 0.4 : 0.0), width: 2),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: art ? const Icon(LucideIcons.sparkles, size: 12, color: Colors.black87) : null,
      ),
    ),
  );
}

/// A line of sample text in the chosen style.
class _Preview extends StatelessWidget {
  const _Preview({required this.session});
  final PlayerSession session;
  @override
  Widget build(BuildContext context) {
    final s = session;
    final size = 15.0 * s.subtitleSize / 100;
    final text = 'The tide is turning.';
    final base = ConsoleText.body.copyWith(fontSize: size, height: 1.3, fontWeight: FontWeight.w600);
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.space2, Space.space1, Space.space2, 0),
      height: 92,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.radiusMd),
        gradient: LinearGradient(colors: [(s.tint ?? Colors.blueGrey).withValues(alpha: 0.45), Colors.black.withValues(alpha: 0.6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      alignment: Alignment(0, 0.8 - s.subtitleRaise / 25),
      child: switch (s.subtitleBackground) {
        'box' => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          color: Colors.black.withValues(alpha: 0.7),
          child: Text(text, style: base.copyWith(color: s.subtitleSwatch)),
        ),
        'shadow' => Text(
          text,
          style: base.copyWith(
            color: s.subtitleSwatch,
            shadows: const [Shadow(color: Colors.black, offset: Offset(1.5, 1.5), blurRadius: 2)],
          ),
        ),
        _ => Stack(
          children: [
            Text(
              text,
              style: base.copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 3
                  ..color = Colors.black,
              ),
            ),
            Text(text, style: base.copyWith(color: s.subtitleSwatch)),
          ],
        ),
      },
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({required this.chapter, required this.on, required this.tint, required this.thumb, required this.headers, required this.onTap});
  final PlexChapter chapter;
  final bool on;
  final Color tint;
  final String? thumb;
  final Map<String, String> headers;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Focusable(
    onTap: onTap,
    semanticLabel: chapter.title,
    builder: (context, hover, focus) => AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.only(bottom: Space.space1),
      padding: const EdgeInsets.all(Space.space2),
      foregroundDecoration: tvRing(focus, radius: Radii.radiusMd),
      decoration: BoxDecoration(
        color: on ? tint.withValues(alpha: 0.16) : (hover || focus ? Colors.white.withValues(alpha: 0.07) : Colors.transparent),
        borderRadius: BorderRadius.circular(Radii.radiusMd),
        border: Border.all(color: on ? tint.withValues(alpha: 0.6) : (focus ? Colors.white.withValues(alpha: 0.7) : Colors.transparent)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.radiusSm),
            child: SizedBox(
              width: 96,
              height: 54,
              child: thumb == null
                  ? ColoredBox(
                      color: Colors.white.withValues(alpha: 0.08),
                      child: Icon(LucideIcons.film, size: 18, color: Colors.white.withValues(alpha: 0.4)),
                    )
                  : ArtImage(
                      thumb!,
                      headers: headers,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(color: Colors.white.withValues(alpha: 0.08)),
                    ),
            ),
          ),
          const SizedBox(width: Space.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chapter.title.isEmpty ? 'Chapter ${chapter.index ?? ''}' : chapter.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ConsoleText.body.copyWith(color: Colors.white, fontWeight: on ? FontWeight.w600 : FontWeight.w400),
                ),
                Text(
                  clock(Duration(milliseconds: chapter.startMs)),
                  style: ConsoleText.caption.copyWith(color: Colors.white.withValues(alpha: 0.55)),
                ),
              ],
            ),
          ),
          if (on) Icon(LucideIcons.play, size: 14, color: tint),
        ],
      ),
    ),
  );
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.label, required this.onTap, this.size = 16});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;
  @override
  Widget build(BuildContext context) => Focusable(
    onTap: onTap,
    semanticLabel: label,
    builder: (context, hover, focus) => Container(
      width: 32,
      height: 32,
      foregroundDecoration: tvRing(focus, circle: true),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hover || focus ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
        border: focus ? Border.all(color: Colors.white.withValues(alpha: 0.7)) : null,
      ),
      child: Icon(
        icon,
        size: size,
        color: Colors.white.withValues(alpha: onTap == null ? 0.3 : 0.9),
      ),
    ),
  );
}

/// mpv's own track list entry label, used when Plex has no stream details.
String mpvTrackLabel(SubtitleTrack t) => t.title ?? t.language ?? 'Track ${t.id}';
