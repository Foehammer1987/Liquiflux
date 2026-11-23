import 'dart:async';
import 'dart:io' show Platform;

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../app_info.dart';
import '../../platform.dart';
import '../../services/display_match.dart';
import '../../services/links.dart';
import '../../services/settings_store.dart';
import '../../state/app_state.dart';
import '../../state/scope.dart';
import '../common.dart';
import '../nav.dart';
import '../player/player_dock.dart';
import '../profiles.dart';
import '../settings/focus_handle.dart';
import '../settings/licenses_view.dart';
import '../settings/plex_link_code.dart';
import '../settings/qr_view.dart';
import '../settings/settings_field.dart';
import '../settings/tracking_panel.dart';
import '../settings/updates_panel.dart';
import '../shell.dart' show isWindows;
import '../tv_focus.dart';

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
  final _riptide = TextEditingController();
  String? _discoveryMsg;
  String? _riptideMsg;
  bool _savingRiptide = false;
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

  // A TV's layout: the categories down the left, each with its own focus node so Left from
  // the settings can come back to the one that's open, and the settings beside them.
  final _categoryNodes = {for (final t in _Tab.values) t: FocusNode(debugLabel: 'Settings category ${t.label}')};
  final _paneFocus = FocusHandle();
  final _paneScroll = ScrollController();

  /// The setting that had focus when Left went back to the categories.
  FocusNode? _leftFrom;

  late _Tab _tab = widget.update ? _Tab.advanced : _Tab.general;
  final _mpv = TextEditingController();

  bool _seeded = false;

  @override
  void dispose() {
    for (final c in [_plexUrl, _plexToken, _seerrUrl, _seerrKey, _trakt, _region, _riptide, _mpv]) {
      c.dispose();
    }
    _tick?.cancel();
    for (final h in [_signInFocus, _linkFocus, _serverFocus, _paneFocus]) {
      h.dispose();
    }
    for (final n in _categoryNodes.values) {
      n.dispose();
    }
    _paneScroll.dispose();
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
    if (_riptide.text.isEmpty) _riptide.text = s.riptideUrl;
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
  /// so the Riptide server can check the account with plex.tv.
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
    // A new sign-in starts as the account that signed in, not whichever Home user was in use.
    app.forgetHome();
    await app.update(app.settings.backToOwner().copyWith(plexUrl: url, plexToken: s.accessToken, plexAccountToken: _accountToken, plexServerName: s.name, plexMachineId: s.machineIdentifier));
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
    if (pasted.isNotEmpty) app.forgetHome();
    await app.update((pasted.isNotEmpty ? app.settings.backToOwner() : app.settings).copyWith(plexUrl: url, plexToken: pasted.isNotEmpty ? pasted : null, plexAccountToken: pasted.isNotEmpty ? '' : null, plexMachineId: fresh ? '' : null));
    _plexToken.clear();
    if (!mounted) return;
    setState(() {
      _savingPlex = false;
      _plexStatus = app.plexConn == Conn.ok ? ('Connected to ${app.server?.name} (${app.server?.shortVersion})', Tone.success) : (app.plexError ?? 'Could not connect', Tone.danger);
    });
  }

  /// Turns Seerr on or off. Off keeps the address and sign-in for next time, but nothing
  /// asks Seerr anything and every row, page and button it adds goes away.
  Future<void> _setSeerr(AppState app, bool on) async {
    setState(() => _seerrMsg = null);
    await app.update(app.settings.copyWith(seerrEnabled: on));
  }

  Future<void> _saveRiptide() async {
    final app = AppScope.read(context);
    final riptide = _riptide.text.trim();
    if (riptide.isNotEmpty && !isWebUrl(riptide)) {
      setState(() => _riptideMsg = 'The Riptide server needs an http:// or https:// address');
      return;
    }
    setState(() => _savingRiptide = true);
    await app.setRiptide(url: riptide);
    var msg = riptide.isEmpty ? 'Saved. Add an address to use it' : 'Saved';
    final server = riptide.isEmpty || app.plex == null ? null : RiptideServer.shared(riptide, app.settings.riptideSignInToken);
    if (server != null) {
      if (mounted) setState(() => _riptideMsg = 'Checking Riptide...');
      try {
        msg = await server.check() ? 'Saved, signed in to Riptide' : (sendsCredentialsInClear(riptide) ? 'Saved, but Riptide outside your network needs https' : 'Saved (plain file server)');
      } on ApiException catch (e) {
        msg = 'Saved, but Riptide: ${e.message}';
      }
    }
    if (mounted) {
      setState(() {
        _savingRiptide = false;
        _riptideMsg = msg;
      });
    }
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
    if (isTv && !widget.welcome) return _tvLayout(app, c, s);
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
                    Text('Sign in with Plex to get started. Add-ons like Seerr can be turned on in Settings later.', style: ConsoleText.body.copyWith(color: c.text200)),
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
          ConsoleSegmented<_Tab>(options: [for (final t in _Tab.values) if (t != _Tab.notifications || s.seerrEnabled) (t, t.label)], value: _tab, onChanged: (t) => setState(() => _tab = t)),
        ],
        if (widget.welcome)
          ..._general(app, c, s, welcome: true)
        else
          ..._tabContent(app, c, s),
      ],
    );
  }

  List<Widget> _tabContent(AppState app, ConsoleColors c, Settings s) => switch (_tab) {
    _Tab.general => _general(app, c, s),
    _Tab.playback => _playback(app, s.playback),
    _Tab.audio => _audioSubs(app, s.playback),
    _Tab.video => _video(app, s.playback),
    _Tab.appearance => _appearance(app, s),
    _Tab.notifications => s.seerrEnabled ? _notifications(app, s) : const [],
    _Tab.tracking => [TrackingPanels(app: app)],
    _Tab.advanced => _advanced(app, c, s.playback),
  };

  /// Settings on a TV: the categories in a column on the left and the open one's settings in
  /// a single column beside it, so the remote only ever moves along one line. Up and Down
  /// walk the categories (the one in focus opens) or the settings; Right or Select enters
  /// the settings, Left comes back to the category, and Left again opens the rail.
  ///
  /// The tabs across the top wrapped onto two lines on a TV, and the settings' controls sat
  /// at the far right in different widths, so Down hopped from line to line and passed over
  /// most of them.
  Widget _tvLayout(AppState app, ConsoleColors c, Settings s) {
    final tabs = [
      for (final t in _Tab.values)
        if (t != _Tab.notifications || s.seerrEnabled) t,
    ];
    // Seerr was turned off while its Notifications were open.
    final open = tabs.contains(_tab) ? _tab : _Tab.general;
    // Back to the setting Left came from, or the first one.
    void enter() {
      final back = _leftFrom;
      back != null && _paneFocus.holds(back) ? back.requestFocus() : _paneFocus.focusNow();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.space6, Space.space6, Space.space6, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 248,
            child: FocusPanel(
              // Left and Up leave the column as they leave any page: to the rail, to search.
              onEdge: (d) => switch (d) {
                TraversalDirection.right => enter(),
                TraversalDirection.down => null,
                _ => Actions.maybeInvoke(context, DirectionalFocusIntent(d)),
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: Space.space3, bottom: Space.space4),
                    child: Text(
                      'Settings',
                      style: ConsoleText.display.copyWith(fontSize: 32, fontWeight: FontWeight.w800, color: c.text100),
                    ),
                  ),
                  for (final t in tabs)
                    _Category(
                      label: t.label,
                      open: t == open,
                      autofocus: t == open,
                      focusNode: _categoryNodes[t]!,
                      onFocus: () {
                        if (_tab == t) return;
                        setState(() => _tab = t);
                        _leftFrom = null;
                        if (_paneScroll.hasClients) _paneScroll.jumpTo(0);
                      },
                      onTap: enter,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: Space.space6),
          Expanded(
            child: FocusPanel(
              onEdge: (d) {
                if (d != TraversalDirection.left) return;
                _leftFrom = FocusManager.instance.primaryFocus;
                _categoryNodes[open]!.requestFocus();
              },
              child: _paneFocus.wrap(
                // The settings take focus without the page gliding each one to the middle:
                // it stays still until focus nears its top or bottom ([FocusReveal]).
                FocusTraversalGroup(
                  policy: TvTraversalPolicy(requestFocusCallback: _focusOnly),
                  child: FocusReveal(
                    child: PageBody(
                      maxWidth: 880,
                      controller: _paneScroll,
                      padding: const EdgeInsets.only(bottom: Space.space6),
                      children: (_tab == open ? _tabContent(app, c, s) : _general(app, c, s)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void _focusOnly(FocusNode node, {ScrollPositionAlignmentPolicy? alignmentPolicy, double? alignment, Duration? duration, Curve? curve}) => node.requestFocus();

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
              _wrap(
                spacing: Space.space2,
                [
                  ConsoleButton(
                    label: _signingIn ? 'Waiting for Plex' : (s.plexReady ? 'Sign In Again' : 'Sign In with Plex'),
                    kind: ButtonKind.primary,
                    // A remote needs focus somewhere to start; on a computer a focus ring on
                    // a page nobody has typed on yet looks like a glitch (Tab still gets here).
                    autofocus: widget.welcome && !isDesktop,
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
                  : isTizen
                  ? "This TV's secure storage couldn't be used to keep sign-ins in, so $appName only remembers them until it closes (they are never saved in plain text). "
                        'Turning the TV off and on and signing in again usually fixes it.'
                  : Platform.isLinux
                  ? 'This computer has no keyring to keep sign-ins in, so $appName only remembers them until it closes (they are never saved in plain text). '
                        'Install and unlock GNOME Keyring or KWallet, then sign in again.'
                  : "$appName couldn't save your sign-in in this computer's secure storage, so it only remembers it until it closes (it is never saved in plain text). "
                        'Quitting and opening $appName again, then signing in again, usually fixes it.',
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
            _wrap([ConsoleButton(label: _savingPlex ? 'Saving' : 'Save and Test', kind: ButtonKind.primary, onPressed: _unlessBusy(_savingPlex, _saveManualPlex))]),
          ],
        ],
      ),
    ),
    if (!welcome && (app.homeList?.length ?? 0) > 1)
      ConsolePanel(
        title: 'Plex Home',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (app.profile != null) ...[ProfileAvatar(user: app.profile, size: 40), const SizedBox(width: Space.space3)],
                Expanded(
                  child: Text(
                    app.profile == null ? 'Switch between the people in your Plex Home.' : 'Watching as ${app.profile!.name}. Each person has their own Continue Watching, watched marks, thumbs and Trakt/AniList sign-ins.',
                    style: ConsoleText.body.copyWith(color: c.text200),
                  ),
                ),
                const SizedBox(width: Space.space3),
                ConsoleButton(
                  label: 'Switch Profile',
                  icon: LucideIcons.usersRound,
                  onPressed: () async {
                    final nav = ShellNav.of(context);
                    if (await showProfiles(context)) nav.go(const HomeDest());
                  },
                ),
              ],
            ),
            const SizedBox(height: Space.space3),
            _Row(
              label: "Ask Who's Watching",
              help: 'Show the profiles each time $appName opens.',
              control: ConsoleSwitch(value: s.askProfile, onChanged: (v) => app.tweak((x) => x.copyWith(askProfile: v))),
              last: true,
            ),
          ],
        ),
      ),
    if (!welcome)
      ConsolePanel(
        title: 'Seerr',
        meta: app.seerrConn == Conn.ok ? StatusDot(app.seerrUser ?? 'Connected', tone: Tone.success, style: ConsoleText.small) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Row(
              label: 'Use Seerr',
              help: "Request titles that aren't in your library, and see Trending and suggestions. Needs your own Seerr, Overseerr or Jellyseerr server.",
              control: ConsoleSwitch(value: s.seerrEnabled, onChanged: (v) => _setSeerr(app, v)),
              last: !s.seerrEnabled,
            ),
            if (s.seerrEnabled) ...[
              const SizedBox(height: Space.space3),
              SettingsField(label: 'Seerr Address', controller: _seerrUrl, mono: true, hint: 'http://seerr.local:5055', help: 'Works with Seerr, Overseerr and Jellyseerr.'),
              const SizedBox(height: Space.space3),
              ..._choice(
                label: 'Sign In',
                help: _usePlexLogin
                    ? 'Requests are filed under your own Seerr user and follow its approval rules.'
                    : 'Requests are filed under the API key owner, usually the admin, so they are approved automatically.',
                control: ConsoleSegmented<bool>(options: const [(true, 'My Plex Account'), (false, 'API Key')], value: _usePlexLogin, onChanged: (v) => setState(() => _usePlexLogin = v)),
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
              _wrap(
                [
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
          ],
        ),
      ),
    if (!welcome) ...[
      // Trakt charts and the streaming region feed Trending, which comes from Seerr.
      if (s.seerrEnabled)
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
            _wrap(
              [
                ConsoleButton(
                  label: 'Save',
                  kind: ButtonKind.primary,
                  onPressed: () async {
                    final region = _region.text.trim().toUpperCase();
                    await app.setDiscovery(traktClientId: _trakt.text.trim(), region: RegExp(r'^[A-Z]{2}$').hasMatch(region) ? region : 'US');
                    if (mounted) setState(() => _discoveryMsg = 'Saved');
                  },
                ),
                if (_discoveryMsg != null) StatusDot(_discoveryMsg!, tone: Tone.success),
              ],
            ),
          ],
        ),
      ),
      ConsolePanel(
        title: 'Riptide Server',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Row(
              label: 'Use a Riptide Server',
              help: "Pausing shows who's in the scene. Needs your own Liquiflux Riptide server. Without one, Riptide shows the whole cast from Plex.",
              control: ConsoleSwitch(
                value: s.riptideEnabled,
                onChanged: (v) {
                  setState(() => _riptideMsg = null);
                  app.setRiptide(enabled: v);
                },
              ),
              last: !s.riptideEnabled,
            ),
            if (s.riptideEnabled) ...[
              const SizedBox(height: Space.space3),
              SettingsField(
                label: 'Riptide Server Address',
                controller: _riptide,
                mono: true,
                hint: 'http://homeserver:8089',
                help: 'At home (http://homeserver:8089) or through Cloudflare Tunnel (https://...). Liquiflux signs in with your Plex account.',
              ),
              const SizedBox(height: Space.space3),
              _wrap(
                [
                  ConsoleButton(label: _savingRiptide ? 'Saving' : 'Save and Test', kind: ButtonKind.primary, onPressed: _unlessBusy(_savingRiptide, _saveRiptide)),
                  if (_riptideMsg != null) StatusDot(_riptideMsg!, tone: _riptideMsg!.startsWith('Saved') && !_riptideMsg!.contains(' but ') ? Tone.success : Tone.warning),
                ],
              ),
            ],
          ],
        ),
      ),
      if (app.settings.plexReady)
        ConsolePanel(
          title: 'Account',
          child: isTv
              ? TvSettingRow(
                  label: 'Sign Out',
                  help: 'Signed in to ${s.plexServerName.isEmpty ? (app.server?.name ?? 'Plex') : s.plexServerName}. Signing out forgets the Plex token on this device.',
                  control: ConsoleButton(label: 'Sign Out', onPressed: _confirmSignOut),
                )
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Signed in to ${s.plexServerName.isEmpty ? (app.server?.name ?? 'Plex') : s.plexServerName}. Signing out forgets the Plex token on this computer.',
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

  /// Buttons side by side with their status beside them; on a TV (past the welcome page), each
  /// button a row of its own in the settings' column, and the status on a line below.
  Widget _wrap(List<Widget> children, {double spacing = Space.space3}) => isTv && !widget.welcome
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final w in children)
              w is ConsoleButton
                  ? TvSettingRow(label: w.label, control: w)
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.space4, vertical: Space.space1),
                      child: w,
                    ),
          ],
        )
      : Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: spacing, runSpacing: Space.space2, children: children);

  /// A choice with its name above it and its help below, as Appearance lays them out; on a
  /// TV, a row like every other setting, so it sits in the same column.
  List<Widget> _choice({required String label, String? help, required Widget control}) => isTv
      ? [_Row(label: label, help: help, control: control, last: true)]
      : [
          Text(label, style: ConsoleText.caption.copyWith(color: context.c.text200)),
          const SizedBox(height: Space.space1),
          control,
          if (help != null) ...[const SizedBox(height: Space.space1), Text(help, style: ConsoleText.caption.copyWith(color: context.c.text300))],
        ];

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
              last: isTizen,
            ),
            // The app draws every subtitle as plain text on a Samsung TV, so there's no ASS styling to replace.
            if (!isTizen) _Row(
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
      // Each of these is an mpv setting; Samsung's player has none of them.
      if (!isTizen) ConsolePanel(
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
          // Samsung's player always decodes in hardware and has no mpv picture options: only
          // Picture Size applies there.
          if (!isTizen) _Row(
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
          if (DisplayMatch.supported)
            _Row(
              label: 'Match Frame Rate',
              help: DisplayMatch.resolutionSupported
                  ? 'Switches the TV to the video\'s frame rate while it plays, so films at 24 frames a second move smoothly instead of juddering, and back afterwards. With resolution, 1080p titles also play at 1080p for the TV to upscale. The screen goes dark for a moment as it switches.'
                  : 'Switches this monitor to the video\'s frame rate while it plays (24 Hz for most films, if the monitor offers it), and back afterwards. The screen may go dark for a moment as it switches.',
              control: ConsoleDropdown<String>(
                width: 200,
                options: [
                  for (final m in DisplayMatchMode.values)
                    if (m != DisplayMatchMode.rateAndResolution || DisplayMatch.resolutionSupported) (m.name, m.label),
                ],
                value: DisplayMatch.effective(p.displayMatch).name,
                onChanged: (v) => _set(app, p.copyWith(displayMatch: v)),
              ),
            ),
          _Row(
            label: 'Picture Size',
            control: ConsoleSegmented<String>(
              options: const [('fit', 'Fit'), ('fill', 'Fill'), ('stretch', 'Stretch')],
              value: p.aspect,
              onChanged: (v) => _set(app, p.copyWith(aspect: v)),
            ),
            last: isTizen,
          ),
          if (!isTizen) ...[
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
          ..._choice(
            label: 'Theme',
            control: ConsoleSegmented<String>(options: const [('dark', 'Dark'), ('light', 'Light')], value: s.theme, onChanged: app.setTheme),
          ),
          if (!isTv) const SizedBox(height: Space.space4),
          ..._choice(
            label: 'Surfaces',
            help: isTv ? 'Flat is lighter on TVs with little memory.' : 'Flat is lighter on older graphics cards.',
            control: ConsoleSegmented<bool>(options: const [(true, 'Frosted Glass'), (false, 'Flat')], value: s.glass, onChanged: app.setGlass),
          ),
          if (trailersSupported) ...[
            if (!isTv) const SizedBox(height: Space.space4),
            ..._choice(
              label: 'Home Trailers',
              help: homeTrailersSupported
                  ? 'Muted trailer clips behind the Home spotlight and the title you point at.'
                  : 'This device runs 32-bit Android, which leaves little memory for a second video player. Spotlight Only plays a trailer just while you’re on the spotlight’s buttons, and frees its player as soon as you move away. Experimental.',
              control: homeTrailersSupported
                  ? ConsoleSegmented<bool>(options: const [(true, 'Play'), (false, 'Off')], value: s.homeTrailers, onChanged: app.setHomeTrailers)
                  : ConsoleSegmented<bool>(options: const [(true, 'Spotlight Only'), (false, 'Off')], value: s.spotlightTrailers, onChanged: app.setSpotlightTrailers),
            ),
          ],
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
    // A store build, or a Mac or iPhone, is updated by its store (and a Samsung TV installs
    // nothing else).
    if (selfUpdates) UpdatesPanel(updater: app.updater, start: widget.update),
    if (!isTizen) ConsolePanel(
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
          _wrap(
            [
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
            for (final (keys, what) in [
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
              ('R (or X)', "Riptide: the cast, and who's in the scene"),
              if (PlayerDock.enabled) ('B', 'Mini player: keep playing in a corner while you browse'),
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
    ConsolePanel(
      title: 'About',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row(
            label: 'Open-Source Licenses',
            help: '$appName is built on open-source software, including mpv and FFmpeg for playback. Their licenses, and every other package\'s.',
            control: ConsoleButton(label: 'View', icon: LucideIcons.scrollText, onPressed: () => unawaited(showLicenses(context))),
          ),
          // A TV shows the address (and a QR code for a phone) instead of opening a browser.
          _Row(
            label: 'Privacy Policy',
            help: isTv || !canOpenLinks ? 'Read it on your phone or computer: $privacyPolicyUrl' : 'What $appName keeps, and where your sign-ins and history go.',
            control: isTv || !canOpenLinks
                ? ClipRRect(borderRadius: BorderRadius.circular(Radii.radiusSm), child: QrView(privacyPolicyUrl, size: 96, label: 'QR code for the privacy policy'))
                : ConsoleButton(label: 'Open', icon: LucideIcons.externalLink, onPressed: () => unawaited(openExternal(privacyPolicyUrl))),
            last: true,
          ),
        ],
      ),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.space1),
      child: Text('$appName $appVersion', style: ConsoleText.caption.copyWith(color: c.text300)),
    ),
    // Plex's trademark guidelines ask for this line wherever the Plex name is used.
    Padding(
      padding: const EdgeInsets.fromLTRB(Space.space1, Space.space1, Space.space1, 0),
      child: Text(plexAttribution, style: ConsoleText.caption.copyWith(color: c.text300)),
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
  tracking('Tracking'),
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
    if (isTv) return TvSettingRow(label: label, help: help, control: control);
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


/// A category in a TV's Settings: it opens as focus reaches it ([onFocus]), and Select moves
/// on into its settings ([onTap]).
class _Category extends StatefulWidget {
  const _Category({required this.label, required this.open, required this.focusNode, required this.onFocus, required this.onTap, this.autofocus = false});
  final bool autofocus;
  final String label;
  final bool open;
  final FocusNode focusNode;
  final VoidCallback onFocus;
  final VoidCallback onTap;

  @override
  State<_Category> createState() => _CategoryState();
}

class _CategoryState extends State<_Category> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_focusChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_focusChanged);
    super.dispose();
  }

  void _focusChanged() {
    if (widget.focusNode.hasPrimaryFocus) widget.onFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final open = widget.open;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.space1),
      child: Focusable(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        semanticLabel: widget.label,
        reveal: false,
        onTap: widget.onTap,
        builder: (context, hover, focus) => AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: Space.space4),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(color: focus ? c.text100 : (open ? c.surface300 : Colors.transparent), borderRadius: BorderRadius.circular(Radii.radiusMd)),
          child: Text(
            widget.label,
            style: ConsoleText.body.copyWith(fontSize: 16, color: focus ? c.surface000 : (open ? c.text100 : c.text200), fontWeight: open || focus ? FontWeight.w700 : FontWeight.w400),
          ),
        ),
      ),
    );
  }
}

/// A setting on a TV: the whole row is one stop for the remote and lights up from edge to
/// edge, with its value at the right. Select flips a switch, presses a button, or opens the
/// list of choices of a dropdown or a segmented control ([pickChoice]). The small control at
/// the far right is no stop of its own any more: a switch was a 36-pixel target, and a
/// segmented control three of them.
class TvSettingRow extends StatelessWidget {
  const TvSettingRow({super.key, required this.label, required this.control, this.help});
  final String label;
  final String? help;

  /// A [ConsoleSwitch], [ConsoleDropdown], [ConsoleSegmented] or [ConsoleButton]; anything
  /// else is shown as it is and keeps its own focus.
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ctl = control;
    VoidCallback? tap;
    Widget Function(bool focus)? value;
    Widget choice(List<String> labels, int selected, void Function(int) pick) {
      tap = () async {
        final i = await pickChoice(context, title: label, options: labels, selected: selected);
        if (i != null && i != selected) pick(i);
      };
      return const SizedBox();
    }

    Widget shown(String text, {bool chevron = true}) => Builder(
      builder: (context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: ConsoleText.body.copyWith(fontSize: 15, color: c.text200)),
          ),
          if (chevron) ...[const SizedBox(width: Space.space1), Icon(LucideIcons.chevronRight, size: 16, color: c.text300)],
        ],
      ),
    );

    if (ctl is ConsoleSwitch) {
      final change = ctl.onChanged;
      tap = change == null ? null : () => change(!ctl.value);
      value = (_) => ExcludeFocus(child: IgnorePointer(child: ctl));
    } else if (ctl is ConsoleDropdown) {
      choice(ctl.labels, ctl.selected, ctl.pick);
      value = (_) => shown(ctl.selected < 0 ? '' : ctl.labels[ctl.selected]);
    } else if (ctl is ConsoleSegmented) {
      choice(ctl.labels, ctl.selected, ctl.pick);
      value = (_) => shown(ctl.selected < 0 ? '' : ctl.labels[ctl.selected]);
    } else if (ctl is ConsoleButton) {
      tap = ctl.onPressed;
      value = (_) => shown(ctl.label == label ? '' : ctl.label);
    }
    Widget row(bool focus, Widget trailing) => AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: Space.space4, vertical: Space.space2),
      decoration: BoxDecoration(
        color: focus ? c.surface300 : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.radiusMd),
        border: Border.all(color: focus ? c.text100 : Colors.transparent, width: 2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: ConsoleText.bodyStrong.copyWith(fontSize: 15, color: c.text100)),
                if (help != null) Text(help!, style: ConsoleText.caption.copyWith(color: focus ? c.text200 : c.text300)),
              ],
            ),
          ),
          const SizedBox(width: Space.space4),
          trailing,
        ],
      ),
    );
    final v = value;
    // A control this row doesn't know, or one that's switched off: no stop, shown as it is.
    if (v == null) return row(false, ctl);
    if (tap == null) return Opacity(opacity: 0.5, child: row(false, v(false)));
    return Focusable(onTap: tap, semanticLabel: label, builder: (context, hover, focus) => row(focus, v(focus)));
  }
}

/// A TV's list of choices for one setting: [options] in a column with [selected] ticked and
/// in focus. Up and Down stay inside it, Select picks, Back closes it. The option's place, or
/// null when it was closed.
Future<int?> pickChoice(BuildContext context, {required String title, required List<String> options, required int selected}) => showDialog<int>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: 0.6),
  builder: (context) {
    final c = context.c;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Material(
          color: c.surface100,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: c.border200),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.space5, Space.space5, Space.space5, Space.space3),
                child: Text(title, style: ConsoleText.titleLg.copyWith(color: c.text100)),
              ),
              Flexible(
                child: FocusTraversalGroup(
                  policy: TvTraversalPolicy(requestFocusCallback: _SettingsPageState._focusOnly),
                  child: FocusReveal(
                    margin: 56,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(Space.space3, 0, Space.space3, Space.space3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, o) in options.indexed)
                            Focusable(
                              autofocus: i == selected || (selected < 0 && i == 0),
                              semanticLabel: o,
                              onTap: () => Navigator.pop(context, i),
                              builder: (context, hover, focus) => Container(
                                height: 48,
                                padding: const EdgeInsets.symmetric(horizontal: Space.space4),
                                decoration: BoxDecoration(color: focus ? c.text100 : Colors.transparent, borderRadius: BorderRadius.circular(Radii.radiusMd)),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        o,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: ConsoleText.body.copyWith(fontSize: 15, color: focus ? c.surface000 : (i == selected ? c.text100 : c.text200), fontWeight: i == selected || focus ? FontWeight.w600 : FontWeight.w400),
                                      ),
                                    ),
                                    if (i == selected) Icon(LucideIcons.check, size: 18, color: focus ? c.surface000 : c.primary),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  },
);
