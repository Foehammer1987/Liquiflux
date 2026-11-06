import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Whether the TV has a network connection, for Samsung's rule that a message shows while
/// it's lost and goes away once it's back (checklist CO-CN-01/02), and that network playback
/// stops meanwhile (multitasking guide).
///
/// It looks at the TV's own network interfaces every few seconds: a cable pulled or Wi-Fi
/// gone leaves none with a usable address. That needs no extra Tizen privilege and no
/// server, so it says nothing about whether Plex itself answers (the app's error notes do
/// that). Only started on Samsung TVs (see [start]).
class NetworkWatch {
  NetworkWatch._();
  static final instance = NetworkWatch._();

  /// False while the TV has no network.
  final ValueNotifier<bool> online = ValueNotifier(true);

  Timer? _timer;
  int _misses = 0;

  /// Two looks in a row without a network before it counts as lost, so a DHCP renewal or a
  /// Wi-Fi roam doesn't flash the message.
  static const _missesToLose = 2;
  static const every = Duration(seconds: 3);

  /// [interfaces] stands in for the system's list in tests.
  void start({Future<List<NetworkInterface>> Function()? interfaces}) {
    if (_timer != null) return;
    final list = interfaces ?? () => NetworkInterface.list(includeLoopback: false, includeLinkLocal: false);
    _timer = Timer.periodic(every, (_) => unawaited(_look(list)));
  }

  bool _looking = false;

  Future<void> _look(Future<List<NetworkInterface>> Function() list) async {
    if (_looking) return;
    _looking = true;
    try {
      final up = hasNetwork(await list().timeout(const Duration(seconds: 2)));
      observe(up);
    } catch (e) {
      // Not knowing isn't the same as being offline.
      debugPrint('network check: $e');
    } finally {
      _looking = false;
    }
  }

  /// One look's result: [up] when an interface had an address.
  @visibleForTesting
  void observe(bool up) {
    if (up) {
      _misses = 0;
      if (!online.value) debugPrint('network: back');
      online.value = true;
    } else if (++_misses >= _missesToLose && online.value) {
      debugPrint('network: lost');
      online.value = false;
    }
  }

  @visibleForTesting
  void reset() {
    _timer?.cancel();
    _timer = null;
    _misses = 0;
    online.value = true;
  }
}

/// Whether any of [interfaces] has an address that can reach another machine: not loopback,
/// not link-local (169.254.x.x, fe80::), which is all an interface keeps once its network is gone.
bool hasNetwork(Iterable<NetworkInterface> interfaces) => interfaces.any((i) => i.addresses.any(usableAddress));

bool usableAddress(InternetAddress a) => !a.isLoopback && !a.isLinkLocal && !a.isMulticast;
