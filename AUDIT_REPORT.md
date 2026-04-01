# AUDIT_REPORT

Date: 2026-04-01
Scope: `lib/**/*.dart` (first-party app code)
Method: source-only static audit via indexed pattern search and targeted file inspection.

## Executive Summary

Primary risks identified:
1. High rebuild pressure in streaming AI chat paths (assistant output updated on nearly every token).
2. Navigation inconsistency risk in browser duplicate-torrent flow (`pushNamed('/torrent_detail')` not present in router table).
3. Theme-hardcoded color values spread across multiple UI screens/widgets.
4. Timer-heavy polling architecture in UI/services (potential battery/CPU overhead).
5. Null-safety force-unwrap hotspots in core models/database code.
6. Legacy naming/remnants (`vault`/`swarm`) still present in data model and copy.

## Findings By Severity

### Critical

None found in this pass.

### High

#### H1: Streaming chat update flood causes excessive UI rebuilds
- Evidence:
  - `lib/screens/ai_chat_screen.dart:303` (`chatStream` loop)
  - `lib/screens/torrentspire_ai_screen.dart:479` (`chatChunkStream` loop)
- Risk:
  - Rebuild per token can cause frame drops/jank and unnecessary CPU usage during long AI responses.
- Status:
  - Remediated in this cycle by throttling visible stream updates (~80ms cadence) with forced final flush.

#### H2: Named route mismatch in duplicate torrent navigation
- Evidence:
  - `lib/router.dart:21-25` (declared routes do not include `/torrent_detail`)
  - `lib/screens/browser_screen.dart` duplicate-torrent handling previously attempted `pushNamed('/torrent_detail')` and fallback.
- Risk:
  - Runtime navigation failure path and inconsistent behavior.
- Status:
  - Remediated in this cycle by using direct `MaterialPageRoute(TorrentDetailScreen)` path consistently.

### Medium

#### M1: Hardcoded colors reduce theme consistency
- Evidence (sample):
  - `lib/screens/torrentspire_ai_screen.dart:688`
  - `lib/screens/torrentspire_ai_screen.dart:713`
  - `lib/screens/messages_screen.dart:121`
  - `lib/widgets/platform_adaptive_scaffold.dart:121`
  - `lib/main.dart:182`
- Risk:
  - Inconsistent light/dark behavior, visual drift, accessibility contrast regressions.
- Recommendation:
  - Move screen-level color constants to theme tokens (`ThemeData`, `ColorScheme`, extension tokens).

#### M2: Multiple periodic timers increase baseline polling load
- Evidence (sample):
  - `lib/screens/torrentspire_ai_screen.dart:83`
  - `lib/screens/browser_screen.dart:445`
  - `lib/services/background_service.dart:74`
  - `lib/services/torrent_engine_service.dart:712`
- Risk:
  - Elevated battery/CPU/network use and potential duplicate polling logic.
- Recommendation:
  - Consolidate polling ownership, switch to event-driven streams where feasible, and gate timers by lifecycle/visibility.

### Low

#### L1: Null-safety force unwrap hotspots
- Evidence (sample):
  - `lib/models/torrent.dart:34` (`totalPieces!`)
  - `lib/db/database.dart:21`
  - `lib/db/database.dart:52`
- Risk:
  - Crash risk if assumptions drift over time.
- Recommendation:
  - Replace with explicit guards and fail-soft defaults where possible.

#### L2: Legacy naming remnants (`vault`/`swarm`)
- Evidence (sample):
  - `lib/models/torrent.dart:13` (`vaultKey`)
  - `lib/models/torrent.dart:15` (`vaultLink`)
  - `lib/constants.dart:1` (`/vault/api`)
  - `lib/screens/home_screen.dart:33` (Vault copy)
- Risk:
  - Product terminology inconsistency and migration friction.
- Recommendation:
  - Introduce alias/deprecation plan (schema + API + UI copy) to avoid breaking persistence/backward compatibility.

## Remediation Order

1. Completed: H1 streaming chat throttling.
2. Completed: H2 route mismatch cleanup.
3. Next: M1 theme tokenization of hardcoded colors.
4. Next: M2 timer/polling consolidation.
5. Next: L1 force-unwrap hardening.
6. Next: L2 naming remnant migration plan.

## Verification Plan

- Run analyzer on modified files and full project analyzer pass.
- Run targeted tests around AI chat, browser/torrent flows, routing, and torrent status updates.
- Manual checks:
  - Stream long AI responses and verify smooth scrolling/rendering.
  - Add duplicate torrent from browser flow and verify direct detail navigation.
  - Validate light/dark theme consistency after token migration.

## Notes

- Third-party code in `third_party/` was excluded from first-party risk ownership except when noted as reference context.
- This report was generated from source-only evidence to avoid binary/build artifact contamination.
