---
phase: planning
title: Project Planning & Task Breakdown
description: Task breakdown for macOS menubar network monitor app
---

# Project Planning & Task Breakdown

## Milestones

- [x] **M1 — Skeleton:** Menubar icon appears; popover opens/closes.
- [x] **M2 — Live Data:** Connection list populated from `lsof`; auto-refreshes.
- [x] **M3 — Polish:** Reverse DNS, sorting, empty state, error handling. *(dark mode: manual verify pending)*
- [x] **M4 — Identity:** App/process column; process name cleaning (hex-escape, parentheticals, reverse-domain).
- [x] **M5 — Enrichment:** ipinfo.io org lookup; separate hostname (PTR) and org columns. *(manual verify pending)*

## Task Breakdown

### Phase 1: Project Scaffold

- [x] **T1.1** Create SPM project with `Package.swift` (macOS 13+, two targets: `NetworkTracerCore` library + `NetworkTracer` executable).
- [x] **T1.2** No Dock icon — set via `NSApplication.shared.setActivationPolicy(.accessory)` in `main.swift`.
- [x] **T1.3** Implement `AppDelegate` with `NSStatusItem` creation (system symbol `network`).
- [x] **T1.4** Create `NSPopover` and wire status item button click to toggle show/close.
- [x] **T1.5** `PopoverView` wired as popover content from day one (no placeholder needed).
- [ ] **T1.6** Verify: app launches, icon appears in menubar, click shows/hides popover. *(manual)*

### Phase 2: Network Data Layer

- [x] **T2.1** Implement `ConnectionParser.parse(_:) -> [ParsedConnection]` — parses `lsof -i` text output; returns unique `(processName, remoteAddress)` pairs. Uses `+c 0` flag for full process names.
- [x] **T2.2** Write unit tests for `ConnectionParser` (21 tests, all passing).
- [x] **T2.3** Implement `NetworkMonitor` actor — runs `lsof -i -n -P +c 0` as a subprocess every 5 seconds.
- [x] **T2.4** Implement `ConnectionRecord` struct and `ConnectionStore` `ObservableObject` with `update(with:)` upsert logic. Dedup key is `"processName|remoteAddress"`.
- [x] **T2.5** Wire `NetworkMonitor` → `ConnectionStore` in `AppDelegate`; start monitor on launch.

### Phase 3: UI

- [x] **T3.1** Implement `PopoverView` with `List` of connection rows — 4 columns: App | Host:Port | Org | Last Seen.
- [x] **T3.2** Format `lastSeen` as `HH:mm:ss` using `DateFormatter`.
- [x] **T3.3** Sort connections newest-first in `ConnectionStore`.
- [x] **T3.4** Add empty state: centered "No active connections" text when list is empty.
- [x] **T3.5** Popover size 580 × 340 pt (widened to accommodate 4 columns).

### Phase 4: DNS Resolution & Polish

- [x] **T4.1** Implement `DNSResolver` actor — async reverse DNS via `getnameinfo`; separate caches for hostname (PTR) and org (ipinfo.io).
- [x] **T4.2** Wire DNS resolution into `ConnectionStore.resolveAndApply` — resolves new addresses in background via two methods: `resolveHostname` and `resolveOrg`.
- [x] **T4.3** Host:Port column shows `displayName` (`hostname:port` when PTR resolves, else `ip:port`).
- [x] **T4.4** Stale-connection removal — records not seen for > 15 s are purged on next update.
- [x] **T4.5** `lsof` failure handled gracefully (returns `""`, store retains last-known state).
- [ ] **T4.6** Verify light mode and dark mode appearance. *(manual)*
- [x] **T4.7** Menubar icon tooltip updated with connection count on each popover open.

### Phase 5: Process Identity (discovered)

- [x] **T5.1** Extend `ParsedConnection` to carry `processName` (COMMAND field from lsof `+c 0`).
- [x] **T5.2** Implement `ConnectionParser.cleanProcessName(_:)` — strips ` (Renderer)` / ` (GPU)` suffixes; shortens `com.apple.X` → `X`.
- [x] **T5.3** Implement `ConnectionParser.unescapeLSOF(_:)` — decodes lsof `\xNN` hex sequences (e.g. `Google\x20Chrome` → `Google Chrome`).
- [x] **T5.4** Add App column to `PopoverView` (width 100 pt, truncates tail).
- [x] **T5.5** Tests: 21 `ConnectionParser` tests covering parse, cleanProcessName, unescapeLSOF.

### Phase 6: Org Enrichment (discovered)

- [x] **T6.1** Add `fetchOrg(ip:)` to `DNSResolver` — GET `https://ipinfo.io/{ip}/org`; strip `AS##### ` prefix.
- [x] **T6.2** Add `org: String?` field to `ConnectionRecord`; `hostname` field now PTR-only.
- [x] **T6.3** `ConnectionStore.applyOrg(_:forID:)` applies resolved org to existing records.
- [x] **T6.4** Org column in `PopoverView` shows `record.org ?? "—"` (independent of hostname).
- [x] **T6.5** Tests: `DNSResolverTests` covers `resolveHostname` and `resolveOrg` separately.

## Dependencies

- T2.1 before T2.3 (parser needed before monitor can produce records).
- T2.3, T2.4 before T2.5 (need store + monitor before wiring).
- T2.5 before T3.x (need live data before UI can show real content).
- T3.x before T4.1 (UI stable before adding async DNS on top).
- T4.1 before T4.2 (resolver needed before wiring).

No external library dependencies. Xcode + Swift standard library only.

## Risks & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `lsof` output format varies across macOS versions | Low | Medium | Pin to parsing the `NAME` column only; add regression fixtures for multiple OS versions. |
| DNS resolution slow / blocking UI | Medium | Medium | Always resolve in a background `Task`; UI renders raw IP immediately and updates when hostname arrives. |
| User's system has restricted `lsof` (SIP, MDM) | Low | High | Detect empty output; show informative error message in popover instead of empty list. |
| Popover dismiss conflicts with NSPopover behavior | Low | Low | Use `NSPopover.behavior = .transient` so clicks outside dismiss it. |

## Resources Needed

- Xcode 15+ with macOS 13 SDK.
- A Mac running macOS 13+ for testing.
- No external accounts or services required.
