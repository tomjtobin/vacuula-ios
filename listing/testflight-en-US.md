# Vacuula Remote — external TestFlight listing draft

Status: Beta App Description, Marketing URL, feedback email, private contact, published privacy URL and build-3 reviewer demo instructions saved in App Store Connect through Safari. What to Test remains prepared for the next uploaded build; not submitted to Beta App Review. Private contact details are saved. The visible demo is implemented locally and requires uploading the new build before review. Observed builds 1 and 2 are both Internal Only. Build 3 must be uploaded using the normal App Store Connect option for external eligibility.

## Identity

- App name: Vacuula Remote
- Bundle ID: com.vacuula.ios
- App Store Connect app ID: 6824692460
- Primary language: English (U.S.)
- Suggested category: Utilities
- Subtitle: Works with Vacuula server
- Marketing URL: https://github.com/tomjtobin/vacuula-ios
- Support URL: https://github.com/tomjtobin/vacuula-ios/issues
- Feedback email: vacuulaios@gmail.com
- Privacy policy URL: https://github.com/tomjtobin/vacuula-ios/blob/main/PRIVACY.md

## Beta App Description

Keep your Neato cleaning with Vacuula Remote, a native iPhone companion for the community Vacuula server.

Check your robot’s status and battery, start or pause a clean, send it back to its base, and choose cleaning power and gentle navigation. Explore saved floor maps, rotate them to suit your view, and select configured rooms to clean.

For supported Gen4 robots, create weekly cleaning schedules and review previous cleans with duration, cleaned area and estimated coverage. Coverage estimates use the current saved floor or requested rooms, excluding no-go areas. Notification activity and foreground banners help explain what the robot reports.

This beta requires iOS 26 or later, a compatible Neato robot configured with a Vacuula server, and access to that server on the same local network. Robot setup and room editing are handled in the server’s web app. Gen3 support is limited, and some features require a server version that exposes the corresponding APIs. Background push alerts are not available in this beta.

Vacuula Remote is an independent, open-source project and is not affiliated with or endorsed by Neato Robotics.

## What to Test

Please test with your Vacuula server and compatible robot on the same Wi-Fi network:

• First-launch server discovery, reconnecting to a remembered server, and recovery when the server is unavailable.
• Robot status, battery and clear error messages, including recovery after an error clears.
• Start, pause, resume, stop and return-to-base controls. Check that available actions match the robot’s actual state.
• Remembered cleaning power and gentle navigation between runs.
• Saved maps, map rotation, room selection and no-go overlays.
• Gen4 schedule creation, editing, enabling/disabling and deletion. Check timing at the robot’s location.
• Cleaning history: run source, duration, cleaned area and automatic estimated coverage. Unknown scopes should have no percentage; cancelled runs should remain labelled cancelled.
• Foreground notification banners and Activity with a compatible server.
• Readability and layout with larger text and Dark Mode.

Please include your iPhone model, iOS version, robot model and server version with feedback. Describe what you expected and what happened. Remove credentials, robot serial numbers, home maps and private server details before sharing logs or screenshots publicly.

## Beta App Review Information — private fields

- First name: saved privately in App Store Connect
- Last name: saved privately in App Store Connect
- Contact email: vacuulaios@gmail.com
- Contact phone: saved privately in App Store Connect; deliberately omitted here
- Sign-in required: no app account/login exists; hardware/server access is required for live operation

## Review Notes — current truthful draft

Vacuula Remote is an independent local-network client for the open-source Vacuula server. It does not use a developer-hosted production account service. Live operation requires a compatible Neato robot connected to a Vacuula server on the same local network. Local Network permission is used to discover and communicate with that server.

Review instructions for the next uploaded build (0.1.0 build 3), after verifying that build contains the visible demo:

1. Launch the app. On the server connection screen, tap **Try demo** in the top-right toolbar. No account, server or robot is needed for demo access. If already connected to a server, **Settings → Try demo** opens the same demo.
2. The persistent **Demo · Sample data** strip confirms sample mode. Explore Robot, Rooms, Schedule, History and Settings. Open the activity bell, Preview floor map, schedule forms and clean details.
3. Robot movement/cleaning controls are disabled in demo. Sample schedule edits stay in memory and do not contact a server. Maps, rooms, statistics and activity are simulated sample data.
4. Tap **Exit demo** to return to normal server connection. Live operation requires the user’s own compatible robot and Vacuula server on the same local network.

Do not submit an older build with these instructions: the visible demo is newly implemented in build 3 and requires a fresh archive/upload.

## External testing setup

1. Upload a new archive using normal App Store Connect distribution, with “TestFlight internal testing only” disabled. Internal-only builds cannot be used for external testing.
2. Wait for processing, then confirm the build is eligible for external testing and encryption compliance is resolved. New archives include ITSAppUsesNonExemptEncryption = false.
3. Save beta description, feedback email, reviewer contacts and accurate access instructions.
4. Create an external group, add the eligible build and its What to Test notes.
5. Submit the build for TestFlight App Review. Invite testers or enable a public link after approval, according to the developer’s intended audience.

The initial external build requires Beta App Review. External TestFlight does not require completing the entire public App Store product page first; use the beta-specific metadata and satisfy the fields App Store Connect requires for the build/account.

## API mapping

Apple’s official App Store Connect API supports betaAppLocalizations (description/feedback/URLs), betaBuildLocalizations (What to Test), betaAppReviewDetails (private review contact/access notes), betaGroups and build relationships, and betaAppReviewSubmissions. API automation requires an authorized API key/JWT. An existing Safari login can be used through the web UI without creating API credentials.

Sources:
- https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information
- https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/
- https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers
- https://developer.apple.com/documentation/appstoreconnectapi/beta-app-review-submissions

## Build-3 validation

All 42 core tests pass, and the signed 0.1.0 (3) archive is ready locally. UI tests were added but could not start because both simulator attempts stalled at the Apple boot screen. Navigation is not yet verified by this run. Build 3 is not uploaded or submitted.
