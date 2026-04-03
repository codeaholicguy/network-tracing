---
phase: implementation
title: Implementation Guide
description: Technical implementation notes for macOS menubar network monitor
---

# Implementation Guide

## Development Setup

**Prerequisites:**
- Xcode 15 or later (or `swift build` from CLI)
- macOS 13 Ventura or later
- No external dependencies

**Build & run:**
```bash
# From the worktree root
swift build
swift run NetworkTracer

# Run tests
swift test

# Run tests with coverage
swift test --enable-code-coverage
```

## Code Structure

SPM layout (no Xcode `.xcodeproj`):

```
Sources/
├── NetworkTracerCore/           # Testable library target
│   ├── ConnectionRecord.swift   # Data model
│   ├── ConnectionStore.swift    # @MainActor ObservableObject
│   ├── ConnectionParser.swift   # Stateless parsing + name cleaning
│   ├── NetworkMonitor.swift     # Actor, lsof subprocess loop
│   └── DNSResolver.swift        # Actor, PTR + ipinfo.io org lookup
└── NetworkTracer/               # Executable target
    ├── main.swift               # Entry point
    ├── AppDelegate.swift        # NSStatusItem + NSPopover
    └── PopoverView.swift        # SwiftUI 4-column list

Tests/
└── NetworkTracerTests/
    ├── ConnectionParserTests.swift   # 21 tests
    ├── ConnectionRecordTests.swift   # 7 tests
    ├── ConnectionStoreTests.swift    # 12 tests
    ├── DNSResolverTests.swift        # 7 tests
    └── NetworkMonitorTests.swift     # 6 tests
```

## Key Implementation Notes

### No Dock icon (SPM executable)

```swift
// main.swift — no Info.plist available in SPM executables
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    app.delegate = delegate
}
app.run()
```

### NSStatusItem + NSPopover

```swift
// AppDelegate.swift
@MainActor class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Network")
        statusItem.button?.action = #selector(togglePopover)

        let store = ConnectionStore.shared
        popover = NSPopover()
        popover.contentSize = NSSize(width: 580, height: 340)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView().environmentObject(store)
        )
        Task { await NetworkMonitor.shared.start(store: store) }
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            button.toolTip = "\(ConnectionStore.shared.connections.count) active connections"
        }
    }
}
```

### Data models

```swift
// ParsedConnection — intermediate parse result
public struct ParsedConnection: Hashable, Sendable {
    public let remoteAddress: String   // "ip:port"
    public let processName: String     // cleaned COMMAND field
}

// ConnectionRecord — one UI row
public struct ConnectionRecord: Identifiable, Hashable, Sendable {
    public let id: String              // "processName|ip:port"
    public var remoteAddress: String
    public var processName: String
    public var hostname: String?       // PTR record; nil until resolved
    public var org: String?            // ipinfo.io org; nil until resolved
    public var lastSeen: Date

    // "hostname:port" when PTR resolves, else raw "ip:port"
    public var displayName: String { ... }
    // Bare IP without port, for DNS lookup
    public var ipAddress: String { Self.extractIP(from: remoteAddress) }
    public static func extractIP(from address: String) -> String { ... }
}
```

### ConnectionParser

```swift
public enum ConnectionParser {
    // Returns deduplicated (processName, remoteAddress) pairs
    public static func parse(_ output: String) -> [ParsedConnection]

    // Decodes lsof \xNN hex escapes, strips " (Renderer)" suffix,
    // shortens "com.apple.X" → "X"
    static func cleanProcessName(_ raw: String) -> String

    // Decodes \xNN sequences (e.g. \x20 → space)
    static func unescapeLSOF(_ s: String) -> String
}
```

lsof args: `-i -n -P +c 0`
- `-i` network files only
- `-n` numeric IPs (no hostname resolution in lsof)
- `-P` numeric ports
- `+c 0` unlimited COMMAND column width (full process name)

### NetworkMonitor

```swift
public actor NetworkMonitor {
    public static let shared = NetworkMonitor()

    // Production init: real lsof, 5 s interval
    public init()
    // Test init: injectable data provider and short interval
    init(pollInterval: TimeInterval, dataProvider: @escaping () -> String)

    public func start(store: ConnectionStore)  // Task loop
    public func stop()                         // cancel loop
}
```

### ConnectionStore

```swift
@MainActor public final class ConnectionStore: ObservableObject {
    @Published public var connections: [ConnectionRecord] = []
    private let staleThreshold: TimeInterval = 15.0
    private let maxConnections = 500

    public func update(with incoming: [ParsedConnection])
    public func applyHostname(_ hostname: String, forID id: String)
    public func applyOrg(_ org: String, forID id: String)

    private func resolveAndApply(remoteAddress: String, id: String) async
    // calls DNSResolver.shared.resolveHostname then .resolveOrg sequentially
}
```

### DNSResolver

```swift
public actor DNSResolver {
    public static let shared = DNSResolver()

    // PTR record via POSIX getnameinfo(NI_NAMEREQD); cached
    public func resolveHostname(ip: String) async -> String?

    // ipinfo.io GET /{ip}/org; strips "AS##### " prefix; cached
    public func resolveOrg(ip: String) async -> String?

    // Blocking POSIX lookup — internal, exposed for unit tests
    static func reverseResolve(ip: String) -> String?
}
```

### PopoverView

4 columns; Host:Port takes flexible space:

| Column | Width |
|--------|-------|
| App | 130 pt (fixed) |
| Host:Port | flexible (`maxWidth: .infinity`) |
| Org | 100 pt (fixed) |
| Last Seen | 70 pt (fixed) |

Total popover width: 580 pt.

## Error Handling

- `lsof` process launch failure → returns `""`, store retains last-known state (stale window applies).
- DNS resolution failure → `hostname` stays nil; `displayName` falls back to raw `ip:port`.
- ipinfo.io failure → `org` stays nil; Org column shows `"—"` in secondary color.
- Actor isolation ensures no data races on `ConnectionStore` or `DNSResolver`.

## Security Notes

- No network entitlements required.
- App reads only connection metadata (IP addresses, ports, process names) — no payload.
- `/usr/sbin/lsof` is a fixed path; no user-provided input is passed to it.
- `resolveOrg` sends IP addresses to ipinfo.io (documented in `DNSResolver` header).
