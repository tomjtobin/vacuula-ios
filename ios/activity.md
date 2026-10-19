# Activity and foreground banners

The app consumes the notification history and SSE events supplied by Vacuula
PR #30. No further server change is needed for this feature. The server migration
must have been applied. The server owns the stored history; read markers are
device-local UserDefaults entries scoped to server origin and robot ID.

## Interface

- A bell on the Robot screen opens Activity. A badge signals unread loaded events;
  its accessibility label includes their count.
- Activity shows recent events, unread count, receipt times, contextual room names
  and plain-language descriptions. Tapping an event marks it read; Mark all read also
  marks offscreen loaded rows. Load earlier activity follows server pagination.
- New events received while the app is foregrounded can display a dismissible
  banner for nine seconds. Tapping it opens Activity. There is no notification
  permission prompt and no push registration.
- Scheduled starts are informational. Known schedule failures, low battery,
  unreachable rooms and saved-map localization failures use an attention icon.
  Unknown codes remain readable as a generic robot update.
- Event descriptions use past tense. They never overwrite current robot status,
  disable controls, retry cleaning, or assume a historical problem still exists.
  Map-failure variants recommend checking current status without claiming the
  robot cancelled or continued solely from the code suffix.

## Transport and lifecycle

`RobotNotification` decodes both history records and named `notification` SSE
events, including arbitrary JSON context. `NotificationPage` decodes
`notifications` and `next_before`. History is fetched in pages of 50 using
`GET /api/robot/{serial}/notifications?limit=50&before={cursor}`.

The app listens on the selected robot's existing `/connect` stream. Its SSE
connection is established before the history fetch so arriving bytes can be
buffered during reconciliation. It does not consume the duplicate server-wide
notification event. Inventory and ordinary status events retain their existing
handlers.

On connection/reconnection, foreground resume and periodic foreground polling,
the app refreshes the latest history page. Older records are available on demand.
Unread counts describe loaded records, not an aggregate server count. On refresh,
the pagination cursor starts at the latest page; repeated pages merge by ID rather
than creating duplicate rows.

Records are filtered by robot, deduplicated by ID and sorted newest-first even
when SSE events arrive out of order. Read markers are explicit IDs, not a high-water
mark, so a late smaller ID is not silently marked read. A robot/server switch or
background transition invalidates outstanding callbacks and dismisses banners.

History fetches never generate banners. A live event must be new to the timeline,
follow a successful initial history load, belong to the active robot, and have a
valid receipt timestamp within two minutes of the phone's clock. This prevents
historical or badly skewed messages becoming misleading foreground alerts. Events
remain in Activity even when they are too old for a banner. Activity already open
receives new rows without a competing banner. A burst replaces the banner with the
newest arrival; every distinct record remains in Activity.

Activity fetch errors appear within Activity, preserving any records already
loaded. They do not disconnect the server or turn into robot control errors.
Notification payloads/history are held in memory and refetched from the server;
there is no persistent offline history cache. Read markers survive app relaunch on
the same phone and are not shared with other devices.

## Preview and validation

`--demo --demo-activity` supplies synthetic history without networking or enabled
robot controls. Add `--demo-banner` to inject one synthetic live event, or
`--reset-activity-read` to reset the preview's read markers. `--dark-preview`
and Dynamic Type launch overrides remain supported. These flags never insert
records into the real server.

Core tests cover payload/receipt decoding, known and unknown messages, deduplication,
robot isolation, ordering and persisted read markers. UI checks cover summary/read
state, foreground banners, accessibility text, the live history endpoint in
read-only mode, and the existing home-screen fit requirement. See
[validation](validation/README.md) for results and screenshots.
