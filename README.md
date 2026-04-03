Vault The Spire

Vault The Spire is a privacy-first, cross-platform Flutter application dedicated to decentralized P2P file downloading. Combining a powerful BitTorrent engine with a built-in web browser, it provides a seamless, all-in-one environment for finding and managing your files—with no telemetry, no accounts, and zero central servers.
Privacy-First Mission

Vault The Spire is built on the simple idea that your download habits are your own business.

    Zero Surveillance: No centralized tracking or hidden telemetry.

    Identity-Free: No mandatory accounts or third-party identity providers.

    Local-First AI (Windows Only): Our AI features run locally via Ollama, ensuring your file queries never leave your machine.

Key Features
📂 Advanced Torrent Management

    Full Android Support: Fully functional, high-speed torrenting right on your mobile device.

    Cross-Platform Desktop: Native support for Windows, macOS, and Linux.

    Flexible Imports: Drag-and-drop support for .torrent files, plus seamless Magnet link integration.

    Integrated Web Browser: Surf the web and find what you need without ever leaving the app.

🤖 Local AI Insight (Windows Only)

    Ollama Integration: Chat with your torrent library. Ask questions about your downloaded content or manage your files using local LLMs.

    Private by Design: Because the AI runs entirely on your hardware, your chat history remains 100% private.

Under the Hood

    Torrent Engine: aria2 backend via JSON-RPC for genuine peer sessions, DHT, and high-speed performance (with fallback simulation logic where unavailable).

    Framework: Built on the Flutter stable channel for responsive UI across all platforms.

    Audio: audioplayers and GStreamer for cross-platform media playback.

    Architecture: Docker-less, auth-less, and telemetry-free.

Quickstart
End-User Install (Recommended)

    Download the latest package from quizthespire.com (Windows zip or Android APK).

    Install and launch.

    Optional: Enable Settings -> Launch on startup to keep your seeds active.

Developer Install

Requirements:

    Flutter SDK (stable channel)

    Dart SDK

    Platform tools for your OS (Windows C++ tools / Xcode / Linux GTK+GStreamer)

Bash

flutter pub get
flutter analyze --no-fatal-infos
flutter test --coverage
flutter run -d windows  # or -d android, -d macos, -d linux

CI / GitHub Actions

    ci.yml runs analysis + tests only.

    release.yml runs full cross-platform builds and includes required dependencies for Linux (GTK/GStreamer).

Contributing & License

Please see CONTRIBUTING.md for our project workflow.
Vault The Spire is released under GNU GPL 3.0. See LICENSE for details.
