import Foundation
import SwiftUI
import UIKit
import VacuulaCore

@MainActor
final class AppStore: ObservableObject {
    enum Connection { case searching, connecting, choose, manual, failed, connected }
    @Published var connection: Connection = .searching
    @Published var candidates = [ServerIdentity]()
    @Published var candidateErrors = [String: String]()
    @Published var server: ServerIdentity?
    @Published var serverInfo: ServerInfo?
    @Published var robots = [Robot]()
    @Published var selectedID: String?
    @Published var state: RobotState?
    @Published var observedAt: Date?
    @Published var maps = [FloorMap]()
    @Published var notice: String?
    @Published var connectionMessage: String?
    @Published var pending: String?
    @Published var refreshing = false
    @Published var mapRotation: MapRotation = .degrees0 { didSet { if !demo { mapRotation.save(defaults: defaults) } } }
    @Published var mode = "eco" { didSet { saveCleaningPreferences() } }
    @Published var gentle = false { didSet { saveCleaningPreferences() } }
    @Published var isActive = true
    @Published var requiresReconciliation = false
    @Published var cleaningHistory = [CleaningRecord]()
    @Published var historyLoading = false
    @Published var historyLoaded = false
    @Published var historyError: String?
    @Published var expectedAreaSquareFeet: Double?
    @Published var schedules = [CleaningSchedule]()
    @Published var scheduleLoaded = false
    @Published var scheduleLoading = false
    @Published var scheduleError: String?
    @Published var scheduleNeedsRefresh = false
    @Published var scheduleEnabled = true
    @Published var activity = ActivityTimeline()
    @Published var activityLoading = false
    @Published var activityLoaded = false
    @Published var activityError: String?
    @Published var nextActivityCursor: Int64?
    @Published var activityBanner: RobotNotification?
    @Published var showActivity = false
    private var restoringCleaningPreferences = false
    private var historyUpdatedAt: Date?
    private var bannerTask: Task<Void, Never>?
    private let discovery = ServerDiscovery()
    private var lifecycleTask: Task<Void, Never>?
    private var inventoryTask: Task<Void, Never>?
    private var robotTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var scheduleReadTask: Task<Void, Never>?
    private var commandTask: Task<Void, Never>?
    private var session = UUID()
    private var robotSession = UUID()
    private let defaults: UserDefaults
    let demo: Bool
    let readOnly: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        demo = ProcessInfo.processInfo.arguments.contains("--demo")
        readOnly = ProcessInfo.processInfo.arguments.contains("--read-only")
        mapRotation = MapRotation.load(defaults: defaults)
    }
    var robot: Robot? { robots.first { $0.id == selectedID } }
    var api: VacuulaAPI? { server.map { VacuulaAPI(origin: $0.origin) } }
    var isFresh: Bool { observedAt.map { Date().timeIntervalSince($0) < 60 } ?? false }
    var canControl: Bool { isActive && !demo && !readOnly && !requiresReconciliation && robot?.connected == true && robot?.supported == true && isFresh && pending == nil && !refreshing }
    var saved: ServerIdentity? {
        guard let data = defaults.data(forKey: "server") else { return nil }
        return try? JSONDecoder().decode(ServerIdentity.self, from: data)
    }
    private var selectionKey: String { "robot:" + (server?.origin.absoluteString ?? "") }
    private var activityReadKey: String { "activity-read:" + (server?.origin.absoluteString ?? "") + ":" + (selectedID ?? "") }

    private func saveCleaningPreferences() {
        guard !restoringCleaningPreferences, !demo, let origin = server?.origin, let selectedID else { return }
        CleaningPreferences(mode: mode, gentle: gentle).save(defaults: defaults, server: origin, robotID: selectedID)
    }
    private func restoreCleaningPreferences() {
        restoringCleaningPreferences = true
        defer { restoringCleaningPreferences = false }
        let value: CleaningPreferences
        if let origin = server?.origin, let selectedID {
            value = CleaningPreferences.load(defaults: defaults, server: origin, robotID: selectedID)
        } else { value = .init() }
        mode = value.mode; gentle = value.gentle
    }
    var canEditSchedule: Bool {
        isActive && !readOnly && robot?.type == "neato.gen4" && robot?.connected == true && pending == nil && !scheduleLoading && scheduleLoaded && scheduleError == nil && !scheduleNeedsRefresh
    }
    private func resetSchedule() {
        scheduleReadTask?.cancel(); scheduleReadTask = nil
        restoreCleaningPreferences(); historyUpdatedAt = nil
        cleaningHistory = []; historyLoading = false; historyLoaded = false; historyError = nil
        let target = defaults.double(forKey: areaTargetKey)
        expectedAreaSquareFeet = target > 0 ? target : nil
        schedules = []; scheduleLoaded = false; scheduleLoading = false; scheduleError = nil; scheduleNeedsRefresh = false; scheduleEnabled = true
    }
    private var areaTargetKey: String { "whole-floor-area:" + (server?.origin.absoluteString ?? "") + ":" + (selectedID ?? "") }
    func setExpectedArea(_ value: Double?) {
        expectedAreaSquareFeet = value.flatMap { $0.isFinite && $0 > 0 && $0 <= 1_000_000 ? $0 : nil }
        if !demo { defaults.set(expectedAreaSquareFeet, forKey: areaTargetKey) }
    }
    func refreshHistory() async {
        guard isActive, !historyLoading else { return }
        if demo {
            if !historyLoaded {
                let json = #"[{"id":"preview-done","robot":"preview","started_by":"app","cleaning_complete":true,"battery_consumed":12,"timing":{"start":"2026-10-18T16:00:00Z","end":"2026-10-18T16:28:00Z"},"runs":[{"track_uuid":"","state":"done","stats":{"area":22},"settings":{"mode":"turbo","navigation_mode":"normal"}}]},{"id":"preview-cancelled","robot":"preview","started_by":"schedule","cleaning_complete":true,"timing":{"start":"2026-10-19T08:40:00Z","end":"2026-10-19T08:42:32Z"},"runs":[{"track_uuid":"","state":"canceled","stats":{"area":1.28}}]}]"#
                cleaningHistory = CleaningRecord.sessions((try? JSONDecoder().decode([CleaningRecord].self, from: Data(json.utf8))) ?? [], robot: "preview")
                historyLoaded = true
            }
            return
        }
        guard let api, let robot, robot.type == "neato.gen4" else { return }
        let token = robotSession
        historyLoading = true; historyError = nil
        defer { if token == robotSession { historyLoading = false } }
        do {
            let value = try await api.cleaningHistory(robot)
            try assertCurrent(token)
            cleaningHistory = value; historyLoaded = true; historyUpdatedAt = Date()
        } catch {
            if token == robotSession, !Task.isCancelled, !RequestFailure.isCancellation(error) {
                historyError = "Cleaning history couldn’t be loaded. " + error.localizedDescription
            }
        }
    }
    func loadSchedule() {
        guard scheduleReadTask == nil, !scheduleLoading else { return }
        let token = robotSession
        scheduleReadTask = Task { await refreshSchedule(); if token == robotSession { scheduleReadTask = nil } }
    }
    func refreshSchedule() async {
        if demo {
            if ProcessInfo.processInfo.arguments.contains("--demo-schedule-loading") { scheduleLoading = true; return }
            if ProcessInfo.processInfo.arguments.contains("--demo-schedule-error") { scheduleError = "The robot couldn’t be reached. Try again when it reconnects."; scheduleNeedsRefresh = true; return }
            scheduleLoaded = true; return
        }
        guard isActive, !scheduleLoading, pending == nil, let api, let robot, robot.connected, robot.type == "neato.gen4" else { return }
        let token = robotSession
        scheduleLoading = true; scheduleError = nil; scheduleNeedsRefresh = true
        defer { if token == robotSession { scheduleLoading = false } }
        do {
            let result = try await api.schedule(robot)
            try assertCurrent(token)
            schedules = result.events; scheduleEnabled = result.enabled; scheduleLoaded = true; scheduleNeedsRefresh = false; scheduleError = nil
        } catch {
            if token == robotSession, !Task.isCancelled, !RequestFailure.isCancellation(error) {
                scheduleError = "The schedule couldn’t be loaded. Check the robot connection and try again. " + error.localizedDescription
            }
        }
    }
    /// Writes once, then reads back. An ambiguous result requires an explicit refresh before another write.
    func saveSchedule(_ event: CleaningSchedule?, deleting id: String? = nil) async -> Bool {
        guard canEditSchedule, let api, let robot else { return false }
        let token = robotSession
        pending = "Saving schedule…"; scheduleError = nil
        defer { if token == robotSession { pending = nil } }
        do {
            let payload: [String: Any]
            if let id { payload = ["ability": "scheduling.delete", "id": id] }
            else if let event { payload = try event.updatePayload() }
            else { return false }
            if demo {
                if let id { schedules.removeAll { $0.id == id } }
                else if var event {
                    event.id = event.id ?? UUID().uuidString
                    schedules.removeAll { $0.id == event.id }; schedules.append(event)
                }
                return true
            }
            try assertCurrent(token)
            try await api.command(robot, payload: payload)
            try assertCurrent(token)
            let result = try await api.schedule(robot)
            try assertCurrent(token)
            schedules = result.events; scheduleEnabled = result.enabled; scheduleLoaded = true
            let confirmed = id.map { deleted in !result.events.contains { $0.id == deleted } } ?? event.map { expected in result.events.contains { expected.matches($0) } } ?? false
            guard confirmed else { throw ClientError.message("The robot’s saved schedule didn’t match the change.") }
            return true
        } catch {
            if token == robotSession {
                scheduleNeedsRefresh = true
                scheduleError = "Couldn’t confirm the saved schedule. Refresh and check the list before trying again. " + (RequestFailure.isCancellation(error) ? "The connection changed while saving." : error.localizedDescription)
            }
            return false
        }
    }

    private func resetActivity() {
        dismissActivityBanner()
        let ids = defaults.data(forKey: activityReadKey).flatMap { try? JSONDecoder().decode([Int64].self, from: $0) } ?? []
        activity = ActivityTimeline(readIDs: Set(ids))
        activityLoaded = false; activityLoading = false; activityError = nil; nextActivityCursor = nil
    }
    func markActivityRead(_ id: Int64? = nil) {
        if let id, activity.readIDs.contains(id) || !activity.items.contains(where: { $0.id == id }) { return }
        if let id { activity.markRead(id) } else { activity.markAllRead() }
        if let data = try? JSONEncoder().encode(Array(activity.readIDs)) { defaults.set(data, forKey: activityReadKey) }
    }
    func refreshActivity(older: Bool = false) async {
        guard !demo, !activityLoading, let api, let robot, robot.type == "neato.gen4" else { return }
        if older && nextActivityCursor == nil { return }
        let token = robotSession
        let cursor = older ? nextActivityCursor : nil
        activityLoading = true
        defer { if token == robotSession { activityLoading = false } }
        do {
            let page = try await api.notifications(robot, before: cursor)
            guard token == robotSession, !Task.isCancelled else { return }
            activity.merge(page.notifications, robot: robot.id)
            nextActivityCursor = page.nextBefore
            activityLoaded = true; activityError = nil
        } catch {
            if token == robotSession, !Task.isCancelled {
                activityError = "Activity couldn’t be refreshed. Check the server connection and try again."
            }
        }
    }
    private func receiveNotification(_ item: RobotNotification, token: UUID) {
        guard token == robotSession, item.robot == selectedID, isActive else { return }
        let added = activity.merge([item], robot: item.robot)
        guard !added.isEmpty, activityLoaded, !showActivity,
              let date = item.date, abs(date.timeIntervalSinceNow) < 120 else { return }
        bannerTask?.cancel(); activityBanner = item
        UIAccessibility.post(notification: .announcement, argument: item.presentation.title)
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(9))
            guard !Task.isCancelled else { return }
            activityBanner = nil
        }
    }
    func dismissActivityBanner() { bannerTask?.cancel(); bannerTask = nil; activityBanner = nil }
    func openActivity() { dismissActivityBanner(); showActivity = true }

    func start() {
        guard lifecycleTask == nil else { return }
        lifecycleTask = Task {
            if demo { loadDemo(); return }
            if let saved {
                connection = .connecting; server = saved
                let target = (try? await discovery.remembered(saved)) ?? saved
                guard !Task.isCancelled else { return }
                if await connect(target) { return }
                if target.origin != saved.origin, await connect(saved) { return }
            }
            await discover()
        }
    }
    func findServers() {
        guard pending == nil else { return }
        suspend(); lifecycleTask = nil
        isActive = true
        lifecycleTask = Task { await discover() }
    }
    private func discover() async {
        connection = .searching; connectionMessage = nil; candidates = []; candidateErrors = [:]
        do {
            let found = try await discovery.scan()
            try Task.checkCancellation()
            if found.isEmpty { connection = .manual; return }
            var valid = [ServerIdentity]()
            for candidate in found {
                do { _ = try await VacuulaAPI(origin: candidate.origin).server(); valid.append(candidate) }
                catch { candidateErrors[candidate.origin.absoluteString] = error.localizedDescription }
                try Task.checkCancellation()
            }
            candidates = found
            if valid.count == 1 {
                if await connect(valid[0]) { return }
                try Task.checkCancellation()
            }
            connection = .choose
        } catch is CancellationError { }
        catch { connectionMessage = error.localizedDescription; connection = .failed }
    }
    func choose(_ target: ServerIdentity) {
        lifecycleTask?.cancel()
        lifecycleTask = Task {
            if !(await connect(target)), !Task.isCancelled { connection = .choose }
        }
    }
    func manual(_ text: String) {
        do {
            let url = try ServerIdentity.normalizedURL(text)
            let target = ServerIdentity(origin: url, name: url.host ?? "Vacuula Server")
            lifecycleTask?.cancel()
            lifecycleTask = Task {
                if !(await connect(target)), !Task.isCancelled { connection = .manual }
            }
        } catch { connectionMessage = error.localizedDescription }
    }
    @discardableResult private func connect(_ target: ServerIdentity) async -> Bool {
        connection = .connecting; connectionMessage = nil
        do {
            let api = VacuulaAPI(origin: target.origin)
            let info = try await api.server()
            try Task.checkCancellation()
            stopStreams(); session = UUID(); robotSession = UUID()
            server = target; serverInfo = info; state = nil; observedAt = nil; robots = []; selectedID = nil; maps = []
            resetActivity(); resetSchedule()
            defaults.set(try JSONEncoder().encode(target), forKey: "server")
            connection = .connected
            await refreshInventory()
            startStreams()
            return true
        } catch {
            if !Task.isCancelled { connectionMessage = error.localizedDescription }
            return false
        }
    }
    func select(_ id: String) {
        guard pending == nil else { return }
        robotTask?.cancel(); commandTask?.cancel(); refreshTask?.cancel()
        selectedID = id; robotSession = UUID(); state = nil; observedAt = nil; maps = []; notice = nil; requiresReconciliation = false
        resetActivity(); resetSchedule()
        refreshing = false
        defaults.set(id, forKey: selectionKey)
        let token = robotSession
        refreshTask = Task { await refresh(); if token == robotSession { startRobotStream() } }
    }
    func refreshInventory() async {
        guard let api else { return }
        let token = session
        do {
            let inventory = try await api.robots()
            guard token == session, !Task.isCancelled else { return }
            applyInventory(inventory)
        } catch { if token == session, !Task.isCancelled { notice = "Couldn’t refresh robots. \(error.localizedDescription)" } }
    }
    private func applyInventory(_ inventory: [Robot]) {
        let wasOnline = robot?.connected == true
        robots = inventory
        if selectedID == nil || !inventory.contains(where: { $0.id == selectedID }) {
            let remembered = defaults.string(forKey: selectionKey)
            if let chosen = inventory.first(where: { $0.id == remembered }) ?? inventory.first(where: { $0.connected }) ?? inventory.first { select(chosen.id) }
        } else if robot?.connected != true {
            state = nil; observedAt = nil
        } else if !wasOnline {
            refreshTask?.cancel(); refreshTask = Task { await refresh() }
        }
    }
    func refresh() async {
        guard !demo, let api, let robot, robot.connected, robot.supported else { return }
        let token = robotSession
        refreshing = true
        defer { if token == robotSession { refreshing = false } }
        do {
            let value = try await api.state(robot)
            guard token == robotSession, !Task.isCancelled else { return }
            state = value; observedAt = Date(); requiresReconciliation = false
            do {
                let floors = try await api.maps(robot)
                if token == robotSession, !Task.isCancelled { maps = floors }
            } catch { if token == robotSession { notice = "Status updated. Maps couldn’t be refreshed: \(error.localizedDescription)" } }
        } catch { if token == robotSession, !Task.isCancelled { observedAt = nil; notice = error.localizedDescription } }
    }
    func perform(_ action: RobotAction, map: FloorMap? = nil, zones: Set<String> = []) {
        guard canControl, let robot, let api else { return }
        let token = robotSession
        pending = action == .returnToBase ? "Checking return to base…" : "Checking robot…"
        notice = nil
        commandTask = Task {
            defer { if token == robotSession { pending = nil } }
            do {
                let fresh = try await api.state(robot)
                try assertCurrent(token)
                state = fresh; observedAt = Date()
                if action == .returnToBase {
                    if fresh.docked { notice = "The robot is already on the base."; return }
                    if !fresh.commands.contains(.returnToBase) {
                        guard fresh.commands.contains(.pause) else { throw ClientError.message("Return to base isn’t available right now. Refresh the robot’s status and try again.") }
                        pending = "Pausing cleaning…"
                        try await api.command(robot, payload: RobotCommand.build(.pause, generation: robot.type))
                        try assertCurrent(token)
                        try await waitFor(robot, api: api, token: token, seconds: 15) { $0.commands.contains(.returnToBase) || $0.docked }
                        if state?.docked == true { notice = "The robot is on the base."; return }
                    }
                    try assertCurrent(token)
                    pending = "Returning to base…"
                    try await api.command(robot, payload: RobotCommand.build(.returnToBase, generation: robot.type))
                    try await waitFor(robot, api: api, token: token, seconds: 120) { $0.docked }
                    notice = "The robot is on the base."
                } else {
                    guard fresh.commands.contains(action) else { throw ClientError.message("That action isn’t available right now. Refresh the robot’s status and try again.") }
                    var cleaningMapID = map?.id
                    if action == .start && map == nil && robot.type == "neato.gen4" {
                        // Use the active floorplan so its uploaded no-go areas apply to house cleaning.
                        let floors = try await api.maps(robot)
                        cleaningMapID = floors.first(where: { $0.promoted == true })?.id
                    }
                    if let map {
                        let floors = try await api.maps(robot)
                        guard floors.contains(where: { $0.id == map.id && $0.canClean(generation: robot.type) }), fresh.docked, !zones.isEmpty else { throw ClientError.message("Room cleaning needs a ready map, selected rooms and a robot on its base.") }
                        let boundaries = try await api.boundaries(robot, map: map)
                        guard zones.isSubset(of: Set(boundaries.filter(\.isRoom).map(\.id))) else { throw ClientError.message("These rooms have changed. Refresh the map and select them again.") }
                    }
                    try assertCurrent(token)
                    pending = "Sending request…"
                    try await api.command(robot, payload: RobotCommand.build(action, generation: robot.type, mode: mode, gentle: gentle, mapID: cleaningMapID, zoneIDs: zones.sorted()))
                    try assertCurrent(token)
                    pending = "Waiting for robot…"
                    try await waitFor(robot, api: api, token: token, seconds: 15) { reported in
                        switch action {
                        case .start, .resume: return reported.state == "busy"
                        case .pause: return reported.state == "paused"
                        case .stop: return reported.state == "idle"
                        case .returnToBase: return reported.docked
                        }
                    }
                    notice = "Robot status updated."
                }
            } catch is CancellationError { }
            catch {
                if token == robotSession {
                    requiresReconciliation = true
                    notice = error.localizedDescription + " No action will be sent again automatically."
                    // Reconcile ambiguous responses; never repeat a motion command.
                    await refresh()
                }
            }
        }
    }
    private func assertCurrent(_ token: UUID) throws {
        try Task.checkCancellation()
        guard token == robotSession, isActive else { throw CancellationError() }
    }
    private func waitFor(_ robot: Robot, api: VacuulaAPI, token: UUID, seconds: Int, predicate: (RobotState) -> Bool) async throws {
        let deadline = Date().addingTimeInterval(Double(seconds))
        while Date() < deadline {
            try assertCurrent(token)
            let value = try await api.state(robot)
            try assertCurrent(token)
            state = value; observedAt = Date()
            if predicate(value) { return }
            try await Task.sleep(for: .seconds(2))
        }
        throw ClientError.message("The request was accepted, but the robot hasn’t confirmed the expected status. Refresh to check its progress.")
    }
    private func startStreams() {
        guard !demo, inventoryTask == nil, let api else { return }
        let token = session
        inventoryTask = Task { [self] in
            var failures = 0
            while !Task.isCancelled, token == session {
                do {
                    try await api.events(["events"]) { [weak self] frame in
                        guard frame.event == "robots", let data = frame.data.data(using: .utf8), let robots = try? Robot.inventory(data) else { return }
                        await self?.receiveInventory(robots, token: token)
                    }
                } catch { }
                guard !Task.isCancelled else { break }
                failures += 1
                if failures >= 3 {
                    do { _ = try await api.server(); failures = 0 }
                    catch {
                        if pending == nil { lifecycleTask = nil; findServers(); return }
                    }
                }
                try? await Task.sleep(for: .seconds(min(30, failures * 2 + Int.random(in: 0...2))))
                await refreshInventory()
            }
        }
        startRobotStream()
    }
    private func receiveInventory(_ robots: [Robot], token: UUID) { if token == session { applyInventory(robots) } }
    private func startRobotStream() {
        robotTask?.cancel()
        guard !demo, let api, let robot, robot.supported else { return }
        let token = robotSession
        robotTask = Task { [self] in
            var failures = 0
            while !Task.isCancelled, token == robotSession {
                do {
                    try await api.events(["robot", robot.id, "connect"], connected: { [weak self] in
                        await self?.refreshActivity()
                    }) { [weak self] frame in
                        if frame.event == "notification" {
                            if let data = frame.data.data(using: .utf8), let item = try? JSONDecoder().decode(RobotNotification.self, from: data) {
                                await self?.receiveNotification(item, token: token)
                            }
                            return
                        }
                        guard frame.event == "message" else { return }
                        guard let data = frame.data.data(using: .utf8), let value = try? RobotState.decode(data, generation: robot.type, event: true) else { return }
                        await self?.receiveState(value, token: token)
                    }
                } catch { }
                guard !Task.isCancelled else { break }
                failures += 1
                try? await Task.sleep(for: .seconds(min(30, failures * 2 + Int.random(in: 0...2))))
                await refresh()
            }
        }
    }
    private func receiveState(_ value: RobotState, token: UUID) {
        guard token == robotSession else { return }
        state = value; observedAt = Date()
    }
    func tick() async {
        guard isActive, connection == .connected, !demo, pending == nil, !refreshing else { return }
        await refreshInventory()
        if observedAt.map({ Date().timeIntervalSince($0) > 40 }) ?? true { await refresh() }
        await refreshActivity()
        if historyUpdatedAt.map({ Date().timeIntervalSince($0) > 60 }) ?? true { await refreshHistory() }
    }
    private func stopStreams() { inventoryTask?.cancel(); inventoryTask = nil; robotTask?.cancel(); robotTask = nil; refreshTask?.cancel(); refreshTask = nil }
    func suspend() {
        isActive = false; lifecycleTask?.cancel(); lifecycleTask = nil; discovery.stop(); stopStreams()
        commandTask?.cancel(); commandTask = nil; pending = nil; observedAt = nil
        session = UUID(); robotSession = UUID(); refreshing = false
        scheduleReadTask?.cancel(); scheduleReadTask = nil
        dismissActivityBanner(); activityLoading = false; historyLoading = false; scheduleLoading = false; scheduleNeedsRefresh = true
    }
    func resume() {
        isActive = true
        if demo { if state == nil { loadDemo() }; return }
        if connection == .connected {
            lifecycleTask = Task {
                guard let api else { return }
                do { _ = try await api.server(); await refreshInventory(); await refresh(); startStreams() }
                catch { await discover() }
            }
        } else { start() }
    }
    private func loadDemo() {
        server = ServerIdentity(origin: URL(string: "http://vacuula.local")!, name: "Vacuula Server")
        robots = [Robot(id: "preview", type: "neato.gen4", connected: true, name: "Vacuula", labelSerial: "Preview")]
        selectedID = "preview"; connection = .connected
        if ProcessInfo.processInfo.arguments.contains("--reset-activity-read") { defaults.removeObject(forKey: activityReadKey) }
        resetActivity(); resetSchedule()
        if ProcessInfo.processInfo.arguments.contains("--demo-map") {
            mapRotation = .degrees0
            maps = (try? JSONDecoder().decode([FloorMap].self, from: Data(#"[{"id":"preview-map","name":"Preview floor","promoted":true}]"#.utf8))) ?? []
        }
        if ProcessInfo.processInfo.arguments.contains("--demo-activity") {
            let now = Date()
            let formatter = ISO8601DateFormatter()
            let samples = [
                RobotNotification(id: 1, robot: "preview", messageCode: "routine_cleaning_start", receivedAt: formatter.string(from: now.addingTimeInterval(-7200))),
                RobotNotification(id: 2, robot: "preview", messageCode: "nav_floorplan_zone_unreachable", payload: ["zone_name": .string("Kitchen")], receivedAt: formatter.string(from: now.addingTimeInterval(-3600))),
                RobotNotification(id: 3, robot: "preview", messageCode: "routine_cleaning_start_low_battery_error", receivedAt: formatter.string(from: now.addingTimeInterval(-300)))
            ]
            activity.merge(samples, robot: "preview"); activityLoaded = true
            if ProcessInfo.processInfo.arguments.contains("--demo-banner") {
                let token = robotSession
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    receiveNotification(.init(id: 4, robot: "preview", messageCode: "nav_floorplan_zone_unreachable", payload: ["zone_name": .string("Kitchen")], receivedAt: formatter.string(from: Date())), token: token)
                }
            }
        } else { activityLoaded = true }
        let cleaning = ProcessInfo.processInfo.arguments.contains("--demo-cleaning")
        let json = cleaning ? """
        {"body":{"state":"busy","action":"cleaning","details":{"charge":86,"is_docked":false,"is_charging":false},"available_commands":{"pause":true,"cancel":true,"return_to_base":true},"errors":null}}
        """ : """
        {"body":{"state":"idle","action":"invalid","details":{"charge":86,"is_docked":true,"is_charging":true},"available_commands":{"start":true},"errors":null}}
        """
        state = try? RobotState.decode(Data(json.utf8), generation: "neato.gen4"); observedAt = Date()
        if ProcessInfo.processInfo.arguments.contains("--demo-bin-missing") {
            state = try? RobotState.decode(Data(#"{"body":{"state":"error","action":"cleaning","errors":[{"code":"dustbin_missing","severity":"error"}],"available_commands":{"cancel":true,"resume":false},"details":{"charge":85,"is_docked":false,"is_charging":false}}}"#.utf8), generation: "neato.gen4")
        }
        notice = nil
    }
}
