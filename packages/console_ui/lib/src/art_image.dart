import 'package:flutter/widgets.dart';

import 'draw_probe.dart';

/// Decoded artwork sits in graphics memory, which on a 2 GB TV (the 2019 Shield) is the
/// same RAM a 4K video decoder needs. The app turns these on for such TVs.
abstract final class ArtMemory {
  /// While on, artwork on pages covered by another page (the pages behind a playing video)
  /// lets go of its picture, and loads it again once its page is uncovered: when the video
  /// ends, only the page it was started from loads its artwork again, not the ones still
  /// covered behind that.
  static final ValueNotifier<bool> releaseCovered = ValueNotifier(false);

  /// While on, all artwork lets go of its picture, covered or not. A covered page keeps what
  /// it last drew, artwork included, until it draws again, which Flutter doesn't do while the
  /// page is hidden; so for a moment the app draws the hidden pages without their artwork.
  static final ValueNotifier<bool> releaseAll = ValueNotifier(false);

  /// The widest any artwork is decoded; null decodes it at the size it arrives.
  static int? maxDecodeWidth;
}

/// A poster, backdrop, logo or photo from the network, following [ArtMemory].
class ArtImage extends StatefulWidget {
  const ArtImage(
    this.url, {
    super.key,
    this.headers,
    this.fit,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.decodeWidth,
    this.gaplessPlayback = false,
    this.errorBuilder,
  });

  final String url;
  final Map<String, String>? headers;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final double? width;
  final double? height;

  /// Decode no wider than this, for art shown small or blurred.
  final int? decodeWidth;
  final bool gaplessPlayback;
  final ImageErrorWidgetBuilder? errorBuilder;

  /// The narrower of what the picture asks for and [ArtMemory.maxDecodeWidth].
  @visibleForTesting
  static int? decodeWidthFor(int? asked, int? cap) {
    if (asked == null) return cap;
    if (cap == null) return asked;
    return asked < cap ? asked : cap;
  }

  @override
  State<ArtImage> createState() => _ArtImageState();
}

class _ArtImageState extends State<ArtImage> {
  /// Let go of while covered, until uncovered.
  bool _released = false;

  @override
  Widget build(BuildContext context) {
    // The navigator turns tickers off on a page while another page covers it.
    final covered = !TickerMode.valuesOf(context).enabled;
    return ListenableBuilder(
      listenable: Listenable.merge([ArtMemory.releaseCovered, ArtMemory.releaseAll]),
      builder: (context, _) {
        _released = covered && (_released || ArtMemory.releaseCovered.value);
        final w = widget;
        if (_released || ArtMemory.releaseAll.value || DrawProbe.noArt) return SizedBox(width: w.width, height: w.height);
        final decode = ArtImage.decodeWidthFor(w.decodeWidth, ArtMemory.maxDecodeWidth);
        final ImageProvider network = NetworkImage(w.url, headers: w.headers);
        return Image(
          image: decode == null ? network : ResizeImage(network, width: decode, policy: ResizeImagePolicy.fit),
          fit: w.fit,
          alignment: w.alignment,
          width: w.width,
          height: w.height,
          gaplessPlayback: w.gaplessPlayback,
          errorBuilder: w.errorBuilder,
        );
      },
    );
  }
}
