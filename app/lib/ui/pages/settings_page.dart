import 'dart:async';
import 'dart:io' show Platform;

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../app_info.dart';
import '../../platform.dart';
import '../../services/links.dart';
import '../../services/settings_store.dart';
import '../../state/app_state.dart';
import '../../state/scope.dart';
import '../common.dart';
import '../settings/focus_handle.dart';
import '../settings/plex_link_code.dart';
import '../settings/settings_field.dart';
import '../settings/updates_panel.dart';
import '../shell.dart' show isWindows;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.welcome = false, this.update = false});
  final bool welcome;

  /// Open on Advanced and start the update (the update card's Update).
  final bool update;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _plexUrl = TextEditingController();
  final _plexToken = TextEditingController();
  final _seerrUrl = TextEditingController();
  final _seerrKey = TextEditingController();
  final _trakt = TextEditingController();
  final _region = TextEditingController();
  final _xray = TextEditingController();
  String? _discoveryMsg;
  String? _advancedMsg;
  bool _usePlexLogin = true;
  bool _manualPlex = false;
  bool _savingPlex = false;
  bool _savingSeerr = false;
  String? _plexMsg;
  Tone _plexTone = Tone.neutral;
  String? _seerrMsg;
  Tone _seerrTone = Tone.neutral;

  set _plexStatus((String, Tone) r) {
    _plexMsg = r.$1;
    _plexTone = r.$2;
  }

  set _seerrStatus((String, Tone) r) {
    _seerrMsg = r.$1;
    _seerrTone = r.$2;
  }

  // Sign in with Plex
  bool _signingIn = false;
  bool _cancelSignIn = false;
  List<PlexServerResource>? _servers;

  // The TV's link code: shown while [_linking], with [_tick] counting down its time left.
  bool _linking = false;
  PlexPin? _pin;
  bool _codeExpired = false;
  Timer? _tick;

  /// Bumped by each sign-in, a new code or Cancel, so an older sign-in still polling
  /// knows to stop and leave the page alone.
  int _attempt = 0;

  // Where the remote's focus goes as the sign-in controls come and go on a TV.
  final _signInFocus = FocusHandle();
  final _linkFocus = FocusHandle();
  final _serverFocus = FocusHandle();

  late _Tab _tab = widget.update ? _Tab.advanced : _Tab.general;
  final _mpv = TextEditingController();

  bool _seeded = false;

  @override
  void dispose() {
    for (final c in [_plexUrl, _plexToken, _seerrUrl, _seerrKey, _trakt, _region, _xray, _mpv]) {
      c.dispose();
    }
    _tick?.cancel();
    for (final h in [_signInFocus, _linkFocus, _serverFocus]) {
      h.dispose();
    }
    super.dispose();
  }

  /// Fills the fields once from what's saved; later rebuilds leave the user's edits alone.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    final s = AppScope.read(context).settings;
    if (_plexUrl.text.isEmpty) _plexUrl.text = s.plexUrl;
    if (_trakt.text.isEmpty) _trakt.text = s.traktClientId;
    if (_region.text.isEmpty) _region.text = s.region;
    if (_xray.text.isEmpty) _xray.text = s.xrayUrl;
    if (_seerrUrl.text.isEmpty) _seerrUrl.text = s.seerrUrl;
    _usePlexLogin = s.seerrApiKey.isEmpty && s.seerrUsePlexLogin;
    if (_mpv.text.isEmpty) _mpv.text = s.playback.mpvOptions;
  }

  /// Signs in with Plex. On a desktop the user approves in the browser; a TV may have no
  /// browser, so it shows a short code to enter at plex.tv/link on a phone or computer.
  Future<void> _signIn() async {
    final app = AppScope.read(context);
    final auth = PlexAuth(clientId: app.settings.clientId, product: appName);
    final attempt = ++_attempt;
    bool current() => mounted && attempt == _attempt;
    final firstCode = !_linking;
    setState(() {
      _signingIn = true;
      _cancelSignIn = false;
      if (isTv) {
        _linking = true;
        _pin = null;
        _codeExpired = false;
        _plexMsg = null;
      } else {
        _plexStatus = ('Approve $appName in the browser window that just opened', Tone.neutral);
      }
    });
    if (isTv && firstCode) _linkFocus.focus();
    try {
      final pin = await auth.createPin(strong: !isTv);
      if (!current()) return;
      var timeout = const Duration(minutes: 5);
      if (isTv) {
        timeout = pin.expiresAt?.difference(DateTime.now()) ?? const Duration(minutes: 15);
        setState(() => _pin = pin);
        _tick?.cancel();
        _tick = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      } else {
        await openExternal(auth.authUrl(pin));
      }
      final token = await auth.waitForToken(pin, timeout: timeout, cancelled: () => _cancelSignIn || !current());
      if (!current()) return;
      if (token == null && isTv && !_cancelSignIn) {
        // The code ran out: leave it up, crossed out, next to Get a New Code.
        _tick?.cancel();
        setState(() {
          _codeExpired = true;
          _signingIn = false;
        });
        return;
      }
      if (token == null) throw 'Sign-in was cancelled or timed out';
      if (isTv) _endLink(status: ('Signed in. Finding your servers', Tone.neutral));
      _accountToken = token;
      final servers = await auth.servers(token);
      if (servers.isEmpty) throw 'No Plex servers found on this account';
      if (!current()) return;
      setState(() {
        _servers = servers..sort((a, b) => (b.owned ? 1 : 0).compareTo(a.owned ? 1 : 0));
        _plexStatus = (servers.length == 1 ? 'Connecting to ${servers.first.name}' : 'Choose a server', Tone.neutral);
      });
      if (servers.length == 1) {
        await _useServer(servers.first);
      } else if (isTv) {
        _serverFocus.focus();
      }
    } catch (e) {
      if (!current()) return;
      if (isTv) {
        _endLink(status: (errorText(e), Tone.danger));
      } else {
        setState(() => _plexStatus = (errorText(e), Tone.danger));
      }
    } finally {
      auth.close();
      if (current() && !_codeExpired) setState(() => _signingIn = false);
    }
  }

  /// Puts the TV's link code away and hands the remote back to the sign-in button. Any
  /// sign-in still waiting on the old code gives up.
  void _endLink({(String, Tone)? status}) {
    _tick?.cancel();
    setState(() {
      _linking = false;
      _pin = null;
      _codeExpired = false;
      _plexMsg = status?.$1;
      _plexTone = status?.$2 ?? Tone.neutral;
    });
    _signInFocus.focus();
  }

  void _cancelLink() {
    _attempt++;
    _signingIn = false;
    _endLink();
  }

  /// The plex.tv token from the last sign-in on this page, kept with the server's own token
  /// so the X-Ray server can check the account with plex.tv.
  String _accountToken = '';

  Future<void> _useServer(PlexServerResource s) async {
    final app = AppScope.read(context);
    setState(() => _plexStatus = ('Finding the best connection to ${s.name}', Tone.neutral));
    final probe = PlexAuth(clientId: app.settings.clientId, product: appName);
    final url = await probe.firstReachable(s).whenComplete(probe.close);
    if (!mounted) return;
    if (url == null) {
      setState(() => _plexStatus = ("Couldn't reach ${s.name}. Is it running and on this network?", Tone.danger));
      return;
    }
    _plexUrl.text = url;
    await app.update(app.settings.copyWith(plexUrl: url, plexToken: s.accessToken, plexAccountToken: _accountToken, plexServerName: s.name, plexMachineId: s.machineIdentifier));
    if (!mounted) return;
    setState(() {
      _servers = null;
      _plexStatus = app.plexConn == Conn.ok ? ('Connected to ${app.server?.name}', Tone.success) : (app.plexError ?? 'Could not connect', Tone.danger);
    });
    if (isTv) _signInFocus.focus();
  }

  /// [action], or nothing while [busy]. A TV keeps the button focusable (a greyed-out one
  /// would drop the remote's focus); elsewhere it greys out.
  VoidCallback? _unlessBusy(bool busy, VoidCallback action) => !busy ? action : (isTv ? () {} : null);

  Future<void> _saveManualPlex() async {
    final app = AppScope.read(context);
    final url = tidyServerUrl(_plexUrl.text);
    final problem = serverUrlProblem(url);
    if (problem != null) {
      setState(() => _plexStatus = (problem, Tone.danger));
      return;
    }
    _plexUrl.text = url;
    setState(() => _savingPlex = true);
    // A pasted token replaces the sign-in; whatever account token the old one came with no longer belongs to it.
    final pasted = _plexToken.text.trim();
    // A new address or token is learned afresh: the server's id is kept on the first launch that reaches it.
    final fresh = pasted.isNotEmpty || url != app.settings.plexUrl;
    await app.update(app.settings.copyWith(plexUrl: url, plexToken: pasted.isNotEmpty ? pasted : null, plexAccountToken: pasted.isNotEmpty ? '' : null, plexMachineId: fresh ? '' : null));
    _plexToken.clear();
    if (!mounted) return;
    setState(() {
      _savingPlex = false;
      _plexStatus = app.plexConn == Conn.ok ? ('Connected to ${app.server?.name} (${app.server?.shortVersion})', Tone.success) : (app.plexError ?? 'Could not connect', Tone.danger);
    });
  }

  Future<void> _saveSeerr() async {
    final app = AppScope.read(context);
    final url = tidyServerUrl(_seerrUrl.text);
    final problem = serverUrlProblem(url);
    if (problem != null) {
      setState(() => _seerrStatus = (problem, Tone.danger));
      return;
    }
    _seerrUrl.text = url;
    setState(() => _savingSeerr = true);
    await app.update(app.settings.copyWith(seerrUrl: url, seerrApiKey: _usePlexLogin ? '' : (_seerrKey.text.trim().isNotEmpty ? _seerrKey.text.trim() : null), seerrUsePlexLogin: _usePlexLogin));
    _seerrKey.clear();
    if (!mounted) return;
    setState(() {
      _savingSeerr = false;
      _seerrStatus = app.seerrConn == Conn.ok ? ('Connected as ${app.seerrUser}', Tone.success) : (app.seerrError ?? 'Could not connect', Tone.danger);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    final s = app.settings;
    return PageBody(
      maxWidth: 760,
      padding: const EdgeInsets.all(Space.space6),
      children: [
        if (widget.welcome)
          Row(
            children: [
              const ConsoleLogo(height: 56, ink: LogoInk.blue),
              const SizedBox(width: Space.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Welcome', style: ConsoleText.display.copyWith(color: c.text100)),
                    Text('Sign in with Plex to get started. Seerr is optional and adds requests.', style: ConsoleText.body.copyWith(color: c.text200)),
                  ],
                ),
              ),
            ],
          )
        else ...[
          Text(
            'Settings',
            style: ConsoleText.display.copyWith(fontSize: 32, fontWeight: FontWeight.w800, color: c.text100),
          ),
          ConsoleSegmented<_Tab>(options: [for (final t in _Tab.values) (t, t.label)], value: _tab, onChanged: (t) => setState(() => _tab = t)),
        ],
        if (widget.welcome)
          ..._general(app, c, s, welcome: true)
        else
          ...switch (_tab) {
            _Tab.general => _general(app, c, s),
            _Tab.playback => _playback(app, s.playback),
            _Tab.audio => _audioSubs(app, s.playback),
            _Tab.video => _video(app, s.playback),
            _Tab.appearance => _appearance(app, s),
            _Tab.notifications => _notifications(app, s),
            _Tab.advanced => _advanced(app, c, s.playback),
          },
      ],
    );
  }

  List<Widget> _general(AppState app, ConsoleColors c, Settings s, {bool welcome = false}) => [
    ConsolePanel(
      title: 'Plex Media Server',
      meta: app.plexConn == Conn.ok ? StatusDot(app.server?.name ?? 'Connected', tone: Tone.success, style: ConsoleText.small) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isTv && _linking)
            _linkFocus.wrap(PlexLinkCode(code: _pin?.code, left: _pin?.expiresAt?.difference(DateTime.now()), expired: _codeExpired, onNewCode: _signIn, onCancel: _cancelLink))
          else
            _signInFocus.wrap(
              Wrap(
                spacing: Space.space2,
                runSpacing: Space.space2,
                children: [
                  ConsoleButton(
                    label: _signingIn ? 'Waiting for Plex' : (s.plexReady ? 'Sign In Again' : 'Sign In with Plex'),
                    kind: ButtonKind.primary,
                    autofocus: widget.welcome,
                    onPressed: _unlessBusy(_signingIn, _signIn),
                  ),
                  if (_signingIn && !isTv) ConsoleButton(label: 'Cancel', onPressed: () => setState(() => _cancelSignIn = true)),
                  ConsoleButton(label: _manualPlex ? 'Hide Manual Setup' : 'Enter Address Manually', kind: ButtonKind.tertiary, onPressed: () => setState(() => _manualPlex = !_manualPlex)),
                ],
              ),
            ),
          if (_plexMsg != null) ...[const SizedBox(height: Space.space3), StatusDot(_plexMsg!, tone: _plexTone)],
          if (!app.credentialsSaved) ...[
            const SizedBox(height: Space.space3),
            _Warning(
              Platform.isAndroid
                  ? "This device's Android Keystore couldn't be used to keep sign-ins in, so $appName only remembers them until it closes (they are never saved in plain text). "
                        'Restarting the device and signing in again usually fixes it.'
                  : 'This computer has no keyring to keep sign-ins in, so $appName only remembers them until it closes (they are never saved in plain text). '
                        'On Linux, install and unlock GNOME Keyring or KWallet, then sign in again.',
            ),
          ],
          if (s.plexReady && sendsCredentialsInClear(s.plexUrl)) ...[
            const SizedBox(height: Space.space3),
            const _Warning('This server is reached over plain http across the internet, so your Plex token travels unencrypted. Sign in again to pick its secure address, or use https.'),
          ],
          if (_servers != null && _servers!.length > 1) ...[
            const SizedBox(height: Space.space3),
            _serverFocus.wrap(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final srv in _servers!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.space2),
                      child: ConsoleButton(label: '${srv.name}${srv.owned ? '' : ' (shared)'}', icon: LucideIcons.server, onPressed: () => _useServer(srv)),
                    ),
                ],
              ),
            ),
          ],
          if (_manualPlex) ...[
            const SizedBox(height: Space.space4),
            SettingsField(label: 'Server Address', controller: _plexUrl, mono: true, hint: 'http://192.168.1.10:32400', help: 'Include the port. Plex uses 32400 by default.'),
            const SizedBox(height: Space.space3),
            SettingsField(
              label: 'Plex Token',
              controller: _plexToken,
              obscure: true,
              mono: true,
              hint: s.plexToken.isNotEmpty ? 'Saved. Leave blank to keep it' : 'X-Plex-Token',
              help: 'In Plex Web, open any item, choose Get Info, then View XML. The token is the X-Plex-Token value in the address.',
              onSubmitted: (_) => _saveManualPlex(),
            ),
            const SizedBox(height: Space.space3),
            ConsoleButton(label: _savingPlex ? 'Saving' : 'Save and Test', kind: ButtonKind.primary, onPressed: _unlessBusy(_savingPlex, _saveManualPlex)),
          ],
        ],
      ),
    ),
    ConsolePanel(
      title: 'Seerr',
      meta: app.seerrConn == Conn.ok ? StatusDot(app.seerrUser ?? 'Connected', tone: Tone.success, style: ConsoleText.small) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsField(label: 'Seerr Address', controller: _seerrUrl, mono: true, hint: 'http://192.168.1.10:5055', help: 'Works with Seerr, Overseerr and Jellyseerr.'),
          const SizedBox(height: Space.space3),
          Text('Sign In', style: ConsoleText.caption.copyWith(color: c.text200)),
          const SizedBox(height: Space.space1),
          ConsoleSegmented<bool>(options: const [(true, 'My Plex Account'), (false, 'API Key')], value: _usePlexLogin, onChanged: (v) => setState(() => _usePlexLogin = v)),
          const SizedBox(height: Space.space1),
          Text(
            _usePlexLogin
                ? 'Requests are filed under your own Seerr user and follow its approval rules.'
                : 'Requests are filed under the API key owner, usually the admin, so they are approved automatically.',
            style: ConsoleText.caption.copyWith(color: c.text300),
          ),
          if (!_usePlexLogin) ...[
            const SizedBox(height: Space.space3),
            SettingsField(
              label: 'API Key',
              controller: _seerrKey,
              obscure: true,
              mono: true,
              hint: s.seerrApiKey.isNotEmpty ? 'Saved. Leave blank to keep it' : 'From Seerr, Settings, General',
              onSubmitted: (_) => _saveSeerr(),
            ),
          ],
          const SizedBox(height: Space.space3),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Space.space3,
            runSpacing: Space.space2,
            children: [
              ConsoleButton(label: _savingSeerr ? 'Saving' : 'Save and Test', kind: ButtonKind.primary, onPressed: _usePlexLogin && !s.plexReady ? null : _unlessBusy(_savingSeerr, _saveSeerr)),
              if (_seerrMsg != null) StatusDot(_seerrMsg!, tone: _seerrTone),
              if (_usePlexLogin && !s.plexReady) muted(context, 'Sign in with Plex first.'),
            ],
          ),
          if (s.seerrReady && sendsCredentialsInClear(s.seerrUrl)) ...[
            const SizedBox(height: Space.space3),
            _Warning('Seerr is reached over plain http across the internet, so your ${s.seerrApiKey.isNotEmpty ? 'API key' : 'Plex sign-in'} travels unencrypted. Use an https address.'),
          ],
        ],
      ),
    ),
    if (!welcome) ...[
      ConsolePanel(
        title: 'Discovery',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsField(
              label: 'Trakt Client ID (optional)',
              controller: _trakt,
              mono: true,
              hint: 'Paste the Client ID of your Trakt app',
              help:
                  "Turns Trending's genre rows into Trakt's live charts of what people are watching now. Free: sign in at trakt.tv, make an app (any name, redirect urn:ietf:wg:oauth:2.0:oob) and copy its Client ID. Without it, rows use TMDB's daily popularity.",
            ),
            const SizedBox(height: Space.space1),
            // A TV may have no browser to open it in.
            if (isTv)
              muted(context, 'Make the app on your phone or computer at trakt.tv/oauth/applications/new.')
            else
              ConsoleLink(label: 'Make a Trakt app', trailingChevron: true, style: ConsoleText.caption, onTap: () => openExternal('https://trakt.tv/oauth/applications/new')),
            const SizedBox(height: Space.space3),
            SizedBox(
              width: 220,
              child: SettingsField(label: 'Streaming Region', controller: _region, mono: true, hint: 'US', help: 'Two-letter country code for the "Popular on Netflix" rows.'),
            ),
            const SizedBox(height: Space.space3),
            SettingsField(
              label: 'X-Ray Server (optional)',
              controller: _xray,
              mono: true,
              hint: 'http://homeserver:8089',
              help: "Your Liquiflux X-Ray server: at home (http://homeserver:8089) or through Cloudflare Tunnel (https://...). Liquiflux signs in with your Plex account. With it, pausing shows who's in the scene; without it, the whole cast.",
            ),
            const SizedBox(height: Space.space3),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.space3,
              children: [
                ConsoleButton(
                  label: 'Save',
                  kind: ButtonKind.primary,
                  onPressed: () async {
                    final region = _region.text.trim().toUpperCase();
                    final xray = _xray.text.trim();
                    if (xray.isNotEmpty && !isWebUrl(xray)) {
                      setState(() => _discoveryMsg = 'The X-Ray server needs an http:// or https:// address');
                      return;
                    }
                    await app.setDiscovery(traktClientId: _trakt.text.trim(), region: RegExp(r'^[A-Z]{2}$').hasMatch(region) ? region : 'US', xrayUrl: xray);
                    var msg = 'Saved';
                    final plex = app.plex;
                    final server = xray.isEmpty || plex == null ? null : XRayServer.shared(xray, app.settings.xraySignInToken);
                    if (server != null) {
                      if (mounted) setState(() => _discoveryMsg = 'Checking X-Ray...');
                      try {
                        msg = await server.check() ? 'Saved, signed in to X-Ray' : (sendsCredentialsInClear(xray) ? 'Saved, but X-Ray outside your network needs https' : 'Saved (plain file server)');
                      } on ApiException catch (e) {
                        msg = 'Saved, but X-Ray: ${e.message}';
                      }
                    }
                    if (mounted) setState(() => _discoveryMsg = msg);
                  },
                ),
                if (_discoveryMsg != null) StatusDot(_discoveryMsg!, tone: _discoveryMsg!.startsWith('Saved') && !_discoveryMsg!.contains(' but ') ? Tone.success : Tone.warning),
              ],
            ),
          ],
        ),
      ),
      if (app.settings.plexReady)
        ConsolePanel(
          title: 'Account',
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Signed in to ${s.plexServerName.isEmpty ? (app.server?.name ?? 'Plex') : s.plexServerName}. Signing out forgets the Plex token on this ${isTv ? 'device' : 'computer'}.',
                  style: ConsoleText.body.copyWith(color: c.text200),
                ),
              ),
              const SizedBox(width: Space.space3),
              ConsoleButton(label: 'Sign Out', icon: LucideIcons.logOut, onPressed: _confirmSignOut),
            ],
          ),
        ),
    ],
  ];

  Future<void> _confirmSignOut() async {
    final app = AppScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of Plex?'),
        content: const Text('You can sign in again any time from this page.'),
        actions: [
          TextButton(autofocus: isTv, onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign Out')),
        ],
      ),
    );
    if (ok == true) await app.signOut();
  }

  void _set(AppState app, PlaybackPrefs p) => app.setPlayback(p);

  List<Widget> _playback(AppState app, PlaybackPrefs p) {
    final qualities = [for (final q in streamingQualities) (q.kbps, q.isOriginal ? 'Original (Direct Play)' : q.label)];
    return [
      ConsolePanel(
        title: 'Quality',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Row(
              label: 'On Your Network',
              help: app.plexIsLocal ? 'In use now: the server is on this network.' : 'For when the server is on the same network.',
              control: ConsoleDropdown<int>(
                options: qualities,
                value: p.localQuality,
                onChanged: (v) => _set(app, p.copyWith(localQuality: v)),
              ),
            ),
            _Row(
              label: 'Away From Home',
              help: app.plexIsLocal ? 'For when the server is reached over the internet.' : 'In use now: the server is reached over the internet.',
              control: ConsoleDropdown<int>(
                options: qualities,
                value: p.remoteQuality,
                onChanged: (v) => _set(app, p.copyWith(remoteQuality: v)),
              ),
            ),
            _Row(
              label: 'Allow Direct Play',
              help: 'Play the file untouched when the player can, which is almost always.',
              control: ConsoleSwitch(
                value: p.allowDirectPlay,
                onChanged: (v) => _set(app, p.copyWith(allowDirectPlay: v)),
              ),
            ),
            _Row(
              label: 'Allow Direct Stream',
              help: 'When converting, keep the original video if only the audio or container needs work.',
              control: ConsoleSwitch(
                value: p.allowDirectStream,
                onChanged: (v) => _set(app, p.copyWith(allowDirectStream: v)),
              ),
              last: true,
            ),
          ],
        ),
      ),
      ConsolePanel(
        title: 'Skipping',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Row(
              label: 'Skip Back',
              control: ConsoleDropdown<int>(
                width: 140,
                options: const [(5, '5 seconds'), (10, '10 seconds'), (15, '15 seconds'), (30, '30 seconds')],
                value: p.skipBack,
                onChanged: (v) => _set(app, p.copyWith(skipBack: v)),
              ),
            ),
            _Row(
              label: 'Skip Forward',
              control: ConsoleDropdown<int>(
                width: 140,
                options: const [(10, '10 seconds'), (15, '15 seconds'), (30, '30 seconds'), (60, '1 minute')],
                value: p.skipForward,
                onChanged: (v) => _set(app, p.copyWith(skipForward: v)),
              ),
            ),
            _Row(
              label: 'Skip Intro',
              help: 'Uses the intro markers your Plex server finds in TV episodes.',
              control: ConsoleSegmented<SkipMode>(
                options: [for (final m in SkipMode.values) (m, m.label)],
                value: p.skipIntro,
                onChanged: (v) => _set(app, p.copyWith(skipIntro: v)),
              ),
            ),
            _Row(
              label: 'Skip Credits',
              help: 'At the final credits of an episode you get Up Next instead.',
              control: ConsoleSegmented<SkipMode>(
                options: [for (final m in SkipMode.values) (m, m.label)],
                value: p.skipCredits,
                onChanged: (v) => _set(app, p.copyWith(skipCredits: v)),
              ),
              last: true,
            ),
          ],
        ),
      ),
      ConsolePanel(
        title: 'Partly Watched',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Row(
              label: 'When You Come Back',
              help: 'Playing something you stopped part-way through. The Resume and Play from Start buttons on a title’s page always do what they say.',
              control: ConsoleSegmented<ResumeMode>(
                options: [for (final m in ResumeMode.values) (m, m.label)],
                value: p.resumeMode,
                onChanged: (v) => _set(app, p.copyWith(resumeMode: v)),
              ),
              last: true,
            ),
          ],
        ),
      ),
      ConsolePanel(
        title: 'Up Next',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Row(
              label: 'Play the Next Episode',
              help: 'Starts the next episode on its own when the credits roll.',
              control: ConsoleSwitch(
                value: p.autoPlayNext,
                onChanged: (v) => _set(app, p.copyWith(autoPlayNext: v)),
              ),
            ),
            _Row(
              label: 'Countdown',
              control: ConsoleDropdown<int>(
                width: 140,
                options: const [(5, '5 seconds'), (10, '10 seconds'), (15, '15 seconds'), (30, '30 seconds')],
                value: p.countdown,
                onChanged: (v) => _set(app, p.copyWith(countdown: v)),
              ),
              last: true,
            ),
          ],
        ),
      ),
      ConsolePanel(
        title: 'While Paused',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Row(
              label: 'Pause Screen',
              help: 'After a few seconds paused, show the title, its story and who’s in it.',
              control: ConsoleSwitch(
                value: app.settings.pauseScreen,
                onChanged: (v) => app.tweak((s) => s.copyWith(pauseScreen: v)),
              ),
              last: true,
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _audioSubs(AppState app, PlaybackPrefs p) {
    final langs = [('', 'Same as the file'), for (final (code, name) in playbackLanguages) (code, name)];
    return [
      ConsolePanel(
        title: 'Languages',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Row(
              label: 'Audio Language',
              help: 'Picked when a file has it. Commentary tracks are passed over.',
              control: ConsoleDropdown<String>(
                options: langs,
                value: p.audioLanguage,
                onChanged: (v) => _set(app, p.copyWith(audioLanguage: v)),
              ),
            ),
            _Row(
              label: 'Subtitles',
              help: switch (p.subtitleMode) {
                SubtitleMode.plex => 'Follows the choice saved on your Plex server for each file.',
                SubtitleMode.off => 'Never on unless you pick a track while watching.',
                SubtitleMode.forced => 'Only signs and lines in another language.',
                SubtitleMode.foreign => 'On when the audio is not in your subtitle language, otherwise forced only.',
                SubtitleMode.always => 'Always on in your subtitle language.',
              },
              control: ConsoleDropdown<SubtitleMode>(
                options: [for (final m in SubtitleMode.values) (m, m.label)],
                value: p.subtitleMode,
                onChanged: (v) => _set(app, p.copyWith(subtitleMode: v)),
              ),
            ),
            _Row(
              label: 'Subtitle Language',
              control: ConsoleDropdown<String>(
                options: [('', 'Same as the audio'), ...langs.skip(1)],
                value: p.subtitleLanguage,
                onChanged: (v) => _set(app, p.copyWith(subtitleLanguage: v)),
              ),
            ),
            _Row(
              label: 'Anime Audio',
              help: 'For shows and films tagged Anime, or in a library named Anime. English picks the dub when there is one.',
              control: ConsoleDropdown<String>(
                options: [('', 'Same as Audio Language'), ...langs.skip(1)],
                value: p.animeAudio,
                onChanged: (v) => _set(app, p.copyWith(animeAudio: v)),
              ),
            ),
            _Row(
              label: 'Remember Per Show',
              help: p.showTracks.isEmpty
                  ? 'Audio and subtitles you pick while watching an episode are used for the rest of that show.'
                  : 'Audio and subtitles you pick while watching an episode are used for the rest of that show. Saved for ${p.showTracks.length} ${p.showTracks.length == 1 ? 'show' : 'shows'}.',
              control: ConsoleButton(
                label: 'Forget All',
                kind: ButtonKind.tertiary,
                onPressed: p.showTracks.isEmpty ? null : () => _set(app, p.copyWith(showTracks: const {})),
              ),
              last: true,
            ),
          ],
        ),
      ),
      ConsolePanel(
        title: 'Subtitle Style',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Row(
              label: 'Size',
              control: ConsoleSegmented<int>(
                options: const [(75, 'Small'), (100, 'Normal'), (125, 'Large'), (150, 'Huge')],
                value: p.subtitleSize,
                onChanged: (v) => _set(app, p.copyWith(subtitleSize: v)),
              ),
            ),
            _Row(
              label: 'Colour',
              help: "Title's Colour matches each film's artwork.",
              control: ConsoleDropdown<String>(
                width: 180,
                options: const [('white', 'White'), ('yellow', 'Yellow'), ('cyan', 'Cyan'), ('green', 'Green'), ('pink', 'Pink'), ('art', "Title's Colour")],
                value: p.subtitleColor,
                onChanged: (v) => _set(app, p.copyWith(subtitleColor: v)),
              ),
            ),
            _Row(
              label: 'Background',
              control: ConsoleSegmented<String>(
                options: const [('outline', 'Outline'), ('shadow', 'Shadow'), ('box', 'Box')],
                value: p.subtitleBackground,
                onChanged: (v) => _set(app, p.copyWith(subtitleBackground: v)),
              ),
            ),
            _Row(
              label: 'Height',
              control: ConsoleDropdown<int>(
                width: 140,
                options: const [(0, 'Bottom'), (4, 'Raised 4%'), (8, 'Raised 8%'), (12, 'Raised 12%'), (20, 'Raised 20%')],
                value: const [0, 4, 8, 12, 20].contains(p.subtitleRaise) ? p.subtitleRaise : 0,
                onChanged: (v) => _set(app, p.copyWith(subtitleRaise: v)),
              ),
            ),
            _Row(
              label: 'Restyle Styled Subtitles',
              help: 'Apply this style to anime-style (ASS) subtitles too, replacing their own fonts and colours.',
              control: ConsoleSwitch(
                value: p.restyleSubtitles,
                onChanged: (v) => _set(app, p.copyWith(restyleSubtitles: v)),
              ),
              last: true,
            ),
          ],
        ),
      ),
      ConsolePanel(
        title: 'Audio',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Row(
              label: 'Passthrough',
              help: 'Sends Dolby and DTS untouched to an AV receiver or soundbar over HDMI or optical. Leave off for speakers and headphones.',
              control: ConsoleSwitch(
                value: p.passthrough,
                onChanged: (v) => _set(app, p.copyWith(passthrough: v)),
              ),
            ),
            _Row(
              label: 'Speakers',
              control: ConsoleDropdown<String>(
                width: 180,
                options: const [('auto', 'Automatic'), ('stereo', 'Stereo'), ('5.1', '5.1 Surround'), ('7.1', '7.1 Surround')],
                value: p.audioChannels,
                onChanged: (v) => _set(app, p.copyWith(audioChannels: v)),
              ),
            ),
            _Row(
              label: 'Night Mode',
              help: 'Evens out loud effects and quiet dialogue.',
              control: ConsoleSwitch(
                value: p.nightMode,
                onChanged: (v) => _set(app, p.copyWith(nightMode: v)),
              ),
            ),
            _Row(
              label: 'Volume Boost',
              help: 'Lets the volume go up to 200% for quiet mixes.',
              control: ConsoleSwitch(
                value: p.volumeBoost,
                onChanged: (v) => _set(app, p.copyWith(volumeBoost: v)),
              ),
              last: true,
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _video(AppState app, PlaybackPrefs p) => [
    ConsolePanel(
      title: 'Video',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row(
            label: 'Hardware Decoding',
            help: 'Uses the graphics card to decode, which is cooler and quieter. Turn off if you see green frames or glitches.',
            control: ConsoleDropdown<String>(
              width: 200,
              options: const [('auto-safe', 'On'), ('auto-copy', 'On (Compatible)'), ('no', 'Off')],
              value: p.hwdec,
              onChanged: (v) => _set(app, p.copyWith(hwdec: v)),
            ),
          ),
          if (Platform.isAndroid)
            _Row(
              label: 'Video Output',
              help: isLowMemoryTv
                  ? 'Video Plane puts the picture on its own layer behind Liquiflux, as Plex\'s app does, which lets this TV play 4K. Direct draws it inside Liquiflux. Both leave subtitles to Liquiflux, and picture-based ones are burned in by the server. Enhanced renders with mpv for HDR tone mapping and the picture options below, but 4K is too much for this TV that way. Applies to the next title.'
                  : 'Direct has the TV draw the picture itself, which uses far less memory. Subtitles are then drawn by Liquiflux, and picture-based ones are burned in by the server. Enhanced renders with mpv for HDR tone mapping and the picture options below. Applies to the next title.',
              control: ConsoleDropdown<String>(
                width: 200,
                options: [('auto', isLowMemoryTv ? 'Auto (Video Plane)' : 'Auto (Enhanced)'), if (isLowMemoryTv) ('plane', 'Video Plane'), ('direct', 'Direct'), ('mpv', 'Enhanced')],
                // Video Plane needs a 32-bit TV's window; elsewhere it runs as Direct.
                value: !isLowMemoryTv && p.videoOutput == 'plane' ? 'direct' : p.videoOutput,
                onChanged: (v) => _set(app, p.copyWith(videoOutput: v)),
              ),
            ),
          _Row(
            label: 'Picture Size',
            control: ConsoleSegmented<String>(
              options: const [('fit', 'Fit'), ('fill', 'Fill'), ('stretch', 'Stretch')],
              value: p.aspect,
              onChanged: (v) => _set(app, p.copyWith(aspect: v)),
            ),
          ),
          _Row(
            label: 'Deinterlace',
            help: 'For old TV recordings with combing on motion.',
            control: ConsoleSwitch(
              value: p.deinterlace,
              onChanged: (v) => _set(app, p.copyWith(deinterlace: v)),
            ),
          ),
          _Row(
            label: 'High Quality Scaling',
            help: 'Sharper upscaling of lower resolution video. Needs a capable graphics card.',
            control: ConsoleSwitch(
              value: p.highQualityScaling,
              onChanged: (v) => _set(app, p.copyWith(highQualityScaling: v)),
            ),
          ),
          _Row(
            label: 'Debanding',
            help: 'Smooths the steps in skies and dark gradients of heavily compressed video.',
            control: ConsoleSwitch(
              value: p.deband,
              onChanged: (v) => _set(app, p.copyWith(deband: v)),
            ),
            last: true,
          ),
        ],
      ),
    ),
  ];

  List<Widget> _notifications(AppState app, Settings s) => [
    ConsolePanel(
      title: 'Ready to Watch',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row(
            label: 'When a Request Is Ready',
            help: isTv
                ? 'A card in the app with a Play button.'
                : isWindows
                ? 'A card in the app, or a Windows notification with a Play button when Liquiflux is in the background.'
                : 'A card in the app, or a desktop notification with a Play button when Liquiflux is in the background.',
            control: ConsoleSegmented<String>(
              options: const [('mine', 'My Requests'), ('everyone', 'Everyone’s'), ('off', 'Off')],
              value: s.notifyReady,
              onChanged: (v) => app.tweak((s) => s.copyWith(notifyReady: v)),
            ),
            last: true,
          ),
        ],
      ),
    ),
  ];

  List<Widget> _appearance(AppState app, Settings s) => [
    ConsolePanel(
      title: 'Appearance',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Theme', style: ConsoleText.caption.copyWith(color: context.c.text200)),
          const SizedBox(height: Space.space1),
          ConsoleSegmented<String>(options: const [('dark', 'Dark'), ('light', 'Light')], value: s.theme, onChanged: app.setTheme),
          const SizedBox(height: Space.space4),
          Text('Surfaces', style: ConsoleText.caption.copyWith(color: context.c.text200)),
          const SizedBox(height: Space.space1),
          ConsoleSegmented<bool>(options: const [(true, 'Frosted Glass'), (false, 'Flat')], value: s.glass, onChanged: app.setGlass),
          const SizedBox(height: Space.space1),
          Text('Flat is lighter on older graphics cards.', style: ConsoleText.caption.copyWith(color: context.c.text300)),
          const SizedBox(height: Space.space4),
          Text('Home Trailers', style: ConsoleText.caption.copyWith(color: context.c.text200)),
          const SizedBox(height: Space.space1),
          homeTrailersSupported
              ? ConsoleSegmented<bool>(options: const [(true, 'Play'), (false, 'Off')], value: s.homeTrailers, onChanged: app.setHomeTrailers)
              : ConsoleSegmented<bool>(options: const [(true, 'Spotlight Only'), (false, 'Off')], value: s.spotlightTrailers, onChanged: app.setSpotlightTrailers),
          const SizedBox(height: Space.space1),
          Text(
            homeTrailersSupported
                ? 'Muted trailer clips behind the Home spotlight and the title you point at.'
                : 'This device runs 32-bit Android, which leaves little memory for a second video player. Spotlight Only plays a trailer just while you’re on the spotlight’s buttons, and frees its player as soon as you move away. Experimental.',
            style: ConsoleText.caption.copyWith(color: context.c.text300),
          ),
        ],
      ),
    ),
    ConsolePanel(
      title: 'Spoilers',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row(
            label: 'Blur Episode Pictures',
            help: 'Stills from episodes you haven’t watched yet, in episode lists, Continue Watching and Up Next.',
            control: ConsoleSwitch(
              value: s.spoilers.images,
              onChanged: (v) => app.tweak((s) => s.copyWith(spoilers: s.spoilers.copyWith(images: v))),
            ),
          ),
          _Row(
            label: 'Hide Episode Stories',
            help: 'The synopsis of an episode you haven’t watched. Select it to read it anyway.',
            control: ConsoleSwitch(
              value: s.spoilers.summaries,
              onChanged: (v) => app.tweak((s) => s.copyWith(spoilers: s.spoilers.copyWith(summaries: v))),
            ),
          ),
          _Row(
            label: 'Hide Episode Names',
            help: 'Shows “Episode 4” until you’ve watched it, for names that give the twist away.',
            control: ConsoleSwitch(
              value: s.spoilers.titles,
              onChanged: (v) => app.tweak((s) => s.copyWith(spoilers: s.spoilers.copyWith(titles: v))),
            ),
            last: true,
          ),
        ],
      ),
    ),
  ];

  List<Widget> _advanced(AppState app, ConsoleColors c, PlaybackPrefs p) => [
    UpdatesPanel(updater: app.updater, start: widget.update),
    ConsolePanel(
      title: 'mpv Options',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsField(
            label: 'Extra Options',
            controller: _mpv,
            mono: true,
            lines: 5,
            hint: 'demuxer-max-bytes=400MiB\ntone-mapping=bt.2446a',
            help: 'One name=value per line, applied when playback starts. Lines starting with # are ignored. See mpv.io/manual for names.',
          ),
          const SizedBox(height: Space.space3),
          Wrap(
            spacing: Space.space3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConsoleButton(
                label: 'Save',
                kind: ButtonKind.primary,
                onPressed: () async {
                  await app.setPlayback(p.copyWith(mpvOptions: _mpv.text.trim()));
                  if (mounted) setState(() => _advancedMsg = 'Saved');
                },
              ),
              if (_advancedMsg != null) StatusDot(_advancedMsg!, tone: Tone.success),
            ],
          ),
          if (mpvOptions(p.mpvOptions).blocked case final blocked when blocked.isNotEmpty) ...[
            const SizedBox(height: Space.space3),
            _Warning('Not applied, since only known-safe picture, audio, subtitle and cache options can be set here: ${blocked.join(', ')}.'),
          ],
        ],
      ),
    ),
    ConsolePanel(
      title: 'Maintenance',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row(
            label: 'Clear Image Cache',
            help: 'Reloads posters and artwork, and their colours.',
            control: ConsoleButton(
              label: 'Clear',
              onPressed: () {
                PaintingBinding.instance.imageCache
                  ..clear()
                  ..clearLiveImages();
                ArtColor.clear();
                setState(() => _advancedMsg = 'Image cache cleared');
              },
            ),
          ),
          _Row(
            label: 'Reset Playback Settings',
            help: 'Puts quality, languages, subtitles, audio and video back to their defaults.',
            control: ConsoleButton(
              label: 'Reset',
              onPressed: () async {
                await app.setPlayback(const PlaybackPrefs());
                _mpv.clear();
                if (mounted) setState(() => _advancedMsg = 'Playback settings reset');
              },
            ),
            last: true,
          ),
        ],
      ),
    ),
    // The player's keys are a keyboard's; a remote has its own.
    if (!isTv)
      ConsolePanel(
        title: 'Keyboard Shortcuts',
        child: Column(
          children: [
            for (final (keys, what) in const [
              ('Space or K', 'Play or pause'),
              ('← → or J L', 'Skip back or forward'),
              ('↑ ↓', 'Volume'),
              ('M', 'Mute'),
              ('F or double click', 'Full screen'),
              ('C', 'Next subtitle track'),
              ('A', 'Next audio track'),
              ('S', 'Skip intro or credits, or play Up Next'),
              ('N  /  P', 'Next or previous episode'),
              ('[  /  ]', 'Slower or faster'),
              ('0 to 9', 'Jump to 0% to 90%'),
              ('I', 'Playback info'),
              ('Esc', 'Close panel, leave full screen, then exit'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 170,
                      child: Text(keys, style: ConsoleText.data.copyWith(color: c.text100)),
                    ),
                    Expanded(
                      child: Text(what, style: ConsoleText.body.copyWith(color: c.text200)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.space1),
      child: Text('$appName $appVersion', style: ConsoleText.caption.copyWith(color: c.text300)),
    ),
  ];
}

enum _Tab {
  general('Servers'),
  playback('Playback'),
  audio('Audio & Subtitles'),
  video('Video'),
  appearance('Appearance'),
  notifications('Notifications'),
  advanced('Advanced');

  const _Tab(this.label);
  final String label;
}

/// A setting: name and help on the left, its control on the right.
/// A caution in the warning colour that wraps onto as many lines as it needs.
class _Warning extends StatelessWidget {
  const _Warning(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(LucideIcons.shieldAlert, size: 16, color: context.c.warning),
      ),
      const SizedBox(width: Space.space2),
      Expanded(
        child: Text(text, style: ConsoleText.small.copyWith(color: context.c.text100)),
      ),
    ],
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.control, this.help, this.last = false});
  final String label;
  final String? help;
  final Widget control;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.space3),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.border100)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: ConsoleText.bodyStrong.copyWith(color: c.text100)),
                if (help != null) Text(help!, style: ConsoleText.caption.copyWith(color: c.text300)),
              ],
            ),
          ),
          const SizedBox(width: Space.space4),
          control,
        ],
      ),
    );
  }
}
