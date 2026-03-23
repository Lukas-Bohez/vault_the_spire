# Vault The Spire

Desktop-first Flutter torrent + identity project.

## Quick start

Vault The Spire is a user-facing client for https://quizthespire.com/. It talks to the QuizTheSpire API for channels, messaging, and torrent vault sync.

### End-user install (recommended)
1. Visit https://quizthespire.com/ and download the latest app package for your platform.
2. Install normally (Windows MSI, macOS DMG, Linux AppImage).
3. Run the app and choose `Settings -> Launch on startup` to enable automatic startup.

### Developer install
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

## Privacy-first mission

Vault The Spire was born from the radical idea that private file and message sharing should not require giving up personal freedom.

- No central surveillance; no opaque tracking.
- Local encrypted storage with SQLCipher.
- End-to-end encryption for vault files (AES-256-GCM) and message sessions (X25519 + ratchet keys).
- Peer-to-peer BitTorrent protocol with standard DHT but your data is your data.

Use it for:
- Private torrents and vault files that do not leak metadata to third parties.
- Secure contact sharing via QR imports.
- Read-only cross-platform channel sync from public sources with no content tracking.

## Spread the word (marketing copy)

### Tagline
**"Vault The Spire: Share privately, share securely, share without compromise."**

### Social pitch
> Built on open standards (BitTorrent + DHT + WebRTC) with encrypted vault overlays and contact QR onboarding. No ads, no telemetry, no hidden publisher keys. Run it on Windows/macOS/Linux/Android/iOS.

### GitHub description suggestion
`Vault The Spire - cross-platform Flutter app for encrypted torrent + peer-to-peer messaging and vault sharing. Privacy-first, open source, no airdrop spy routes.`

### Call to action for contributors
- Star the repo and share on Hacker News, Reddit r/privacy, r/selfhosted.
- Write a blog post: "How to run private torrents + encrypted chats from a single app." 
- Add demo videos showing drag/drop torrent import, magnet link sharing, and desktop fullscreen mode.

## Notes

- Package versions are currently not up-to-date; run `flutter pub outdated` and upgrade carefully.

