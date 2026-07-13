---
phase: testing
title: Testing Strategy
description: Test coverage for unusual connection highlighting
---

# Testing Strategy

## Test Coverage Goals

- Unit test 100% of new attention evaluation and accepted-pattern persistence logic.
- Keep attention evaluation deterministic, with no DNS, HTTP, or real `lsof` dependency in rule tests.
- Add focused store integration tests for async enrichment updates, filtering, accepted-pattern behavior, and import/export.
- Add lightweight UI coverage where feasible; otherwise document manual smoke checks for the popover.

## Unit Tests

### AttentionEvaluator
- [x] Returns `accepted` when `processName + hostname:port` exists in accepted patterns.
- [x] Returns `accepted` when `processName + ip:port` exists in accepted patterns.
- [x] Returns `needsAttention` when no accepted endpoint value matches.
- [x] Prefers hostname:port when hostname is available.
- [x] Falls back to IP:port when hostname is unavailable.
- [x] Treats a row as accepted if either hostname:port or IP:port is accepted after hostname enrichment.
- [x] Does not require org data to evaluate attention state.
- [x] Produces user-facing reason `Not accepted yet` for attention rows.

### AcceptedPatternStore
- [x] Saves accepted patterns to local JSON.
- [x] Loads accepted patterns across app/store initialization.
- [x] Deduplicates equivalent accepted patterns.
- [x] Removes accepted patterns by id.
- [x] Generates deterministic ids from `processName + value`.
- [x] Generated ids include process slug and value slug.
- [x] Generated ids do not change when optional `org` is present.
- [x] Slug generation lowercases, trims, replaces non-alphanumeric runs with `-`, and trims leading/trailing `-`.
- [x] Exports accepted patterns to a plain JSON object keyed by id.
- [x] Stores accepted patterns under the user application support `NetworkTracer/accepted-patterns.json` path.
- [x] Missing accepted-pattern file loads as an empty dictionary.
- [ ] Save writes atomically without corrupting an existing file on failure.
- [x] Save/import failure paths do not commit failed changes to in-memory accepted patterns.
- [x] Imports valid accepted-pattern JSON.
- [x] Merges imports with existing accepted patterns.
- [x] Reports added, duplicate, and rejected import counts.
- [x] Rejects malformed JSON without modifying existing accepted patterns.
- [x] Rejects records with missing, empty, or invalid object keys.
- [x] Rejects records missing string `processName` or `value`.
- [x] Rejects records where `org` is present but is not a string.
- [x] Rejects duplicate ids that map to different `processName` or `value`.
- [x] Rejects non-canonical ids that do not match `processName + value`.
- [x] Duplicate imports with the same canonical id may fill missing local `org` but do not overwrite an existing local `org`.
- [x] Does not export live connection history, DNS cache, org cache, or session observation history.

### ConnectionRecord / Row Model
- [x] Exposes stable attention state.
- [x] Exposes user-facing attention text.
- [x] Stores attention result on `ConnectionRecord`.
- [x] Exposes accepted-pattern id candidate used for matching.
- [x] Handles IPv4 port extraction.
- [x] Handles IPv6 port extraction.
- [x] Keeps existing display name behavior.

## Integration Tests

- [x] `ConnectionStore.update(with:)` evaluates attention state for new records.
- [x] Existing connection refreshes keep accepted rows accepted.
- [x] Applying hostname updates re-evaluates endpoint attention state.
- [x] Applying org updates preserves org metadata but does not drive v1 attention matching.
- [x] Accepting endpoint value removes matching row attention immediately.
- [x] Accepting host:port does not suppress a different port for the same host.
- [x] Needs-attention filtering returns only non-accepted rows.
- [x] Accepted patterns remain effective after store/app restart.
- [x] Importing accepted patterns affects subsequent highlight evaluation.
- [x] Removing an accepted pattern makes matching rows need attention again.
- [x] Stale connection eviction does not erase accepted-pattern storage.
- [x] Large connection lists remain capped by existing `maxConnections` behavior.

## End-to-End Tests

- [x] Launch app, open popover, and confirm rows needing attention show compact markers.
- [x] Toggle needs-attention-only filter and confirm accepted rows are hidden.
- [x] Accept an endpoint and confirm the row no longer needs attention.
- [x] Restart the app and confirm the accepted pattern remains accepted.
- [x] Export accepted patterns to JSON.
- [x] Import exported JSON on a clean profile/machine and confirm matching rows are accepted.
- [x] Remove an accepted pattern and confirm matching rows need attention again.
- [x] Confirm empty needs-attention-only state differs from no-active-connections state.
- [x] Confirm VoiceOver/text access exposes attention state without relying only on color.

## Test Data

- Canned `ParsedConnection` fixtures for:
  - raw IP endpoint
  - hostname-resolved endpoint
  - org-enriched endpoint
  - IPv6 endpoint
  - private/local IP endpoint
- Temporary directories/files for accepted-pattern persistence and import/export tests.

## Test Reporting & Coverage

- `swift test`: passed, 85 tests, 0 failures before the persistence-path coverage addition.
- `swift test --enable-code-coverage`: passed, 86 tests, 0 failures after the persistence-path coverage addition.
- `swift test --enable-code-coverage`: passed, 89 tests, 0 failures after the save-failure consistency fix.
- Coverage artifact `.build/arm64-apple-macosx/debug/codecov/NetworkTracer.json`: 97.78% line coverage, 97.88% function coverage, 94.47% region coverage.
- `npx ai-devkit@latest lint --feature unusual-connection-highlight`: passed before the save-failure consistency fix; rerun after doc update.
- Integration tests that require real network access should remain skippable with `SKIP_INTEGRATION_TESTS=1`.
- No new rule test should depend on live DNS or ipinfo.io.

## Manual Testing

- P4 UI has compile coverage through `swift test`; interactive smoke testing was completed manually by the user.
- Launch smoke completed with `swift run NetworkTracer`: app target built and stayed running until manually stopped with Ctrl-C. This validates startup/build, not visual menu bar interaction.
- Visual popover interaction was verified in a real macOS session by the user.
- Atomic-write behavior relies on Foundation `.atomic`; tests now cover failed save/import consistency, but not a low-level interrupted replacement of an existing regular file.
- Verify row marker visual weight in light and dark mode.
- Verify attention count in header does not crowd the existing connection count.
- Verify long reason strings truncate or wrap cleanly.
- Verify first-run behavior does not look like an emergency alert.
- Verify accepted-pattern review, remove, export, and import flows are understandable.
- Verify export UI communicates that the file can reveal app/network destination patterns.

## Performance Testing

- Add a synthetic test with hundreds of parsed connections to ensure highlight evaluation remains lightweight.
- Confirm no change to the 5-second polling interval.
- Confirm no added network requests beyond existing DNS/org enrichment behavior.

## Bug Tracking

- Treat alarmist language as a product bug.
- Treat missing explanations for attention rows as a blocking bug.
- Treat network-dependent rule tests as a test design bug.
- Treat data loss or silent import overwrite as a blocking bug.
