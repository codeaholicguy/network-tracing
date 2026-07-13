---
phase: planning
title: Project Planning & Task Breakdown
description: Break down work into actionable tasks and estimate timeline
---

# Project Planning & Task Breakdown

## Milestones

- [x] **M1: Attention model foundation** - add deterministic accepted-pattern ids, endpoint value helpers, and pure attention evaluation.
- [x] **M2: Persistent accepted-pattern store** - save/load/import/export the minimal JSON object under Application Support.
- [x] **M3: Store integration** - wire accepted patterns into `ConnectionStore` so every active row is accepted or needs attention.
- [x] **M4: User workflow** - expose count, filter, accept, review, remove, import, and export actions in the popover.
- [x] **M5: Verification** - cover evaluator, persistence, store integration, and manual UI workflows.

## Task Breakdown

### Phase 1: Foundation

- [x] **P1.1: Add attention data types**
  - Outcome: introduce `AttentionState`, `AttentionResult`, `AcceptedHighlightPattern`, and a small attention configuration type in `NetworkTracerCore`.
  - Validation: unit tests compile with existing `ConnectionRecord` call sites and default attention state is deterministic.
- [x] **P1.2: Add accepted-pattern id generation**
  - Outcome: deterministic id helper produces `<process-slug>--<value-slug>` from `processName + value`; `org` does not affect the id.
  - Validation: slug tests cover lowercase, trimming, non-alphanumeric runs, IPv4, IPv6, domains, host:port, and IP:port values.
- [x] **P1.3: Add endpoint value helpers**
  - Outcome: row evaluation can use `hostname:port` when hostname exists and `ip:port` otherwise, while still checking both hostname and IP variants after enrichment.
  - Validation: tests cover hostname preference, IP fallback, different ports, IPv4, and IPv6.
- [x] **P1.4: Implement `AttentionEvaluator`**
  - Outcome: pure evaluator returns `accepted` when a matching `processName + value` exists, otherwise `needsAttention` with `Not accepted yet`.
  - Validation: unit tests cover accepted hostname, accepted IP, no match, org ignored, and accepted-pattern id recorded in the result.

### Phase 2: Persistence

- [x] **P2.1: Implement `AcceptedPatternStore` persistence**
  - Outcome: load missing file as empty, save object keyed by id to `~/Library/Application Support/NetworkTracer/accepted-patterns.json`, create the directory when needed, and write atomically.
  - Validation: temp-directory tests cover save/load, missing file, object keyed by id, and atomic-write behavior.
- [x] **P2.2: Implement validation and import merge**
  - Outcome: import validates object keys, string `processName`, string `value`, optional string `org`, rejects conflicts, merges by `processName + value`, fills missing local `org` only when safe, and reports summary counts.
  - Validation: tests cover valid import, malformed JSON, missing fields, invalid org type, duplicate imports, id conflicts, rejected records, and no mutation on invalid file.
- [x] **P2.3: Implement export**
  - Outcome: export writes only accepted patterns, never live connections, observation timestamps, DNS cache, org cache, or session history.
  - Validation: export tests assert the JSON shape and absence of non-pattern fields.

### Phase 3: Store Integration

- [x] **P3.1: Extend `ConnectionRecord` with attention state**
  - Outcome: each published row carries `AttentionResult` without replacing the existing `connections` publication path.
  - Validation: existing record tests still pass; new tests assert stable attention state and display text.
- [x] **P3.2: Load accepted patterns in `ConnectionStore`**
  - Outcome: store owns the accepted-pattern dictionary, loads it at initialization, and supports injected stores/URLs for tests.
  - Validation: restart-style tests prove accepted patterns survive across store instances.
- [x] **P3.3: Evaluate rows on all relevant updates**
  - Outcome: new rows, refreshed rows, hostname updates, org updates, accepted-pattern imports, removals, and accept actions all re-evaluate attention.
  - Validation: integration tests cover new records, refresh, hostname enrichment, org metadata updates, remove pattern, import pattern, stale eviction, and `maxConnections`.
- [x] **P3.4: Add accepted-pattern actions to `ConnectionStore`**
  - Outcome: `acceptEndpoint`, `removeAcceptedPattern`, `importAcceptedPatterns`, and `exportAcceptedPatterns` update persistence and visible state.
  - Validation: tests cover accepting the current endpoint, host:port not accepting a different port, imports affecting evaluation, and removals restoring attention.
- [x] **P3.5: Add needs-attention filtering**
  - Outcome: expose a `needsAttentionOnly` toggle and derived visible rows/counts without changing underlying connection retention.
  - Validation: tests cover accepted rows hidden by the filter and the empty-filter state.

### Phase 4: UI Workflow

- [x] **P4.1: Update popover row presentation**
  - Outcome: rows needing attention show a compact non-alarm marker and reason text without breaking the four-column layout.
  - Validation: manual light/dark checks and text truncation checks.
- [x] **P4.2: Add header count and filter control**
  - Outcome: header shows text like `4 need attention`; the filter shows only rows needing attention and has a distinct empty state.
  - Validation: manual popover checks and, where practical, SwiftUI state tests.
- [x] **P4.3: Add row-level `Accept Endpoint` action**
  - Outcome: an inline `Approve` button writes the current endpoint value, preferably hostname:port otherwise IP:port, plus optional org metadata, then clears attention immediately for matching rows.
  - Validation: integration test plus manual accept/reopen smoke check.
- [x] **P4.3b: Add top-bar batch approval**
  - Outcome: `Approve All` accepts every current row needing attention with one persisted JSON update, then clears attention for matching rows.
  - Validation: integration tests cover successful batch persistence and save-failure rollback.
- [x] **P4.4: Add accepted-pattern management UI**
  - Outcome: `Accepted Patterns...` lists id, process, value, and org; supports removing one pattern, exporting JSON, importing JSON, and showing import summary counts.
  - Validation: manual management workflow and import/export store tests.

### Phase 5: Verification

- [x] **P5.1: Update focused unit and integration tests**
  - Outcome: evaluator, accepted-pattern store, connection record, and connection store tests reflect the simplified v1 rule.
  - Validation: `swift test`.
- [x] **P5.2: Run project validation**
  - Outcome: lifecycle docs and implementation pass repository validation.
  - Validation: `npx ai-devkit@latest lint --feature unusual-connection-highlight`.
- [x] **P5.3: Manual app smoke test**
  - Outcome: verify first-run behavior, accept endpoint, restart persistence, import/export, remove pattern, and needs-attention filtering.
  - Validation: user completed manual macOS UI testing and confirmed the workflow works.

## Dependencies

- P1 is required before P2/P3 because the store and UI need canonical ids and endpoint values.
- P2 can be built mostly independently after P1.2, but store integration should wait for persistence APIs to support test injection.
- P3 depends on P1.4 and P2.1 because `ConnectionStore` needs both evaluator and persistence.
- P4 depends on P3 because UI actions should call store APIs, not duplicate persistence logic.
- P5 runs throughout, with full validation after P4.
- No external network service is required for v1 attention matching, import, or export.

## Timeline & Estimates

- **P1 Foundation:** 0.5 day.
- **P2 Persistence:** 0.5-1 day, mostly validation and merge edge cases.
- **P3 Store integration:** 0.5-1 day, highest regression risk because it touches existing update/enrichment behavior.
- **P4 UI workflow:** 0.5-1 day, depending on how polished the management UI needs to be in v1.
- **P5 Verification:** 0.5 day, plus time for any regressions found by `swift test`.

## Risks & Mitigation

- **Hostname timing can change the accepted value.** Mitigation: evaluate both IP:port and hostname:port candidates after hostname enrichment, and test both paths.
- **Slug ids may collide for unusual punctuation.** Mitigation: reject same-id imports that map to different `processName` or `value`; dedupe matching by actual `processName + value`.
- **Existing `ConnectionRecord` initializers/tests may break.** Mitigation: provide sensible defaults for attention fields and update fixtures deliberately.
- **Persistence tests could touch real user data.** Mitigation: inject a temporary store URL in tests and keep Application Support path behind a default initializer.
- **Import could partially mutate state on malformed files.** Mitigation: validate into a temporary dictionary/summary before applying changes.
- **UI could feel alarmist on first launch.** Mitigation: use "needs attention" language, compact markers, and no security verdict copy.
- **Testing doc still had an old org-only acceptance idea.** Mitigation: remove it from implementation scope; org remains metadata only in v1.

## Resources Needed

- Existing Swift package and XCTest suite.
- `Foundation` JSON encoding/decoding and `FileManager` for local persistence.
- SwiftUI/AppKit file panels or equivalent local file selection for import/export.
- Existing `ConnectionStore`, `ConnectionRecord`, `DNSResolver`, and `PopoverView` patterns.
- Requirements, design, and testing docs for this feature.
