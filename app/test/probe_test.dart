import 'package:console_app/services/probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => Probe.set(null));

  test('switches and values from the launch option', () {
    Probe.set('noglass, cover=25,play=4k,');
    expect(Probe.on, isTrue);
    expect(Probe.has('noglass'), isTrue);
    expect(Probe.has('noart'), isFalse);
    expect(Probe.value('cover'), '25');
    expect(Probe.value('play'), '4k');
    expect(Probe.value('cache'), isNull);
  });

  test('a normal launch has none', () {
    Probe.set('');
    expect(Probe.on, isFalse);
    Probe.set(null);
    expect(Probe.on, isFalse);
  });

  test('sums the GPU buffers the process has mapped, largest first', () {
    const smaps = '''
12c00000-12d00000 rw-p 00000000 00:00 0                                  [anon:dalvik-main space]
Size:               1024 kB
Rss:                 124 kB
a0000000-a4000000 rw-s 00000000 00:0f 1201                               /dev/nvmap
Size:              65536 kB
Rss:                2048 kB
a4000000-a5000000 rw-s 00000000 00:0f 1201                               /dev/nvmap
Size:              16384 kB
Rss:                   0 kB
b0000000-b0800000 rw-s 00000000 00:08 77                                 anon_inode:dmabuf
Size:               8192 kB
Rss:                8192 kB
c0000000-c0001000 r-xp 00000000 b3:19 912                                /system/lib/libc.so
Size:                  4 kB
Rss:                   4 kB
''';
    expect(Probe.mapped(smaps), ', mapped: /dev/nvmap 80 MB (2 resident), anon_inode:dmabuf 8 MB (8 resident)');
  });

  test('says when nothing is mapped', () {
    expect(Probe.mapped('c0000000-c0001000 r-xp 00000000 b3:19 912 /system/lib/libc.so\nSize: 4 kB\n'), ', mapped: none');
  });
}
