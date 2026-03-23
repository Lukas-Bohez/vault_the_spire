# VaultTheSpire — Discord-Direction Feature Suggestions

## 0. Roadmap & release plan
- [x] Phase 1: Core Discord-like UX, task lists, messaging + torrents navigation, style and theming (completed)
- [ ] Phase 2: Channels/guilds, role system, invite links, DM + server message persistence
- [ ] Phase 3: Voice rooms, rich embeds, server discovery, advanced permission system

## 1. Differentiation & Marketing
- [ ] Write clear landing page copy emphasizing "no company in the middle"
- [ ] Add in-app messaging: "Your community, your rules, your keys"
- [ ] Document clearly that no messages are stored on any central server
- [ ] Add a comparison page vs Discord highlighting E2E encryption and P2P architecture

## 2. Voice Channels
- [ ] Design voice channel UI (room list in server sidebar)
- [ ] Implement WebRTC audio streams for voice rooms
- [ ] Add mute/deafen controls
- [ ] Add user speaking indicators (visual feedback when someone talks)
- [ ] Support multiple simultaneous voice rooms per server
- [ ] Add voice channel join/leave notifications in text channel

## 3. Server/Guild System
- [ ] Design server creation flow (name, icon, invite link)
- [ ] Implement server list sidebar (like Discord's left icon rail)
- [ ] Add channel categories within servers (text channels + voice channels)
- [ ] Support server icons and banners
- [ ] Add server discovery/explore screen for public servers

## 4. Invite Links & Onboarding
- [ ] Generate shareable invite links for servers
- [ ] Support QR code invites (scan to join)
- [ ] Add invite link expiry options (1 use, 7 days, never, etc.)
- [ ] Deep link support: tapping a vault:// invite link opens the app and joins server
- [ ] Show server preview (name, member count, description) before joining

## 5. Torrent Integration in Servers
- [ ] Allow sharing magnet/vault links directly in chat channels
- [ ] Render vault/magnet links as rich cards in chat (name, size, seed count)
- [ ] Tap a shared torrent card to add it directly to the torrent engine
- [ ] Show download progress inline in chat
- [ ] Add a "Files" tab per server showing all shared torrents in that community

## 6. Roles & Permissions
- [ ] Implement basic role system: Owner, Admin, Moderator, Member
- [ ] Add role-based channel visibility (private channels for specific roles)
- [ ] Add role-based permissions: who can post, upload, manage members
- [ ] Allow custom roles with custom names and colors
- [ ] Add role assignment UI in server settings

## 7. Rich Link Embeds
- [ ] Fetch Open Graph metadata for pasted URLs
- [ ] Render link previews in chat (title, description, thumbnail)
- [ ] Support image URL auto-preview inline
- [ ] Support YouTube/video link embed cards
- [ ] Add option to dismiss/collapse embeds per message

## 8. Scope & Prioritization (Stay Focused)
- [ ] Lock v1.x scope to: servers, text channels, DMs, basic roles, invite links
- [ ] Defer voice channels to v1.5 or v2.0
- [ ] Defer rich embeds until core stability is proven
- [ ] Write a public roadmap so community knows what's coming
- [ ] Set up a feedback channel (GitHub Issues or in-app) for user suggestions