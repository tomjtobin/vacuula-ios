# Vacuula iOS technical specification

Prepared 2026-10-17. Source baseline and deployment qualification: [README](README.md). Requirements: [functional spec](functional-spec.md). This document separates observed behavior, source contracts, and proposed client behavior.

## 1. Architecture and protocol boundary

```text
iPhone (SwiftUI, URLSession REST + SSE)
    → http://192.168.1.100/api/…
    → Vacuula Python HTTP server / SQLite / map files
    → existing generation-specific robot connection
    → Neato robot
```

Use the HTTP API on the web server's origin. `/web` is a UI path, not the API base. The iPhone does not connect to port 3443 (Gen4 robot protocol) or implement Gen3 HMAC signing. Those are server responsibilities. Standard deployment also uses port 443 for Gen3; the web/API HTTP port defaults to 80 and is configurable.

The inspected app routes have no account, bearer-token, API-key or pairing enforcement. CORS allows all origins for `/api/`; CORS does not provide native client authorization. This integration assumes the user's local network. Do not design a login flow around nonexistent authentication endpoints or expose this server publicly as part of the app.

## 2. REST endpoint inventory

Prefix every path below with `/api`. `{serial}` is the dictionary key from `/robots`, never the Gen4 label serial. Encode dynamic path components. Maps/runs are unpaginated arrays; ordering is not guaranteed. The source handlers choose map/run tables using serial formatting; clients should choose adapters using the explicit robot `type` instead.

| Method | Path | Request / result | Scope / verification |
| --- | --- | --- | --- |
| GET | `/server` | `{version,gen4_port,timezone,utc_offset_minutes}` | Live 200, version 1.0.0 |
| GET | `/robots` | Object keyed by serial: `{type,connected,name,label_serial?}` | Live 200, one Gen4 |
| GET | `/events` | SSE, named `robots` event containing complete robot dictionary | Live snapshot captured |
| GET | `/robot/{serial}/connect` | Per-robot SSE, unnamed JSON messages, comment heartbeats | Live stream/keepalive captured; no state event guaranteed during sample |
| POST | `/robot/{serial}/command` | Generation-specific JSON body; forwards robot response | Only read-only Gen4 `state.show` live-tested |
| POST | `/robot/{serial}` | `{name:string}` → text `OK` | Rename, emits robot-list change; source only |
| GET | `/robot/{serial}/maps` | Array of saved/in-list map records | Live one map |
| GET | `/robot/{serial}/maps/{mapId}` | Floor map JSON plus `in_maps_list` and `base` | Live map captured; may also retrieve retained run floor artifacts by ID |
| POST | `/robot/{serial}/maps/{mapId}` | Both `{name,enabled}` required → `OK` | Updates Gen3 name+enabled, Gen4 name; source only |
| GET | `/robot/{serial}/maps/{mapId}/boundaries` | Array of stored boundaries | Gen4 live `[]`; use command bridge for Gen3 |
| POST | `/robot/{serial}/maps/{mapId}/boundaries` | Complete boundary array → `OK` | Gen4 replacement semantics; omitted records deleted; source only |
| POST | `/robot/{serial}/maps/{mapId}/promote` | No body required; returns generated promotion payload | Gen4 upload/activate; source only; robot acknowledgement required |
| DELETE | `/robot/{serial}/maps/{mapId}` | No body → `OK` | Gen4 **demote**, not deletion of map data; source only |
| POST | `/robot/{serial}/maps/{mapId}/use` | No body → `OK` | Gen4 adds to maps list; does not promote; source only |
| POST | `/robot/{serial}/maps/{mapId}/unuse` | No body → `OK` | Gen4 removes from maps list; source only |
| GET | `/robot/{serial}/runs` | Array of generation-specific run records | Live three records |
| GET | `/robot/{serial}/run/{runId}` | Run/path map JSON | Live captured; singular `run` is intentional |
| GET | `/cert` | Download `vacuula-ca.crt` (`application/x-x509-ca-cert`) | Support endpoint, not authentication; source only |
| GET | `/log` | Recent log tail, plain text | `?download=true` requests attachment; source only |
| GET | `/log/full` | Full available logs, plain text | `?download=true` requests attachment; source only |

`OPTIONS` is implemented for CORS. There is no discovered `/rooms`, `/status`, `/start`, `/stop`, or OpenAPI route. Control and state queries go through `/command`.

Robot-facing routes are separate: Gen3 `POST /vendors/neato/login`, `POST /links`, `POST /{…}/upload_jobs`, `GET /persistent_maps`, `PUT /{…}/upload_jobs/{…}` and upload `POST /`. Vendor Accept headers select Gen3 handlers. Gen4 uses its socket protocol. These are infrastructure, not APIs the iOS app should call.

## 3. Request and response semantics

Send JSON with `Content-Type: application/json`; no vendor Accept header needed. `/command` validates registered and connected robot, sends through its existing connection, waits up to **30 seconds**, and forwards the robot reply with robot HTTP status. Configure client command timeout above this, initially 40 seconds. This is a proposal; verify on iOS with the deployed server.

| Condition | Server behavior from source | Client treatment |
| --- | --- | --- |
| Unknown robot | 404, `{"error":"Robot not found"}` | Reload robot inventory |
| Offline robot | 400, `{"error":"Robot not connected"}` | Disable control, retain display |
| Invalid JSON | 400 error object | Report client/protocol error |
| Unsupported generation | 400 error object | Display unsupported type |
| Failed robot write | 502 error object | Refresh connection/state |
| No robot response in 30 s | 504, `{"error":"Robot did not answer in time"}` | Outcome unknown; query state; do not auto-repeat motion |
| Robot reply | Status/body forwarded | Validate robot result as well as HTTP success |

Ordinary mutation success uses raw `OK` bytes even though the shared response helper labels it `application/json`. Decode these as text/empty success as appropriate, not as a mandatory JSON object. Gen3 command replies use fields such as `reqId`, `result`, `state`, `details`; Gen4 uses `{type:"response",id,code,body}`. Retain raw robot error details for diagnostics and show understandable UI text.

## 4. Core commands and requirement mapping

All examples are JSON bodies for `POST /api/robot/{serial}/command`. They document the protocol; they were **not** sent as movement commands.

| Intent | Gen3 (`neato.gen3`) | Gen4 (`neato.gen4`) | Requirement |
| --- | --- | --- | --- |
| Read state | `{"cmd":"getRobotState"}` | `{"ability":"state.show"}` | F03 |
| Stop | `{"cmd":"stopCleaning"}` | `{"ability":"cleaning.cancel"}` | F08 |
| Pause | `{"cmd":"pauseCleaning"}` | `{"ability":"cleaning.pause"}` | F07/F09 |
| Resume | `{"cmd":"resumeCleaning"}` | `{"ability":"cleaning.resume"}` | F07 |
| Return | `{"cmd":"sendToBase"}` | `{"ability":"navigation.return_to_base"}` | F09 |
| Locate | `{"cmd":"findMe"}` | `{"ability":"utilities.find_me"}` | Follow-on |

Gen4 whole-house start (F05):

```json
{"ability":"cleaning.start","runs":[{"map":null,"settings":{"mode":"eco","navigation_mode":"normal"}}]}
```

Gen4 saved-map start (all eligible map area with no-go enabled):

```json
{"ability":"cleaning.start","runs":[{"map":{"rank_id":"<promoted-map-id>","track_id":null,"nogo_enabled":true},"settings":{"mode":"eco","navigation_mode":"normal"}}]}
```

Gen4 selected rooms (F06): one `runs` entry per selected cleaning boundary on the **same promoted floorplan**:

```json
{"ability":"cleaning.start","runs":[
  {"map":{"rank_id":"<promoted-map-id>","track_id":"<zone-1-id>","nogo_enabled":true},"settings":{"mode":"eco","navigation_mode":"normal"}},
  {"map":{"rank_id":"<promoted-map-id>","track_id":"<zone-2-id>","nogo_enabled":true},"settings":{"mode":"eco","navigation_mode":"normal"}}
]}
```

Gen4 modes: `eco`, `turbo`; UI exposes `max`, `auto` for D10 using a model heuristic, so do not assume support on all Gen4 robots. Navigation: `normal`, `gentle`.

Gen3 whole-house start:

```json
{"cmd":"startCleaning","params":{"category":2,"mode":1,"navigationMode":1}}
```

Gen3 single room:

```json
{"cmd":"startCleaning","params":{"category":4,"mode":1,"navigationMode":1,"mapId":"<enabled-map-id>","boundaryId":"<zone-id>"}}
```

Gen3 enum values: category house=2, spot=3, map=4; power eco=1, normal=2; navigation normal=1, extra care=2, deep=3. Spot start adds `spotHeight` and `spotWidth` (web default 200 each; validate physical units before exposing). The helper `startCleaningZones` sends `boundaryIds` but is explicitly uncertain in source and not the supported UI path: do not implement Gen3 multi-room batching on that evidence.

## 5. State normalization and return-to-base sequencing

Normalize to a client model containing identity, connected/freshness state, activity, battery percent, docked, charging, errors and capabilities. Retain unrecognized state/action/error values rather than failing the whole response.

| Normalized field | Gen3 | Gen4 |
| --- | --- | --- |
| State location | Response root | Response `body` |
| State values | 1 idle, 2 busy, 3 paused, 4 error | `idle`, `busy`, `paused`, `error` |
| Common action | 1 house, 2 spot, 4 docking, 11 map cleaning, 12 exploration | `cleaning`, `docking`, `cleaning_standby`, `updating_software`, `diagnostic_test` |
| Battery | `details.charge` | `details.charge` |
| Docked/charging | `details.isDocked`, `isCharging` | `details.is_docked`, `is_charging` |
| Capabilities | `availableCommands.start/stop/pause/resume/goToBase` | `available_commands.start/cancel/pause/resume/return_to_base` |
| Errors | `error`, `alert` | `errors: [{code,severity}]` or null |

The live Gen4 state response is stored in [robot-state evidence](evidence/robot-state.json). The refreshed capture reports idle, docked and charging at 86%, with only start available. The supplied earlier notes reported cleaning with pause/cancel available and return unavailable; the original response was absent, so that earlier observation is not independently evidenced here. Do not assume direct return is available during cleaning.

Proposed client sequence (F09):

1. Require connected robot and fresh state; suppress duplicate return workflows.
2. If return capability true, send return directly. If already docked, report that instead.
3. Otherwise, when pause capability true, send pause once; inspect its result.
4. Wait for SSE state permitting return; use a read-only state refresh if needed. Initially allow 15 s to reach this capability, then stop with a recoverable explanation. This limit needs hardware tuning.
5. Send return once; observe docking activity. Mark “Docked” only on reported docked state. Initially allow 120 s for arrival confirmation, then report that arrival is unconfirmed and continue displaying live status. A UI timer must not cancel docking.
6. On lost connection, rejection or ambiguous command timeout, refresh before further actions. No automatic retry of state-changing commands.

Current web implementation instead pauses and waits a hard-coded **3500 ms** before sending return. Its own source calls for capability-based handling; do not reproduce the fixed delay as a protocol requirement. Stop/cancel is a separate operation and must not silently trigger docking.

## 6. SSE contract and recovery

Server inventory stream `GET /api/events` immediately sends:

```text
event: robots
data: {"<internal-serial>":{"type":"neato.gen4","connected":true,"name":"…","label_serial":"…"}}

```

Then it broadcasts robot connect/disconnect/rename changes. Idle streams receive `: keepalive` comments about every 15 s. The per-robot stream `GET /api/robot/{serial}/connect` initially sends a comment, **not a state snapshot**. Query state after the stream opens, as the web client does.

Per-robot unnamed `data:` messages wrap events:

```json
{"serial":"<internal-serial>","type":"neato.gen4","ts":1792298042.0,"data":{"type":"event","id":"<uuid>","to":{"service":"peer.state"},"body":{"state":"busy","action":"cleaning","available_commands":{},"details":{},"errors":null}}}
```

The above is a structural illustration, not a captured complete state event. Dispatch Gen4 state by `data.to.service == "peer.state"`, using `data.body`. Gen3 web handling accepts `data.type == "state"` or `data.eventId == "77"`, using `data.data`. `ts` is server epoch seconds. Ignore unfamiliar services safely.

Implement SSE parsing over `URLSession` streamed bytes/lines: handle comments, CRLF/LF, multiple `data:` lines, named events, empty-line frame boundaries, UTF-8 split across network chunks, and cancellation. An extra blank line after robot messages must be harmless. Maintain separate selected-robot and server subscriptions; dispose old robot stream on selection change.

Queues are bounded to 100 frames and drop oldest on overflow. The original streams have no replay IDs or initial per-robot snapshot. PR #30 adds persisted notification history and named notification events; see the Activity integration update below. Reconnect with bounded exponential backoff/jitter; re-query `/robots` and robot state. Use stream comments for transport liveness only; track last state observation separately. Proposed initial health check: refresh state after 45 s without state data while foregrounded; adjust after observing hardware cadence. An idle robot need not emit frequent state changes.

## 7. Map and room contracts

`GET /robot/{serial}/maps` returns:

- Gen3: `{id,robot,name,enabled,in_maps_list,base}`.
- Gen4: `{id,robot,name,promoted,in_maps_list,base,origin,resolution,alignment,imgsize,created_at}`. Only one promoted floorplan per robot is allowed in the database.

Gen4 room source: `/maps/{mapId}/boundaries`. Each record has exactly these stored fields:

```json
{"id":"<zone-id>","name":"Kitchen","color":"#49b98b","type":"polygon","function":"cleaning","vertices":[[0.2,0.2],[0.4,0.2],[0.4,0.5],[0.2,0.5]],"enabled":true}
```

This is an illustrative boundary. Vertices are normalized fractions of full map image width and height. Room candidates are enabled cleaning polygons; exclude `function:"nogo"` polygons and `type:"polyline"` lines. MVP should validate zone membership, enabled status, docked status, start capability and promoted map immediately before submitting. Do not treat an arbitrary viewed map as the uploaded cleaning map.

For Gen3 use `{"cmd":"getMapBoundaries","params":{"mapId":"…"}}`; read `response.data.boundaries`. The existing web app treats polygon boundaries as cleaning zones. `setMapBoundaries` additionally includes computed `relevancy` for polygons; not needed for read-only MVP.

Map image JSON schema from source:

```text
width, height: decoded grid dimensions
downsample: server's image reduction factor
map_type: "floor" or "path"
legend: numeric pixel value → label
rle: [[pixelValue, repeatCount], …]
metadata: generation-dependent; Gen4 resolution, origin_x, origin_y
img_size: [originalWidth, originalHeight]
base: [x, y, heading?]
in_maps_list: boolean (added for floor-map GET)
```

Decode RLE row-major: repeat each value by count; expect `width * height` cells and bound memory/counts before allocation. Render the raster off the main thread and use Canvas/CoreGraphics for native overlays. Use normalized vertices against displayed map dimensions; preserve full-map coordinate space when fitting/cropping the viewport. Use legends/source mapping rather than inventing cell meanings for unknown versions. Path maps have distinct path values; the web app assigns deterministic colors.

Gen4 dock conversion copied from web implementation:

```text
normalizedX = ((baseX - origin_x) / resolution) / img_size[0]
normalizedY = ((baseY - origin_y) / resolution) / img_size[1]
heading = base[2] or 0
```

Hide dock for missing metadata or sentinel coordinate `2147483647`. The renderer uses heading as degrees. Validate orientation, downsampling and coordinate conventions with a real map; Gen3 metadata is explicitly not fully typed in the web schema. No live pose field has been established for an animated robot marker.

Gen4 boundary editing, if added later, replaces the whole list; every incoming object must have exactly `id,name,color,type,vertices,enabled,function`. Saving boundaries only changes server storage. Re-promote a modified active map to upload zones/no-go tracks to the robot, as the web client does. Promotion may demote the previous map first, waits up to **60 seconds**, rasterizes tracks, and returns a large generated payload. Plan a separate longer client timeout and recovery state. Do not introduce promotion into routine room viewing or cleaning.

## 8. Remaining commands and data for future parity

| Feature | Gen3 bridge commands | Gen4 bridge abilities |
| --- | --- | --- |
| Schedule | `getSchedule`, `setSchedule` with `params.events`, `enableSchedule`, `disableSchedule` | `scheduling.show`, `scheduling.update` with `event`, `scheduling.delete` with `id` |
| Preferences/settings | `getPreferences`, `setPreferences` with `params` | `settings.cleaning_options`, `settings.set_cleaning_options` (`force_floorplan`); `settings.robot_language`, `settings.set_robot_language` (`language`) |
| Map management | `startPersistentMapExploration`, `getMapBoundaries`, `setMapBoundaries` | Server map routes; `maps.demote_floorplan` exists but prefer server route to keep DB state synchronized |
| Diagnostics | `getLocalStats`, `getGeneralInfo`, `dismissCurrentAlert`, `uploadLogs` (`params.recentCount`), `getLogsUploadState` | `cleaning.show`; `info.robot` used by server registration |
| Reset | No matching app helper established | `settings.factory_reset` (destructive; exclude MVP) |

Gen4 schedule event: `{id?,enabled,days:["mon",…],time:"HH:MM",command:{ability,auto_localization,force_floorplan,runs:[…]}}`. Gen3 schedule events use numeric generation-specific day/mode values, `startTime`, optional `boundaryId`. Read server IANA timezone from `/server`; a fixed UTC offset is insufficient across daylight-saving transitions. Validate actual schedule payloads before implementing edits.

History schemas: Gen3 records `{id,robot,persistent_map,run:{…}}`; Gen4 `{id,robot,floorplan,started_by,battery_consumed,cleaning_complete,timing,runs}`. Nested run statistics/timing differ by generation. Follow source `pages/runs/runs.tsx` for presentation, and obtain real fixtures before hardening Codable types. No pagination endpoint was found.

## 9. Proposed native implementation

Use SwiftUI and structured concurrency with these responsibilities:

- `ServerConfiguration`: persist successful origin, Bonjour service name/type/domain when available, and selected robot serial scoped to that server. Normalize manually supplied URLs, discard `/web` and query/fragment, and validate http/https scheme and port. Do not replace a saved server until the new connection validates.
- `ServerDiscovery`: browse `_vacuula._tcp` using `NWBrowser`, resolve service endpoints and advertised ports, deduplicate candidates by service identity, validate `/api/server`, and drive discovery/selection/reconnect/fallback states. Keep discovery cancellation separate from robot streams.
- `VacuulaAPI`: URLSession HTTP operations, status/error handling, tolerant success text decoding, typed inventory/map DTOs.
- `RobotProtocolAdapter`: Gen3 and Gen4 builders/decoders behind a shared control/state interface. Do not sprinkle generation conditionals throughout views.
- `SSEClient`: cancellable stream parser and reconnect behavior. No background execution guarantee.
- `RobotStore` on MainActor: selected robot, normalized state, freshness and pending operation; serialize control workflows and isolate responses by robot selection/session.
- `MapRepository` and renderer: cache by server+serial+map ID; decode and render off-main; invalidate on explicit refresh and foreground/map changes. Current SSE offers no reliable map-list invalidation contract.

F01 uses Bonjour discovery, remembered-server resolution and `/server` validation; F02 uses `/robots` plus inventory SSE; F03 uses state command plus selected-robot SSE; F04 uses maps/map/boundaries; F05–F09 use adapter commands; F10/F11 use workflow, transport and lifecycle handling. F12 is native view and accessibility work.

Cancel outstanding reads and subscriptions on server/robot change; discard late responses for the previous selection. Persist display preferences/configuration; do not persist a queue of motion intents. Foreground return always reconciles state before enabling controls.

## 10. iOS LAN integration

Include `NSLocalNetworkUsageDescription`, for example “Connect to your Vacuula server to show rooms and control your robot.” Handle denied local network access with recovery instructions and a retry action. Local network privacy and ATS are separate checks. See Apple's [usage-description documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription) and [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

Plan `NSAppTransportSecurity` / `NSAllowsLocalNetworking` for the local HTTP origin. Apple's documentation describes different IP-address behavior across OS releases; validate HTTP to this literal IPv4 address on the chosen minimum and current iOS versions before finalizing narrowly scoped exceptions. Avoid assuming a global arbitrary-load setting is required. See [NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking).

Discovery is part of MVP. The server advertises `_vacuula._tcp.local.`, instance `Vacuula Server`, hostname `vacuula.local.`, HTTP port, TXT `version`, `cert-path`, `protocol`, `url`. A live macOS DNS-SD browse and lookup on 2026-10-17 found `Vacuula Server` at `vacuula.local.:80`, with version `1.0.0` and protocol `http`. This verifies LAN advertisement from the Mac, not iPhone discovery behavior.

Browse `_vacuula._tcp` with `NWBrowser` and declare `_vacuula._tcp` in `NSBonjourServices`. Resolve the service target and port; do not hard-code port 80 or rely on the optional TXT URL as the only location. Validate candidates through `/api/server` before saving or enabling control.

Connection state machine:

1. With a saved server, first resolve its saved Bonjour identity (when present) and try its current endpoint, with its saved origin as a fallback within the remembered-server attempt. A manually configured server can be tried directly. Use a bounded connection attempt; an initial overall 8-second budget is proposed and requires device validation.
2. If there is no saved server or that attempt fails, run a bounded Bonjour discovery window (initially 5 seconds after browsing becomes ready). Collect and deduplicate candidates before deciding there is exactly one; do not select the first callback immediately. Cancel browsing/validation when backgrounded or when a newer connection attempt supersedes the current one.
3. Validate discovered candidates with bounded requests. Exactly one valid server connects automatically; multiple valid servers require a picker. If discovered candidates all fail validation, show their errors and Retry. Do not treat invalid responses as successful Vacuula connections.
4. Only when a completed discovery window finds zero services show manual address entry, with Retry discovery. Browser failure or permission denial is a separate recoverable state, not evidence of an empty network. Manual entry cannot bypass denied local network access.
5. Persist the successful origin and service identity when available. Reconnect through that identity on later launches so DHCP address changes can be resolved. No stable server UUID is established by the API; treat Bonjour identity as a discovery hint and revalidate each connection. Retain the saved configuration during failures and replace it only after a new successful connection.

A successful server response followed by zero robots or an offline robot remains connected to that server. Reconcile state on foreground and use remembered-server recovery before global rediscovery after a confirmed server connection loss. A brief SSE interruption should first use the existing stream reconnect policy; it must not immediately reopen setup. Never replay a motion command during connection recovery.

HTTPS requires deliberate certificate trust handling. `/api/cert` downloads the server's self-signed certificate; it is not a login token and does not make iOS trust the server automatically. MVP targets the supplied local HTTP endpoint.

## 11. Evidence, risks and validation work

**Verified live:** web HTML reachable; `/server`, `/robots`, one promoted map, empty boundary list, three runs, floor/run map JSON, Gen4 `state.show`, inventory SSE snapshot, selected-robot SSE subscription/keepalive. See [evidence directory](evidence/).

**Not live-validated:** all motion commands, map rendering/orientation, populated boundaries and room cleaning, scheduling/settings mutations, Gen3 commands, iPhone Bonjour discovery/reconnect and physical docking. History records and one run map were read without exercising a history UI. Real floor and run map responses are now saved, but map rendering and orientation remain unvalidated. Report these limits in release notes and test plans.

Implement meaningful protocol fixtures for Gen4/Gen3 state and error decoding, SSE framing, RLE size validation, map coordinate conversion and return workflow transitions. Test ambiguous timeouts without duplicate motion, duplicate taps, generation selection, robot-switch races and reconnection resync. Then run the supervised hardware matrix in the functional spec.

Important existing server behavior: generic command forwarding lacks a client-visible idempotency contract; several map handlers identify maps by ID without consistently checking robot ownership, and boundary updates replace the complete set. Validate every selected ID against current inventory in the client. Version 1.0.0 does not establish capability negotiation or schema versioning. Keep adapters tolerant of extra fields and explicitly unsupported generations.

No server modification is proposed for the MVP. Potential follow-ons are a normalized state/capability endpoint, map-change events, command idempotency and consistent map ownership validation; these should be justified by actual integration failures or expanded scope.

## 12. Source references at pinned commit

- Routes and response framing: [route_matcher.py](../vacuula/server/src/vacuula_server/handlers/route_matcher.py), [router.py](../vacuula/server/src/vacuula_server/handlers/router.py).
- App API / command wait: [handlers/app.py](../vacuula/server/src/vacuula_server/handlers/app.py); inventory SSE: [events.py](../vacuula/server/src/vacuula_server/handlers/events.py).
- Client HTTP facade: [http.ts](../vacuula/app/src/http.ts), [Gen3 commands](../vacuula/app/src/http/gen3.ts), [Gen4 commands](../vacuula/app/src/http/gen4.ts).
- Current workflows: [home.tsx](../vacuula/app/src/pages/home/home.tsx), [map.tsx](../vacuula/app/src/pages/map/map.tsx), [AppContext.tsx](../vacuula/app/src/context/AppContext.tsx).
- Gen4 schemas: [state.ts](../vacuula/app/src/types/neato/gen4/state.ts), [api.ts](../vacuula/app/src/types/neato/gen4/api.ts), [schedule.ts](../vacuula/app/src/types/neato/gen4/schedule.ts).
- Gen3 schema: [state.ts](../vacuula/app/src/types/neato/gen3/state.ts).
- Maps: [types.ts](../vacuula/app/src/components/map/types.ts), [map renderer](../vacuula/app/src/components/map/map.tsx), [map API/promotion](../vacuula/server/src/vacuula_server/gen4/app.py), [persistent_map.py](../vacuula/server/src/vacuula_server/models/persistent_map.py).
- Transport/events: [Gen4 handlers](../vacuula/server/src/vacuula_server/gen4/handlers.py), [Gen3 signing](../vacuula/server/src/vacuula_server/gen3/commands.py); discovery/certificate/logs: [setup.py](../vacuula/server/src/vacuula_server/handlers/setup.py).
- History models: [run.py](../vacuula/server/src/vacuula_server/models/run.py).

Repository license is AGPL-3.0; retain upstream licensing/provenance when reusing source. The proposed app architecture does not require copying the React implementation.

## 13. First implementation

The `ios/` project now implements the initial native app and a reusable `VacuulaCore` package. The app target is iOS 26+; the core library remains iOS 17+/macOS 14+. Discovery uses `NWBrowser` plus Foundation service resolution. A remembered server currently allows up to 3 seconds for resolution followed by 5-second endpoint validation attempts, rather than enforcing the earlier proposed single 8-second budget. Core protocol tests use retained live responses plus malformed/error fixtures. See [ios/README.md](ios/README.md) for running, scope and validation limits. Gen3 cleaning-run history/scheduling, native run-map detail, persistent offline map caching and Gen3 room selection remain deferred. Native Gen4 history, schedules and notification Activity are described in the later implementation updates.

## Activity integration update: PR #30

Server PR #30 adds `GET /api/robot/{serial}/notifications` with `limit` and exclusive `before` pagination, returning `{notifications:[{id,robot,message_code,payload,received_at}],next_before}`. Both existing SSE streams can carry named `notification` events with the same item shape. This is an additional route beyond the original 20-route discovery inventory.

The iOS app consumes only the selected robot's notification stream, merges history by ID, preserves arbitrary JSON payload context and provides device-local read markers. It keeps notification history separate from current robot state and never sends movement requests in response to an alert. See [ios/activity.md](ios/activity.md) for lifecycle, pagination, banner policy and validation scope.


## Native schedule integration — 2026-10-19

Native Gen4 scheduling is implemented in the Schedule tab. Create recurring cleans with repeat days, local time, power/navigation, active saved-map/no-go support and optional configured rooms; edit timing without rewriting existing cleaning settings, toggle enabled state and confirm deletion. Read back every write and require refresh after ambiguous results. Read-only mode blocks changes; demo changes are local only. See [implementation, payloads and Activity test procedure](ios/scheduling.md).


## Cleaning history and loading readiness — 2026-10-19

The native History tab reads existing Gen4 run records, combines intermediate/final snapshots per robot/start time, distinguishes cancellation from successful completion, and shows cleaned sq ft, elapsed duration, battery and segment settings. Users may save a local whole-floor area target for explicitly labelled area comparisons; no expected area is inferred from saved maps. The Schedule tab now shows loading/incomplete/retry states, suppresses request cancellation errors and visibly greys unavailable actions until a successful read. See [history implementation and data semantics](ios/history.md).


## Persistent defaults and recent runs — 2026-10-19

Manual power/navigation defaults are stored locally per server origin/robot, restored on connection/selection/restart, and used to initialize new schedules. Existing schedules and resumed cleans retain their original settings. Home lists recent runs and Schedule lists reported scheduled runs, with trigger/source, duration, cleaned sq ft and expected-area comparison when configured. Run records lack schedule IDs, so per-schedule membership is not inferred from edited/current times. See [behavior and integration limits](ios/cleaning-options-and-recent-runs.md).


## Map display orientation — 2026-10-19

Settings → Maps → Rotation provides four clockwise orientations (0°, 90°, 180°, 270°), defaulting to zero and saved locally across all maps/robots/servers. Raster, room/no-go overlays, selection fills and base position use a shared rotation; rectangular maps are fitted after swapping axes for quarter turns. Rotation changes reset zoom/pan; ordinary Reset view keeps the chosen orientation. Robot/map/cleaning coordinates and server data remain unchanged. See [renderer and validation notes](ios/map-orientation.md).


## Proposed server schedule/run association — 2026-10-19

A developer-ready proposed contract is in [server-schedule-run-association-spec.md](server-schedule-run-association-spec.md). It covers immutable observed schedule revisions, inferred timestamp-based execution association, failure/ambiguity handling, additive APIs/SSE, durable reconciliation, migration/backfill and acceptance tests. This is a specification, not an implemented server change.
