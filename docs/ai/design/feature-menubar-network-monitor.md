---
phase: design
title: System Design & Architecture
description: macOS menubar app architecture using SwiftUI + NSStatusItem, lsof polling, reverse DNS
---

# System Design & Architecture

## Architecture Overview

```mermaid
graph TD
    App[AppDelegate / App Entry] -->|creates| StatusItem[NSStatusItem\nMenubar Icon]
    App -->|starts| Monitor[NetworkMonitor\nBackground Actor]
    Monitor -->|polls every 5s| LSOF[lsof -i -n -P +c 0]
    LSOF -->|raw output| Parser[ConnectionParser]
    Parser -->|ParsedConnection list| Store[ConnectionStore\n@Published state]
    Store -->|observed by| PopoverView[SwiftUI PopoverView\nNSPopover]
    StatusItem -->|click| PopoverView
    Store -->|new connection| DNSResolver[DNSResolver\nasync/await]
    DNSResolver -->|hostname PTR| Store
    DNSResolver -->|org ipinfo.io| Store
```

**Key components:**
- `AppDelegate` / `@main` — bootstraps the app as a menubar-only agent (no Dock icon) via `setActivationPolicy(.accessory)`.
- `NSStatusItem` — the menubar icon; toggles an `NSPopover` on click.
- `NetworkMonitor` — Swift `actor` with a `Task` loop that shells out to `lsof` every 5 s and updates the store.
- `ConnectionParser` — pure functions that turn raw `lsof` text into `[ParsedConnection]`; cleans process names.
- `ConnectionStore` — `@MainActor ObservableObject` holding deduplicated, sorted connection list.
- `DNSResolver` — async actor; `resolveHostname(ip:)` via POSIX `getnameinfo`; `resolveOrg(ip:)` via ipinfo.io; separate caches.
- `PopoverView` — SwiftUI `List` with 4 columns: App | Host:Port | Org | Last Seen.

**Technology stack:**
- Swift 5.9+, SwiftUI, AppKit (for `NSStatusItem` / `NSPopover`).
- No third-party dependencies.
- Deployment target: macOS 13 Ventura.

## Data Models

```swift
// Intermediate parse result from lsof output
struct ParsedConnection: Hashable, Sendable {
    let remoteAddress: String   // "ip:port"
    let processName: String     // cleaned COMMAND field
}

// Stored connection record (one row in the UI)
struct ConnectionRecord: Identifiable, Hashable, Sendable {
    let id: String              // "processName|ip:port" — dedup key
    var remoteAddress: String   // raw "ip:port"
    var processName: String     // cleaned app name (e.g. "Google Chrome")
    var hostname: String?       // PTR record hostname (e.g. "dns.google"), nil until resolved
    var org: String?            // owning org from ipinfo.io (e.g. "Google LLC"), nil until resolved
    var lastSeen: Date

    var displayName: String     // "hostname:port" when PTR resolves, else "ip:port"
    var ipAddress: String       // bare IP without port (for DNS lookup)
}
```

**Data flow:**
1. `NetworkMonitor` task loop → shells `lsof -i -n -P +c 0`.
2. `ConnectionParser.parse(_:)` extracts unique `(processName, remoteAddress)` pairs as `[ParsedConnection]`.
3. `ConnectionStore.update(with:)` upserts records (update `lastSeen`; add new; purge stale after 15 s).
4. For each new record, `resolveAndApply` fires two concurrent background lookups:
   - `DNSResolver.resolveHostname(ip:)` → updates `hostname` (used in Host:Port column).
   - `DNSResolver.resolveOrg(ip:)` → updates `org` (shown in Org column).
5. SwiftUI view re-renders via `@Published` / `@EnvironmentObject`.

## API Design

Internal interfaces only (no external HTTP API).

**`NetworkMonitor`**
```swift
actor NetworkMonitor {
    func start(store: ConnectionStore)  // begins polling loop
    func stop()                         // cancels loop
}
```

**`ConnectionParser`**
```swift
enum ConnectionParser {
    static func parse(_ lsofOutput: String) -> [ParsedConnection]
    static func cleanProcessName(_ raw: String) -> String  // unescape + strip suffix + shorten domain
    static func unescapeLSOF(_ s: String) -> String        // decode \xNN hex sequences
}
```

**`ConnectionStore`**
```swift
@MainActor class ConnectionStore: ObservableObject {
    @Published var connections: [ConnectionRecord]  // sorted newest-first
    func update(with incoming: [ParsedConnection])
    func applyHostname(_ hostname: String, forID id: String)
    func applyOrg(_ org: String, forID id: String)
}
```

**`DNSResolver`**
```swift
actor DNSResolver {
    func resolveHostname(ip: String) async -> String?  // PTR record; cached
    func resolveOrg(ip: String) async -> String?       // ipinfo.io org; cached
}
```

## Component Breakdown

### AppDelegate / MenubarApp
- No Info.plist — calls `NSApplication.shared.setActivationPolicy(.accessory)` (SPM executable, no Dock icon).
- Creates `NSStatusItem` with system symbol `network`.
- Creates `NSPopover` (580 × 340 pt, `.transient` behavior) hosting `NSHostingController<PopoverView>`.
- On status item button click: toggle popover show/close; update tooltip with connection count.

### PopoverView (SwiftUI)
```
┌──────────────────────────────────────────────────────────────┐
│ Network Connections                              23 active    │
├──────────────┬──────────────────────┬────────────┬───────────┤
│ App          │ Host : Port          │ Org        │ Last Seen │
├──────────────┼──────────────────────┼────────────┼───────────┤
│ curl         │ dns.google:443       │ Google LLC │ 14:23:05  │
│ Safari       │ 17.57.144.20:443     │ Apple Inc  │ 14:22:58  │
│ …            │ …                    │ …          │ …         │
└──────────────┴──────────────────────┴────────────┴───────────┘
```
- Fixed widths: App 130 pt · Host:Port flexible (`maxWidth: .infinity`) · Org 100 pt · Last Seen 70 pt.
- Empty state: centered text "No active connections".
- Popover size: 580 × 340 pt; scrollable.

### NetworkMonitor
- Swift `actor` to avoid data races.
- `Task` loop with `Task.sleep(for: .seconds(5))` — no timer.
- Shells out: `Process` running `/usr/sbin/lsof -i -n -P +c 0` (`+c 0` = unlimited COMMAND width).
- Captures stdout, passes to `ConnectionParser`.

### ConnectionParser
- Stateless pure functions.
- Includes only lines with `->` (connected sockets); excludes `*:*` and `*:port` (listening/wildcard).
- Extracts remote address (right of `->`, strip `(STATE)`), and process name (first whitespace token).
- `cleanProcessName`: decodes lsof `\xNN` hex escapes → strips ` (Renderer)`-style suffixes → shortens `com.apple.X` → `X`.
- Returns deduplicated `[ParsedConnection]` (by `processName + remoteAddress`).

### DNSResolver
- Swift `actor` with two independent caches: `hostnameCache` and `orgCache`.
- `resolveHostname(ip:)`: blocking POSIX `getaddrinfo(AI_NUMERICHOST)` + `getnameinfo(NI_NAMEREQD)` on a background `DispatchQueue` thread.
- `resolveOrg(ip:)`: async HTTP GET `https://ipinfo.io/{ip}/org`; strips leading `AS##### ` prefix.

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Network data source | Shell out to `lsof` | No entitlements required; works for current user without root; simple to implement. Network Extension requires Apple dev account + notarization for distribution. |
| UI framework | SwiftUI inside NSPopover | Native look; no dependencies; SwiftUI handles reactive updates cleanly. |
| Concurrency | Swift actors + async/await | Prevents data races; modern Swift idiom. |
| Dedup key | `"processName\|remoteAddress"` | Same IP:port can be held by multiple processes simultaneously; including the process name prevents merging unrelated connections. |
| "Last seen" semantics | Timestamp when polling loop last observed the connection | True send-time requires pcap; polling timestamp is a good-enough proxy. |
| Stale connection window | Keep records 15 seconds after last seen | Avoids flicker when a connection briefly drops off the poll. |

## Non-Functional Requirements

- **Performance:** `lsof` poll completes in < 500 ms on a typical Mac; timer interval of 5 s keeps CPU impact negligible.
- **Memory:** Connection list bounded to ~500 unique remote hosts max (drop oldest if exceeded).
- **Security:** App only reads connection metadata; no payload data captured. No network entitlements needed.
- **Reliability:** If `lsof` fails (not found, permission error), log the error and retry next interval; UI shows last known state.
- **Accessibility:** Row text uses system fonts; popover respects system appearance (light/dark mode).
