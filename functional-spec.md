# Vacuula iOS functional specification

Status: implementation proposal informed by downloaded source and read-only deployment inspection. Prepared 2026-10-17. See [baseline and evidence](README.md).

## 1. Objective

Provide a native iPhone app that connects to the user's existing Vacuula server, shows the robot and saved rooms/maps, starts and stops cleaning, and returns the robot to its charging base. Match the web app's core capabilities and terminology while keeping the first release small enough to validate on the installed Gen4 robot.

The server remains responsible for communicating with the robot. The app is a LAN client; it does not replace the server or robot firmware.

## 2. Existing web application

The React application has Home, Map, Runs, Schedule, and Settings pages, a robot switcher, connection/empty states, battery and docking information, and a command loading indicator. State updates use server-sent events (SSE).

| Area | What users can see | What users can do | Qualification |
| --- | --- | --- | --- |
| Robot selection | Registered robots, names, connection status; Gen4 label serial | Select an online robot; remember selection; rename | Live deployment has one connected Gen4 robot |
| Home/status | Battery, charging/docked status, activity, errors/warnings, time since last state event | Start, pause, resume, stop/cancel, return to base, locate by sound; Gen3 alert dismissal | Buttons follow robot-reported command availability |
| Cleaning options | House/map/zone choices; power and navigation modes | Choose mode and map/zone cleaning; Gen3 spot dimensions | Gen4 supports multiple cleaning zones; Gen3 UI limits selection to one |
| Maps | Saved floor maps, dock marker, named colored cleaning zones, no-go polygons/lines | Pan/zoom; edit boundaries/names/colors; enable no-go boundaries; clean a zone | Zones are configured boundaries, not automatically discovered room objects |
| Map lifecycle | Gen3 enabled maps; Gen4 saved/promoted maps | Gen3 exploration; Gen4 use a run map as a floor map, promote/demote, hide an unpromoted map | Gen4 promotion uploads map/zone data to robot |
| History | Run date, initiator, duration, area, battery used, completion, run map and per-run details | Open run details and map; retain suitable Gen4 run map for floor use | Deployment returned three run records at refreshed capture |
| Schedule | Generation-specific recurring events | Gen3 set events and enable/disable scheduling; Gen4 add/update/delete events, select days/time and cleaning options | Uses server timezone information |
| Robot settings | Name/serial; Gen3 preferences; Gen4 cleaning and language settings | Rename; Gen3 sounds/maintenance reminders; Gen4 force-floorplan and voice language; guarded factory reset | Hardware-dependent options; reset is outside MVP |
| App settings/support | Theme, accent color, language, units, mascot, server version | Change local display preferences; download certificate/logs; open feedback | Some settings are browser-local, not server APIs |

The repository also contains helper commands not necessarily exposed as complete user flows: Gen3 local stats, general info and log upload; Gen4 cleaning session information and robot information. The API is a command bridge rather than a fixed list of REST action endpoints.

No supported joystick driving, arbitrary go-to coordinates, camera feed, or continuous live robot position is established by the inspected UI/API. A dock icon is not evidence of live pose tracking. Run maps are uploaded artifacts, not a promised live navigation stream.

## 3. What the installed system currently offers

| Observation | Result |
| --- | --- |
| Server | Version 1.0.0, America/Los_Angeles, UTC offset -420 minutes at capture |
| Robot | Internal serial `EXAMPLE-ROBOT-001`, type `neato.gen4` |
| User-facing identity | Name `gen4-EXAMPLE-LABEL-001`; label serial `EXAMPLE-LABEL-001` |
| State | Idle, battery 86%, docked and charging, no errors (refreshed capture) |
| Available commands | Start true; cancel, pause, resume, return-to-base false |
| Saved maps / runs | One promoted saved map, zero configured boundaries, three runs |

This is enough to implement status and core control integration. Seeing actual rooms requires configured cleaning zones on the existing saved floor map. The saved map is now present, but its boundary list is empty. Configuring zones is an operational setup step and was not performed during discovery. Controls and successful docking require a supervised hardware validation session before release.

## 4. First release requirements

| ID | Requirement | Acceptance criterion |
| --- | --- | --- |
| F01 | Discover and remember a server | First launch requests local network access and discovers Bonjour servers; automatically connect when exactly one server validates through `/api/server`; show a picker for multiple servers; remember the successful server. Later launches try the remembered server first, rediscover only if it cannot be reached/validated, and show manual address entry only when discovery finds no servers. Manual entry accepts IP/hostname and optional port, normalizes pasted `/web` URLs, and validates before saving |
| F02 | Select and identify robot | List registered robots and online state; use internal serial for all API calls; show name and label serial; preserve selection; explain no-robot and offline states |
| F03 | Show current status | Show battery, activity, docking/charging, errors and freshness; distinguish server unreachable, robot offline, and stale state; refresh on foreground/reconnect |
| F04 | Show floors and rooms | List maps and display pan/zoom floor image, saved dock and named colored cleaning zones; distinguish cleaning zones from no-go boundaries; show “No saved maps yet” when the map list is empty |
| F05 | Start cleaning | Offer whole-house cleaning with generation-appropriate defaults; submit once only when `start` is available; confirm through subsequent reported state; continue to offer house cleaning when no map exists |
| F06 | Clean selected rooms | Show eligible saved zones; restrict Gen4 cleaning to zones on the promoted map; restrict Gen3 to one zone on an enabled map; require docked status for the initial zone workflow, matching web UI; never silently substitute whole-house cleaning when a selected zone is invalid |
| F07 | Pause and resume | Show pause/resume according to available commands; preserve selected cleaning settings; show acknowledgement separately from observed activity |
| F08 | Stop | Clearly label “Stop cleaning”; send Gen4 cancel or Gen3 stop; stop is distinct from pause and from return-to-base; confirm stopped activity from refreshed state |
| F09 | Return to base | If directly available, request return. If cleaning can be paused, pause first and wait for reported return availability, then send return. Show stages “Pausing”, “Returning”, and “Docked”; show failure if docking cannot be confirmed |
| F10 | Handle command results | Indicate in-flight requests; suppress duplicate taps; surface robot rejection, disconnected robot, server error and timeout; after ambiguous timeout refresh status before another user action |
| F11 | Support interruption | On background, release streaming resources; on foreground reconnect and refresh. Never queue movement commands for later automatic execution |
| F12 | Provide usable native controls | Accessible labels and scalable text; battery and error meaning available without color; map zones also selectable in a text list; core controls remain available outside map gestures |

Suggested defaults: Gen4 `eco` / `normal`; Gen3 mode `1` / navigation `1`. Use reported device type/capabilities and avoid offering unsupported power modes. Map creation, map edits and promotion remain in the existing web app for MVP. A link to that web app is sufficient during initial setup.

## 5. Main screens and flows

**Connection:** First launch → explain/request local network access → show “Finding your Vacuula server…” → browse Bonjour for a bounded discovery window → validate candidates through `/api/server`. Exactly one valid server connects automatically; multiple valid servers show a picker with names and addresses. Save the successful server and load its robot inventory, fresh state and subscriptions. A server with no robots or an offline robot is still a successful server connection; show its robot empty/offline state instead of returning to discovery.

**Later launches:** Try the remembered server first, resolving its saved Bonjour service identity when available so an IP change does not require setup again. If it cannot be reached or validated, return to discovery. Apply the same one-server auto-connect and multiple-server picker rules. Preserve the existing saved choice until another server connects successfully.

**Discovery fallback:** Show manual address entry only after discovery finds no servers. Explain that the phone and server need to share a network that allows discovery, and offer Retry discovery alongside entry. If servers are discovered but fail validation, show the discovered servers and connection errors with Retry; do not silently connect to an arbitrary endpoint. If local network permission is known to be denied, show permission recovery and Retry before fallback; manual IP entry does not bypass permission. A failed request alone must not be labeled conclusively as denied permission.

**Robot:** Name, online/freshness indication, battery, status, errors, cleaning mode, primary Start/Pause/Resume, separate Stop and Return to base. Optional Locate can follow core control validation. Activity is determined by state plus action, not HTTP success alone.

**Rooms:** Select floor → render saved map and dock with cleaning zone overlay → select zone(s) → review names and mode → start. Permit viewing an unpromoted map, but explain why its rooms cannot currently be cleaned. Keep read-only maps available from cache when offline, explicitly marked as cached.

**Return:** Refresh state → return immediately if permitted, otherwise pause when permitted → await state allowing return → submit return → observe docking activity → observe docked/charging. Stop waiting and explain when the robot rejects the action, disconnects, or fails to become eligible. Never equate an accepted return command with arrival at the base.

**Empty map:** Explain that rooms will appear after a floor map and cleaning zones are configured in the web app. Keep whole-house controls available. Do not invent room names or infer geometry from a missing map.

## 6. Follow-on parity work

1. History list and run map detail; Locate; rename robot.
2. Schedule management with timezone-aware presentation; robot settings and local display preferences.
3. Native map/zone editor, Gen4 promotion workflow and Gen3 exploration, with explicit save/upload status and failure recovery.

Remote access, cloud accounts, push notifications, HomeKit/Shortcuts, widgets, joystick controls, and continuous live positioning have no MVP commitment. Existing source support must be established before adding each feature.

## 7. Release validation

- Validate normal and failure flows with fixtures before using hardware: no robots, offline robot, empty maps, invalid zone, denied network, SSE reconnect, stale state, rejected command and ambiguous timeout.
- On the installed Gen4 robot, supervise start → pause → resume → stop; then start → return-to-base, confirming actual docking and reported state. Capture protocol responses without relying on UI animation.
- After a floor map and zones exist, verify map orientation/dock alignment and clean a selected zone; verify that no-go boundaries are never offered as rooms and selected rooms refer to the uploaded promoted map.
- Validate return while already docked, from paused state, and after a connection interruption. No repeated motion command after timeout.
- Test first launch with zero, one and multiple discovered servers; one-server auto-connect; server validation failure; remembered-server reconnect; changed IP via saved Bonjour identity; fallback discovery after server removal; manual entry only after no discovery results; and manual `/web` URL normalization.
- Test an iPhone on the same LAN, permission denial/recovery, discovery timeout, background/foreground and server restart.
- Gen3 support remains source-derived until tested on Gen3 hardware; do not advertise it as verified based on Gen4 results.

## 8. Open decisions and dependencies

The first implementation is a native SwiftUI app targeting iOS 26+, using standard system navigation and controls to adopt the current Apple design. Its protocol library supports iOS 17+ for reuse/testing; extending the app UI to older systems is deferred. Gen4 is the first hardware validation target, with a separate Gen3 command adapter. Deployment/distribution remains an implementation decision. No server endpoint additions are apparent for the core scope, but this remains conditional on live command/map validation against the deployed version.

Room cleaning acceptance depends on configuring zones on the existing promoted map. Exact docking timeout, event freshness threshold, and available capability signals need hardware observations. Documentation does not imply that these operations have been tested.

## 9. First implementation

A first native implementation is in [ios/](ios/README.md), including discovery-first setup, Robot/Rooms/Schedule/History/Settings tabs, protocol adapters, live events, core control workflows and Gen4 map/room integration. This is a prototype pass, not acceptance of every release requirement. See its README for deferred scope and validation results. The design uses native SwiftUI components, semantic colors, system typography and plain action labels; it does not draw a custom navigation or glass system.

## Activity summary and foreground banners

The Robot toolbar bell opens a native Activity sheet with recent notification summaries, room context, receipt times and a loaded-event unread count. Tapping an event marks it read; Mark all read handles all loaded rows. Read markers persist on this phone. Earlier events can be fetched on demand.

Distinct new foreground events may show a dismissible banner that opens Activity. Initial/reconnect history never replays banners, duplicate IDs do not create duplicate rows or alerts, and historical failures never replace current robot status. Normal starts are informational; known schedule failures, unreachable rooms and map localization failures receive attention styling. The app does not automatically retry an action. Push delivery and a persistent offline notification cache are deferred. Server PR #30 supplies persistence; no additional server API is required for this scope.


## Native schedule acceptance — 2026-10-19

Native Gen4 scheduling is implemented in the Schedule tab. Create recurring cleans with repeat days, local time, power/navigation, active saved-map/no-go support and optional configured rooms; edit timing without rewriting existing cleaning settings, toggle enabled state and confirm deletion. Read back every write and require refresh after ambiguous results. Read-only mode blocks changes; demo changes are local only. See [implementation, payloads and Activity test procedure](ios/scheduling.md).


## Cleaning history and loading readiness — 2026-10-19

The native History tab reads existing Gen4 run records, combines intermediate/final snapshots per robot/start time, distinguishes cancellation from successful completion, and shows cleaned sq ft, elapsed duration, battery and segment settings. Users may save a local whole-floor area target for explicitly labelled area comparisons; no expected area is inferred from saved maps. The Schedule tab now shows loading/incomplete/retry states, suppresses request cancellation errors and visibly greys unavailable actions until a successful read. See [history implementation and data semantics](ios/history.md).


## Persistent defaults and recent runs — 2026-10-19

Manual power/navigation defaults are stored locally per server origin/robot, restored on connection/selection/restart, and used to initialize new schedules. Existing schedules and resumed cleans retain their original settings. Home lists recent runs and Schedule lists reported scheduled runs, with trigger/source, duration, cleaned sq ft and expected-area comparison when configured. Run records lack schedule IDs, so per-schedule membership is not inferred from edited/current times. See [behavior and integration limits](ios/cleaning-options-and-recent-runs.md).


## Map display orientation — 2026-10-19

Settings → Maps → Rotation provides four clockwise orientations (0°, 90°, 180°, 270°), defaulting to zero and saved locally across all maps/robots/servers. Raster, room/no-go overlays, selection fills and base position use a shared rotation; rectangular maps are fitted after swapping axes for quarter turns. Rotation changes reset zoom/pan; ordinary Reset view keeps the chosen orientation. Robot/map/cleaning coordinates and server data remain unchanged. See [renderer and validation notes](ios/map-orientation.md).
