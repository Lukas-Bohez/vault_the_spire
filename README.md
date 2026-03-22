# Vault The Spire

Desktop-first Flutter torrent + identity project.

## Quick start

Requirements:
- Flutter SDK (stable channel)
- Dart SDK
- Platform tools for your OS (Windows/macOS/Linux)

Commands:

- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter run -d windows` (or `-d macos`, `-d linux`)

## Features implemented

- local torrent metadata persistence (SQFlite + SQLCipher)
- drag/drop `.torrent` import on torrents screen
- parser for `.torrent` files (bencode, info-hash)
- magnet link generation
- identity service initialization and status display

## Development workflow

1. Checkout branch and install deps
2. Run `flutter test` regularly after changes
3. `dart format .` before commit
4. Add tests for new service/screen behavior

## Improvement included in this commit

- Completed TODO for torrent file parsing and insertion from drag/drop
- Added `TorrentService.addTorrentFromTorrentFile`
- Added user snack bars for success/failure in `TorrentsScreen`
- Added `TorrentService.createMagnetLink` + unit test
- Added AppBar user hint to trigger drag-and-drop instructions

## Notes

- package versions are currently not up-to-date; run `flutter pub outdated` and upgrade carefully.

