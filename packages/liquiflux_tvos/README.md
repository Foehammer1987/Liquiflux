# liquiflux_tvos

Small Apple TV services for Liquiflux, a tvOS-only Flutter plugin used through flutter-tvos.
Channel `liquiflux/tvos`:

- `defaultsGet` / `defaultsSet` (`key`, `value`; a null value removes the key):
  NSUserDefaults.standard, where the app keeps its settings and channels on tvOS (tvOS may
  purge an app's files). The Dart side is `app/lib/services/doc_store.dart`.

The player is a separate plugin, `liquiflux_aether`.
