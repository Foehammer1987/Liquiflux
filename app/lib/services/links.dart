import 'package:console_core/console_core.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../platform.dart';

/// Whether web links can open: not on a Samsung TV, where the store's reviewers fail any
/// button that does nothing and the TV's browser isn't something an app should rely on.
/// Buttons that only open a web page are left out there.
final bool canOpenLinks = !isTizen;

/// Opens [url] in the browser. Links often come from a server (a trailer, a Seerr page), so
/// only plain http and https links open: never file:, javascript: or an app's own scheme,
/// and never one with a user name or password in it. False when nothing opened.
Future<bool> openExternal(String? url) async {
  final uri = safeExternalUri(url);
  if (uri == null) {
    debugPrint('not opening a link that is not a web address');
    return false;
  }
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('open link: ${errorText(e)}');
    return false;
  }
}
