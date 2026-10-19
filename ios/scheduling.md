# Native scheduling

Implemented 2026-10-19. No server changes are needed: Gen4 uses the existing generic command bridge.

## In the app

Open **Schedule → Add schedule**, choose a time at the robot’s location, select repeat days and save. New schedules support Eco/Turbo, gentle navigation, the active promoted floor map and optional configured cleaning zones. Saved-map cleaning enables its no-go areas. Without a saved map, the form explicitly explains that saved no-go areas and rooms cannot apply.

The list supports enabling/disabling, editing time/days/enabled state and deleting with confirmation. Editing preserves the complete existing cleaning command, including unknown fields and mixed runs; use a replacement schedule to change cleaning options. Repeat days are mandatory. These are weekly recurring events, not one-shot timers.

Writes are disabled for offline/unsupported robots, read-only mode, background scenes, concurrent commands and unrefreshed/ambiguous schedule state. `--demo` changes only an in-memory preview list and never sends a robot request. A successful live write is followed by `scheduling.show` and a content check. A timeout or read-back mismatch never causes an automatic retry. Refresh and inspect the list before trying another change; refresh from a failed editor closes it to avoid resubmitting a possibly saved new event.

## Protocol

- Read: `{"ability":"scheduling.show"}` → `{code:200,body:{enabled:true,events:[...]}}`.
- Create/update: `{"ability":"scheduling.update","event":{"id":"existing-only","enabled":true,"days":["mon"],"time":"09:00","command":{...}}}`. Omit ID for creation; robot assigns it.
- Delete: `{"ability":"scheduling.delete","id":"..."}`.
- New commands use `cleaning.start`, `auto_localization:false`, `force_floorplan:false`, with runs containing `settings:{mode:"eco"|"turbo",navigation_mode:"normal"|"gentle"}` and `map:null` or `{rank_id,track_id:null|zoneID,nogo_enabled:true}`.
- `force_floorplan` is read from the robot's global setting by firmware `scheduling.show`; `scheduling.update` does not save that field. Read-back matching ignores it and legacy `auto_localization`, while retaining both in edits.
- Time is a wall-clock `HH:mm` and days are `mon` through `sun`. Firmware's scheduler uses its configured local time zone. The form displays the server's reported zone; it does not set the robot's clock/time zone. Verify robot configuration if scheduled execution is offset.
- Maps and any selected zones are revalidated before creating an event. Basic scheduling does not depend on current cleaning-state capabilities.

Contract checked against upstream `app/src/types/neato/gen4/schedule.ts`, web `scheudle_gen4.tsx`, and saved firmware's `neato_call_rpc.py` scheduling handlers plus `scheduler.py`. Firmware backups remain private.

## Test Activity with a real schedule

1. Rebuild/run on iPhone. Keep it on the server's Wi-Fi and leave the robot charged on its base.
2. Add a schedule for today's weekday, several minutes ahead, using the robot's local time. Check it appears after saving.
3. Keep Vacuula in the foreground. When the robot executes the schedule, `routine_cleaning_start` should appear as **Scheduled clean started**, or a reported off-base/low-battery failure as **Scheduled clean couldn’t start**. Open the bell to inspect Activity. Saving an event alone does not produce a notification.
4. Disable or delete the repeating test schedule afterward. The robot runs its saved schedule even when the app is closed; only foreground banners require the app to be active. Server history can be loaded on the next app connection.

No live schedule or physical movement was requested by the development/verification commands.

## Validation

The app and UI-test target build with Xcode 27.1. All 20 core tests pass, including four schedule protocol/validation tests. The simulator preview test passes through native creation, repeat-day editing and deletion. See [validation evidence](validation/README.md). The live baseline read succeeded with no saved events; actual live writes and timed execution have not been exercised by the agent.
