import 'package:console_core/console_core.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

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
