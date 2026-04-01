# Changelog

## [3.0.1] - 2026-04-01
### Changed
- Reduced AI chat render churn by throttling streaming assistant UI updates.
- Improved lifecycle behavior by pausing/resuming polling timers when app state changes.
- Migrated key messaging UI surfaces to theme-driven `ColorScheme` values.
- Fixed duplicate-torrent detail navigation to use a consistent route path.
- Rewrote `.gitignore` as UTF-8 to unblock Flutter web release build pipeline.

### Verified
- `flutter analyze` passes with no issues.
- `flutter test` passes.
- `flutter build windows --release` passes.
- `flutter build appbundle --release` passes.

## [3.0.0] - 2026-03-23
### Added
- Skeuomorphic sound effects (click, send, notification, mention) via `audioplayers`.
- Mobile haptic feedback on action triggers.
- Configurable sound toggle in settings (persistent via shared_preferences).
- DM/mention pattern handling in chat flows.
- Server invite encode/decode support (base64/JSON). 
- Server/channel CRUD: create, rename, delete, add/remove channel.
- Persistent SQLCipher-backed storage for servers, channels, and chat messages.
- Theme setting and system tray settings improved by robust service layer.
- GPL-3.0 license and metadata.

### Changed
- Bumped version to `3.0.0+0`.
- Annotated README with sound and release details.

### Fixed
- Copied initial code with several user-facing feature improvements and bugfixes.

## [Unreleased]
### Changed
- README restructured for clarity, focus, and maintainability.
- CI pipeline optimized: `ci.yml` run analysis/tests only; remove full Linux production build there.
- `release.yml` Linux install steps extended with GStreamer sysdeps for `audioplayers_linux`.

## [2.0.0] - earlier
- Feature snapshot from prior milestone.
