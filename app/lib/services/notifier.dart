import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../app_info.dart';

/// System notifications (Windows toasts, Linux desktop notifications) with a Play button.
/// Clicking either the toast or Play hands "play:ratingKey" to [onAction].
///
/// Everywhere else, Android TV included, it does nothing: a TV has no use for system
/// notifications (and Android would want a permission and a channel), so the in-app cards
/// are all there is.
class Notifier {
  Notifier._();
  static final instance = Notifier._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _next = 1;

  /// Receives the toast's payload, e.g. "play:12345".
  void Function(String payload)? onAction;

  /// Identifies Liquiflux's toasts to Windows; must never change once shipped.
  static const _windowsGuid = '5b0a3c6e-8f1d-4c2b-9a7e-2d4f6b8c1e93';

  /// Whether this platform gets system notifications at all.
  static bool get supported => Platform.isWindows || Platform.isLinux;

  Future<void> init() async {
    if (_ready || !supported) return;
    // Linux notifications go over the desktop's session bus; without one there's nobody to show them.
    if (Platform.isLinux && (Platform.environment['DBUS_SESSION_BUS_ADDRESS'] ?? '').isEmpty) return;
    try {
      _ready =
          await _plugin.initialize(
            settings: const InitializationSettings(
              windows: WindowsInitializationSettings(appName: appName, appUserModelId: 'Foehammer.Liquiflux', guid: _windowsGuid),
              linux: LinuxInitializationSettings(defaultActionName: 'Open'),
            ),
            onDidReceiveNotificationResponse: (r) {
              final p = r.actionId?.isNotEmpty == true ? r.actionId! : (r.payload ?? '');
              if (p.isNotEmpty) onAction?.call(p);
            },
          ) ??
          false;
    } catch (e) {
      debugPrint('notifications: $e');
      return;
    }
    // Launched by clicking a toast while Liquiflux was closed (not every platform can tell).
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final p = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true && p != null) Timer(const Duration(seconds: 3), () => onAction?.call(p));
    } catch (_) {}
  }

  /// "Ready to watch" (or an invitation) with the poster and a button.
  Future<void> ready({required String title, required String body, required String payload, String? posterUrl, String action = 'Play'}) async {
    if (!_ready || !supported) return;
    try {
      final poster = posterUrl == null ? null : await _download(posterUrl);
      await _plugin.show(
        id: _next++,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          windows: WindowsNotificationDetails(
            actions: [WindowsAction(content: action, arguments: payload)],
            images: [if (poster != null) WindowsImage(Uri.file(poster.path, windows: true), altText: title, placement: WindowsImagePlacement.appLogoOverride)],
          ),
          linux: LinuxNotificationDetails(
            actions: [LinuxNotificationAction(key: payload, label: action)],
          ),
        ),
      );
    } catch (e) {
      debugPrint('notification: $e');
    }
  }

  /// Toasts can only show local files, so the poster is saved to the temp folder first.
  Future<File?> _download(String url) async {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'http' && uri.scheme != 'https') return null;
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      // A poster is a few hundred KB; anything huge isn't one.
      if (res.statusCode != 200 || res.bodyBytes.length > 8 * 1024 * 1024) return null;
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}${Platform.pathSeparator}liquiflux-toast-${url.hashCode.toUnsigned(32)}.jpg');
      await f.writeAsBytes(res.bodyBytes);
      return f;
    } catch (_) {
      return null;
    }
  }
}

/// What a toast asks for: play a Plex title, join a Watch Together room, or open a title.
typedef ToastAction = ({String kind, String id, String? mediaType});

/// Reads a toast's payload ("play:12345", "join:abc", "open:movie:603"). It comes back from
/// the system, so only these shapes with plain ids are accepted; anything else is null.
ToastAction? parseToastPayload(String payload) {
  if (payload.length > 200) return null;
  final parts = payload.split(':');
  final id = RegExp(r'^[\w-]{1,128}$');
  return switch (parts) {
    ['play', final key] when RegExp(r'^\w{1,64}$').hasMatch(key) => (kind: 'play', id: key, mediaType: null),
    ['join', final room] when id.hasMatch(room) => (kind: 'join', id: room, mediaType: null),
    ['open', final type && ('movie' || 'tv'), final tmdb] when (int.tryParse(tmdb) ?? 0) > 0 && RegExp(r'^\d{1,10}$').hasMatch(tmdb) => (kind: 'open', id: tmdb, mediaType: type),
    _ => null,
  };
}
