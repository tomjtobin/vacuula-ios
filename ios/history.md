# Cleaning history and area statistics

Implemented 2026-10-19. **History** is separate from the bell's notification Activity. It reads the existing `GET /api/robot/{serial}/runs` endpoint, without changing robot state or requiring a server update. Initial native support is Gen4; unsupported generations show an explicit unavailable state.

## Presentation

- Loading, failure/retry, no-history and populated states. Pull to refresh or use Refresh; foregrounding the visible History tab reloads history. Uploaded records are historical snapshots, never live robot status.
- Newest cleans first, with localized date/time, outcome, start source, cleaned square feet and elapsed time. Summary shows the latest reported area and number of distinct cleans.
- Details show battery percentage used, per-segment area, elapsed time, cleaning power/navigation, return-to-base report and pickup count when present. Missing or invalid data is unavailable, not zero.
- Server Gen4 areas are square metres. Conversion: 1 m² = 10.7639104167 sq ft. Duration is wall-clock elapsed time including pauses; it is not labelled active cleaning time.

## Avoid duplicate and misleading statistics

The live server returned ten records representing six distinct robot/start-time sessions. Firmware uploads paused/intermediate and final snapshots with different record IDs. For matching robot + valid start time, retain the latest end time; prefer a closed record on a tie, then deterministic ID ordering. Keep invalid/missing-start records separate by ID. Do not add snapshot areas or count each upload as a separate clean. Filter out records for other robots.

`cleaning_complete:true` alone does not mean the whole floor was cleaned: the live records include `state:"canceled"` with that flag true. Cancellation and error/unreachable states take precedence; Completed requires closed + all segments done. Paused/in-progress snapshots are labelled as snapshots.

## Expected space and percentage

The endpoint provides no expected-area or measured unique-coverage percentage. Saved-map free pixels and a historical record's `floorplan` field do not establish a trustworthy expected cleaning scope; in these records `floorplan` is a run-specific UUID.

**Whole-floor target → Set area** lets the user enter expected cleanable square feet. It is saved locally per server/robot, independently of schedules/maps. Area vs target = reported cleaned square feet / entered square feet × 100. There is no default or inferred denominator. Missing/nonpositive/nonfinite targets and room/unknown-scope cleans produce no percentage. Whole-floor scope requires every segment to explicitly have an empty track UUID. The current target applies to whole-floor records; changing the target changes historical comparisons too.

This is explicitly an **area comparison**, not measured coverage: overlapping passes may count more than once, and percentages may exceed 100. Room cleans need their own expected area before a reliable comparison can be offered. The app does not cap values or call a cancelled run completed to make the ratio look successful.

## Schedule loading correction

The previous screenshot's raw `cancelled` error could originate from a cancelled request. Schedule loading now uses a store-owned task, so leaving the tab does not cancel an in-flight read. Session/background cancellation does not become a raw user-facing error. Loading/incomplete/error states have clear copy and retry controls; cached results cannot enable edits after failed/unverified reads. Add/Edit/Delete and invalid Save controls use an explicit grey foreground when disabled, including icons. A successful schedule read is required before creation is available.

## Evidence and validation

Read-only live response: [validation/history/live-runs.json](validation/history/live-runs.json). Unit tests use a retained fixture, including a scheduled cancelled clean, and perform no network operations. See [validation/README.md](validation/README.md) for current build/UI results. No live schedule or physical control was changed by this work.

Current validation: Xcode build succeeds; all 25 core tests pass. Simulator checks pass for schedule loading/failure disabled states, schedule create/edit/delete, and history target entry/statistics. Screenshot review confirms the grey action appearance and displayed area comparison. Live source data was read without issuing a robot control or schedule mutation.
