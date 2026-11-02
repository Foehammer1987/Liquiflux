/// Switches for measuring what the UI's drawing costs in graphics memory on a TV, set by the
/// app's probe launch option. All off in normal use.
abstract final class DrawProbe {
  /// No artwork at all.
  static bool noArt = false;

  /// No blurred art behind the pages and no faded edge on the Home spotlight.
  static bool noBlur = false;
}
