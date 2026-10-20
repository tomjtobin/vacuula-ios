# Visible demo mode and offline tests

From any connection screen, tap **Try demo** in the top-right toolbar. From a connected app, use **Settings → Try demo**. The **Demo · Sample data** strip appears throughout the main tabs; **Exit demo** returns to normal connection behavior. No login, robot or server is needed to explore the sample mode.

The demo contains a synthetic saved floor, one room and a no-go polygon, a weekly room schedule, whole-floor and room history, a cancelled scheduled run, and notification activity. Robot controls remain disabled. Schedule creation/editing/deletion work on sample data in memory. Power/navigation options, map rotation, schedules and activity read markers do not overwrite real robot preferences. Exiting discards sample changes; it preserves the remembered real server and reloads saved map rotation.

Entering demo cancels active discovery/connection/stream tasks and invalidates session tokens. The API accessor returns nil while demo is active; network entry points and physical controls have separate guards. Leaving while a sample-area calculation is suspended cannot publish stale sample results into the live session. Web setup links are hidden for the simulated server.

## Swift core tests

`DemoContent` is the shared fixture source for the app, map view, schedule editor and protocol tests. Tests validate fixture decoding, map coordinates, free area minus no-go cells (24 m²), room area (10 m²), whole-floor/room history comparisons and schedule map/room references. These are ordinary Swift package tests and need no simulator or network:

```sh
swift test --package-path ios
```

## Swift-written UI tests

XCUITests exercise the actual SwiftUI views rather than replacing them with test views. `testVisibleDemoNavigatesMainScreensAndExits` launches with `--demo-entry`, which shows the connection UI without discovery, taps the real Try demo button, opens all five main tabs, Activity, the floor map, a new-schedule form and clean details, then exits and re-enters demo. It verifies disabled robot controls.

Additional tests exercise in-memory schedule CRUD, automatic history percentages, activity read markers, loading/failure states, map rotations, large text and Dark Mode. Demo read markers reset between sessions. Live read-only checks are opt-in through the test runner environment variable `VACUULA_LIVE_TESTS=1`; by default they skip.

```sh
xcodebuild -project ios/Vacuula.xcodeproj -scheme Vacuula \
  -destination 'platform=iOS Simulator,name=YOUR_SIMULATOR' test
```

`--demo` starts directly in sample mode for focused tests. `--demo-cleaning`, `--demo-bin-missing`, `--demo-schedule-loading`, `--demo-schedule-error`, `--demo-activity` and `--demo-banner` provide existing scenarios. `--demo-empty-schedules` starts with no sample schedule for creation/deletion tests. Launch arguments are test conveniences; reviewers use the visible Try demo button.

This tests presentation and local behavior. Real discovery, protocol/server compatibility, schedule execution and physical cleaning require separate supervised hardware validation.

## Physical-device UI tests

Select a paired, unlocked iPhone as the test destination. The VacuulaUITests target must have a development team as well as the app target. Live tests remain opt-in; the demo suite never requires a robot connection.

On a machine where parallel Swift compilation causes memory pressure, use `-jobs 1 SWIFT_COMPILATION_MODE=wholemodule` for a one-off `xcodebuild test` run. This does not change the release configuration.

Validated on a physical iPhone 17 on 2026-10-19: visible demo entry/exit and navigation, activity read-marker reset, automatic history/map-area comparisons, and schedule creation/editing/deletion all passed. The navigation check visits all five tabs plus Activity, map, schedule and clean-detail screens. These four focused checks use sample data only.
