---
phase: requirements
title: Requirements & Problem Understanding
description: Highlight unusual active network connections without claiming security verdicts
---

# Requirements & Problem Understanding

## Problem Statement

NetworkTracer currently lists active network connections, but every row has the same visual weight. That makes the popover useful as a raw monitor and weak as a decision tool: users still need to manually scan process names, ports, hosts, and organizations to decide what deserves attention.

The problem is not that users need malware detection. The real problem is triage. Developers, privacy-conscious users, and power users need help spotting connections that are new, uncommon, unexplained, or worth investigating while avoiding false certainty.

**Who is affected:**
- Developers checking what local apps, CLIs, SDKs, and background tools are connecting to.
- Privacy-conscious users looking for surprising outbound traffic.
- Power users investigating a specific app's network behavior.

**Current workaround:**
- Manually inspect every visible row.
- Mentally remember whether an app has connected to a host/org before.
- Run terminal tools like `lsof`, `netstat`, or ad hoc IP lookup commands.

This does not scale once the list contains browsers, sync tools, helper processes, and many short-lived connections.

## Goals & Objectives

**Primary goals:**
- Mark active connections that are not yet accepted by the user.
- Treat a connection as accepted when its process and endpoint value exist in the accepted-pattern JSON.
- Keep language careful: "needs attention" or "accepted", not "dangerous" or "malicious".
- Work with the current `lsof`-based architecture and without root privileges.
- Provide value even when external IP enrichment is disabled or unavailable.

**Secondary goals:**
- Allow users to filter the popover to connections needing attention only.
- Allow users to accept expected highlight patterns and persist those acceptances across launches.
- Allow users to export and import accepted patterns so trusted decisions can move to another Mac.
- Keep the model compatible with future persistent behavioral baselines.
- Support app-level rollups once app-centric grouping exists.
- Keep the first version simple enough that users can understand exactly why a row needs attention.

**Non-goals:**
- No traffic blocking or firewall controls.
- No malware, threat, attack, or compromise classification.
- No packet payload inspection.
- No Network Extension, system extension, or root-only dependency.
- No upload of full connection history to any backend.
- No notifications for every highlighted row.
- No persistent full historical connection baseline in the first version.
- No automatic sync of accepted patterns between machines.
- No country/ASN dependency for core value in the first version.

## User Stories & Use Cases

- As a developer, I want unaccepted connections to be marked so I can quickly focus on rows that may matter.
- As a privacy-conscious user, I want to see whether a connection is accepted or needs attention so I can decide whether it is expected.
- As a power user, I want to filter to rows needing attention so I do not scan the full connection list.
- As a user, I want to accept expected highlights so repeated known behavior stops distracting me across app launches.
- As a user, I want to export and import accepted patterns so I can carry known-good decisions to another machine.
- As a user, I want cautious wording so I do not confuse "needs attention" with "unsafe".
- As a future user of app-centric grouping, I want app rows to show whether any child connection needs attention.

**Key workflows:**
- Open popover and immediately spot rows that need attention.
- Hover or select a row and see whether it is accepted or needs attention.
- Toggle a needs-attention-only filter.
- Accept a known app-endpoint pattern and have it remain accepted after restarting NetworkTracer.
- Export accepted patterns to a portable file.
- Import accepted patterns from a portable file on another Mac.
- Continue using the app when DNS/org lookup fails, because acceptance is based on process and endpoint value.

**Edge cases:**
- First app launch after NetworkTracer starts can produce many unaccepted rows; UI must not look like a security incident.
- Browsers and Electron apps connect to many hosts; the needs-attention state should be quiet and review-oriented.
- Raw IPs can be normal for CDNs, local services, VPNs, and developer tools.
- A host may resolve after the row is first created; the accepted value should use the best current endpoint display value.
- IPv6 endpoints must be parsed consistently with current `ConnectionRecord.extractIP` and port handling.
- Private/local/reserved IP ranges should not be treated the same as public internet endpoints.

## Attention Rules

The first version should implement an allowlist-style attention model. Full heuristic detection, persistent connection history, and long-term behavioral baselines are deferred.

**Required v1 rule:**
- Build the current endpoint value for each row, preferably `hostname:port` when hostname is available, otherwise `ip:port`.
- Generate the accepted-pattern id from `processName + value`.
- If that id exists in the accepted-pattern JSON and its record matches the same `processName` and `value`, the row is accepted.
- If no matching accepted pattern exists, the row needs attention.

**Deferred signals:**
- New host for app.
- New org for app.
- Raw IP only.
- Uncommon port.
- Many hosts from one process.
- Country changes.
- ASN changes.
- Background/frontmost app activity.
- Code signing identity or parent process based rules.

These deferred signals add complexity and should not block v1. The accepted-endpoint model is the source of truth for the first release.

## Severity & Language

Use explainability labels, not threat labels.

**Suggested states:**
- `Accepted`: a matching accepted pattern exists.
- `Needs attention`: no matching accepted pattern exists.

**Banned labels in UI copy:**
- dangerous
- malware
- threat
- attack
- compromised
- infected
- suspicious, unless the user explicitly opts into stronger security wording later

The feature is a review aid. It does not determine intent or safety.

## UX Requirements

- Rows needing attention must have a compact visual marker that does not break the existing four-column table.
- Each row needing attention should expose a short reason, such as `Not accepted yet`.
- The row marker must be scannable without turning the entire popover into an alert surface.
- A needs-attention-only filter must be available from the popover.
- The header should show attention count when attention rows exist, for example `4 need attention`.
- Users must be able to accept a specific pattern persistently.
- Accepted patterns should be intentionally simple: `processName` plus a `value`.
- `value` is the accepted endpoint string, preferably host:port when hostname is available, otherwise IP:port.
- `org` should be stored when available so accepted entries preserve the owning organization shown in the UI.
- Accepted patterns must stop contributing row highlights across app launches.
- Users must be able to review and remove accepted patterns.
- Users must be able to export accepted patterns to a file.
- Users must be able to import accepted patterns from a file.
- Imports must not silently overwrite all existing accepted patterns; default behavior should merge and deduplicate.
- The empty needs-attention-only state must say there are no connections needing attention, not that there are no active connections.

## Data Requirements

The app needs accepted patterns loaded from local persistent storage.

Each connection record, or a companion view model, must expose:
- attention state: accepted or needs attention
- attention reason, initially `Not accepted yet`
- accepted-pattern id candidate used for matching

The feature also needs a durable accepted-pattern store.

Accepted pattern records must include:
- process/app identifier used for matching, initially process name
- accepted value string
- optional organization string

The store must be local-only. The import/export format should be a plain human-readable JSON object keyed by accepted-pattern id.

Required JSON shape:

```json
{
  "safari--example-com": {
    "processName": "Safari",
    "value": "example.com",
    "org": "Cloudflare, Inc."
  },
  "node--example-com-3000": {
    "processName": "node",
    "value": "example.com:3000"
  },
  "curl--192-168-1-1": {
    "processName": "curl",
    "value": "192.168.1.1"
  }
}
```

The object key is the accepted-pattern id. Values must contain `processName` and `value`, and may contain `org` when known. No other fields are required.

Accepted-pattern ids must be generated deterministically from the accepted `processName` and `value`:
- Normalize `processName` into a slug.
- Normalize `value` into a slug.
- Join them as `<process-slug>--<value-slug>`.

Slug normalization:
- lowercase
- trim surrounding whitespace
- replace every run of non-alphanumeric characters with `-`
- trim leading/trailing `-`

Examples:
- `Safari` + `example.com` -> `safari--example-com`
- `node` + `example.com:3000` -> `node--example-com-3000`
- `curl` + `192.168.1.1` -> `curl--192-168-1-1`

If two imported records use the same id but different `processName` or `value`, the import should reject the conflicting record and report it. Imported ids must be canonical ids generated from their own `processName + value`; non-canonical ids are rejected rather than silently accepted. `org` is metadata and must not change the id.

The accepted-pattern store is the v1 source of truth:
- Accepted-pattern store determines whether a row is accepted.
- Missing accepted pattern means the row needs attention.
- Future heuristic baselines can be added without changing the accepted-pattern JSON format.

## Import / Export Requirements

- Export writes accepted patterns to a user-chosen JSON file.
- Import reads a user-selected JSON file and validates that it is an object whose keys are accepted-pattern ids and whose values contain string `processName` and `value` fields. If present, `org` must also be a string.
- Default import behavior merges accepted patterns into the local store.
- Duplicate imported patterns are deduplicated by the same canonical id and matching `processName + value`.
- If a duplicate import has an `org` and the local record does not, import may fill the missing `org`; otherwise local data should win.
- Imported records with missing, empty, or invalid ids should be rejected rather than silently regenerated.
- Import must report how many patterns were added, skipped as duplicates, or rejected as invalid.
- Invalid import files must fail safely without modifying the existing accepted-pattern store.
- Exported files must not include live connection history, timestamps of all observations, or DNS/org lookup cache contents.
- Import/export should not require network access.
- Imported patterns should be visible in the accepted-pattern review UI after import.

## Privacy Requirements

- Core highlighting must work without external lookup services.
- Host-based and port-based rules must not require ipinfo.io.
- Org-based rules may depend on existing org lookup behavior.
- If a local-only privacy mode is added later, unusual highlighting must respect it.
- Requirements and UI must be transparent that org enrichment can send IPs to a third-party provider when enabled by existing behavior.
- Accepted-pattern persistence must remain local to the user's Mac unless the user explicitly exports a file.
- Exported accepted-pattern files are user-controlled data and may reveal installed apps and expected network destinations; export UI should make that clear.
- Import should treat files as untrusted input: validate structure, reject malformed records, and avoid path traversal or executable content concerns by only parsing data.

## Alternatives Considered

**Option A: Simple row badges only**
- Trade-off: fastest to build and lowest risk, but limited learning value.
- Suitable for v1 if the app remains row-centric.

**Option B: Accepted-endpoint attention model with persistent accepted patterns**
- Trade-off: simpler and easier to understand, but less analytical than heuristic detection.
- Recommended for v1.

**Option C: Full persistent behavioral baseline**
- Trade-off: highest long-term value, but adds storage, reset controls, privacy expectations, and false-positive management.
- Defer until highlighting proves useful.

**Chosen approach:** Option B. Build an accepted-endpoint attention model with careful UI labels and persistent accepted patterns. Store only explicit user acceptances, not full historical connection behavior. Add JSON import/export so accepted decisions can move across machines.

## Success Criteria

- Opening the popover makes rows needing attention visually distinguishable from accepted rows.
- Every attention row has a machine-readable state and user-facing explanation.
- Users can filter to rows needing attention only.
- Users can accept an expected app-endpoint pattern and keep it accepted after restarting the app.
- Users can review and remove accepted patterns.
- Users can export accepted patterns to JSON.
- Users can import accepted patterns from JSON on another Mac.
- Import validates the object-by-id shape and fails without modifying local data when the file is malformed.
- The feature works with current-user `lsof` data and requires no root privileges or Network Extension entitlement.
- The feature remains useful if org lookup fails or is unavailable.
- A first-run burst of unaccepted connections is presented as review work, not as an alarm.
- Existing rows without highlights remain readable and do not lose current columns.
- Unit tests cover accepted matching, attention state, persistence, import/export validation, and hostname/org updates.

## Constraints & Assumptions

**Technical constraints:**
- macOS 13+.
- Swift 5.9, SwiftUI, AppKit.
- No new third-party dependencies for v1.
- Current source of truth is `lsof -i -n -P +c 0`.
- Active connection records are currently deduped by `processName|remoteAddress`.
- DNS and org lookup results arrive asynchronously after row creation.

**Product constraints:**
- Be honest about uncertainty.
- Favor quiet triage over alarm.
- Avoid making browsers and common sync tools unusably noisy.
- Treat accepted-pattern files as portable user data, not telemetry or analytics.

**Assumptions accepted for v1:**
- Accepted-endpoint review is enough to create v1 user value.
- Persistent explicit acceptances are required for v1.
- Full persistent behavioral baselines remain deferred.
- Country/ASN/process metadata can be deferred.
- A process name is an acceptable app identity until a later process detail feature adds bundle/path metadata.

## Questions & Open Items

- Accepted-pattern storage path: resolved in design as `~/Library/Application Support/NetworkTracer/accepted-patterns.json`.
- Organization acceptance: deferred. For v1, `org` is metadata on accepted endpoint records, not a separately matched acceptance scope.
- App-centric grouping: deferred. This feature ships in the existing row-centric UI and exposes attention state that app-centric grouping can roll up later.
- Heuristic rules: deferred. v1 uses accepted endpoint matching only.
