# NetworkTracer

A macOS menubar app that shows all active network connections in real time — which process is connecting, where it's connecting to, and who owns that IP.

**Columns:** App | Host:Port | Org | Last Seen

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ command-line tools (`xcode-select --install`)
- No external dependencies

## Build

```bash
swift build
```

For a release build:

```bash
swift build -c release
```

The compiled binary is at `.build/debug/NetworkTracer` or `.build/release/NetworkTracer`.

## Run

```bash
swift run NetworkTracer
```

Or run the compiled binary directly:

```bash
.build/debug/NetworkTracer
```

The app has no Dock icon — it lives in the menubar. Click the network icon to open the connection list. Click anywhere outside the popover to dismiss it.

> The app calls `lsof` to read your network connections. It only sees connections owned by your user account (no root required).

## Test

```bash
# Run all tests
swift test

# Skip tests that require a network connection
SKIP_INTEGRATION_TESTS=1 swift test

# Run with code coverage
swift test --enable-code-coverage
```

## Project Structure

```
Sources/
├── NetworkTracerCore/        # Core library (testable)
│   ├── ConnectionParser.swift    # Parses lsof output, cleans process names
│   ├── ConnectionRecord.swift    # Data model for one connection row
│   ├── ConnectionStore.swift     # Observable state (@MainActor)
│   ├── NetworkMonitor.swift      # Polls lsof every 5 seconds
│   └── DNSResolver.swift         # Reverse DNS + ipinfo.io org lookup
└── NetworkTracer/            # App executable
    ├── main.swift                # Entry point
    ├── AppDelegate.swift         # NSStatusItem + NSPopover setup
    └── PopoverView.swift         # SwiftUI 4-column list

Tests/
└── NetworkTracerTests/       # 53 unit + integration tests
    ├── ConnectionParserTests.swift
    ├── ConnectionRecordTests.swift
    ├── ConnectionStoreTests.swift
    ├── DNSResolverTests.swift
    └── NetworkMonitorTests.swift

docs/ai/                      # Dev lifecycle docs (requirements → testing)
```

## How It Works

1. `NetworkMonitor` runs `lsof -i -n -P +c 0` every 5 seconds as a subprocess.
2. `ConnectionParser` extracts `(processName, remoteAddress)` pairs, cleaning lsof's hex-escaped names (e.g. `Google\x20Chrome` → `Google Chrome`).
3. `ConnectionStore` upserts records keyed by `"processName|ip:port"`. Records not seen for 15 seconds are removed.
4. For each new connection, two background lookups fire:
   - **Reverse DNS** (PTR record) — shown in the Host:Port column as `hostname:port`.
   - **Org lookup** via [ipinfo.io](https://ipinfo.io) — shown in the Org column (e.g. `Google LLC`).

## Continue Development

### Adding a feature

1. Make changes in `Sources/NetworkTracerCore/` (business logic) or `Sources/NetworkTracer/` (UI).
2. Add or update tests in `Tests/NetworkTracerTests/`.
3. Run `swift test` to verify nothing is broken.
4. Run `swift run NetworkTracer` for a manual smoke test.

### Key extension points

| What to change | Where |
|---|---|
| Poll interval | `NetworkMonitor.init()` — `self.pollInterval = 5.0` |
| Stale timeout | `ConnectionStore` — `staleThreshold = 15.0` |
| Max rows | `ConnectionStore` — `maxConnections = 500` |
| Process name cleaning rules | `ConnectionParser.cleanProcessName(_:)` |
| Column widths | `PopoverView` — `appWidth`, `orgWidth`, `timeWidth` constants |
| Popover size | `AppDelegate` — `popover.contentSize` |

### Running a single test file

```bash
swift test --filter ConnectionParserTests
```

### Checking code coverage

```bash
swift test --enable-code-coverage
xcrun llvm-cov report \
  .build/debug/NetworkTracerPackageTests.xctest/Contents/MacOS/NetworkTracerPackageTests \
  -instr-profile=.build/debug/codecov/default.profdata \
  --ignore-filename-regex='.build|Tests'
```
