# Vacuula Remote

A native iPhone app for [Vacuula](https://github.com/vacuula/vacuula), the community server that keeps Neato robot vacuums running. Built with SwiftUI, with an original D-shaped vacuum app icon.

## Features

- Find a server on the local network using Bonjour, remember it, and reconnect automatically.
- View robot status, battery, docking state and actionable robot errors with live updates.
- Start, pause, resume, stop and return to base using the robot’s reported capabilities.
- Remember cleaning power and gentle navigation per robot.
- View saved maps, select configured rooms, zoom/pan and rotate all maps in 90° increments.
- Create and edit Gen4 weekly cleaning schedules.
- Review recent cleans and history, including run source, duration and cleaned square feet.
- Estimate coverage automatically against the current saved floor or requested rooms, excluding no-go areas.
- View notification activity and foreground banners when supported by the server.

## Build and run

Requires Xcode 26 or later and iOS 26 or later. The `VacuulaCore` Swift package also supports macOS 14 and iOS 17 for protocol testing.

1. Clone this repository and open `ios/Vacuula.xcodeproj`.
2. Select the **Vacuula** scheme. For a physical iPhone, select your own development team under **Signing & Capabilities**.
3. Build and run. Keep the iPhone and Vacuula server on the same local network and allow local network access.
4. The app discovers servers advertising `_vacuula._tcp`. If none are found, enter a hostname or server address.

For a preview without a server, add `--demo` to the scheme’s launch arguments. Preview mode disables physical robot controls; schedule edits stay in memory. `--read-only` connects to a real server with physical controls and schedule changes disabled.

```sh
swift test --package-path ios
xcodebuild -project ios/Vacuula.xcodeproj -scheme Vacuula \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/vacuula-ios-build build
```

See [iOS development notes](ios/README.md) for preview modes and validation details. UI tests whose names contain `Live` require a configured LAN server; preview tests use demo fixtures.

## Current scope

This is an early development app. Gen4 scheduling, history and room cleaning are implemented; Gen3 support is more limited. Initial robot setup, room editing and some preferences remain in the server’s web app. Foreground notifications do not provide background APNs push alerts.

History can distinguish scheduled runs from other sources when the robot reports them. Linking a run to an individual schedule still requires server support. Coverage estimates compare reported cleaned area with the current saved floor or identifiable requested rooms. They can change after map edits and are not measurements of unique spatial coverage.

## Specifications

- [Functional specification](functional-spec.md)
- [Technical specification](technical-spec.md)
- [Discovery notes](discovery-notes.md), with placeholder device identifiers
- [Proposed server schedule/run association](server-schedule-run-association-spec.md)
- [Icon artwork](ios/Design/README.md)

Raw device captures, firmware backups, generated screenshots, build outputs and Xcode user settings are excluded from the public repository. Published test fixtures use anonymous identifiers and a synthetic floor map. Historical documents may reference local evidence files that are not published.

## License

The iOS app, VacuulaCore library, original app artwork and project documentation are licensed under the GNU Affero General Public License, version 3 (AGPL-3.0), matching [Vacuula’s upstream license](https://github.com/vacuula/vacuula/blob/main/LICENSE). See [LICENSE](LICENSE).

Third-party software retains its own license and copyright notices. Robot firmware backups, extracted proprietary files and captured device data are not covered by this project’s license grant.
