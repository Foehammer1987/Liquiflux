# cacert.pem

Mozilla's list of trusted certificate authorities, as packaged by certifi 2026.10.23
(https://github.com/certifi/python-certifi, MPL-2.0; the same list curl ships), with
Liquiflux's own removals below. 117 roots.

Everything Liquiflux itself connects to over https checks certificates against this list
and nothing else:

- mpv (lib/services/mpv_tls.dart). media_kit's libmpv for Windows and Android does TLS with
  mbedtls, which can't read the system's certificate store and has no revocation checks.
- The app's own requests and artwork (lib/services/trusted_roots.dart): Plex, plex.tv,
  Seerr, the Riptide server, Trakt, TMDB. Using this list instead of the system's means an old
  TV's root store (the 2019 Shield is on Android 11 and gets few updates) can't keep trusting a
  root the browsers have dropped.

## Removed by Liquiflux

- **emSign Root CA - G1 (eMudhra).** In October 2026 eight eMudhra intermediate CAs were found
  to have private keys computable from their public certificates (CVE-2026-111943). Firefox
  and Chrome blocked them on 2026-10-17, eMudhra revoked them on 2026-10-18, and Mozilla
  removed emSign ECC Root CA - G3 (NSS 3.131.1, 2026-10-20; already absent from certifi
  2026.10.19 on). Mozilla kept G1, but browsers also block the bad intermediates by
  revocation lists that a fixed file like this can't carry, eMudhra is leaving the TLS
  business, and nothing Liquiflux talks to uses it, so every eMudhra/emSign root is out.
- Sectigo's cross-signed copies of the same intermediates chain to "AAA Certificate
  Services", which is not in Mozilla's list for websites and so not in this file.

app/test/trusted_roots_test.dart fails if an emSign/eMudhra or AAA Certificate
Services root comes back, or if the file stops parsing.

To refresh: take a newer certifi (or https://curl.se/ca/cacert.pem), remove the blocks
listed above, and run the test.
