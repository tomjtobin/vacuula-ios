# Server specification: associate scheduled attempts and cleaning runs

**Status:** proposed implementation contract, not implemented by this document. 2026-10-19.

## Objective

Let clients show the cleaning attempts and runs associated with each recurring schedule, including failed starts and historical schedules that were edited or deleted. Use the existing robot protocol and PR #30 notifications; no firmware change is required for an **inferred** association.

A successful result answers: which schedule most likely fired, which version was active, whether a cleaning run followed, and why the server considers the association unique or uncertain. Never present time correlation as an explicit identifier reported by the robot.

Initial scope is `neato.gen4`. Gen3 run responses remain unchanged; new schedule-association routes should reject unsupported robot models with a documented 400 error after validating the robot exists. Clients check both the server capability and robot generation.

## Existing evidence and constraints

- `scheduling.show` returns events with robot-local `id`, enabled, days, `HH:mm` and a cleaning command. Update/delete pass through `POST /api/robot/{serial}/command`; creation returns no assigned event ID, so read-back is necessary.
- PR #30 stores `routine_cleaning_start`, `routine_cleaning_start_offbase_error` and `routine_cleaning_start_low_battery_error`. The retained sample has a start notification received at `2026-10-19T08:40:02.136451Z` and a scheduled run starting at `2026-10-19T08:40:00Z`. The notification has no schedule ID and no robot occurrence timestamp.
- Gen4 run uploads contain `started_by`, `timing.start/end`, segment settings and track IDs. They do not expose a schedule ID. `floorplan` in existing run rows is a run-specific UUID, not an authoritative reference to the scheduled floor map.
- The firmware scheduler knows its event ID internally but forwards cleaning parameters without that ID. Server correlation can work without extending this firmware path.
- Multiple uploaded records can represent one clean. A closed record with `cleaning_complete:true` can still contain `state:canceled`; closure is not successful completion.

## Firmware trace clarification

A follow-up trace confirms the scheduler knows the exact robot event ID internally. `scheduler.py` selects `desired_event` using `_execute_id`, then calls `_send_clean_ipc(desired_event["params"])`. That function sends cleaning options with `CleanStartBy.SCHEDULER`, omitting the event ID. After the IPC call returns it assigns `_last_executed_id = _execute_id`; the value starts as `None` at process startup. An internal `get_last_executed_id()` getter exists, but no caller or remotely exposed ability was found in the saved Python sources. This is a volatile last-dispatched-ID value, not a durable per-run association or proof that cleaning succeeded.

`CleaningStartData` contains `started_by` but no schedule ID in its constructor or packed IPC layout. The run upload then reports `started_by:"schedule"` without an event ID. Thus the robot's scheduler knows which schedule it dispatched, but the inspected cleaning/run-report path does not retain that identity.

Another useful upload field is `persistent_rank_uuid`: firmware `map_upload.py` includes the original persistent-map reference, even though the inspected server run model/API does not retain it. The server should preserve this nullable field on newly ingested run records for stronger map-scope comparisons. Do not substitute the run-specific `rank_uuid`/existing `floorplan` value. Historical values may be imported only from retained original upload evidence, not guessed. This helps candidate rejection but is not a schedule identifier.

For a future definitive association, a robot-side extension should emit the schedule event ID with an execution identifier and occurrence time, and carry/link that execution identifier into the run report. Exposing only the volatile last-ID getter would still be unsafe for delayed uploads or subsequent starts.

## Required behavior

1. Retain schedules and immutable revisions, including disabled and deleted schedules.
2. Record observed scheduled attempts, even if no run is uploaded.
3. Correlate scheduled run uploads with attempts and historical schedule occurrences.
4. Store the decision and supporting evidence; handle delayed/out-of-order messages and restart recovery.
5. Expose associations and uncertainty through additive APIs and SSE.
6. Never start, retry, enable, disable or otherwise alter a cleaning operation as part of correlation.

### 1. Capture schedule history

On robot connection, read `scheduling.show` in a background worker. Also observe successful schedule reads through the command bridge, and reconcile after schedule update/delete requests. Periodically refresh while the robot is connected; proposed default: every 60 seconds. Coalesce reads per robot and use the existing command/request machinery; do not block robot message/heartbeat handlers waiting for another robot response.

Record the complete returned event collection and the time-zone context. Preserve the last known collection on failed reads: a timeout is not an empty schedule list or a deletion.

After a write, use a successful read-back as the observed truth. Do not invent an ID for a new event by matching only its time; identical events may exist. The entire returned collection contains the robot-assigned IDs. Ambiguous writes are reconciled by read-back, never by automatically repeating a mutation.

For changes, record the observation window rather than claiming an exact robot-side effective instant. Store command-send/response timestamps when available, and the previous/next successful snapshot timestamps. Changes made while disconnected or between polls can only be bounded by observations. A first observation must not be backdated to cover earlier runs.

### 2. Data model

Names below describe the required logical model; conform to existing SQLAlchemy/Alembic conventions.

| Entity | Required fields |
| --- | --- |
| `schedule` | Server UUID, robot serial, robot-local event ID, first/last seen UTC, current revision ID, observed-deleted timestamp |
| `schedule_revision` | Server UUID, schedule UUID, revision number, observed-from/until UTC, change uncertainty window, enabled, days, local `HH:mm`, time-zone ID and its provenance, full command JSON, canonical content hash, observation source |
| `schedule_execution` | Monotonic server ID, robot, observed attempt time, actual run start if known, candidate scheduled occurrence UTC if uniquely inferred, attempt outcome, latest run outcome, nullable schedule/revision UUIDs, match status/method/reason, created/updated timestamps |
| Execution evidence | Execution ID, notification IDs, all associated raw run IDs, candidate revision/occurrence pairs, relevant timestamps, matching-policy version and explanatory reason codes |

Robot event IDs are scoped to a robot. If an ID reappears after confirmed deletion/reset, retain the old schedule identity and create a new identity rather than reassigning old history. Revision hashes must be canonicalized across JSON key order and weekday order. Ignore legacy/global fields that are not actually saved per event (`auto_localization` and global `force_floorplan`) for change detection; retain their original values for diagnostics.

Keep raw runs and PR #30 notifications intact. Add links or association tables; do not replace their identifiers. Schedule/revision deletion must not cascade into historical executions. Robot deletion may follow the server's existing robot-data deletion policy.

### 3. Execution and run ingestion

- A persisted scheduled-start or scheduled-start-failure notification creates or updates an observed attempt. Preserve the PR #30 notification's original ID and `received_at`.
- A run with `started_by:"schedule"` may create an execution even if no notification was received. A notification is supporting evidence, not a mandatory prerequisite.
- Runs reported as app/button/internal/unknown must never be assigned to a schedule based on time alone.
- Link intermediate/final uploads for the same robot and actual start time to one execution when their content is compatible. Keep all raw IDs, use the newest compatible snapshot for statistics, and do not sum snapshot areas. Conflicting records or timestamp collisions must remain distinguishable and flagged rather than silently merged.
- Separate attempt and run outcomes. `routine_cleaning_start` means a start was reported, not that cleaning completed. Off-base/low-battery failures need no synthetic run. Run cancellation/error takes precedence over the closed-record flag when presenting completion.
- A delayed run upload is matched using its robot start time, not its HTTP upload time. Late notifications/uploads trigger reconsideration of affected records without restarting a cleaning.

### 4. Matching policy, version 1

Run matching per robot, in UTC, with a named configurable policy. Proposed initial start/notification tolerance: **120 seconds**; retain this value with each decision. Treat it as an upper bound, not a promise that all deliveries occur within it.

1. Identify the observed execution: prefer the run's actual `timing.start`; otherwise use notification receipt as a provisional time.
2. Generate candidate occurrences from enabled historical schedule revisions in their recorded IANA time zone. Use the weekday and wall-clock time, and preserve the resulting UTC offset/occurrence. Do not match solely on today's schedule or a fixed UTC offset.
3. Select occurrences within the tolerance, whose revision observations support that time. A run's start may differ slightly from its due time. A notification's receipt is a delivery timestamp and provides weaker evidence, especially when delivery delay or robot clock skew is unknown.
4. Use actual available segment power/navigation and track IDs to reject incompatible candidates. Missing fields are unknown, not a match or mismatch. Do not use the run-specific `floorplan` UUID as a persistent-map comparison.
5. Assign only when one candidate remains and the observation/time-zone evidence is adequate. Do not break ties by nearest second, lowest schedule ID, schedule ordering, or enabled state today.
6. Re-run the decision when relevant evidence arrives or the matching policy is deliberately upgraded. Keep a decision audit trail. New current schedule revisions must not rewrite older revision snapshots.

Statuses:

| Status | Meaning / client behavior |
| --- | --- |
| `matched` | Unique supported correlation. Set schedule/revision IDs, `confidence:"inferred"`, and method `time_correlation_v1`. Group under that schedule with an inferred association. |
| `ambiguous` | More than one supported candidate or a change/time-zone uncertainty affects ownership. IDs are null; return candidates and reason. Do not group under one schedule. |
| `unmatched` | No supported candidate, missing historical observations, invalid timestamps, unknown time zone, or insufficient evidence. IDs are null; retain the execution in general scheduled history. |

All v1 matches are inferred. There is no `confirmed` status or arbitrary numeric confidence score in this implementation. An explicit robot execution/schedule identifier could support confirmation in a later protocol version.

For DST, handle both folds explicitly. Do not manufacture occurrences in a nonexistent spring-forward local time. If the robot's behavior/offset cannot distinguish a repeated local time, keep the association uncertain. Preserve the robot/server time-zone source; do not silently substitute the client's phone time zone. If robot time zone is unavailable, a configured server-zone assumption must be recorded and surfaced as such.

### 5. Notification idempotency and persistence

PR #30's `(robot, request_id)` deduplication and commit-before-ack behavior remain unchanged. Reprocessing the same notification must not duplicate an execution. Different request IDs near one another are not automatically duplicates: they can describe separate attempts. Combine evidence only with a supported common occurrence/execution; preserve ambiguous cases.

Persist reconciliation work with the ingestion transaction, or provide a durable pending-work mechanism plus startup reconciliation. A crash after accepting a notification/run must not permanently omit its association. Publish changes only after commit. Offline clients recover through GET endpoints; SSE is not authoritative history. Avoid publishing an association change if the committed decision/evidence did not change.

## API contract

Keep existing command routes and the existing run-array response shape. Add fields without changing old fields or requiring updated clients.

### Existing `GET /api/robot/{serial}/runs`

Each scheduled run gains a nullable `execution_id` and `schedule_association`:

```json
{
  "id": "existing-raw-run-id",
  "started_by": "schedule",
  "execution_id": 42,
  "schedule_association": {
    "status": "matched",
    "schedule_id": "server-schedule-uuid",
    "schedule_revision_id": "immutable-revision-uuid",
    "robot_schedule_id": "7",
    "scheduled_for": "2026-10-19T08:40:00Z",
    "confidence": "inferred",
    "method": "time_correlation_v1",
    "reason": "unique_observed_occurrence",
    "notification_ids": [1],
    "updated_at": "2026-10-19T09:00:00Z"
  }
}
```

For ambiguous/unmatched scheduled runs, return the status/reason with null assigned schedule/revision IDs. For non-scheduled runs, both new fields are null. Multiple raw snapshots may share `execution_id` and the same association; clients must not treat those snapshots as separate executions.

### New read-only endpoints

- `GET /api/robot/{serial}/schedules`: observed schedule catalog, including stable server ID, robot event ID, latest revision, observed/deleted state and last successful refresh time. Include tombstones so clients can label history for deleted schedules. This is an observed mirror, not a new source of robot control truth.
- `GET /api/robot/{serial}/schedules/{schedule_id}/revisions`: immutable revisions and observation/time-zone metadata.
- `GET /api/robot/{serial}/schedule-executions?limit=50&before={id}`: newest-first actual observed attempts/executions, including matched, ambiguous, unmatched and failed starts. Optional `schedule_id` filters **assigned matches only**, never ambiguous candidates. Return `{executions:[...],next_before:...}`. Use stable descending monotonic IDs, not mutable latest-upload ordering, for pagination.

Execution entries include the fields from the logical model, `run_ids`, latest representative run ID/statistics, notification evidence, candidates where applicable and decision reason. Validate robot ownership for every nested schedule/revision/execution lookup. Use the existing notification pagination constraints (limit 1–100, positive 64-bit cursor); unknown resources return 404 and invalid query values 400.

Add an optional read-only capability to `/api/server`, e.g. `features.schedule_run_association:1`, so clients can prefer server associations and fall back to generic scheduled history on older servers.

### Live updates

Publish named `schedule_execution` events on existing global and per-robot SSE streams after execution/association changes commit. Include execution ID, robot, updated execution, and an update timestamp. Clients upsert by ID, then refresh affected run/catalog data as needed. Duplicates and reconnect must not produce duplicate rows or replay old foreground alerts.

## Migration and backfill

Use an additive Alembic migration and indexes on robot/start time, schedule/revision identity, notification links and raw run links. Preserve PR #30 history and all existing run/map records.

Reconcile existing scheduled runs with existing notifications where possible, creating unassigned executions even without historical schedules. Only assign historical schedule ownership when an observation/import establishes which revision existed at that time. First seeing a current schedule after an old run is not sufficient. A later edit, disable or deletion does not remove a valid earlier link. Backfill is deterministic, idempotent and restartable.

## Expected-area percentages

Schedule association alone does not establish expected floor area. The current iOS app has a local user-entered whole-floor target; v1 may continue using it. Do not label cleaned-area / bounding-box-area as measured coverage.

Optional follow-up for shared, historically stable percentages: store an explicit expected-area value and scope/unit alongside each schedule revision, snapshot it onto the execution, and return `expected_area_m2` plus its provenance. Only calculate the ratio for compatible scopes. Keep room targets separate from whole-floor targets. Overlapping passes can produce a ratio above 100%; it remains an area comparison, not measured unique map coverage.

## Acceptance tests

1. Unique observed Monday 01:40 schedule + 01:40:02 start notification + scheduled run at 01:40:00 creates one matched inferred execution linked to the correct revision.
2. Run upload before notification and notification before run produce the same final association; late uploads use run start time. Restart between ingestion and reconciliation recovers the work.
3. Two enabled same-time schedules with identical options remain ambiguous. Incompatible known options can narrow candidates; missing options cannot resolve a tie.
4. App/button runs at the scheduled minute remain unassigned. Test all supported start-source values and unknown future values.
5. An edit/delete after a run preserves the original revision and association. A change spanning the possible execution time remains uncertain. Robot ID reuse after deletion does not relabel old history.
6. First schedule observation after an old run cannot silently backfill ownership. Failed schedule reads do not create deletions. Direct/other-client edits are discovered by reconciliation and retain observation uncertainty.
7. Duplicate PR #30 request delivery creates no duplicate notification or execution. Distinct nearby requests are not blindly collapsed. Intermediate/final run snapshots share one execution without adding areas twice.
8. Off-base/low-battery scheduled failure appears under a uniquely matched schedule with no invented cleaning run. Cancelled final uploads are not labelled successful completion.
9. Time-zone mismatch, missing zone, clock-skew/delay outside policy bounds, DST gaps/folds, invalid dates and timestamp collisions return documented uncertainty rather than a false match.
10. API compatibility, cursor pagination under concurrent updates, invalid limits/cursors, cross-robot access, deleted schedules, empty history and older-client fallback pass. SSE emits only committed changes; reconnect GET reconstructs the same state.
11. Matching/reconciliation issues no cleaning or schedule-mutation commands. Robot request handling remains responsive while schedule reads and backfill run.

## Implementation locations and scope

Start from the deployed PR #30-capable server version, preserving subsequent upstream changes. Relevant source areas in the inspected tree: `handlers/app.py` (command bridge/run API), `gen4/handlers.py` (run ingestion), `notifications.py` (committed notification ingestion), `models/`, `handlers/events.py`, router registration and Alembic migrations. Prefer a dedicated schedule-history/correlation module and worker over placing matching logic in socket callbacks.

Deliver: migration, schedule observation/revision capture, durable reconciliation, additive run fields/read endpoints/SSE, automated acceptance coverage, and protocol/API documentation. Firmware changes, moving scheduling into the server, push delivery, and retrospectively guessing ownership from current schedules are outside this change.
