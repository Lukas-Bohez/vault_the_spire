# Release Readiness Report (2026-04-01)

Closed Alpha tester group: https://groups.google.com/g/testersvaultthespire/c/BLdOUseagro

## Summary

Codebase is release-ready for validated targets in this environment:
- Windows desktop release
- Android AAB release
- Web release (JS build path with `--no-wasm-dry-run`)

## Implemented Improvements

- Throttled AI chat streaming render updates to reduce UI jank.
- Made polling timers lifecycle-aware in browser/AI screens.
- Replaced key hardcoded messaging colors with theme `ColorScheme` usage.
- Fixed duplicate torrent detail navigation consistency.
- Removed/renamed remaining first-party VaultSwarm naming in DM topic API.
- Added conditional SQLCipher bootstrap to avoid web `dart:ffi` compile coupling.
- Rewrote `.gitignore` as valid UTF-8 to remove toolchain decode crash.
- Updated app version to `3.0.1+1` and changelog entry for this release.

## Verification Commands And Results

1. `flutter analyze`
- Result: PASS (no issues)

2. `flutter test`
- Result: PASS (all tests passed)

3. `flutter build windows --release`
- Result: PASS
- Artifact: `build/windows/x64/runner/Release/vault the spire.exe`

4. `flutter build appbundle --release`
- Result: PASS
- Artifact: `build/app/outputs/bundle/release/app-release.aab`

5. `flutter build web --release --no-wasm-dry-run`
- Result: PASS
- Artifact: `build/web`

## Important Notes

- Web build currently requires `--no-wasm-dry-run` because dependencies include non-WASM-compatible paths (notably `dart:ffi`-related and web plugin caveats). JS web release build is working.
- iOS/macOS/Linux release binaries were not built in this Windows environment; those need CI/macOS/Linux runners for final cross-platform sign-off.

## Remaining Non-Code Release Tasks

- Play Console account, policy forms, data safety, and store listing assets.
- Physical-device release validation and staged rollout setup.
- Final permission/security policy review in store submission context.
