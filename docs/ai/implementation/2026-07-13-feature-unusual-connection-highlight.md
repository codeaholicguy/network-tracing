---
phase: implementation
title: Implementation Guide
description: Technical implementation notes, patterns, and code guidelines
---

# Implementation Guide

## Development Setup

- Work in feature worktree `.worktrees/feature-unusual-connection-highlight`.
- Use the existing Swift package; no new dependencies are required for the attention foundation.
- `swift test` may need to run outside the Codex filesystem sandbox because SwiftPM can fail manifest sandbox setup with `sandbox_apply: Operation not permitted`.

## Code Structure

- `Sources/NetworkTracerCore/AttentionEvaluator.swift`
  - `AttentionState`
  - `AttentionResult`
  - `AcceptedHighlightPattern`
  - `AcceptedPatternID`
  - `AttentionEvaluator`
- `Sources/NetworkTracerCore/AcceptedPatternStore.swift`
  - `AcceptedPatternStore`
  - `ImportSummary`
  - `AcceptedPatternStoreError`
- `Sources/NetworkTracerCore/ConnectionRecord.swift`
  - Carries `attention`.
  - Provides endpoint value generation.
  - Uses explicit `Hashable`/`Equatable` by stable `id`.
- `Sources/NetworkTracerCore/ConnectionStore.swift`
  - Loads accepted patterns.
  - Evaluates row attention on update, hostname/org enrichment, accept, remove, and import.
  - Exposes `needsAttentionOnly`, `visibleConnections`, and `attentionCount`.
  - Persists accept/remove/import/export actions through `AcceptedPatternStore`.
- `Sources/NetworkTracer/PopoverView.swift`
  - Shows attention markers, attention count, needs-attention filter, and row accept action.
- `Sources/NetworkTracer/AcceptedPatternsView.swift`
  - Shows the accepted-pattern management sheet with remove, import, and export actions.
- `Sources/NetworkTracer/AppDelegate.swift`
  - Includes attention count in the menubar tooltip when any row needs attention.
  - Shows a visible warning emoji on the bottom-right of the menubar network icon when any row needs attention.
- `Tests/NetworkTracerTests/AttentionEvaluatorTests.swift`
  - Covers id generation, slug normalization, endpoint matching, hostname/IP candidate behavior, org metadata independence, and port specificity.
- `Tests/NetworkTracerTests/AcceptedPatternStoreTests.swift`
  - Covers missing-file load, save/load, export shape, import merge, malformed imports, invalid records, conflicts, duplicate handling, and org-fill behavior.
- `Tests/NetworkTracerTests/ConnectionStoreTests.swift`
  - Covers attention evaluation on store updates, accepted-pattern loading, hostname re-evaluation, org metadata behavior, accept/remove/import actions, filtering, stale eviction, and max row retention.

## Implementation Notes

### Core Features
- Implemented foundation slice:
  - `AttentionState.accepted` and `AttentionState.needsAttention`.
  - `AttentionResult.accepted(patternID:)` and `AttentionResult.needsAttention(patternID:)`.
  - `AcceptedHighlightPattern` with required `processName`, required `value`, and optional `org`.
  - `AcceptedPatternID.make(processName:value:)` using `<process-slug>--<value-slug>`.
  - `ConnectionRecord.endpointValues(preferHostname:)`.
  - `AttentionEvaluator.evaluate(record:acceptedPatterns:)`.

Matching behavior:
- Candidate values are `hostname:port` first when hostname exists, then raw `remoteAddress` as IP:port.
- A row is accepted when the canonical accepted-pattern id exists and its stored `processName + value` matches the row candidate.
- Imported JSON must use canonical ids generated from `processName + value`; non-canonical ids are rejected during import instead of supported through runtime fallback matching.
- If no candidate matches, the result is `needsAttention` with message `Not accepted yet`.
- `org` is metadata only and never participates in id generation or acceptance matching.

Implemented persistence slice:
- `AcceptedPatternStore.defaultFileURL()` resolves `~/Library/Application Support/NetworkTracer/accepted-patterns.json`.
- `load()` returns an empty dictionary when the file is missing.
- `save(_:)` writes a pretty-printed, sorted-key JSON object and creates missing directories.
- `export(_:to:)` writes only accepted-pattern records.
- `importPatterns(from:into:)` validates a JSON object keyed by accepted-pattern id and merges into the current dictionary.
- Import rejects malformed JSON/top-level arrays without mutating local state.
- Import rejects empty/invalid ids, non-canonical ids, missing `processName`, missing `value`, non-string `org`, and same-id conflicts where `processName` or `value` differs.
- Duplicate imports with the same canonical id may fill missing local `org` but do not overwrite existing local `org`.

Implemented store integration slice:
- `ConnectionStore` accepts an injected `AcceptedPatternStore` for tests and loads accepted patterns during initialization.
- Default `ConnectionStore()` creates the default app-support accepted-pattern store when available.
- `update(with:)` evaluates attention on every published row after stale eviction, sort, and max-row capping.
- `applyHostname(_:forID:)` re-evaluates the row because hostname may change the preferred endpoint value.
- `applyOrg(_:forID:)` preserves org metadata and re-evaluates without making org part of matching.
- `acceptEndpoint(forID:)` writes the current preferred endpoint candidate, including optional org metadata, persists it, and re-evaluates visible rows.
- `acceptAllNeedingAttention()` writes preferred endpoint candidates for every current row needing attention, persists once, and re-evaluates visible rows.
- `removeAcceptedPattern(id:)` persists removal and re-evaluates visible rows.
- `importAcceptedPatterns(from:)` merges JSON through `AcceptedPatternStore`, then re-evaluates visible rows.
- `exportAcceptedPatterns(to:)` delegates the current accepted-pattern dictionary to `AcceptedPatternStore`.
- `needsAttentionOnly` and `visibleConnections` provide filtering without changing the underlying active connection list.

Implemented UI workflow slice:
- Header shows active connection count and attention count.
- Header shows `Approve All` when any row needs attention.
- Header includes a `Needs Attention` checkbox bound to `ConnectionStore.needsAttentionOnly`.
- Empty state distinguishes no active connections from no connections needing attention.
- Rows show a compact SF Symbol marker for accepted vs needs-attention state.
- Row tooltip exposes `Not accepted yet` or `Accepted`.
- Rows needing attention expose an inline `Approve` button that accepts the current endpoint without requiring a context menu.
- The top-bar `Approve All` button batch-accepts all current rows needing attention.
- Accepted rows show a quiet checkmark in the action column to keep row layout stable.
- `Accepted Patterns` sheet lists id, process, endpoint value, and optional org.
- Management sheet supports remove, JSON import, JSON export, and import summary feedback.
- Menubar tooltip includes attention count when applicable.
- Menubar icon overlays a warning emoji on the bottom-right of the network icon when any current connection needs attention.

### Patterns & Best Practices
- Keep attention evaluation pure and network-free.
- Keep persistence out of the evaluator; persistence belongs in `AcceptedPatternStore` and `ConnectionStore` actions.
- Keep file persistence synchronous and deterministic for now; `ConnectionStore` can call it from main-actor actions because files are small.
- Use `ConnectionRecord` as the row model instead of creating a separate UI projection for v1.
- Preserve existing row identity semantics: equality and hashing are by stable `id`, not mutable fields like `lastSeen`, `hostname`, `org`, or `attention`.

## Integration Points

- `ConnectionStore` now owns runtime attention state and accepted-pattern actions.
- `PopoverView` calls `ConnectionStore` APIs for accept/remove/import/export and does not duplicate persistence logic.
- `AcceptedPatternsView` is split from `PopoverView` so live-connection UI and accepted-pattern management are easier to scan independently.
- `AppDelegate` caches normal and attention status-bar images so frequent connection publications do not recreate menu bar image assets.

## Error Handling

- Store load/save/export methods throw file or decoding errors to the caller.
- Import throws only for unreadable/malformed files or non-object JSON; per-record validation failures are counted in `ImportSummary.rejected`.
- Import validates into a working dictionary first so malformed files do not mutate local state.

## Performance Considerations

- Evaluator checks generated id first for O(1) lookup.
- Endpoint value generation allocates at most two values per row.
- Accepted-pattern JSON files should stay small; sorted pretty JSON favors human review over byte size.

## Security Notes

- No network calls, credentials, or external services were added.
- The feature language remains non-alarmist: `accepted` or `needs attention`, not threat verdicts.
- Import/export contains accepted endpoint patterns only; tests assert no live connection fields such as `remoteAddress`, `hostname`, or `lastSeen` are exported.

## Validation

- `SKIP_INTEGRATION_TESTS=1 swift test` passed after simplification: 90 tests, 3 expected integration skips, 0 failures.
- `swift test --enable-code-coverage` passed after review fixes: 89 tests, 0 failures.
- `npx ai-devkit@latest lint --feature unusual-connection-highlight` passed after review documentation updates.
- P4 UI compile validation passed through `swift test`.
- Launch smoke with `swift run NetworkTracer` built the app target and kept it running until intentionally stopped with Ctrl-C.
- Interactive popover/manual import-export checks were completed by the user in a real macOS session.
- New coverage:
  - 11 `AttentionEvaluatorTests`.
  - 14 `AcceptedPatternStoreTests`.
  - 9 new `ConnectionStoreTests` for P3 integration, bringing store coverage to 24 tests.
