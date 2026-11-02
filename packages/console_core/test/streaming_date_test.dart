import 'package:console_core/console_core.dart';
import 'package:test/test.dart';

final now = DateTime(2026, 10, 24, 12);

Map<String, dynamic> rel(String country, List<(int, String)> dates) => {
  'iso_3166_1': country,
  'release_dates': [for (final (type, date) in dates) {'type': type, 'release_date': date, 'certification': ''}],
};

SeerrResult movie({String? releaseDate, String? status = 'Released', List<Map<String, dynamic>> releases = const []}) => SeerrResult.fromJson({
  'id': 1,
  'mediaType': 'movie',
  'title': 'Film',
  'releaseDate': ?releaseDate,
  'status': ?status,
  'releases': {'results': releases},
});

SeerrResult series({String? firstAirDate, String? status, List<(int, String?)> seasons = const []}) => SeerrResult.fromJson({
  'id': 2,
  'mediaType': 'tv',
  'name': 'Show',
  'firstAirDate': ?firstAirDate,
  'status': ?status,
  'seasons': [for (final (n, air) in seasons) {'seasonNumber': n, 'name': 'Season $n', 'airDate': ?air}],
});

SeerrRequest approved(String type, {List<int> seasons = const []}) => SeerrRequest.fromJson({
  'id': 9,
  'status': RequestStatus.approved,
  'createdAt': '2026-10-01T00:00:00.000Z',
  'type': type,
  'media': {'id': 3, 'tmdbId': 1, 'mediaType': type, 'status': MediaStatus.processing},
  'seasons': [for (final n in seasons) {'id': n, 'seasonNumber': n}],
});

void main() {
  group('movies', () {
    test('a future digital date waits for it (US first)', () {
      final w = streamingWaitOf(
        movie(
          releaseDate: '2026-10-03',
          releases: [
            rel('GB', [(4, '2026-11-02T00:00:00.000Z')]),
            rel('US', [(3, '2026-10-03T00:00:00.000Z'), (4, '2026-11-18T00:00:00.000Z')]),
          ],
        ),
        now: now,
      )!;
      expect(w.date, DateTime(2026, 11, 18));
      expect(w.headline, 'Digital release November 18, 2026');
      expect(w.until(now: now), 'in 25 days');
      expect(w.note, 'In theaters since October 3, 2026');
    });

    test('a past digital date is out', () {
      expect(streamingWaitOf(movie(releases: [rel('US', [(4, '2026-09-01T00:00:00.000Z')])]), now: now), isNull);
    });

    test('released today counts as out', () {
      expect(streamingWaitOf(movie(releases: [rel('US', [(4, '2026-10-24T00:00:00.000Z')])]), now: now), isNull);
    });

    test('in theaters with no digital date waits undated', () {
      final w = streamingWaitOf(movie(releases: [rel('US', [(3, '2026-09-20T00:00:00.000Z')])]), now: now)!;
      expect(w.date, isNull);
      expect(w.headline, 'Digital release date not announced');
    });

    test('an old film without a digital date is taken to be out', () {
      expect(streamingWaitOf(movie(releaseDate: '1999-03-31'), now: now), isNull);
    });

    test('already on disc is out', () {
      expect(streamingWaitOf(movie(releases: [rel('US', [(3, '2026-08-01T00:00:00.000Z'), (5, '2026-10-10T00:00:00.000Z')])]), now: now), isNull);
    });

    test('announced with no dates waits', () {
      expect(streamingWaitOf(movie(status: 'In Production'), now: now)?.headline, 'Release date not announced');
      expect(streamingWaitOf(movie(), now: now), isNull);
    });
  });

  group('series', () {
    test('a future premiere waits for it', () {
      final w = streamingWaitOf(series(firstAirDate: '2027-01-15', status: 'Planned'), now: now)!;
      expect(w.date, DateTime(2027, 1, 15));
      expect(w.headline, 'Premiere January 15, 2027');
    });

    test('a requested season still to air waits for it', () {
      final d = series(firstAirDate: '2020-01-01', status: 'Returning Series', seasons: [(1, '2020-01-01'), (2, '2022-01-01'), (3, '2026-12-05')]);
      final w = streamingWaitOf(d, seasons: [3], now: now)!;
      expect(w.what, 'Season 3 premiere');
      expect(w.date, DateTime(2026, 12, 5));
      expect(streamingWaitOf(d, seasons: [2, 3], now: now), isNull);
      expect(streamingWaitOf(d, now: now), isNull);
    });
  });

  group('request state', () {
    test('an approved request for an unreleased film shows the date, no bar', () {
      final d = movie(releases: [rel('US', [(4, '2026-11-18T00:00:00.000Z')])]);
      final r = approved('movie');
      final s = requestStateWith(r.media, r, d, now: now);
      expect(s.label, notOnStreamingLabel);
      expect(s.progress, isNull);
      expect(s.waiting, isFalse);
      expect(s.notOnStreaming, isTrue);
      expect(s.detail, 'Digital release November 18, 2026 · in 25 days');
    });

    test('once it is out it is an ordinary request again', () {
      final d = movie(releases: [rel('US', [(4, '2026-10-01T00:00:00.000Z')])]);
      final r = approved('movie');
      expect(requestStateWith(r.media, r, d, now: now).label, 'Requested');
    });

    test('requested season numbers come from the request', () {
      final r = approved('tv', seasons: [3]);
      expect(r.seasonNumbers, [3]);
      final d = series(firstAirDate: '2020-01-01', seasons: [(1, '2020-01-01'), (3, '2026-12-05')]);
      expect(requestStateWith(r.media, r, d, now: now).notOnStreaming, isTrue);
    });

    test('a download in progress wins over the date', () {
      final r = SeerrRequest.fromJson({
        'id': 9,
        'status': RequestStatus.approved,
        'media': {
          'tmdbId': 1,
          'mediaType': 'movie',
          'status': MediaStatus.processing,
          'downloadStatus': [{'size': 100, 'sizeLeft': 50}],
        },
      });
      final d = movie(releases: [rel('US', [(4, '2026-11-18T00:00:00.000Z')])]);
      expect(requestStateWith(r.media, r, d, now: now).label, 'Downloading');
    });
  });
}
