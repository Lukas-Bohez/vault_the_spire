# VaultTheSpire — Flutter App TODO (Final + Compatibility + All Platforms)
>
> Platforms: Android · iOS · Windows · macOS · Linux
> One Flutter codebase. Five targets. Zero rewrites.
>
> VaultTheSpire is compatible with:
>   1. Standard BitTorrent (magnet links, .torrent files, standard DHT, peer wire protocol)
>   2. Telegram public channels (read-only import via Bot API bridge on the server)
>   3. Signal-style contact QR codes (import public key + identifier to start a vault chat)
>
> Architecture:
>   - Messaging layer: WebRTC DataChannel, E2E encrypted (X25519 + AES-256-GCM)
>   - File distribution: standard BitTorrent peer wire protocol + VaultTheSpire swarm for
>     encrypted vault files. Both can run simultaneously.
>   - DHT: standard Kademlia DHT (BEP 5) for BitTorrent. Bootstrapped from quizthespire.com
>     plus standard public bootstrap nodes (router.bittorrent.com, router.utorrent.com).
>   - Desktop: Flutter stable, same codebase, adaptive UI per platform.
>
> Tagline: "What goes into the Vault, stays in the Vault."

> ⚠️ PORT CONSTRAINT (server only)
> quizthespire.com exposes only 80 and 443.
> App-to-server calls: `https://quizthespire.com/vault/api/...` only.
> BitTorrent peer wire protocol between devices uses standard ports 6881-6889 TCP/UDP
> directly between peers — this does NOT involve quizthespire.com at all.
> Standard BitTorrent DHT uses UDP 6881 between peers — again, not through quizthespire.com.
> FCM push: Android + iOS only. Windows/macOS/Linux use polling fallback (see Phase 11).

---

## FULL FEATURE SET

### Messaging (Telegram-style)
- DMs: 1:1 E2E encrypted chat (text, emoji, reactions, replies, voice, files, images, video)
- Groups: encrypted mesh P2P up to ~50 members, invite links
- Channels: one-to-many broadcast, owner posts, subscribers pull from swarm
- Private channels: invite-link only
- Public channels: discoverable, importable
- Self-destructing messages (per-message timer)
- Disappearing conversations (all messages expire after N hours)
- Read receipts, typing indicators, online status (all optional)
- Message forwarding, pinned messages
- Inline media preview (image, video, voice, file)

### BitTorrent layer (qBittorrent-style)
- Open standard magnet links: `magnet:?xt=urn:btih:...` and `urn:btmh:...` (v1 + v2)
- Open .torrent files (drag-and-drop on desktop, file picker on mobile)
- Join existing BitTorrent swarms as a full peer
- Standard peer wire protocol (BEP 3)
- Standard DHT (BEP 5, Kademlia) — bootstraps from public nodes
- PEX (BEP 11) — peer exchange
- µTP transport (BEP 29) — congestion-friendly UDP
- Seeding ratio tracked globally and per-swarm
- Download/upload speed limits (settable per-swarm or globally)
- Sequential download mode (for streaming media before complete)
- File selection in multi-file torrents
- Magnet link and .torrent sharing inside chats — tap to open in Vault torrent engine

### Vault swarm (encrypted overlay on top of BT)
- Encrypted file drops in DMs, groups, channels
- Vault links: `vault://<infohash>#<AES_key>` — standard magnet infohash, key in fragment
- Pieces encrypted with AES-256-GCM before entering swarm
- Vault swarm peers are VaultTheSpire users — can be found via VaultTheSpire DHT bootstrap
- Standard BT swarm for unencrypted content, vault swarm for encrypted content
- Rarest-first piece selection, SHA-256 verification per piece

### Telegram bridge (read-only import)
- Paste `t.me/channelname` or `https://t.me/channelname` → import as read-only vault channel
- Channel posts fetched via server-side Telegram Bot API bridge (GET `/vault/api/telegram/channel/:name`)
- No Telegram account required
- Posts displayed in vault channel UI, images/videos cached locally
- Auto-refresh every 15 minutes
- Cannot post back to Telegram — read-only

### Signal contact import
- Scan a Signal-style contact QR (any QR containing a public key + identifier)
- If the QR contains an X25519 public key and a username/identifier: import as a vault contact
- Derive shared secret, open a vault DM
- Cannot interoperate with Signal's actual messaging protocol — import only

### Platform features (desktop)
- System tray icon (Windows, macOS, Linux)
- Native notifications via OS notification system
- Drag-and-drop .torrent files and magnet links onto the window
- Keyboard shortcuts (Ctrl+N new message, Ctrl+F search, etc.)
- Window state persistence (size, position, maximised state)
- Native file picker and save dialogs
- Auto-launch on login (optional, off by default)
- Adaptive UI: sidebar layout on desktop, bottom nav on mobile

---

## Stack & dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter

  # P2P transport (vault messaging)
  flutter_webrtc: ^0.10.0

  # BitTorrent engine — use a Dart FFI wrapper around libtorrent-rasterbar
  # or implement BEP 3/5/11 in pure Dart (see Phase 5)
  # Recommended: torrent_client (pub.dev) for pure Dart BT implementation
  # or bittorrent (pub.dev) — check current pub.dev for latest stable
  # If no suitable package: implement peer wire + DHT in Dart (Phase 5 specifies this)

  # Networking
  http: ^1.2.0
  web_socket_channel: ^2.4.0      # For Telegram bridge polling (desktop fallback)

  # Encryption
  cryptography: ^2.7.0            # X25519
  pointycastle: ^3.7.0            # AES-256-GCM
  crypto: ^3.0.3                  # SHA-1 (BT v1 infohash), SHA-256 (BT v2 + vault)

  # Local DB (encrypted)
  sqflite: ^2.3.0
  sqlcipher_flutter_libs: ^0.5.0
  flutter_secure_storage: ^9.0.0

  # Media
  image_picker: ^1.0.0            # Mobile only — conditional import
  file_picker: ^8.0.0             # All platforms
  record: ^5.0.0                  # Voice messages
  just_audio: ^0.9.0
  video_player: ^2.8.0
  photo_view: ^0.14.0

  # QR
  qr_flutter: ^4.1.0
  mobile_scanner: ^5.0.0         # Mobile only — desktop uses image file QR decode

  # Notifications
  firebase_core: ^2.27.0         # Android + iOS only
  firebase_messaging: ^14.7.0   # Android + iOS only
  flutter_local_notifications: ^17.0.0  # All platforms

  # Desktop
  window_manager: ^0.3.0         # Window control on desktop
  system_tray: ^2.0.0            # System tray on desktop
  hotkey_manager: ^0.2.0         # Global keyboard shortcuts
  launch_at_startup: ^0.3.0      # Auto-launch setting
  desktop_drop: ^0.4.0           # Drag-and-drop .torrent files on desktop

  # Navigation
  go_router: ^13.0.0

  # Utils
  uuid: ^4.3.0
  intl: ^0.19.0
  path_provider: ^2.1.0
  mime: ^1.0.0
  url_launcher: ^6.2.0           # Open magnet links, t.me links
  bencode_torrent: ^1.0.0        # Bencode parsing for .torrent files
                                  # If not available: implement bencode decoder (Phase 5)
```

---

## PHASE 0 — Project structure

```
lib/
├── main.dart
├── router.dart
├── constants.dart
│
├── crypto/
│   ├── identity.dart
│   ├── key_exchange.dart
│   ├── aes_gcm.dart
│   ├── ratchet.dart
│   └── db_key.dart
│
├── bittorrent/
│   ├── bencode.dart             # Bencode encoder/decoder (BEP 3)
│   ├── torrent_file.dart        # Parse .torrent files
│   ├── magnet_link.dart         # Parse magnet:? URIs (v1 + v2)
│   ├── dht.dart                 # Kademlia DHT (BEP 5)
│   ├── peer_wire.dart           # BitTorrent peer wire protocol (BEP 3)
│   ├── pex.dart                 # Peer exchange (BEP 11)
│   ├── piece_manager.dart       # Piece storage, verification, rarest-first
│   └── torrent_session.dart     # Manages one active torrent (seeding or leeching)
│
├── vault_swarm/
│   ├── vault_link.dart          # vault:// link generation and parsing
│   ├── vault_piece.dart         # Encrypted piece handling
│   └── vault_session.dart      # Vault-encrypted torrent session (extends TorrentSession)
│
├── bridges/
│   ├── telegram_bridge.dart     # Fetch public channel posts via server proxy
│   └── signal_qr.dart          # Parse Signal-style contact QR codes
│
├── db/
│   ├── database.dart
│   ├── contacts_dao.dart
│   ├── conversations_dao.dart
│   ├── messages_dao.dart
│   ├── channels_dao.dart
│   └── torrents_dao.dart        # Active/completed torrents, piece state
│
├── models/
│   ├── contact.dart
│   ├── conversation.dart
│   ├── message.dart
│   ├── channel.dart
│   ├── channel_post.dart
│   ├── group.dart
│   ├── torrent.dart             # Represents one torrent (BT or vault)
│   └── piece.dart
│
├── services/
│   ├── signal_service.dart      # WebRTC signalling HTTP calls
│   ├── p2p_service.dart         # WebRTC connections (vault messaging)
│   ├── group_service.dart       # Group mesh P2P
│   ├── channel_service.dart     # Channel publish/subscribe
│   ├── torrent_service.dart     # BitTorrent engine orchestration
│   ├── telegram_service.dart    # Telegram channel import
│   ├── auth_service.dart
│   └── notification_service.dart
│
├── screens/
│   ├── home_screen.dart         # Adaptive: sidebar (desktop) / bottom nav (mobile)
│   ├── conversations_screen.dart
│   ├── chat_screen.dart
│   ├── group_screen.dart
│   ├── channel_screen.dart
│   ├── torrents_screen.dart     # All active torrents (BT + vault)
│   ├── torrent_detail_screen.dart
│   ├── explore_screen.dart
│   ├── add_contact_screen.dart
│   ├── create_group_screen.dart
│   ├── create_channel_screen.dart
│   ├── own_profile_screen.dart
│   ├── settings_screen.dart
│   └── onboarding_screen.dart
│
├── widgets/
│   ├── message_bubble.dart
│   ├── media_bubble.dart
│   ├── magnet_bubble.dart       # Magnet link or vault link in chat
│   ├── channel_post_card.dart
│   ├── torrent_card.dart        # Compact torrent status card
│   ├── piece_map_bar.dart
│   ├── voice_player.dart
│   ├── typing_indicator.dart
│   ├── connection_dot.dart
│   ├── destruct_timer.dart
│   ├── vault_avatar.dart
│   ├── ratio_badge.dart
│   └── platform_adaptive_scaffold.dart  # Sidebar vs bottom nav
│
├── platform/
│   ├── desktop_window.dart      # window_manager setup
│   ├── system_tray.dart         # system_tray setup
│   ├── drag_drop.dart           # desktop_drop .torrent handling
│   └── notifications_desktop.dart  # Polling-based notifications for desktop
│
└── theme/
    └── vault_theme.dart
```

---

## PHASE 1 — Identity (same as before) ✅ DONE

- [x] X25519 key pair on first launch
- [x] Private key in `FlutterSecureStorage` only
- [x] DHT node ID = first 20 bytes of SHA-256(public_key) (derived from public key)
- [x] DB encryption key: 32 random bytes in `FlutterSecureStorage` (planned schema)
- [x] Never logged, never transmitted in plaintext

---

## PHASE 2 — Local DB (SQLCipher, same schema as before + torrents table) ✅ IN PROGRESS

- [x] `torrents` table created in local DB schema
- [x] DAO layer for torrents (insert / update / delete / load)
- [x] `TorrentModel` mapping implementation

### Additional table: `torrents`
```sql
CREATE TABLE torrents (
  id TEXT PRIMARY KEY,           -- infohash (v1 SHA-1 hex OR v2 SHA-256 hex)
  name TEXT NOT NULL,
  total_size INTEGER,
  total_pieces INTEGER,
  piece_length INTEGER,
  pieces_have TEXT,              -- JSON bitfield
  status TEXT,                   -- 'downloading'|'seeding'|'paused'|'complete'|'error'
  type TEXT NOT NULL,            -- 'bittorrent' | 'vault'
  vault_key TEXT,                -- AES key if type='vault', null otherwise
  file_path TEXT,                -- local path when complete
  vault_link TEXT,               -- vault:// link if type='vault'
  magnet_link TEXT,              -- original magnet link if opened from one
  bytes_down INTEGER DEFAULT 0,
  bytes_up INTEGER DEFAULT 0,
  added_at INTEGER,
  completed_at INTEGER,
  is_sequential INTEGER DEFAULT 0,
  selected_files TEXT            -- JSON array of selected file indices (multi-file torrents)
);
```

---

## PHASE 3 — Encryption (same as before)

X25519 DH + HKDF → AES-256-GCM. Per-message ratchet. Group key distributed P2P.
File pieces in vault swarm: encrypted with per-file AES key, stored pre-encrypted on disk.

---

## PHASE 4 — BitTorrent engine ✅ IN PROGRESS

This is the core new addition. VaultTheSpire implements a full BitTorrent client in Dart.

- [x] `lib/bittorrent/bencode.dart`
- [x] `lib/bittorrent/torrent_file.dart`
- [x] `lib/bittorrent/magnet_link.dart`
- [x] `lib/bittorrent/dht.dart`
- [x] `lib/bittorrent/peer_wire.dart`
- [x] `lib/bittorrent/piece_manager.dart`
- [x] `lib/bittorrent/torrent_session.dart`
- [x] `lib/vault_swarm/vault_link.dart`
- [x] `lib/vault_swarm/vault_piece.dart`
- [x] `lib/vault_swarm/vault_session.dart`
- [x] `lib/bridges/telegram_bridge.dart`
- [x] `lib/bridges/signal_qr.dart`
- [x] `lib/screens/torrents_screen.dart`
- [x] `lib/screens/torrent_detail_screen.dart`

### `lib/bittorrent/bencode.dart`

Implement bencode encoder and decoder per BEP 3.
Bencode types: integers (`i42e`), byte strings (`4:spam`), lists (`l...e`), dicts (`d...e`).
```dart
dynamic bdecode(Uint8List data);         // returns int, String, List, or Map
Uint8List bencode(dynamic value);        // encodes int, String, List, or Map
```

### `lib/bittorrent/torrent_file.dart`

Parse a `.torrent` file (bencoded dict) into a `TorrentMetadata` object:
```dart
class TorrentMetadata {
  final String infoHashV1;       // SHA-1 of info dict, hex
  final String? infoHashV2;      // SHA-256 of info dict, hex (BEP 52 only)
  final String name;
  final int pieceLength;
  final List<String> pieceHashes;  // SHA-1 per piece (v1) or merkle roots (v2)
  final List<TorrentFile> files;
  final List<String> trackers;
  final List<String> webSeeds;
}
```

Compute infohash:
```dart
// v1: SHA-1 of bencoded info dict
final infoHashV1 = sha1.convert(bencodeInfoDict).toString();
// v2: SHA-256 of bencoded info dict
final infoHashV2 = sha256.convert(bencodeInfoDict).toString();
```

### `lib/bittorrent/magnet_link.dart`

Parse `magnet:?xt=urn:btih:<hash>&dn=<name>&tr=<tracker>&x.pe=<peer>` URIs.
Support both v1 (`btih`) and v2 (`btmh`) infohashes.
Support hybrid magnets with both `btih` and `btmh` parameters.
Extract: infohash, display name, trackers, web seeds, direct peer hints.

```dart
class MagnetLink {
  final String? infoHashV1;      // 40-char hex SHA-1
  final String? infoHashV2;      // 64-char hex SHA-256
  final String? displayName;
  final List<String> trackers;
  final List<String> peers;      // x.pe hints
  factory MagnetLink.parse(String uri) { ... }
  String toUri() { ... }         // regenerate magnet URI
}
```

### `lib/bittorrent/dht.dart`

Implement BEP 5 (Kademlia DHT) in pure Dart.

**Node ID:** 160-bit, stored as 20-byte Uint8List.
**Distance:** XOR of two node IDs.
**K-buckets:** 160 buckets, k=8 per bucket. Evict stale nodes when full.
**Bootstrap nodes:**
```dart
const kDhtBootstrapNodes = [
  'router.bittorrent.com:6881',
  'router.utorrent.com:6881',
  'dht.transmissionbt.com:6881',
  'dht.libtorrent.org:25401',
];
// Plus: fetch from https://quizthespire.com/vault/api/dht/bootstrap
// for VaultTheSpire peers specifically
```

**DHT uses UDP on port 6881** between peers (standard BitTorrent DHT).
This is device-to-device traffic, NOT through quizthespire.com.
On platforms where UDP is available (Android, iOS, desktop): use `dart:io` RawDatagramSocket.

**Core operations:**
- `ping(NodeInfo node)` — verify a node is alive
- `findNode(Uint8List targetId)` — find nodes close to target
- `getPeers(String infohash)` — find peers for a torrent
- `announcePeer(String infohash, int port)` — tell DHT we have this torrent
- Routing table maintenance: refresh buckets every 15 minutes

### `lib/bittorrent/peer_wire.dart`

Implement BEP 3 peer wire protocol over TCP (or µTP via BEP 29 if available).

**Handshake:**
```
<pstrlen=19><pstr="BitTorrent protocol"><reserved (8 bytes)><infohash (20 bytes)><peer_id (20 bytes)>
```

**Messages:**
- `choke` / `unchoke` / `interested` / `not_interested`
- `have <piece_index>` — announce a piece we have
- `bitfield <bitfield>` — send our full piece availability on connect
- `request <index> <begin> <length>` — request a 16KB block
- `piece <index> <begin> <data>` — send a block
- `cancel <index> <begin> <length>` — cancel a request
- `port <port>` — DHT extension (BEP 5)

**Choking algorithm:**
- Unchoke the 4 peers with the highest upload rate to us (optimistic unchoke one random peer)
- Rechoke every 10 seconds
- This is the standard BitTorrent tit-for-tat mechanism

**For vault swarms:** before handing a piece to the caller, decrypt it with the vault AES key.
The peer wire protocol itself is identical — the decryption is a post-receive layer.

### `lib/bittorrent/piece_manager.dart`

- Store pieces at `{appDocDir}/vault/pieces/{infohash}/{piece_index}.piece`
- Verify each piece: SHA-1 hash (v1) or SHA-256 Merkle verification (v2)
- Piece selection: rarest-first (collect bitfields from all peers, pick lowest-count piece)
- For sequential mode: next-piece-first override
- Mark pieces as complete in `torrents.pieces_have` JSON bitfield
- On all pieces complete: concatenate, move to final path, update DB status to 'complete'

### `lib/bittorrent/torrent_session.dart`

Orchestrates everything for one active torrent:
- Load metadata (from .torrent file or fetched via DHT magnet bootstrap)
- Connect to trackers (HTTP GET announce — standard BEP 3)
- Bootstrap DHT peers for this infohash
- Maintain up to 50 peer connections
- Run piece manager
- Track stats: download speed, upload speed, ETA, ratio
- Expose as a `Stream<TorrentStatus>` for UI consumption

---

## PHASE 5 — Vault swarm (encrypted layer)

### `lib/vault_swarm/vault_link.dart`

```dart
class VaultLink {
  final String infohash;    // SHA-256 of plaintext file content — this IS the BT infohash
  final String keyB64;      // AES-256 key, base64url — lives in URI fragment

  String toUri() => 'vault://$infohash#$keyB64';
  // Also expressible as a hybrid magnet link for BT compatibility:
  // magnet:?xt=urn:btmh:1220$infohash&x.vault=1#$keyB64
  // (x.vault=1 is a custom extension parameter signalling encrypted content)

  static VaultLink parse(String uri) {
    if (uri.startsWith('vault://')) {
      final parsed = Uri.parse(uri);
      return VaultLink(parsed.host, parsed.fragment);
    }
    if (uri.startsWith('magnet:')) {
      final mag = MagnetLink.parse(uri);
      // Extract key from URI fragment if present
      return VaultLink(mag.infoHashV2!, Uri.parse(uri).fragment);
    }
    throw FormatException('Not a vault link or magnet link');
  }
}
```

**Seeding a vault file:**
1. Generate 32-byte AES file key
2. Split file into 256KB pieces
3. Encrypt each piece: `encryptBytes(piece, fileKey)` → encrypted bytes
4. Compute SHA-256 of each encrypted piece → piece hashes
5. Compute SHA-256 of the infohash structure → infohash (this IS the BT v2 infohash)
6. Create a `TorrentSession` seeding these encrypted pieces
7. Generate vault link: `vault://<infohash>#<keyB64>`

**Leeching a vault file:**
- Parse vault link → get infohash + key
- Create `TorrentSession` for the infohash (finds peers via DHT)
- On each piece received: verify hash, then decrypt with key
- Reassemble after all pieces verified and decrypted

---

## PHASE 6 — Telegram bridge

### `lib/bridges/telegram_bridge.dart`

```dart
class TelegramBridge {
  // Parse t.me links
  static String? extractChannelName(String input) {
    // Handles:
    // https://t.me/channelname
    // t.me/channelname
    // @channelname
    final patterns = [
      RegExp(r'https?://t\.me/([^/?]+)'),
      RegExp(r't\.me/([^/?]+)'),
      RegExp(r'^@([a-zA-Z0-9_]+)$'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(input.trim());
      if (m != null) return m.group(1);
    }
    return null;
  }

  // Fetch channel info + posts via VaultTheSpire server proxy
  Future<TelegramChannelData> fetchChannel(String channelName) async {
    final response = await http.get(
      Uri.parse('${kBaseUrl}/telegram/channel/$channelName'),
    );
    if (response.statusCode == 403) throw PrivateChannelException();
    if (response.statusCode != 200) throw TelegramBridgeException();
    return TelegramChannelData.fromJson(jsonDecode(response.body));
  }

  // Import as read-only vault channel
  Future<Channel> importAsVaultChannel(TelegramChannelData data) async {
    final existing = await channelsDao.findByTelegramHandle(data.username);
    if (existing != null) return existing;
    final channel = Channel(
      id: Uuid().v4(),
      name: data.name,
      description: data.description,
      ownerUsername: '@telegram/${data.username}',
      channelKey: '',            // no encryption for imported Telegram channels
      isPublic: true,
      isTelegramImport: true,
      telegramHandle: data.username,
      lastPostAt: data.posts.first.date,
    );
    await channelsDao.insert(channel);
    for (final post in data.posts) {
      await channelPostsDao.insert(ChannelPost.fromTelegram(channel.id, post));
    }
    return channel;
  }

  // Refresh (called every 15 minutes for subscribed imported channels)
  Future<void> refreshChannel(String telegramHandle) async {
    final data = await fetchChannel(telegramHandle);
    // Insert only new posts (by Telegram message ID)
    for (final post in data.posts) {
      final exists = await channelPostsDao.existsByTelegramId(post.id);
      if (!exists) await channelPostsDao.insert(ChannelPost.fromTelegram(...));
    }
  }
}
```

**What imported Telegram channels look like in UI:**
- Shown in Channels list with a "TG" badge on the avatar
- Posts display correctly: text, images cached locally, video linked
- No compose button — read-only, cannot post back
- "View on Telegram" link opens t.me URL in browser

---

## PHASE 7 — Signal contact QR import

### `lib/bridges/signal_qr.dart`

Signal's contact QR codes encode a URL like:
`https://signal.me/#p/<base64url_public_key>`

Parse this on scan:
```dart
class SignalQrImport {
  static Contact? tryParse(String qrData) {
    // Signal format
    final signalMatch = RegExp(r'signal\.me/#p/([A-Za-z0-9_\-]+)').firstMatch(qrData);
    if (signalMatch != null) {
      final keyB64 = signalMatch.group(1)!;
      // This is their X25519 public key (Signal uses X25519 for key exchange)
      return Contact(
        id: Uuid().v4(),
        username: 'signal_import_${keyB64.substring(0, 8)}',
        publicKey: keyB64,
        avatarSeed: keyB64.substring(0, 8),
        displayName: 'Signal contact',
        importedFrom: 'signal',
      );
    }
    // Generic vault QR format: JSON { username, public_key, avatar_seed }
    try {
      final json = jsonDecode(qrData);
      if (json['public_key'] != null) {
        return Contact.fromJson(json);
      }
    } catch (_) {}
    return null; // not a recognisable contact QR
  }
}
```

**On import:** derive shared secret, save to contacts DB, open a vault DM.
The Signal contact will receive a connection request if they also use VaultTheSpire
(unlikely initially, but the architecture supports it).
If they don't: the DM exists locally but cannot connect — show "Contact not yet on VaultTheSpire."

---

## PHASE 8 — Messaging (same as previous version, abbreviated)

- P2P service: one `RTCPeerConnection` per contact, DataChannel shared for DHT + chat + swarm
- Group service: mesh topology, shared group AES key distributed P2P
- Channel service: owner seeds channel content, subscribers pull from swarm
- Self-destruct: per-message timer, deletes from both devices + local media files
- Disappearing conversations: all messages get `self_destruct_at = sent_at + N hours`
- Message queue: outbound messages queued when peer offline, flushed on reconnect

---

## PHASE 9 — Torrent management UI

### SCREEN: `torrents_screen.dart`

List of all active torrents (both BitTorrent and vault). Columns on desktop, cards on mobile.

**Each entry shows:**
- Name, total size
- Type badge: `BT` (standard BitTorrent) or `VAULT` (encrypted vault)
- Status: downloading X% / seeding / paused / complete
- `PieceMapBar` widget (compact version)
- Download speed ↓ / Upload speed ↑
- Seeds × Leeches
- Ratio: uploaded/downloaded

**Actions:**
- Pause / Resume
- Remove (keep files / delete files)
- Open file location
- Copy magnet link / vault link
- Share vault link into a chat (opens contact/group picker)

**Add torrent:**
- FAB on mobile: "Add" → bottom sheet
  - "Paste magnet link" — text field, parse and add
  - "Open .torrent file" — file picker
  - "Paste vault link" — text field, parse and add
- Desktop: drag-and-drop .torrent file onto the window (handled by `desktop_drop`)
  or paste a magnet/vault link from clipboard (detect on focus via clipboard listener)

### SCREEN: `torrent_detail_screen.dart`

Full torrent detail:
- Large `PieceMapBar`
- Peer list: each peer's IP (shown as hash for privacy), piece availability %, connection speed
- File list (for multi-file torrents) with individual progress and selection toggles
- Stats: total downloaded, total uploaded, ratio, time active, ETA
- Vault link card (if type='vault') with copy and share buttons
- Tracker list with status (working / not working)
- Speed limits: per-torrent download/upload speed cap sliders

---

## PHASE 10 — Platform-adaptive layout

### `lib/platform/platform_adaptive_scaffold.dart`

Different layout on different platforms:

**Mobile (Android, iOS):**
- `BottomNavigationBar` with 4 items: Chats / Channels / Torrents / Explore
- Standard Flutter mobile navigation

**Desktop (Windows, macOS, Linux):**
- `NavigationRail` or sidebar (always-visible on large screens)
- Items: Chats / Channels / Torrents / Explore / Settings
- Window titlebar integrated: no custom title bar, use platform native
- Resizable columns: contacts list + conversation panel side by side
- Min window size: 800×600

**Detect platform:**
```dart
bool get isDesktop =>
  Platform.isWindows || Platform.isMacOS || Platform.isLinux;
bool get isMobile =>
  Platform.isAndroid || Platform.isIOS;
```

### `lib/platform/desktop_window.dart`

```dart
Future<void> setupDesktopWindow() async {
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1100, 700),
    minimumSize: Size(800, 600),
    center: true,
    title: 'VaultTheSpire',
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
```

### `lib/platform/system_tray.dart`

```dart
Future<void> setupSystemTray() async {
  final tray = SystemTray();
  await tray.initSystemTray(
    iconPath: 'assets/tray_icon.png',
    toolTip: 'VaultTheSpire',
  );
  final menu = Menu();
  await menu.buildFrom([
    MenuItemLabel(label: 'Show', onClicked: (_) => windowManager.show()),
    MenuItemLabel(label: 'New Message', onClicked: (_) { windowManager.show(); router.go('/'); }),
    MenuSeparator(),
    MenuItemLabel(label: 'Quit', onClicked: (_) => exit(0)),
  ]);
  await tray.setContextMenu(menu);
  tray.registerSystemTrayEventHandler((event) {
    if (event == kSystemTrayEventClick) windowManager.show();
  });
}
```

### Desktop keyboard shortcuts (`lib/platform/hotkeys.dart`)

Register these on desktop init:
- `Ctrl+N` / `Cmd+N`: new message
- `Ctrl+F` / `Cmd+F`: search
- `Ctrl+,` / `Cmd+,`: settings
- `Ctrl+T` / `Cmd+T`: new torrent (paste magnet or open file)
- `Escape`: close current modal/panel

### Drag and drop (`lib/platform/drag_drop.dart`)

```dart
DropTarget(
  onDragDone: (details) async {
    for (final file in details.files) {
      if (file.name.endsWith('.torrent')) {
        await torrentService.addTorrentFile(File(file.path));
      }
    }
  },
  child: ...,
)
```

Also detect magnet links pasted from clipboard:
```dart
// On window focus, check clipboard
final clip = await Clipboard.getData('text/plain');
if (clip?.text?.startsWith('magnet:') == true) {
  showAddTorrentDialog(clip!.text!);
}
```

---

## PHASE 11 — Push notifications (all platforms)

### Android + iOS: Firebase Cloud Messaging (as before)

FCM payload — zero message content:
```json
{ "type": "vault_wake", "room_code": "WOLF-3847",
  "from_username": "alice", "avatar_seed": "a3f9" }
```

### Windows + macOS + Linux: polling fallback

FCM does not support Windows/Linux desktop (as of 2026, Firebase desktop support is incomplete).
Desktop uses a background polling loop instead.

```dart
// lib/platform/notifications_desktop.dart
class DesktopNotificationPoller {
  Timer? _timer;

  void start() {
    _timer = Timer.periodic(Duration(seconds: 30), (_) => _poll());
  }

  Future<void> _poll() async {
    // Check if any contacts have pending connection requests
    // by querying each contact's signal room (if we know they tried to reach us)
    // Alternatively: use a lightweight long-poll endpoint:
    // GET /vault/api/notify/poll?username=<ours>
    // Server returns { pending: [{ from, room_code }] } if someone tried to reach us
    // This requires one more server-side table (vault_pending_wakes):
    //   id, to_username, from_username, room_code, avatar_seed, created_at, expires_at
    // Post to this table when FCM is unavailable (server detects desktop user agent)
    final pending = await signalService.pollPendingWakes(ourUsername);
    for (final wake in pending) {
      await _showDesktopNotification(wake.fromUsername);
      await p2pService.acceptConnection(wake.fromUsername, wake.roomCode);
    }
  }

  Future<void> _showDesktopNotification(String from) async {
    await flutterLocalNotifications.show(
      from.hashCode,
      'VaultTheSpire',
      'New message from $from',
      const NotificationDetails(/* platform-specific */),
    );
  }
}
```

**Additional server route for desktop polling (add to website todo):**
- `POST /vault/api/notify/wake` — called by sender when target is a desktop user
  Body: `{ to_username, from_username, room_code, avatar_seed }`
  Inserts into `vault_pending_wakes` with `expires_at = NOW() + 5 minutes`
- `GET /vault/api/notify/poll?username=<ours>`
  Returns and DELETES all pending wakes for this username
  Desktop polls this every 30 seconds

---

## PHASE 12 — Platform-specific build notes

### Android
- `minSdkVersion 21`
- Internet permission in AndroidManifest: `<uses-permission android:name="android.permission.INTERNET" />`
- Camera permission for QR scanner
- Microphone permission for voice messages
- Storage permission for file access (Android 12 and below)
- Build: `flutter build apk --release` for APK, `flutter build appbundle` for Play Store

### iOS
- Deployment target: iOS 13
- NSCameraUsageDescription, NSMicrophoneUsageDescription in Info.plist
- Background modes: `fetch`, `remote-notification` in Info.plist
- Build: `flutter build ipa` for TestFlight/App Store

### Windows
- `flutter build windows --release`
- Creates an `.exe` in `build/windows/runner/Release/`
- Package with Inno Setup or MSIX for distribution
- Code signing: required for distribution outside the app store to avoid SmartScreen warnings
  (same issue Oroka notes on quizthespire.com with ConvertTheSpire — same solution: warn users)
- No Firebase support on Windows — use desktop polling fallback (Phase 11)

### macOS
- `flutter build macos --release`
- Creates `.app` in `build/macos/Build/Products/Release/`
- Package as `.dmg` using `create-dmg` CLI tool
- Requires code signing + notarization for Gatekeeper
  Without signing: users must right-click → Open to bypass Gatekeeper
- Entitlements needed: `com.apple.security.network.client` (outbound network)
- No Firebase support on macOS — use desktop polling fallback

### Linux
- `flutter build linux --release`
- Creates binary in `build/linux/x64/release/bundle/`
- Package as `.AppImage` using `appimagetool` for portable distribution
  Or as `.deb` / `.rpm` for distro packages
- No system tray on all Linux DEs — check `system_tray` compatibility and fail gracefully

### CI/CD build matrix (GitHub Actions example):
```yaml
jobs:
  build-android:  runs-on: ubuntu-latest
  build-ios:      runs-on: macos-latest
  build-windows:  runs-on: windows-latest
  build-macos:    runs-on: macos-latest
  build-linux:    runs-on: ubuntu-latest
```
Each job: checkout → flutter setup → build → upload artifact to `/vault/downloads/`

---

## PHASE 13 — Onboarding (all platforms)

**Step 1:** "Generating your identity..." — spinner
**Step 2:** Choose username (optional — skip for offline-only use)
**Step 3:** "Connecting to the network..." — DHT bootstrap
  - Connects to public BT bootstrap nodes (router.bittorrent.com etc.)
  - Connects to VaultTheSpire bootstrap nodes (from quizthespire.com)
  - Shows "X peers found"
**Step 4:** "Import from another app?" — optional cards:
  - "I use Telegram" → paste a t.me channel link to import
  - "I use Signal" → scan a Signal contact QR to import a contact
  - "I use qBittorrent" → "Your magnet links work here automatically"
  - "Skip" → go directly to home
**Step 5:** Own QR contact card

---

## PHASE 14 — QA checklist

**BitTorrent compatibility:**
- [ ] Magnet link (v1 btih) opens and joins existing swarm (test with a known public torrent)
- [ ] Magnet link (v2 btmh) opens and joins existing swarm
- [ ] Hybrid magnet (both btih + btmh) works correctly
- [ ] .torrent file opens via file picker (mobile) and drag-and-drop (desktop)
- [ ] Pieces SHA-1 verified on receipt (v1 torrent)
- [ ] DHT finds peers for a popular infohash within 60 seconds
- [ ] PEX: peer list grows over time beyond initial DHT results
- [ ] Upload slot choking algorithm: verified with two simultaneous leechers

**Vault swarm:**
- [ ] Vault link generated correctly: `vault://<sha256>#<base64key>`
- [ ] Vault link shared in chat, recipient taps → downloads and decrypts
- [ ] Piece verification + decryption roundtrip: corrupted piece rejected
- [ ] Seeded vault file accessible after sharer goes offline (if other peers have it)

**Telegram import:**
- [ ] `t.me/telegram` imports as read-only channel
- [ ] Private channel returns clear error message
- [ ] Imported channel shows "TG" badge, no compose button
- [ ] Posts refresh every 15 minutes
- [ ] Image attachments in posts cached locally

**Signal import:**
- [ ] Signal QR code parsed correctly (extract public key from `signal.me/#p/` URL)
- [ ] Contact imported, shared secret derived, DM screen opens
- [ ] "Contact not yet on VaultTheSpire" shown if contact can't connect

**Desktop:**
- [ ] Windows: app runs, system tray icon visible, no SmartScreen block (or clear warning)
- [ ] macOS: app runs, Gatekeeper warning shown if unsigned (expected)
- [ ] Linux: AppImage runs on Ubuntu 22.04, Fedora 38, and Arch
- [ ] Sidebar layout on desktop, bottom nav on mobile
- [ ] Drag-and-drop .torrent file onto desktop window
- [ ] Ctrl+N / Cmd+N opens new message
- [ ] Desktop polling: notification appears within 30 seconds of message

**Privacy:**
- [ ] Zero message content in any HTTP request to quizthespire.com (Charles Proxy)
- [ ] Zero content in logs
- [ ] SQLCipher DB unreadable without key
- [ ] Vault link key stays in URI fragment — never in HTTP request

**All platforms:**
- [ ] Onboarding completes on Android, iOS, Windows, macOS, Linux
- [ ] Chat, group, channel, torrent screens all render correctly on each platform
- [ ] Dark theme correct on all platforms

---

## Notes for the AI building this

- ALL HTTP calls to quizthespire.com: `https://quizthespire.com/vault/api/...` — no other ports.
- BitTorrent DHT and peer wire protocol use standard ports (6881-6889 UDP/TCP) BETWEEN PEERS.
  quizthespire.com is not a peer and does not need those ports open.
- Standard BT bootstrap nodes (router.bittorrent.com:6881 etc.) are separate from
  quizthespire.com and use their own standard ports. This is correct and expected.
- Firebase push (FCM) does NOT support Windows or Linux as of 2026.
  Use the desktop polling fallback (Phase 11) for those platforms. Do not try to make FCM
  work on desktop — it will fail at build time.
- macOS requires code signing + notarization for seamless distribution. Without it,
  users get a Gatekeeper warning. Document this clearly in the installer.
- Windows requires code signing to avoid SmartScreen. Same as ConvertTheSpire — warn users.
- SQLCipher: all platforms supported. The `sqlcipher_flutter_libs` package handles
  per-platform native builds.
- The Telegram bridge is READ-ONLY. VaultTheSpire does not post to Telegram, does not
  require a Telegram account, and does not implement MTProto. It uses the public Bot API
  through the server proxy. This is legal and within Telegram's Bot API terms.
- The Signal QR import is key-import only. VaultTheSpire does not implement the Signal
  protocol. It cannot communicate with Signal users who don't also have VaultTheSpire.
  Be honest about this in the UI: "Import a contact's public key to start a vault chat."
- Bencode implementation: implement from scratch in Dart. It is ~100 lines and well-specified.
  Do not use a binary blob or native library for something this simple.
- App name: VaultTheSpire — V-T-S capitals, no spaces, everywhere consistently.
- Tagline: "What goes into the Vault, stays in the Vault."