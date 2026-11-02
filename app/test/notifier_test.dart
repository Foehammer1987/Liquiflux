import 'package:console_app/services/notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toast payloads are read only in the shapes the app writes', () {
    expect(parseToastPayload('play:12345'), (kind: 'play', id: '12345', mediaType: null));
    expect(parseToastPayload('join:room-1_a'), (kind: 'join', id: 'room-1_a', mediaType: null));
    expect(parseToastPayload('open:movie:603'), (kind: 'open', id: '603', mediaType: 'movie'));
    expect(parseToastPayload('open:tv:1399'), (kind: 'open', id: '1399', mediaType: 'tv'));
    for (final bad in [
      '',
      'play',
      'play:',
      'play:../../library/sections',
      'play:123?X-Plex-Token=x',
      'play:https://evil.example',
      'play:1:2',
      'open:person:5',
      'open:movie:0',
      'open:movie:-3',
      'open:movie:abc',
      'open:movie:99999999999999999999',
      'open:movie',
      'join:a/b',
      'join:${'x' * 500}',
      'delete:5',
      'PLAY:5',
      'play:5\n',
    ]) {
      expect(parseToastPayload(bad), isNull, reason: bad);
    }
  });
}
