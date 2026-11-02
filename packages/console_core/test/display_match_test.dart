import 'package:console_core/console_core.dart';
import 'package:test/test.dart';

DisplayMode m(int id, int w, int h, double hz) => DisplayMode(id: id, width: w, height: h, refreshRate: hz);

/// The 2019 Shield on a 4K TV, as Android lists it (rates as reported).
final shield = [
  m(1, 3840, 2160, 59.94006),
  m(2, 3840, 2160, 60.000004),
  m(3, 3840, 2160, 50.0),
  m(4, 3840, 2160, 30.000002),
  m(5, 3840, 2160, 29.97003),
  m(6, 3840, 2160, 25.0),
  m(7, 3840, 2160, 24.000002),
  m(8, 3840, 2160, 23.976025),
  m(9, 1920, 1080, 60.000004),
  m(10, 1920, 1080, 59.94006),
  m(11, 1920, 1080, 50.0),
  m(12, 1920, 1080, 24.000002),
  m(13, 1920, 1080, 23.976025),
  m(14, 1280, 720, 60.000004),
  m(15, 720, 480, 59.94006),
];

void main() {
  final uhd60 = shield[1];

  group('frame rate', () {
    test('snaps to the standard rates', () {
      expect(snapFrameRate(23.976023), 23.976);
      expect(snapFrameRate(24000 / 1001), 23.976);
      expect(snapFrameRate(29.97003), 29.97);
      expect(snapFrameRate(25.0), 25);
      expect(snapFrameRate(17.3), 17.3);
    });

    test('takes Plex, then mpv, then the label', () {
      expect(contentFrameRate(stream: 23.976, mpv: 25, label: 'PAL'), 23.976);
      expect(contentFrameRate(mpv: 24.0, label: '24p'), 24);
      expect(contentFrameRate(label: '24p'), 23.976);
      expect(contentFrameRate(label: 'NTSC'), 29.97);
      expect(contentFrameRate(label: 'PAL'), 25);
      expect(contentFrameRate(stream: 0.5, label: 'sd'), isNull);
      expect(contentFrameRate(), isNull);
    });

    test('rate fits', () {
      expect(rateFit(23.976025, 23.976), 0);
      expect(rateFit(47.952, 23.976), 1);
      expect(rateFit(119.88, 23.976), 4);
      expect(rateFit(24.000002, 23.976), 10);
      expect(rateFit(59.94006, 23.976), isNull);
      expect(rateFit(60, 24), isNull);
      expect(rateFit(59.94006, 29.97), 1);
      expect(rateFit(50, 25), 1);
      expect(rateFit(60, 59.94), 10);
    });

    test('Plex fields are read', () {
      final s = PlexStream.fromJson({'streamType': 1, 'frameRate': '23.976', 'width': 1920, 'height': 800});
      expect(s.frameRate, 23.976);
      expect(s.width, 1920);
      expect(s.height, 800);
      expect(PlexStream.fromJson({'streamType': 1, 'frameRate': 'fast'}).frameRate, isNull);
      expect(PlexStream.fromJson({'streamType': 1, 'frameRate': 9999}).frameRate, isNull);
      final media = PlexMedia.fromJson({'id': 1, 'videoFrameRate': '24p', 'width': 3840, 'height': 2160});
      expect(media.videoFrameRate, '24p');
      expect(media.height, 2160);
    });
  });

  group('frame rate only', () {
    test('23.976 film on a 60 Hz 4K screen goes to 23.976 Hz at 4K', () {
      expect(pickDisplayMode(modes: shield, current: uhd60, fps: 23.976)?.id, 8);
    });

    test('24 goes to 24, 25 to 25 (exact beats the 50 Hz multiple)', () {
      expect(pickDisplayMode(modes: shield, current: uhd60, fps: 24)?.id, 7);
      expect(pickDisplayMode(modes: shield, current: uhd60, fps: 25)?.id, 6);
    });

    test('stays when the screen already fits', () {
      expect(pickDisplayMode(modes: shield, current: shield[0], fps: 59.94), isNull);
      expect(pickDisplayMode(modes: shield, current: shield[0], fps: 29.97), isNull, reason: '59.94 shows 29.97 evenly');
      expect(pickDisplayMode(modes: shield, current: shield[7], fps: 23.976), isNull);
    });

    test('60 fps on 59.94 moves to 60', () {
      expect(pickDisplayMode(modes: shield, current: shield[0], fps: 60)?.id, 2);
    });

    test('23.976 falls back to 24 Hz when the screen has no 23.976', () {
      final modes = shield.where((x) => x.id != 8).toList();
      expect(pickDisplayMode(modes: modes, current: uhd60, fps: 23.976)?.id, 7);
    });

    test('no fitting rate stays put', () {
      final modes = [m(1, 1920, 1080, 60), m(2, 1920, 1080, 75)];
      expect(pickDisplayMode(modes: modes, current: modes[0], fps: 23.976), isNull);
      expect(pickDisplayMode(modes: const [], current: modes[0], fps: 24), isNull);
    });

    test('never changes the size', () {
      expect(pickDisplayMode(modes: shield, current: shield[8], fps: 23.976)?.id, 13);
    });

    test('a 120 Hz monitor takes 119.88 for film', () {
      final pc = [m(0, 2560, 1440, 59.94), m(1, 2560, 1440, 119.88), m(2, 2560, 1440, 144)];
      expect(pickDisplayMode(modes: pc, current: pc[2], fps: 23.976)?.id, 1);
    });
  });

  group('frame rate and resolution', () {
    test('1080p scope film on 4K goes to 1080p 23.976', () {
      expect(pickDisplayMode(modes: shield, current: uhd60, fps: 23.976, resolution: true, videoWidth: 1920, videoHeight: 800)?.id, 13);
    });

    test('4K film stays at 4K', () {
      expect(pickDisplayMode(modes: shield, current: uhd60, fps: 23.976, resolution: true, videoWidth: 3840, videoHeight: 2160)?.id, 8);
    });

    test('SD and 720p go no lower than 1080p', () {
      expect(pickDisplayMode(modes: shield, current: uhd60, fps: 29.97, resolution: true, videoWidth: 720, videoHeight: 480)?.id, 10);
      expect(pickDisplayMode(modes: shield, current: uhd60, fps: 59.94, resolution: true, videoWidth: 1280, videoHeight: 720)?.id, 10);
    });

    test('a size without the rate falls back to the rate at the current size', () {
      final modes = [m(1, 3840, 2160, 60), m(2, 3840, 2160, 23.976), m(3, 1920, 1080, 60)];
      expect(pickDisplayMode(modes: modes, current: modes[0], fps: 23.976, resolution: true, videoWidth: 1920, videoHeight: 1080)?.id, 2);
    });

    test('bigger than the screen uses the largest size', () {
      final modes = [m(1, 1920, 1080, 60), m(2, 1920, 1080, 24)];
      expect(pickDisplayMode(modes: modes, current: modes[0], fps: 24, resolution: true, videoWidth: 3840, videoHeight: 2160)?.id, 2);
    });
  });

  test('modes from the channel', () {
    expect(DisplayMode.fromMap({'id': 3, 'width': 1920, 'height': 1080, 'refreshRate': 23.976}), m(3, 1920, 1080, 23.976));
    expect(DisplayMode.fromMap({'id': 3, 'width': 0, 'height': 1080, 'refreshRate': 24}), isNull);
    expect(DisplayMode.fromMap({'id': '3'}), isNull);
    expect(DisplayMode.fromMap(null), isNull);
    expect(DisplayMatchMode.parse('rate'), DisplayMatchMode.rate);
    expect(DisplayMatchMode.parse('x'), isNull);
  });
}
