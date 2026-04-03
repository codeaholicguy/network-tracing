---
phase: testing
title: Testing Strategy
description: Testing approach for macOS menubar network monitor
---

# Testing Strategy

## Test Coverage Goals

- Unit tests: 100% of `ConnectionParser`, `ConnectionStore`, `DNSResolver`, `ConnectionRecord`, `NetworkMonitor` logic.
- Integration: real lsof subprocess path + real network DNS tested (skip with `SKIP_INTEGRATION_TESTS=1`).
- Manual: UI popover behavior, dark/light mode, empty state.

## Coverage Results

| File | Lines | Functions | Notes |
|---|---|---|---|
| `ConnectionStore.swift` | 100% | 100% | ✅ |
| `DNSResolver.swift` | 100% | 100% | ✅ |
| `ConnectionParser.swift` | 100% | 100% | ✅ |
| `ConnectionRecord.swift` | ~97% | ~80% | ✅ (missed: synthesized `hash` guard branch) |
| `NetworkMonitor.swift` | ~95% | ~88% | ✅ (missed: `catch {}` in `runLSOF()` — unreachable on macOS) |

Run: `swift test --enable-code-coverage`

## Unit Tests (53 total)

### ConnectionParser (21 tests)

**parse()**
- [x] `parse_emptyString_returnsEmpty`
- [x] `parse_noArrowLines_returnsEmpty`
- [x] `parse_singleEstablishedLine_returnsRemoteAndProcess` — extracts `remoteAddress` and `processName`
- [x] `parse_deduplicatesSameProcessAndRemote`
- [x] `parse_differentProcessesSameRemote_returnsTwoRows`
- [x] `parse_ignoresStarStarRemotes`
- [x] `parse_ignoresListeningWildcardRemotes`
- [x] `parse_multipleLines_returnsAllUnique`
- [x] `parse_handlesIPv6Address` — bracketed `[::1]:8080` parsed correctly
- [x] `parse_hexEscapedProcessName_unescaped` — `Google\x20Chrome` → `Google Chrome`

**cleanProcessName()**
- [x] `cleanProcessName_plainName_unchanged`
- [x] `cleanProcessName_stripsParentheticalSuffix` — ` (Renderer)`, ` (GPU)`
- [x] `cleanProcessName_reverseDomain_takesLastComponent` — `com.apple.WebKit.Networking` → `Networking`
- [x] `cleanProcessName_withVersionSuffix_unchanged` — `python3.11`
- [x] `cleanProcessName_unescapesHexBeforeStripping`

**unescapeLSOF()**
- [x] `unescapeLSOF_noEscapes_unchanged`
- [x] `unescapeLSOF_spaceEscape` — `\x20` → space
- [x] `unescapeLSOF_openParenEscape` — `\x28\x29` → `()`
- [x] `unescapeLSOF_multipleEscapes`
- [x] `unescapeLSOF_bareBackslash_passedThrough`
- [x] `unescapeLSOF_backslashX_noDigits_passedThrough`

### ConnectionRecord (7 tests)

- [x] `displayName_withHostname_returnsHostnameAndPort`
- [x] `displayName_nilHostname_returnsRawAddress`
- [x] `displayName_withIPv6AndHostname`
- [x] `ipAddress_extractsIPv4` — `"192.168.1.1:80"` → `"192.168.1.1"`
- [x] `ipAddress_extractsIPv6` — `"[::1]:8080"` → `"::1"`
- [x] `hashable_deduplicatesInSet`
- [x] `differentProcesses_notDeduplicated`

### ConnectionStore (12 tests)

- [x] `update_newAddress_createsRecord`
- [x] `update_existingAddress_updatesLastSeen`
- [x] `update_staleAddress_removed` — purged after > 15 s
- [x] `update_sortedNewestFirst`
- [x] `update_emptyAddresses_keepsWithinStaleWindow`
- [x] `update_differentProcessSameRemote_twoRows`
- [x] `update_exceedsMaxConnections_dropsOldest` — bounded at 500
- [x] `applyHostname_updatesExistingRecord` — sets `hostname`, `displayName` reflects it
- [x] `applyHostname_unknownID_noOp`
- [x] `applyOrg_updatesExistingRecord` — sets `org`
- [x] `applyOrg_unknownID_noOp`
- [x] `update_hostnameAndOrgPreservedOnRefresh`

### DNSResolver (7 tests)

- [x] `resolveHostname_loopback_returnsLocalhost` — loopback always has PTR; no external network
- [x] `resolveHostname_ipv6Loopback_returnsLocalhost`
- [x] `resolveHostname_cachesResult`
- [x] `reverseResolve_invalidIP_returnsNil` — synchronous POSIX helper
- [x] `reverseResolve_loopback_returnsLocalhost`
- [x] `resolveOrg_knownIP_returnsOrgName` *(integration — skip with `SKIP_INTEGRATION_TESTS=1`)*
- [x] `resolveOrg_cachesResult` *(integration)*

### NetworkMonitor (6 tests)

- [x] `start_updatesStoreWithParsedConnections` — injectable data provider
- [x] `start_withEmptyData_storeRemainsEmpty`
- [x] `start_withEmptyData_existingRecordsRetainedWithinStaleWindow`
- [x] `stop_preventsMonitorTaskFromRunning` — `SendableBox` call-count check
- [x] `pollInterval_isCorrectForDefaultInit`
- [x] `integration_realLSOF_doesNotCrash` *(integration — skip with `SKIP_INTEGRATION_TESTS=1`)*

## End-to-End Tests (Manual)

- [ ] **E2E-1:** Launch app → menubar icon appears within 2 s.
- [ ] **E2E-2:** Click icon → popover opens; list shows at least one connection if network is active.
- [ ] **E2E-3:** Wait 5 s → list updates (timestamps change for active connections).
- [ ] **E2E-4:** Disconnect all network → after 15 s list empties; empty state message shown.
- [ ] **E2E-5:** Click outside popover → popover dismisses.
- [ ] **E2E-6:** Toggle system appearance Light ↔ Dark → popover adapts.
- [ ] **E2E-7:** Hover status item → tooltip shows connection count.
- [ ] **E2E-8:** Process with spaces in name (e.g. "Google Chrome") displays correctly (no `\x20`).
- [ ] **E2E-9:** Host:Port column shows `hostname:port` when PTR resolves; Org column shows org name independently.

## Manual Testing Outcomes

| Test | Result | Notes |
|---|---|---|
| E2E-1 | — | Not yet run |
| E2E-2 | — | Not yet run |
| E2E-3 | — | Not yet run |
| E2E-4 | — | Not yet run |
| E2E-5 | — | Not yet run |
| E2E-6 | — | Not yet run |
| E2E-7 | — | Not yet run |
| E2E-8 | — | Not yet run |
| E2E-9 | — | Not yet run |

## Test Data

Sample `lsof` fixture (for unit tests):
```
COMMAND   PID   USER  FD  TYPE  DEVICE  SIZE/OFF  NODE  NAME
curl      1234  user  5u  IPv4  0x0     0t0       TCP   192.168.1.5:54321->142.250.80.46:443 (ESTABLISHED)
Safari    5678  user  12u IPv4  0x0     0t0       TCP   192.168.1.5:60001->17.57.144.20:443 (ESTABLISHED)
curl      1234  user  6u  IPv4  0x0     0t0       TCP   192.168.1.5:54322->142.250.80.46:443 (ESTABLISHED)
```
Expected `parse` result: two `ParsedConnection` values —
`(processName: "curl", remoteAddress: "142.250.80.46:443")` and
`(processName: "Safari", remoteAddress: "17.57.144.20:443")`.
(The duplicate curl→142.250.80.46:443 on a different local port is deduped.)

## Performance Testing

- Poll cycle (lsof subprocess) should complete in < 500 ms; measurable via `Date()` diff in `NetworkMonitor`.
- UI re-render triggered by `@Published` update should not stutter; profile with Instruments if needed.
