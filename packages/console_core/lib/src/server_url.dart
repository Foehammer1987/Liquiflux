/// A server address as typed in Settings, tidied: spaces and trailing slashes go, and
/// http:// is assumed when no scheme is given (192.168.1.10:32400).
String tidyServerUrl(String input) {
  var s = input.trim().replaceAll(RegExp(r'/+$'), '');
  if (s.isNotEmpty && !s.contains('://')) s = 'http://$s';
  return s;
}

/// Why [url] can't be used as a Plex or Seerr address, in words for the viewer, or null when
/// it can. Empty is fine (no server). Only http and https, with a host, and no user name or
/// password in the address: those would be saved in plain text and sent to every page.
String? serverUrlProblem(String url) {
  if (url.isEmpty) return null;
  final u = Uri.tryParse(url);
  if (u == null) return 'That isn’t a web address.';
  if (u.scheme != 'http' && u.scheme != 'https') return 'Use an address that starts with http:// or https://.';
  if (u.host.isEmpty || u.host.contains('%')) return 'The address needs a server name or IP address.';
  if (u.userInfo.isNotEmpty) return 'Leave the user name and password out of the address.';
  if (u.hasPort && (u.port < 1 || u.port > 65535)) return 'The port must be between 1 and 65535.';
  if (u.hasQuery || u.hasFragment) return 'Leave out anything after ? or #.';
  return null;
}
