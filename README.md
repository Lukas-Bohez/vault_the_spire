# Vault The Spire

**Vault The Spire** is a privacy-centric, cross-platform Flutter application designed for robust P2P file management and secure local storage. By combining the power of BitTorrent with an encrypted vault and local AI analysis, it provides a sanctuary for your data—no accounts, no telemetry, and zero central servers.

-----

## Privacy-First Mission

Vault The Spire is built on the radical idea that your files and the way you interact with them should be entirely under your control.

  * **Zero Surveillance:** No centralized tracking or hidden telemetry.
  * **Identity-Free:** No mandatory accounts or third-party identity providers.
  * **Local-First AI:** Our AI features run locally via Ollama, ensuring your file queries never leave your machine.
  * **Hardened Storage:** AES-256-GCM encryption for your local vault by default.

-----

## Key Features

### 📂 Advanced Torrent Management

  * **Full Android Support:** Experience fully functional, high-speed torrenting on mobile.
  * **Cross-Platform Desktop:** Native support for Windows, macOS, and Linux.
  * **Flexible Imports:** Drag-and-drop support for `.torrent` files and magnet links.
  * **Real-Time Engine:** Powered by `aria2` JSON-RPC for genuine peer sessions and performance.

### 🤖 Local AI Insight (Windows Only)

  * **Ollama Integration:** Chat with your torrent library. Ask questions about your downloaded content or manage your files using local LLMs.
  * **Private by Design:** Because the AI runs on your hardware, your chat history and file metadata remain 100% private.

### 🔐 The Vault

  * **Encrypted Storage:** A secure local vault utilizing **SQLCipher** for per-item metadata and file security.
  * **P2P Discovery:** Optional DHT-based file discovery for decentralized sharing without middle-men.

-----

## Under the Hood

| Component | Technology |
| :--- | :--- |
| **Framework** | Flutter (Stable Channel) |
| **Database** | `sqflite` with **SQLCipher** (AES-256-GCM) |
| **Torrent Engine** | `aria2` backend with fallback simulation logic |
| **Audio** | `audioplayers` + GStreamer for cross-platform playback |
| **Local AI** | Ollama API (Windows specialized) |
| **Architecture** | Docker-less, auth-less, and telemetry-free |

-----

## Quickstart

### End-User Install (Recommended)

1.  **Download:** Grab the latest package from [quizthespire.com](https://quizthespire.com/) (Windows MSI, macOS DMG, Linux AppImage, or Android APK).
2.  **Launch:** Install and open the app.
3.  **Config:** (Optional) Enable `Settings -> Launch on startup` to keep your seeds active.

### Developer Setup

**Requirements:**

  * Flutter SDK & Dart SDK
  * Platform-specific tools (C++ tools for Windows, Xcode for macOS, GTK/GStreamer for Linux)

<!-- end list -->

```bash
# Fetch dependencies
flutter pub get

# Run quality checks
flutter analyze --no-fatal-infos
flutter test --coverage

# Launch on your preferred platform
flutter run -d windows  # or android, macos, linux
```

-----

## CI / GitHub Actions

  * **`ci.yml`**: Handles automated analysis and unit testing.
  * **`release.yml`**: Manages full cross-platform builds, including specific Linux dependencies like GTK and GStreamer to ensure compatibility across distributions.

-----

## Contributing & License

We welcome contributions to the Spire\! Please review our [CONTRIBUTING.md](https://www.google.com/search?q=CONTRIBUTING.md) for our workflow.

**License:** Vault The Spire is proud to be open-source under the **GNU GPL 3.0**. See [LICENSE](https://www.google.com/search?q=LICENSE) for details.

> **Note:** Keep your environment lean. Use `flutter pub outdated` regularly and refer to the internal `todo.md` for the current development backlog. For public bugs, please use GitHub Issues.
