# Shared Apple files

One copy of what the Mac, iPhone/iPad and (later) Apple TV apps share. Edit these, then run

```sh
dart tools/apple_sync.dart            # from the repository root
```

which writes them into each Xcode project (`macos/`, `ios/`, later `tvos/`):

| File | Goes to |
| --- | --- |
| `PrivacyInfo.xcprivacy` | each target's `Runner/PrivacyInfo.xcprivacy`, whole |
| `Info.plist.keys` | the marked block in each `Runner/Info.plist`: display name, App Store category, local network text, App Transport Security, export compliance |
| `keychain.entitlements` | the marked block in each entitlements file: the keychain access group that keeps sign-ins |

Everything outside the marked blocks belongs to its target (the Mac sandbox, iOS orientations
and scenes). CI runs `dart tools/apple_sync.dart --check`, and `app/test/apple_files_test.dart`
does the same, so a hand edit to a generated copy fails the build.

App icons come from `docs/brand/liquiflux-mark.svg` through `tools/make-apple-icons.swift`
(`mac`, `ios`, `launch` and `layers` modes); `dart tools/apple_sync.dart --icons` redraws
every target's icon on a Mac.
