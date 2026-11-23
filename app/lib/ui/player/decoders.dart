import '../../platform.dart';

/// What the player on a platform decodes itself, by Plex's codec names. A track it can't
/// decode goes through Plex instead: sound alone is converted with the picture sent as it is
/// (PlayerSession.soundNeedsServer), a picture it can't decode is converted whole.
///
/// Null means "whatever mpv's FFmpeg decodes", which on Windows, Linux and Android is every
/// codec Plex serves. Samsung TVs have their own rules (PlayerSession.directNeedsServer).
class PlayerDecoders {
  const PlayerDecoders({this.audio, this.video, this.audioFamilies = const {}, this.videoFamilies = const {}});

  /// Every codec (mpv with FFmpeg's full set).
  static const all = PlayerDecoders();

  /// Codecs decoded, by exact name; null for all of them.
  final Set<String>? audio;
  final Set<String>? video;

  /// Name prefixes decoded as a family (FFmpeg's `--enable-decoder='aac*'`): any codec
  /// starting with one of these.
  final Set<String> audioFamilies;
  final Set<String> videoFamilies;

  /// Whether a track in [codec] plays here. An unnamed codec is given the benefit of the doubt.
  bool playsAudio(String? codec) => _plays(codec, audio, audioFamilies);
  bool playsVideo(String? codec) => _plays(codec, video, videoFamilies);

  static bool _plays(String? codec, Set<String>? exact, Set<String> families) {
    if (exact == null || codec == null || codec.isEmpty) return true;
    final c = codec.toLowerCase();
    return exact.contains(c) || families.any(c.startsWith);
  }

  /// Mac, iPhone, iPad: media_kit's libmpv-darwin-build, whose FFmpeg is built with a list
  /// of decoders (read from Avcodec.framework's configure line in the Mac and iOS builds of
  /// media_kit_libs 1.1.x, the same for both). Not in it: Dolby TrueHD and MLP (common on 4K
  /// films), RealAudio Cook, and VC-1 video.
  static const apple = PlayerDecoders(
    // --enable-decoder=ac3, eac3, dca (DTS and DTS-HD), flac, alac, als, ape, opus, vorbis,
    // wavpack, tta, tak, shorten, ralf; and the aac*, mp1*/mp2*/mp3*, pcm*, wma*, atrac*,
    // dsd*, gsm*, mpc*, ra* families.
    audio: {
      'aac', 'ac3', 'eac3', 'dca', 'dca-ma', 'dts', 'dts-hd', 'flac', 'alac', 'als', 'ape', 'opus', 'vorbis', 'wavpack', 'tta', 'tak', 'shorten', 'ralf', //
      'mp1', 'mp2', 'mp3', 'pcm',
    },
    audioFamilies: {'aac', 'mp1', 'mp2', 'mp3', 'pcm', 'wma', 'atrac', 'dsd', 'gsm', 'mpc', 'ra_'},
    // --enable-decoder=h264, hevc, av1 (and libdav1d), mpeg1video, mpeg2video, mpeg4,
    // msmpeg4v1-3, h263, flv, vp6, vp8, vp9, wmv1-3, theora, mjpeg.
    video: {'h264', 'hevc', 'av1', 'mpeg1video', 'mpeg2video', 'mpeg4', 'msmpeg4v1', 'msmpeg4v2', 'msmpeg4v3', 'msmpeg4', 'h263', 'flv', 'flv1', 'vp8', 'vp9', 'wmv1', 'wmv2', 'wmv3', 'theora', 'mjpeg'},
    videoFamilies: {'vp6'},
  );

  /// This platform's player: [apple] on a Mac, iPhone or iPad (mpv there), [all] elsewhere.
  static PlayerDecoders forPlatform({required bool apple}) => apple ? PlayerDecoders.apple : PlayerDecoders.all;

  static final current = forPlatform(apple: isApple && playerIsMpv);
}
