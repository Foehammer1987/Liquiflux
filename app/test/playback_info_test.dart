import 'package:console_app/ui/player/player_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('codec: the first part of mpv\'s name, without the (null) of a build without descriptions', () {
    expect(mpvCodecLabel('hevc ((null))'), 'hevc');
    expect(mpvCodecLabel('h264 (null)'), 'h264');
    expect(mpvCodecLabel('hevc (H.265 / HEVC (High Efficiency Video Coding))'), 'hevc (H.265');
    expect(mpvCodecLabel(''), '');
  });

  test('pixel format: the frames\' own format under hardware decoding', () {
    expect(mpvPixelFormat('videotoolbox', 'p010'), 'p010');
    expect(mpvPixelFormat('yuv420p10', ''), 'yuv420p10');
  });
}
