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

## Automatic requested-area estimates

History no longer asks for a manual area target. Home, History and Schedule show **estimated coverage**, calculated as reported cleaned area divided by cleanable area from a current saved map. Run details show the estimated requested square feet, scope and saved map name.

Whole-floor records require every segment to explicitly report an empty `track_uuid`. They use an explicit saved-map reference when available; otherwise exactly one promoted saved map is required. `floorplan` is used directly only if it actually matches a saved map ID; an uploaded run-result map is never used as the denominator. An explicit but missing `persistent_rank_uuid` does not fall back to an unrelated active map.

Room records require every segment to have a nonempty track ID and all requested IDs to resolve to enabled cleaning polygons on exactly one saved map. Repeated room IDs and overlapping rooms count once in the requested area. Mixed whole-floor/room scope, absent track information, ambiguous maps or missing rooms produce an unavailable explanation.

The estimator counts cell centres classified as free, clipped to the union of requested room polygons when applicable, and excludes the union of enabled no-go polygons/lines. Walls and unknown cells do not count. Gen4 PGM resolution is treated as millimetres per original pixel; `img_size` scales the returned raster on both axes. No-go polylines use the server promotion width of nine original pixels. The server currently returns full-resolution maps; downsampled inputs are scaled physical-area estimates and may differ at boundaries. Cropping, zoom and map rotation do not change the calculation. Invalid scale, malformed active exclusions or failed map/boundary loading leave estimates unavailable; history statistics still load.

These are explicitly **current-map estimates**, not historical scope snapshots or verified unique coverage. A map/room edit or promotion can change historical estimates. Reported passes may overlap, so ratios can exceed 100%; cancelled/error runs retain their outcome. Saved free space cannot prove temporary obstacle reachability. The app does not infer a schedule’s rooms from timing alone. Future server scope snapshots would make these comparisons historically stable; see the [server contract](../server-schedule-run-association-spec.md#requested-area-and-cleaning-coverage).

## Schedule loading correction

The previous screenshot's raw `cancelled` error could originate from a cancelled request. Schedule loading now uses a store-owned task, so leaving the tab does not cancel an in-flight read. Session/background cancellation does not become a raw user-facing error. Loading/incomplete/error states have clear copy and retry controls; cached results cannot enable edits after failed/unverified reads. Add/Edit/Delete and invalid Save controls use an explicit grey foreground when disabled, including icons. A successful schedule read is required before creation is available.

## Evidence and validation

Read-only live response: [validation/history/live-runs.json](validation/history/live-runs.json). Unit tests use an anonymized response fixture, including a scheduled cancelled clean, and perform no network operations. See [validation/README.md](validation/README.md) for current build/UI results. No live schedule or physical control was changed by this work.

Earlier validation covered schedule loading/failure disabled states, schedule create/edit/delete and history statistics. The automatic-area update builds successfully and passes all 39 core tests. A read-only check of the current server’s active map and no-go polygon produces about 268 sq ft of estimated cleanable area. No robot control or schedule mutation was issued.

Automatic-area validation adds geometry, unit conversion, no-go polygon/line, room union, missing scope and ambiguous map tests. The preview history test verifies an automatic 88% estimate without an area editor. See local validation artifacts for this run’s results.
