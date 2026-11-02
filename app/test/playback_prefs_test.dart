import 'dart:convert';

import 'package:console_app/services/playback_prefs.dart';
import 'package:console_core/console_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('playback settings survive a save and load', () {
    const p = PlaybackPrefs(localQuality: 12000, skipIntro: SkipMode.auto, subtitleMode: SubtitleMode.foreign, audioLanguage: 'jpn', volume: 140, mpvOptions: 'deband=yes');
    final back = PlaybackPrefs.fromJson(p.toJson());
    expect(back.toJson(), p.toJson());
  });

  test('per-show track choices are saved, newest last, and capped', () {
    const dub = TrackChoice(audio: 'eng', subtitles: true, subtitleLanguage: 'eng', forced: true);
    var p = const PlaybackPrefs().rememberShow('srv/1', dub).rememberShow('srv/2', const TrackChoice(audio: 'jpn'));
    p = p.rememberShow('srv/1', dub);
    expect(p.showTracks.keys, ['srv/2', 'srv/1']);
    final back = PlaybackPrefs.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
    expect(back.showTracks, p.showTracks);
    expect(back.animeAudio, 'eng');
    for (var i = 0; i < PlaybackPrefs.maxShows + 5; i++) {
      p = p.rememberShow('srv/x$i', dub);
    }
    expect(p.showTracks.length, PlaybackPrefs.maxShows);
    expect(p.showTracks.keys.last, 'srv/x${PlaybackPrefs.maxShows + 4}');
    expect(PlaybackPrefs.fromJson({'showTracks': {'a': 'junk', 'b': {'audio': 'eng'}}}).showTracks.keys, ['b']);
  });

  test('missing or odd values fall back to defaults', () {
    final p = PlaybackPrefs.fromJson({'skipIntro': 'nonsense', 'countdown': 'ten', 'volume': 80});
    expect(p.skipIntro, SkipMode.button);
    expect(p.countdown, 10);
    expect(p.volume, 80);
    expect(PlaybackPrefs.fromJson(null).hwdec, 'auto-safe');
  });

  test('a hand-edited file can\'t break playback', () {
    const d = PlaybackPrefs();
    final hostile = <Object?>[null, 'x', -1, 0, 9223372036854775807, -9223372036854775808, 1e308, 2.5, true, <Object?>[], <String, Object?>{}, 'x' * 100000];
    for (final key in d.toJson().keys) {
      for (final v in hostile) {
        final p = PlaybackPrefs.fromJson({...d.toJson(), key: v});
        expect(p.skipBack, inInclusiveRange(1, 600), reason: '$key = $v');
        expect(p.skipForward, inInclusiveRange(1, 600), reason: '$key = $v');
        expect(p.countdown, inInclusiveRange(1, 120), reason: '$key = $v');
        expect(p.subtitleSize, inInclusiveRange(25, 400), reason: '$key = $v');
        expect(p.subtitleRaise, inInclusiveRange(0, 50), reason: '$key = $v');
        expect(p.volume, inInclusiveRange(0, 200), reason: '$key = $v');
        expect(streamingQualities.map((q) => q.kbps), contains(p.localQuality), reason: '$key = $v');
        expect(streamingQualities.map((q) => q.kbps), contains(p.remoteQuality), reason: '$key = $v');
        expect(p.mpvOptions.length, lessThanOrEqualTo(20000));
        p.mpvOptionPairs;
      }
    }
    expect(PlaybackPrefs.fromJson({'subtitleMode': 5}).subtitleMode, SubtitleMode.plex);
    expect(PlaybackPrefs.fromJson({'volume': '80'}).volume, 100);
    expect(PlaybackPrefs.fromJson({'localQuality': 8000.0}).localQuality, 0);
  });

  test('advanced mpv options can\'t load scripts or write files', () {
    const p = PlaybackPrefs(
      mpvOptions: '''
deband=yes
# a comment
=novalue
scripts=/tmp/evil.lua
--script=/tmp/evil.lua
SCRIPTS-APPEND=/tmp/evil.lua
input-ipc-server=/tmp/sock
ytdl-raw-options=exec=rm -rf ~
input-commands=run rm -rf ~
include=/tmp/evil.conf
log-file=/tmp/log
sub-font-size = 40
''',
    );
    expect(p.mpvOptionPairs, [('deband', 'yes'), ('sub-font-size', '40')]);
    expect(mpvOptionAllowed('scripts-add'), isFalse);
    expect(mpvOptionAllowed('hwdec'), isTrue);
  });
}
