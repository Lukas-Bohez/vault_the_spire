# Vault The Spire

**Vault The Spire** is a cross-platform Flutter app for private file sharing and encrypted peer-to-peer messaging. It combines BitTorrent with an encrypted local vault, end-to-end encrypted messaging, and QR-based contact onboarding — all with no telemetry, no accounts, and no central servers.

## Privacy-first mission

Vault The Spire was built around the principle that private communications and file sharing should be under user control.

- No centralized surveillance, no opaque tracking.
- No mandatory accounts or external identity provider.
- End-to-end cryptography for vault and chat sessions.
- Local encrypted storage by default, with optional seedable DHT-based file discovery.

## Features

### User-facing features

- Drag-and-drop torrent and magnet link import.
- Magnet link generation and QR sharing for contacts.
- Encrypted local vault (AES-256-GCM + SQLCipher) with per-item metadata.
- Cross-platform desktop support (Windows, macOS, Linux) plus mobile (Android/iOS).
- Peer-to-peer channel & messaging sync with contact QR onboarding.

### Under the hood

- SQLCipher-encrypted local database via `sqflite`.
- Torrent parsing & DHT support using BitTorrent protocol standards.
- `audioplayers` and GStreamer for cross-platform audio playback.
- E2E encryption (X25519 key agreement + ratchet session)
- Docker-less, auth-less, and telemetry-free architecture.

### Torrent behavior (updated)

- Magnet links and `.torrent` files are now managed by a real BitTorrent backend via `aria2` JSON-RPC when available.
- `.torrent` file inputs are supported from local paths (`file://` and direct filesystem path) and HTTP/HTTPS downloads.
- Engine logic still retains fallback simulated progress for environments where `aria2` is unavailable, but uses real peer sessions and speeds when `aria2` is running.

## Quickstart

### End-user install (recommended)
1. Download the latest package from https://quizthespire.com/ (Windows MSI, macOS DMG, Linux AppImage).
2. Install and launch.
3. Optional: enable `Settings -> Launch on startup`.

### Developer install
Requirements:
- Flutter SDK (stable channel)
- Dart SDK
- Platform tools for your OS (Windows/macOS/Linux)

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test --coverage
flutter run -d windows  # or -d macos, -d linux
```

## CI / GitHub Actions

- `ci.yml` runs analysis + tests only (no full Linux build in CI due desktop dependency variance).
- `release.yml` runs full cross-platform builds and now includes required dependencies for Linux (GTK/GStreamer).

## Contributing

Please see [CONTRIBUTING.md](CONTRIBUTING.md) for project contribution workflow.

## License

Vault The Spire is released under GNU GPL 3.0. See [LICENSE](LICENSE).

## Notes

- Keep dependencies up to date using `flutter pub outdated` and `flutter pub upgrade` in a feature branch.
- `todo.md` is maintained as an internal backlog; prefer GitHub issues for public task tracking.
