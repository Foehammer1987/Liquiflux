import 'package:console_app/ui/player/player_session.dart';
import 'package:console_core/console_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Apple TV's player (AetherEngine) shows the title on the system's Now Playing card.
void main() {
  test('an episode is shown under its show, with season, number and title beneath', () {
    final ep = PlexItem(ratingKey: '1', key: '/library/metadata/1', type: 'episode', title: 'Sins of the Father', grandparentTitle: 'Yellowstone', parentIndex: 2, index: 10);
    expect(nowPlayingText(ep), ('Yellowstone', 'S2 · E10 · Sins of the Father'));
  });

  test('a film is shown under its own title, with its year', () {
    final film = PlexItem(ratingKey: '2', key: '/library/metadata/2', type: 'movie', title: '2 Guns', year: 2013);
    expect(nowPlayingText(film), ('2 Guns', '2013'));
  });

  test('an episode without numbers keeps just its title beneath', () {
    final ep = PlexItem(ratingKey: '3', key: '/library/metadata/3', type: 'episode', title: 'Pilot', grandparentTitle: 'Show');
    expect(nowPlayingText(ep), ('Show', 'Pilot'));
  });
}
