import 'package:console_app/ui/player/remote.dart';
import 'package:console_app/ui/player/seek_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('remoteAction', () {
    test('with the picture focused the D-pad seeks, Select plays and Up / Down bring the controls', () {
      expect(remoteAction(LogicalKeyboardKey.arrowLeft), RemoteAction.seekBack);
      expect(remoteAction(LogicalKeyboardKey.arrowRight), RemoteAction.seekForward);
      expect(remoteAction(LogicalKeyboardKey.arrowUp), RemoteAction.showControls);
      expect(remoteAction(LogicalKeyboardKey.arrowDown), RemoteAction.showControls);
      for (final k in [LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter, LogicalKeyboardKey.gameButtonA]) {
        expect(remoteAction(k), RemoteAction.playPause);
      }
    });

    test('Select takes Up Next, then a Skip button, before play / pause', () {
      expect(remoteAction(LogicalKeyboardKey.select, upNext: true, skip: true), RemoteAction.playNow);
      expect(remoteAction(LogicalKeyboardKey.select, skip: true), RemoteAction.skip);
    });

    test('with a control focused the D-pad and Select go to it', () {
      for (final k in [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.select, LogicalKeyboardKey.enter]) {
        expect(remoteAction(k, onControl: true, upNext: true), RemoteAction.focus);
      }
    });

    test('media keys and Back work whatever has focus', () {
      for (final onControl in [false, true]) {
        expect(remoteAction(LogicalKeyboardKey.mediaPlayPause, onControl: onControl), RemoteAction.playPause);
        expect(remoteAction(LogicalKeyboardKey.mediaPlay, onControl: onControl), RemoteAction.play);
        expect(remoteAction(LogicalKeyboardKey.mediaPause, onControl: onControl), RemoteAction.pause);
        expect(remoteAction(LogicalKeyboardKey.mediaFastForward, onControl: onControl), RemoteAction.seekForward);
        expect(remoteAction(LogicalKeyboardKey.mediaRewind, onControl: onControl), RemoteAction.seekBack);
        expect(remoteAction(LogicalKeyboardKey.mediaTrackNext, onControl: onControl, samsung: false), RemoteAction.next);
        expect(remoteAction(LogicalKeyboardKey.mediaTrackPrevious, onControl: onControl, samsung: false), RemoteAction.previous);
        expect(remoteAction(LogicalKeyboardKey.mediaStop, onControl: onControl), RemoteAction.stop);
        expect(remoteAction(LogicalKeyboardKey.escape, onControl: onControl), RemoteAction.back);
        expect(remoteAction(LogicalKeyboardKey.goBack, onControl: onControl), RemoteAction.back);
      }
    });

    test('Samsung: the track keys (a long press of Rewind / Fast Forward) seek', () {
      expect(remoteAction(LogicalKeyboardKey.mediaTrackNext, samsung: true), RemoteAction.seekForward);
      expect(remoteAction(LogicalKeyboardKey.mediaTrackPrevious, samsung: true), RemoteAction.seekBack);
    });

    test('keys the player does not use are not player keys (Samsung: they must not respond)', () {
      for (final k in [
        LogicalKeyboardKey.colorF0Red, LogicalKeyboardKey.colorF1Green, LogicalKeyboardKey.colorF2Yellow, LogicalKeyboardKey.colorF3Blue, //
        LogicalKeyboardKey.channelUp, LogicalKeyboardKey.channelDown, LogicalKeyboardKey.info, LogicalKeyboardKey.guide, LogicalKeyboardKey.contextMenu,
      ]) {
        expect(playerKeys.contains(k), isFalse, reason: k.debugName);
        expect(remoteAction(k), isNull, reason: k.debugName);
      }
      for (final k in [LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.mediaPlayPause, LogicalKeyboardKey.mediaFastForward, LogicalKeyboardKey.digit5]) {
        expect(playerKeys.contains(k), isTrue, reason: k.debugName);
      }
    });

    test('the Exit key is told by its physical key (flutter-tizen gives it no logical one)', () {
      KeyEvent down(LogicalKeyboardKey l, PhysicalKeyboardKey p) => KeyDownEvent(logicalKey: l, physicalKey: p, timeStamp: Duration.zero);
      expect(isExitKey(down(const LogicalKeyboardKey(0x1400000000), PhysicalKeyboardKey.exit)), isTrue);
      expect(isExitKey(down(LogicalKeyboardKey.escape, PhysicalKeyboardKey.escape)), isFalse);
    });

    test('Back can be left to the system, and other keys to the keyboard shortcuts', () {
      expect(remoteAction(LogicalKeyboardKey.goBack, goBack: false), isNull);
      expect(remoteAction(LogicalKeyboardKey.escape, goBack: false), RemoteAction.back);
      expect(remoteAction(LogicalKeyboardKey.keyF), isNull);
      expect(remoteAction(LogicalKeyboardKey.space), isNull);
    });

    test('only seeking repeats while held', () {
      expect(remoteRepeats(RemoteAction.seekForward), isTrue);
      expect(remoteRepeats(RemoteAction.seekBack), isTrue);
      expect(remoteRepeats(RemoteAction.playPause), isFalse);
      expect(remoteRepeats(RemoteAction.back), isFalse);
    });
  });

  test('a held seek speeds up', () {
    expect(heldSkip(10, Duration.zero), 10);
    expect(heldSkip(10, const Duration(milliseconds: 1999)), 10);
    expect(heldSkip(10, const Duration(seconds: 2)), 20);
    expect(heldSkip(10, const Duration(seconds: 5)), 40);
  });

  testWidgets('the seek bar scrubs with the D-pad and seeks on Select', (tester) async {
    final seeks = <Duration>[];
    final scrubs = <bool>[];
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              child: SeekBar(
                position: const Duration(minutes: 10),
                duration: const Duration(minutes: 60),
                buffered: Duration.zero,
                color: Colors.blue,
                onSeek: seeks.add,
                onScrub: scrubs.add,
                focusable: true,
                focusNode: focus,
              ),
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(seeks, isEmpty, reason: 'scrubbing only previews');
    expect(scrubs, [true]);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(seeks.single.inSeconds, 10 * 60 + 10);
    expect(scrubs, [true, false]);

    // Esc drops a scrub without seeking.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(seeks, hasLength(1));
    expect(scrubs, [true, false, true, false]);
  });
}
