# Vacuula Remote for iOS

A SwiftUI LAN client for the existing Vacuula server. Open [Vacuula.xcodeproj](Vacuula.xcodeproj) in Xcode 26 or later. This first app target requires iOS 26; the protocol library supports iOS 17 and macOS 14 for testing.

## Included

- Bonjour discovery on first launch. One validated server connects automatically; multiple servers show a picker. A successful server is remembered, including its Bonjour service identity. Manual address entry appears only after discovery finds no services.
- Robot inventory, remembered robot selection, battery, docking/charging, errors, freshness, read-only refresh and SSE updates with reconnect. Live errors such as a missing dirt bin explain the cause and corrective action in the top status card.
- Capability-gated start, pause, resume, stop and return to base. Return pauses when necessary, waits for reported return availability, sends one return command, and waits for reported docking. Ambiguous failures reconcile state without repeating a movement command.
- Eco/Turbo (Gen4) or Eco/Normal (Gen3), with gentle navigation, remembered per robot/server across app restarts. Gen4 whole-house cleaning uses the active promoted map when available so its uploaded no-go areas apply.
- Saved floor maps with RLE validation, cropped display with preserved coordinates, dock marker, zone/no-go overlays, pan/zoom/reset, a text room-selection list, and Gen4 room cleaning after revalidating map and zone eligibility.
- Native Gen4 weekly scheduling: create whole-floor/room cleans, edit timing, enable/disable and delete, with robot read-back confirmation. See [scheduling.md](scheduling.md).
- Activity summary and foreground event banners backed by server notification history. See [activity.md](activity.md).
- Gen4 cleaning History with deduplicated sessions, cleaned square feet, duration/battery and an automatic current-map requested-area estimate. See [history.md](history.md).
- Recent cleans on Home and scheduled-run history in Schedule, with source icons, duration and expected-area comparisons. See [cleaning-options-and-recent-runs.md](cleaning-options-and-recent-runs.md).
- Global saved map orientation at 0°/90°/180°/270°, including room/no-go overlays and base position. See [map-orientation.md](map-orientation.md).
- Server details, robot identity, local network recovery and links to the web app for setup and room editing.

No cleaning or movement request runs at launch or reconnect. Use **Try demo** from the connection toolbar or Settings to explore with sample data. **Exit demo** restores normal connection behavior. The `--demo` launch argument opens the same sample-data mode for automated tests. Demo disables physical controls, removes the API client, and keeps schedule edits/read markers in memory; it makes no server requests. Real server selection, cleaning options and map rotation are preserved. Preview UI tests use that mode; the separate live UI checks use `--read-only`, require the configured LAN server and are skipped unless the test runner environment contains `VACUULA_LIVE_TESTS=1`.

`--demo --dark-preview` also forces Dark Mode for visual testing. At accessibility text sizes the decorative robot is omitted to prioritize status and controls.

The `--read-only` launch argument uses the real server discovery, state, events and maps while disabling every physical control. Use it for the first LAN smoke test.

## Run

1. Open `ios/Vacuula.xcodeproj` in Xcode 26 or later.
2. Select the **Vacuula** scheme and an iOS 26+ simulator, or choose a signing team and a compatible iPhone.
3. Run. Allow local network access and keep the device on the server's local network. First launch should find the existing server automatically.

The project includes `NSLocalNetworkUsageDescription`, `_vacuula._tcp` in `NSBonjourServices`, and `NSAllowsLocalNetworking` for local HTTP. It does not bypass HTTPS certificate validation.

For command-line builds from the repository root:

```sh
export DEVELOPER_DIR="$(xcode-select -p)"
xcodebuild -project ios/Vacuula.xcodeproj -scheme Vacuula \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ios/.derivedData27 ARCHS=arm64 build
swift test --package-path ios
```

Run the scheme's UI tests on a simulator to verify preview navigation, disabled robot controls, large text and Dark Mode. UI tests retain screenshots as test attachments. The package’s protocol tests use anonymized response examples, a synthetic floor map and synthetic edge cases; they do not contact the robot. `DemoContent` supplies shared map, zone, schedule and history fixtures for both the app and core tests. The visible demo navigation UI test uses `--demo-entry` to show the real connection screen without starting discovery, then enters demo through the button.

## Design

Standard `TabView`, `NavigationStack`, `List`, `Form`, `Picker`, `Toggle`, `ContentUnavailableView`, system button styles, system typography, semantic colors and SF Symbols keep the app native. System bars and controls adopt Liquid Glass on supported OS releases without custom glass backgrounds. The Robot tab places status before actions; Rooms provides both a map and a text list. Buttons use explicit action labels and large tap targets. No information depends on color alone.

Apple sources reviewed for this build:

- [Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/liquid-glass)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
- [Writing](https://developer.apple.com/design/human-interface-guidelines/writing)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

## Validation

The app builds with Xcode 27.1 and the iOS 27.1 SDK. All 32 core tests pass, including scheduling and Activity coverage. The native schedule create/edit/delete preview UI test passes; earlier UI checks on the iOS 27.0 simulator cover large text/Dark Mode, real Bonjour discovery plus live status/map loading in read-only mode, and preview navigation with disabled controls. See [validation/README.md](validation/README.md) for evidence and screenshots. Debug simulator builds use local ad-hoc signing, without a developer account.

## First-build limits

Physical controls, actual docking, room cleaning and Gen3 hardware behavior require supervised validation. A reported docked state is not physical docking verification. Gen3 cleaning-run history and scheduling, native room editing, map promotion and robot preferences remain in the web app. Map orientation and dock alignment need confirmation against the real floor. Maps are loaded live; persistent offline map caching is not implemented. Gen3 command support is source-derived; native Gen3 room selection is deferred. This is a development build, without distribution signing. The app icon and Robot tab use original D-shaped vacuum artwork; see [icon artwork](Design/README.md).

Protocol fixtures contain local robot/map identifiers. The server clone and its upstream AGPL-3.0 license are in `../../vacuula`; provenance and refreshed observations are in the parent discovery notes.

## Responsive home screen

The Robot tab uses an inline navigation title, tighter section spacing and a status card that switches to artwork beside the status when the available height is below 740 points. Larger accessibility text keeps a vertical, scrollable layout with the decorative artwork omitted. Normal-size docked and active-cleaning layouts are checked for the final cleaning option clearing the floating tab bar without scrolling. Use `--demo --demo-cleaning` for a disconnected preview with Pause, Stop and Return controls disabled.

## Primary button appearance

The main cleaning button explicitly retains both its SF Symbol and title. Enabled content uses white over the app tint; disabled content uses a secondary foreground. `--demo --button-preview` opens an isolated appearance screen with enabled and disabled copies whose actions are empty, for visual checks without robot commands. Add `--dark-preview` for Dark Mode.

## Activity

The Robot toolbar bell opens recent notification history supplied by server PR #30. Unread markers are saved on this phone. New live events display foreground banners; reconnect history is recovered without replaying old alerts. See [Activity behavior and integration](activity.md). No additional server changes or Apple push credentials are required for this foreground feature.

## License

GNU Affero General Public License, version 3 (AGPL-3.0), matching the Vacuula server. This includes the app’s original D-shaped icon artwork. See [LICENSE](../LICENSE) and the [project license scope](../README.md#license).

## Distribution troubleshooting

See [distribution notes](distribution.md) for the confirmed Apple/Homebrew rsync packaging conflict and the scoped Xcode launcher.
