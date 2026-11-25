# liquiflux_tvos

Small Apple TV services for Liquiflux, a tvOS-only Flutter plugin used through flutter-tvos.
Channel `liquiflux/tvos`:

- `environment` (`key`): a variable from the launch's environment (Dart's
  `Platform.environment` is empty on tvOS); the probe switches come this way.
- `defaultsGet` / `defaultsSet` (`key`, `value`; a null value removes the key):
  NSUserDefaults.standard, where the app keeps its settings and channels on tvOS (tvOS may
  purge an app's files). The Dart side is `app/lib/services/doc_store.dart`.

The player is a separate plugin, `liquiflux_aether`.
