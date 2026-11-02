import 'dart:async';

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../platform.dart';
import '../../services/links.dart';
import '../../services/phone_link.dart';
import '../../services/scrobbler.dart';
import '../../state/app_state.dart';
import '../common.dart' show muted;
import 'focus_handle.dart';
import 'qr_view.dart';
import 'settings_field.dart';

/// Settings > Tracking: Trakt (everything you watch) and AniList (anime episodes).
///
/// Trakt signs in with a code typed at trakt.tv/activate, like Plex's link code. AniList has
/// no code sign-in, so on a TV a QR code opens a page the TV serves on the home network,
/// where the phone signs in to AniList and pastes the token back ([PhoneLink]). The same
/// page takes a Trakt app's long Client ID and Secret.
class TrackingPanels extends StatefulWidget {
  const TrackingPanels({super.key, required this.app, this.tv});
  final AppState app;

  /// The TV layout; [isTv] when not given (tests set it).
  final bool? tv;

  @override
  State<TrackingPanels> createState() => _TrackingPanelsState();
}

class _TrackingPanelsState extends State<TrackingPanels> {
  AppState get _app => widget.app;
  Scrobbler get _s => _app.scrobbler;
  bool get _tv => widget.tv ?? isTv;

  // Trakt's code while signing in.
  TraktDeviceCode? _code;
  bool _gettingCode = false;
  int _attempt = 0;
  Timer? _clock;
  String? _traktMsg;
  Tone _traktTone = Tone.neutral;

  // A phone page that's open, and what it's for.
  PhoneLink? _link;
  String? _linkFor;

  String? _anilistMsg;
  Tone _anilistTone = Tone.neutral;
  bool _busy = false;

  // On a TV the remote is moved onto the code or the phone page when it appears (Down from
  // the Trakt buttons went past the page's Cancel to AniList).
  final _phoneFocus = FocusHandle();
  final _codeFocus = FocusHandle();

  final _id = TextEditingController();
  final _secret = TextEditingController();
  final _anilistId = TextEditingController();
  final _token = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_s.load());
    _id.text = _app.settings.traktClientId;
    _secret.text = _app.settings.traktClientSecret;
    _anilistId.text = _app.settings.anilistClientId;
  }

  @override
  void dispose() {
    _attempt++;
    _clock?.cancel();
    unawaited(_link?.close());
    for (final c in [_id, _secret, _anilistId, _token]) {
      c.dispose();
    }
    _phoneFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- Trakt

  Future<void> _traktConnect() async {
    final attempt = ++_attempt;
    bool current() => mounted && attempt == _attempt;
    setState(() {
      _gettingCode = true;
      _code = null;
      _traktMsg = null;
    });
    try {
      final code = await _s.traktCode();
      if (!current()) return;
      setState(() {
        _code = code;
        _gettingCode = false;
      });
      if (_tv) _codeFocus.focus();
      _clock?.cancel();
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      await _s.traktWait(code, cancelled: () => !current());
      if (!current()) return;
      _traktStatus = ('Connected. What you watch now goes to Trakt.', Tone.success);
    } on TraktSignInException catch (e) {
      if (!current() || e.end == TraktSignInEnd.cancelled) return;
      _traktStatus = ('$e', Tone.warning);
    } catch (e) {
      if (!current()) return;
      _traktStatus = (errorText(e), Tone.danger);
    } finally {
      if (current()) {
        _clock?.cancel();
        setState(() {
          _gettingCode = false;
          _code = null;
        });
      }
    }
  }

  set _traktStatus((String, Tone) r) => setState(() {
    _traktMsg = r.$1;
    _traktTone = r.$2;
  });

  void _cancelCode() {
    _attempt++;
    _clock?.cancel();
    setState(() {
      _code = null;
      _gettingCode = false;
    });
  }

  Future<void> _saveTraktKeys(String id, String secret) async {
    await _app.setScrobbleApps(traktClientId: id.trim(), traktClientSecret: secret.trim());
    if (mounted) setState(() {});
  }

  /// The phone page for a Trakt app's Client ID and Secret.
  Future<void> _traktKeysOnPhone() => _openLink(
    'trakt',
    title: 'Trakt app for Liquiflux',
    intro: 'Make an app at trakt.tv (any name, redirect URI urn:ietf:wg:oauth:2.0:oob), then copy its Client ID and Client Secret here.',
    links: [('Make a Trakt app', 'https://trakt.tv/oauth/applications/new')],
    fields: [PhoneField('id', 'Client ID', value: _app.settings.traktClientId), const PhoneField('secret', 'Client Secret', secret: true)],
    onSubmit: (v) async {
      if (!RegExp(r'^[A-Za-z0-9]{20,128}$').hasMatch(v['id']!) || !RegExp(r'^[A-Za-z0-9]{20,128}$').hasMatch(v['secret']!)) {
        return 'Both should be long strings of letters and numbers. Copy them again from your Trakt app.';
      }
      await _saveTraktKeys(v['id']!, v['secret']!);
      return null;
    },
    done: () => _traktStatus = ('Trakt app saved. Now connect your account.', Tone.success),
  );

  // ---------------------------------------------------------------- AniList

  String get _anilistAuth => AniListAccount.authorizeUrl(_s.anilistClientId);

  Future<void> _anilistWith(String token) async {
    setState(() => _busy = true);
    try {
      await _s.anilistSignIn(token);
      _token.clear();
      _anilistStatus = ('Connected. Anime episodes you finish now move your AniList progress.', Tone.success);
    } catch (e) {
      _anilistStatus = (errorText(e), Tone.danger);
      rethrow;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  set _anilistStatus((String, Tone) r) {
    if (!mounted) return;
    setState(() {
      _anilistMsg = r.$1;
      _anilistTone = r.$2;
    });
  }

  Future<void> _anilistOnPhone() {
    final needId = _s.anilistClientId.isEmpty;
    return _openLink(
      'anilist',
      title: 'Connect AniList',
      intro: needId
          ? 'First make an AniList API client at anilist.co/settings/developer with the redirect URL https://anilist.co/api/v2/oauth/pin and put its ID below. Then send it, and this page will offer the sign-in.'
          : 'Sign in to AniList and approve Liquiflux. AniList then shows a long token: copy all of it, come back to this page and paste it below.',
      links: needId ? [('AniList developer settings', 'https://anilist.co/settings/developer')] : [('Sign in to AniList', _anilistAuth)],
      fields: needId ? [const PhoneField('client', 'AniList client ID')] : [const PhoneField('token', 'Token', multiline: true)],
      onSubmit: (v) async {
        if (needId) {
          final id = v['client']!;
          if (!RegExp(r'^\d{1,10}$').hasMatch(id)) return 'The client ID is a number.';
          await _app.setScrobbleApps(anilistClientId: id);
          return null;
        }
        try {
          await _anilistWith(v['token']!);
          return null;
        } catch (e) {
          return errorText(e);
        }
      },
      // With the client ID in, open the sign-in page straight away.
      done: needId ? () => unawaited(Future<void>.delayed(const Duration(milliseconds: 1200), _anilistOnPhone)) : null,
    );
  }

  // ---------------------------------------------------------------- the phone page

  Future<void> _openLink(
    String what, {
    required String title,
    required String intro,
    List<(String, String)> links = const [],
    required List<PhoneField> fields,
    required Future<String?> Function(Map<String, String>) onSubmit,
    VoidCallback? done,
  }) async {
    await _link?.close();
    final link = await PhoneLink.open(title: title, intro: intro, links: links, fields: fields, onSubmit: onSubmit);
    if (!mounted) return unawaited(link?.close());
    if (link == null) {
      final msg = ('This device isn’t on a home network, so there’s no page for a phone to open.', Tone.warning);
      what == 'trakt' ? _traktStatus = msg : _anilistStatus = msg;
      return;
    }
    link.onDone = () {
      if (!mounted) return;
      setState(() {
        if (identical(_link, link)) {
          _link = null;
          _linkFor = null;
        }
      });
      done?.call();
    };
    setState(() {
      _link = link;
      _linkFor = what;
    });
    if (_tv) _phoneFocus.focus();
  }

  Future<void> _closeLink() async {
    await _link?.close();
    if (mounted) {
      setState(() {
        _link = null;
        _linkFor = null;
      });
    }
  }

  // ---------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _s,
    builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_trakt(context), const SizedBox(height: Space.space4), _anilist(context)]),
  );

  Widget _buttons(List<Widget> buttons) {
    if (!_tv) return Wrap(spacing: Space.space3, runSpacing: Space.space2, children: buttons);
    // On a TV the remote moves straight down, so buttons share the full width (see UpdatesPanel).
    return Row(
      children: [
        for (final (i, b) in buttons.indexed) ...[if (i > 0) const SizedBox(width: Space.space3), Expanded(child: b)],
      ],
    );
  }

  Widget _status(String? msg, Tone tone) => msg == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: Space.space2), child: StatusDot(msg, tone: tone));

  Widget _trakt(BuildContext context) {
    final c = context.c;
    final s = _s;
    final hasApp = s.traktApp != null;
    final own = _app.settings.traktClientId.isNotEmpty && _app.settings.traktClientSecret.isNotEmpty;
    final children = <Widget>[];
    if (s.traktOn) {
      children.add(Text(s.traktUser.isEmpty ? 'Connected to Trakt.' : 'Connected as ${s.traktUser}.', style: ConsoleText.bodyStrong.copyWith(color: c.text100)));
      children.add(Text('Movies and episodes you play show on Trakt as you watch them, and count as watched past 80%. Titles you mark watched are added to your history.', style: ConsoleText.caption.copyWith(color: c.text300)));
      if (s.lastTrakt != null) children.add(_status('Last: ${s.lastTrakt}', Tone.neutral));
      children.add(const SizedBox(height: Space.space3));
      children.add(_buttons([ConsoleButton(label: 'Disconnect Trakt', icon: LucideIcons.logOut, expand: _tv, onPressed: () => unawaited(s.traktSignOut()))]));
    } else if (_code != null || _gettingCode) {
      children.add(_codeFocus.wrap(_TraktCode(code: _code, onNewCode: () => unawaited(_traktConnect()), onCancel: _cancelCode, tv: _tv)));
    } else {
      children.add(Text(
        s.traktAppChanged
            ? 'The Trakt app changed since you connected. Connect again.'
            : hasApp
            ? 'Connect your Trakt account and everything you watch is scrobbled there.'
            : 'Trakt needs an app’s Client ID and Client Secret first. This copy of Liquiflux has none built in, so make your own (free) and add its keys.',
        style: ConsoleText.body.copyWith(color: c.text200),
      ));
      children.add(const SizedBox(height: Space.space3));
      children.add(_buttons([
        if (hasApp) ConsoleButton(label: 'Connect Trakt', icon: LucideIcons.link, kind: ButtonKind.primary, expand: _tv, onPressed: () => unawaited(_traktConnect())),
        if (_tv) ConsoleButton(label: hasApp ? 'Use My Own Trakt App' : 'Add Keys from My Phone', icon: LucideIcons.smartphone, kind: hasApp ? ButtonKind.secondary : ButtonKind.primary, expand: true, onPressed: () => unawaited(_traktKeysOnPhone())),
      ]));
    }
    if (_linkFor == 'trakt' && _link != null) children.addAll([const SizedBox(height: Space.space4), _phoneFocus.wrap(_PhonePage(link: _link!, onCancel: () => unawaited(_closeLink())))]);
    // A keyboard: the keys go in right here.
    if (!_tv && !s.traktOn) {
      children.addAll([
        const SizedBox(height: Space.space4),
        Text(hasApp && !own ? 'Your own Trakt app (optional)' : 'Your Trakt app', style: ConsoleText.bodyStrong.copyWith(color: c.text100)),
        const SizedBox(height: Space.space2),
        SettingsField(label: 'Client ID', controller: _id, mono: true, tv: false),
        const SizedBox(height: Space.space2),
        SettingsField(label: 'Client Secret', controller: _secret, mono: true, obscure: true, tv: false, help: 'Kept in the system’s credential store. Make the app at trakt.tv/oauth/applications/new with the redirect URI urn:ietf:wg:oauth:2.0:oob.'),
        const SizedBox(height: Space.space2),
        _buttons([
          ConsoleButton(label: 'Save Keys', onPressed: () async {
            await _saveTraktKeys(_id.text, _secret.text);
            _traktStatus = ('Saved', Tone.success);
          }),
          ConsoleButton(label: 'Make a Trakt App', icon: LucideIcons.externalLink, onPressed: () => unawaited(openExternal('https://trakt.tv/oauth/applications/new'))),
        ]),
      ]);
    }
    children.add(_status(_traktMsg, _traktTone));
    return ConsolePanel(title: 'Trakt', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children));
  }

  Widget _anilist(BuildContext context) {
    final c = context.c;
    final s = _s;
    final children = <Widget>[];
    if (s.anilistOn) {
      children.add(Text(s.anilistUser.isEmpty ? 'Connected to AniList.' : 'Connected as ${s.anilistUser}.', style: ConsoleText.bodyStrong.copyWith(color: c.text100)));
      children.add(Text(
        'When you finish an anime episode or film (past 80%), its entry on your list moves forward. Progress only ever goes up, and finished shows are left alone. Shows are matched by title and air dates.',
        style: ConsoleText.caption.copyWith(color: c.text300),
      ));
      if (s.lastAniList != null) children.add(_status('Last: ${s.lastAniList}', Tone.neutral));
      children.add(const SizedBox(height: Space.space3));
      children.add(_buttons([
        ConsoleButton(label: 'Disconnect AniList', icon: LucideIcons.logOut, expand: _tv, onPressed: () => unawaited(s.anilistSignOut())),
        ConsoleButton(label: 'Match Shows Again', icon: LucideIcons.refreshCw, expand: _tv, onPressed: () {
          unawaited(s.forgetMatches());
          _anilistStatus = ('Shows will be looked up on AniList again.', Tone.success);
        }),
      ]));
    } else {
      children.add(Text('Connect AniList to keep your anime episode progress up to date as you watch.', style: ConsoleText.body.copyWith(color: c.text200)));
      if (s.lastAniList != null) children.add(_status(s.lastAniList, Tone.warning));
      children.add(const SizedBox(height: Space.space3));
      if (_tv) {
        children.add(_buttons([ConsoleButton(label: 'Connect AniList', icon: LucideIcons.smartphone, kind: ButtonKind.primary, expand: true, onPressed: () => unawaited(_anilistOnPhone()))]));
      } else {
        if (s.anilistClientId.isEmpty) {
          children.addAll([
            SettingsField(label: 'AniList Client ID', controller: _anilistId, mono: true, tv: false, help: 'Make a client at anilist.co/settings/developer with the redirect URL https://anilist.co/api/v2/oauth/pin.'),
            const SizedBox(height: Space.space2),
            _buttons([
              ConsoleButton(label: 'Save', onPressed: () async {
                final id = _anilistId.text.trim();
                if (!RegExp(r'^\d{1,10}$').hasMatch(id)) {
                  _anilistStatus = ('The client ID is a number.', Tone.warning);
                  return;
                }
                await _app.setScrobbleApps(anilistClientId: id);
                if (mounted) setState(() {});
              }),
              ConsoleButton(label: 'AniList Developer Settings', icon: LucideIcons.externalLink, onPressed: () => unawaited(openExternal('https://anilist.co/settings/developer'))),
            ]),
          ]);
        } else {
          children.addAll([
            muted(context, '1. Sign in to AniList and approve Liquiflux. 2. Copy the token AniList shows. 3. Paste it here.'),
            const SizedBox(height: Space.space2),
            _buttons([ConsoleButton(label: 'Open AniList', icon: LucideIcons.externalLink, kind: ButtonKind.primary, onPressed: () => unawaited(openExternal(_anilistAuth)))]),
            const SizedBox(height: Space.space3),
            SettingsField(label: 'Token', controller: _token, mono: true, obscure: true, tv: false),
            const SizedBox(height: Space.space2),
            _buttons([
              ConsoleButton(label: _busy ? 'Checking…' : 'Connect', onPressed: _busy ? null : () => unawaited(_anilistWith(_token.text).catchError((Object _) {}))),
              ConsoleButton(label: 'From My Phone', icon: LucideIcons.smartphone, onPressed: () => unawaited(_anilistOnPhone())),
            ]),
          ]);
        }
      }
    }
    if (_linkFor == 'anilist' && _link != null) children.addAll([const SizedBox(height: Space.space4), _phoneFocus.wrap(_PhonePage(link: _link!, onCancel: () => unawaited(_closeLink())))]);
    children.add(_status(_anilistMsg, _anilistTone));
    return ConsolePanel(title: 'AniList', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children));
  }
}

/// Trakt's code, its QR code (the activate page with the code filled in) and time left.
class _TraktCode extends StatelessWidget {
  const _TraktCode({required this.code, required this.onNewCode, required this.onCancel, required this.tv});
  final TraktDeviceCode? code;
  final VoidCallback onNewCode;
  final VoidCallback onCancel;
  final bool tv;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final k = code;
    final left = k?.expiresAt.difference(DateTime.now());
    final expired = left != null && left.isNegative;
    final shown = k?.userCode ?? '········';
    final status = k == null
        ? 'Getting a code'
        : expired
        ? 'This code has expired. Get a new one to try again.'
        : 'Waiting for you to enter it. The code expires in ${left!.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}.';
    return Wrap(
      spacing: Space.space6,
      runSpacing: Space.space4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (k != null) ClipRRect(borderRadius: BorderRadius.circular(Radii.radiusSm), child: QrView(k.directUrl, label: 'QR code for trakt.tv/activate')),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Go to ${(k?.url ?? 'https://trakt.tv/activate').replaceFirst('https://', '')} on your phone or computer and enter this code', style: ConsoleText.titleLg.copyWith(color: c.text100)),
              const SizedBox(height: Space.space1),
              Text('Or scan the QR code with your phone.', style: ConsoleText.caption.copyWith(color: c.text300)),
              const SizedBox(height: Space.space3),
              Semantics(
                label: k == null ? 'Getting a code' : 'Code ${shown.split('').join(' ')}',
                excludeSemantics: true,
                child: Text(shown, style: ConsoleText.data.copyWith(fontSize: 56, height: 1.1, fontWeight: FontWeight.w700, letterSpacing: 8, color: expired ? c.text300 : c.text100)),
              ),
              const SizedBox(height: Space.space2),
              Text(status, style: ConsoleText.body.copyWith(color: expired ? c.warningText : c.text200)),
              const SizedBox(height: Space.space4),
              Wrap(
                spacing: Space.space2,
                runSpacing: Space.space2,
                children: [
                  ConsoleButton(label: 'Get a New Code', icon: LucideIcons.refreshCw, kind: expired ? ButtonKind.primary : ButtonKind.secondary, autofocus: tv, onPressed: onNewCode),
                  ConsoleButton(label: 'Cancel', onPressed: onCancel),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The QR code for the phone page, its address, and Cancel.
class _PhonePage extends StatelessWidget {
  const _PhonePage({required this.link, required this.onCancel});
  final PhoneLink link;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Wrap(
      spacing: Space.space6,
      runSpacing: Space.space4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(Radii.radiusSm), child: QrView(link.url, label: 'QR code for the phone page')),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Scan this with your phone', style: ConsoleText.titleLg.copyWith(color: c.text100)),
              const SizedBox(height: Space.space1),
              Text('Your phone needs to be on the same Wi-Fi as this device. The page closes after 15 minutes.', style: ConsoleText.caption.copyWith(color: c.text300)),
              const SizedBox(height: Space.space2),
              Text(link.url, style: ConsoleText.data.copyWith(color: c.text200)),
              const SizedBox(height: Space.space3),
              ConsoleButton(label: 'Cancel', onPressed: onCancel),
            ],
          ),
        ),
      ],
    );
  }
}
