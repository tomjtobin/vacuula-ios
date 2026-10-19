# Remembered cleaning options and recent runs

Implemented 2026-10-19.

## Cleaning preferences

Power (Eco/Turbo; Eco/Normal label on Gen3) and gentle navigation are saved on every selection using local UserDefaults, scoped by server origin and robot ID. They are restored after server connection, robot selection and app restart. Restoring a selection does not overwrite the other saved field. Invalid/missing stored modes fall back to Eco; navigation defaults to normal. Demo changes do not write preferences.

Earlier builds did not save these options, so an old selection cannot be recovered reliably; reselect the desired values once after updating. A new manual clean uses these saved choices. Resuming an existing clean retains its original run settings. New schedules start with the current manual choices, but a saved schedule keeps its own independent cleaning command: changing the home defaults does not rewrite existing schedules.

## Run lists

The Robot home screen includes the three most recent distinct cleaning sessions beneath the controls/options, with a link to all history. Rows show date/time, outcome and a source icon/label (App, Schedule, Robot button, Robot or Unknown), square feet, elapsed duration, and percentage of expected whole-floor area when configured. `app` is the robot's generic app-command source and can include web or other app clients; the endpoint does not distinguish the iOS client.

Schedule includes the three most recent reported scheduled sessions and a link to a scheduled-only history list. Manual/app and robot-button runs are excluded from that filtered list. Both surfaces open the existing detailed run statistics and share its snapshot deduplication and area comparison rules.

History is loaded on entering these screens, on pull/explicit refresh, and at most roughly once per minute through the foreground app tick. No background execution or physical control is introduced. The primary robot controls and options remain above the new list; history can be reached by scrolling.

## Percentage and schedule association limits

There is no measured unique-map-coverage percentage or expected floor area in the current run endpoint. Enter an expected cleanable whole-floor area through **All cleans and area target** / History. Rows compare reported area with that value and label it **of expected area**; room/unknown scopes do not use a whole-floor denominator. Overlapping passes can make an area comparison exceed 100%.

Run records report `started_by:"schedule"`, but no schedule-event ID or immutable schedule version. Historical membership in an individual schedule cannot be proven from weekday/time: schedules can be edited/deleted and may overlap. The Schedule screen therefore labels its history as runs from any schedule. Reliable per-schedule histories need an execution-to-schedule identifier from the robot/server; the app does not infer associations or retroactively assign old runs to a current schedule.

## Validation

Core tests exercise persistence/reopening, preference replacement, robot/server isolation, supported-mode fallback, and all start-source classifications. Existing history tests cover area conversion and run deduplication. Current logs and screenshots are under [validation/recent-runs](validation/recent-runs/); full check results are recorded in [validation/README.md](validation/README.md). No live robot movement or schedule mutation was issued for this change.

Current checks: app/UI-test builds succeed; all 30 core tests pass. Simulator checks pass for Home/Schedule recent-run source/stat rows and detail navigation, plus control visibility without scrolling in docked and active-cleaning previews. Real phone preference restoration remains a device smoke test.
