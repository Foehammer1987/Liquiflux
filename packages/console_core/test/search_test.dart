import 'dart:convert';

import 'package:console_core/console_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

PlexItem movie(String key, String title) => PlexItem(ratingKey: key, key: '/library/metadata/$key', type: 'movie', title: title);

PlexItem episode(String key, String title, {required String show, required String showKey}) => PlexItem(
  ratingKey: key,
  key: '/library/metadata/$key',
  type: 'episode',
  title: title,
  grandparentTitle: show,
  grandparentRatingKey: showKey,
  grandparentThumb: '/library/metadata/$showKey/thumb/1',
);

void main() {
  group('searchTitles', () {
    test('episodes become their series, once', () {
      final r = searchTitles([
        movie('1', 'Avatar'),
        movie('2', 'Avatar: The Way of Water'),
        episode('10', 'The Boy in the Iceberg', show: 'Avatar: The Last Airbender', showKey: '9'),
        episode('11', 'The Avatar Returns', show: 'Avatar: The Last Airbender', showKey: '9'),
      ], 'avatar');
      expect(r.items.map((i) => (i.ratingKey, i.type, i.title)), [
        ('1', 'movie', 'Avatar'),
        ('2', 'movie', 'Avatar: The Way of Water'),
        ('9', 'show', 'Avatar: The Last Airbender'),
      ]);
      expect(r.items.last.thumb, '/library/metadata/9/thumb/1');
      expect(r.shows, {'9'});
    });

    test('a show Plex returned is not repeated for its episodes', () {
      final show = PlexItem(ratingKey: '9', key: '/library/metadata/9/children', type: 'show', title: 'Avatar: The Last Airbender', year: 2005);
      final r = searchTitles([show, episode('10', 'The Avatar Returns', show: 'Avatar: The Last Airbender', showKey: '9')], 'avatar');
      expect(r.items, [show]);
      expect(r.shows, isEmpty);
    });

    test('a series whose name does not match is dropped', () {
      // The episode's own title matched, not the show.
      final r = searchTitles([episode('20', 'Avatar Day', show: 'Futurama', showKey: '19')], 'avatar');
      expect(r.items, isEmpty);
    });

    test('every word of the query must be in the series name', () {
      final r = searchTitles([
        episode('10', 'Pilot', show: 'Avatar: The Last Airbender', showKey: '9'),
        episode('30', 'Pilot', show: 'The Legend of Korra', showKey: '29'),
      ], 'Last airbender');
      expect(r.items.map((i) => i.ratingKey), ['9']);
    });
  });

  test('PlexClient.search fills in the series from its own details', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/hubs/search') {
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'Hub': [
                {
                  'type': 'movie',
                  'Metadata': [
                    {'ratingKey': '1', 'type': 'movie', 'title': 'Avatar', 'year': 2009},
                  ],
                },
                {
                  'type': 'episode',
                  'Metadata': [
                    for (final e in [10, 11, 12])
                      {'ratingKey': '$e', 'type': 'episode', 'title': 'Episode $e', 'grandparentTitle': 'Avatar: The Last Airbender', 'grandparentRatingKey': '9'},
                  ],
                },
              ],
            },
          }),
          200,
        );
      }
      if (req.url.path == '/library/metadata/9') {
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'Metadata': [
                {'ratingKey': '9', 'type': 'show', 'title': 'Avatar: The Last Airbender', 'year': 2005, 'childCount': 3},
              ],
            },
          }),
          200,
        );
      }
      return http.Response('', 404);
    });
    final plex = PlexClient(baseUrl: 'http://10.0.0.2:32400', token: 'tok', clientId: 'c', http: JsonHttp(client: client));
    final r = await plex.search('avatar');
    expect(r.map((i) => (i.ratingKey, i.type, i.year)), [('1', 'movie', 2009), ('9', 'show', 2005)]);
  });
}
