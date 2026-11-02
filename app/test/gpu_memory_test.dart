import 'dart:ui' as ui;

import 'package:console_app/services/gpu_memory.dart';
import 'package:console_ui/console_ui.dart' show ArtMemory;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('memory log', () {
    test('reads available and Tegra graphics memory from /proc/meminfo', () {
      const shield = 'MemTotal:        2011420 kB\nMemFree:          301204 kB\nMemAvailable:     742512 kB\nNvMapMemFree:      65536 kB\nNvMapMemUsed:     372736 kB\n';
      expect(GpuMemory.meminfo(shield), 'available 725 MB, graphics 364 MB');
    });

    test('says so when a value is missing', () {
      expect(GpuMemory.meminfo('MemAvailable: 1048576 kB\n'), 'available 1024 MB, graphics ?');
    });
  });

  testWidgets('the image that makes Flutter free released artwork decodes', (tester) async {
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(GpuMemory.pixel);
      final frame = await codec.getNextFrame();
      expect((frame.image.width, frame.image.height), (1, 1));
      frame.image.dispose();
      codec.dispose();
    });
  });

  test('a 64-bit build keeps its artwork while a video plays', () async {
    final hold = GpuMemory.startPlayback(releaseArt: true);
    expect(hold, isNull);
    expect(ArtMemory.releaseCovered.value, isFalse);
    await GpuMemory.afterPlayback(hold);
  });
}
