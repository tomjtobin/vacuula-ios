# Vacuula discovery notes

Refreshed 2026-10-17 at approximately 10:18 p.m. America/Los_Angeles.

## Source

Cloned https://github.com/vacuula/vacuula.git into `../vacuula`.
Branch: `main`. Commit: `0a0787fd1db0dc7907c057bbc3586011c9bdd73f`, dated 2026-10-16, titled `allow custom hostip, fix doubleupload, dbuild:1.0.1-b1`.
The clone contains both the Python server (`server/`) and React web app (`app/`). Upstream license is AGPL-3.0. Git reports a clean checkout.

The supplied functional and technical specs were already present. Their referenced sibling checkout and evidence folder were absent when this session started. The new clone matches their pinned commit; the original observation captures could not be recovered here. Statements about a prior `../source` checkout were removed because that directory does not exist in this workspace.

## Refreshed live observations

Target: http://192.168.1.100/web; API origin: http://192.168.1.100.

- Server reports version `1.0.0`, timezone `America/Los_Angeles`, offset `-420` minutes. This does not identify its deployed Git commit.
- One connected `neato.gen4` robot: internal serial `EXAMPLE-ROBOT-001`, label serial `EXAMPLE-LABEL-001`.
- `state.show`: idle, docked, charging, battery 86%, no errors. Start is available; pause, resume, cancel and return are unavailable.
- One saved, promoted floor map, named `(unnamed)`, ID `00000000-0000-4000-8000-000000000001`.
- That map's boundaries endpoint returns `[]`. Rooms still require configured cleaning zones.
- Three historical run records. A floor map and one run map were retrieved successfully.
- Inventory SSE supplied a named `robots` snapshot. Robot SSE supplied comments/keepalives; no robot state event was captured in the short sample.

These refresh the earlier supplied notes that described an actively cleaning robot at 87% with no maps or runs. They are point-in-time observations. Historical run records and reported docked status do not establish that this session tested physical controls or observed the robot docking.

## Saved evidence

See [evidence/](evidence/). `manifest.json` records HTTP methods, paths, timestamps, status codes and the sole command payload; `source-version.json` records Git provenance. Raw server, inventory, state, maps, boundaries, runs, floor map, run map and web HTML responses are retained. SSE frames are saved in `inventory-events.sse` and `robot-events.sse`; `sse-capture.json` records their bounded 17-second capture exits. Curl exit 28 is expected for these intentionally closed streams.

Only GET requests, SSE subscriptions and one read-only `state.show` POST were sent. No physical control, configuration, map, zone or schedule mutation was sent. Evidence includes local identifiers and should be reviewed before publication.

## Verification and remaining work

The source declares exactly 20 app routes, matching the technical spec inventory. Saved JSON parses successfully. Both retrieved map RLE arrays expand to their declared 2000 × 2000 dimensions. This checks data consistency, not native rendering, map orientation or physical alignment.

The functional spec defines native screens, core controls and acceptance criteria; the technical spec defines command adapters, map/zone contracts, streaming and iOS LAN integration. A first SwiftUI implementation and Xcode project have since been added in `ios/`; see `ios/README.md` for implemented scope and remaining validation. Physical start/pause/resume/stop/return, selected-zone cleaning, populated boundary geometry and iPhone network behavior still require implementation and supervised validation.

## Discovery-first iOS connection requirement

The agreed MVP flow is automatic Bonjour discovery on first launch, automatic connection when exactly one valid server is found, a server picker when multiple are found, and manual address entry only after discovery finds none. Remember a successful server; try it first on subsequent launches and rediscover only when it cannot be reached or validated. Save Bonjour identity as well as the last origin to support resolving address changes. Permission/browser failures and discovered-but-invalid servers need their own recovery states.

A macOS `dns-sd -B _vacuula._tcp local.` browse on 2026-10-17 at approximately 10:20 p.m. PDT found `Vacuula Server`. `dns-sd -L 'Vacuula Server' _vacuula._tcp local.` resolved it to `vacuula.local.:80`, TXT `version=1.0.0 cert-path=/api/cert protocol=http url=http://vacuula.local`. These command results were inspected live; raw terminal output was not saved as an evidence artifact. iPhone discovery remains untested. See the updated connection flow and acceptance criteria in the functional and technical specs.

## Native app validation, 2026-10-18

The Xcode 27.1 build and 10 protocol tests pass. Simulator UI checks passed for discovery-first connection to the real server, live robot status, map loading, navigation, large text and Dark Mode; see [native validation](ios/validation/README.md) and screenshots. At the live UI capture, the robot reported docked at 98% battery and the saved map contained one no-go boundary, with no cleaning rooms. Motion/configuration controls were not exercised. The simulator is left connected with physical controls disabled using `--read-only`.


## Scheduling baseline — 2026-10-19

Read-only `scheduling.show` through the live command bridge returned HTTP 200 and robot code 200, with `body:{enabled:true,events:[]}`. `/api/server` reported version 1.0.0 and America/Los_Angeles, UTC offset −420 minutes. No schedule update/delete or movement was sent. Contract cross-checked with downloaded web Gen4 schedule types and saved firmware scheduling handlers; see [native scheduling notes](ios/scheduling.md).


## Run statistics baseline — 2026-10-19

A read-only GET of `/api/robot/EXAMPLE-ROBOT-001/runs` returned ten Gen4 snapshots representing six start-time sessions, including scheduled paused/final-cancelled uploads. Raw response retained at [ios/validation/history/live-runs.json](ios/validation/history/live-runs.json). Gen4 `runs[].stats.area` is square metres according to the downloaded web source. No expected-area/coverage denominator appears in this API. Several cancelled final records have `cleaning_complete:true`, so native history checks segment outcomes rather than using that flag alone. No configuration or motion was changed.

## Public copy

Robot identifiers and LAN addresses in this document are placeholders. Raw responses, firmware backups and generated validation artifacts are retained locally and excluded from the public repository. Test fixtures use anonymous identifiers and a synthetic floor map.
