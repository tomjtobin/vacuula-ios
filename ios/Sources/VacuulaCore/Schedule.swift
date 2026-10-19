import Foundation

public enum ScheduleDay: String, Codable, CaseIterable, Identifiable, Sendable {
    case mon, tue, wed, thu, fri, sat, sun
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .mon: return "Monday"; case .tue: return "Tuesday"; case .wed: return "Wednesday"
        case .thu: return "Thursday"; case .fri: return "Friday"; case .sat: return "Saturday"; case .sun: return "Sunday"
        }
    }
}

/// Retain the complete command when changing an existing event's timing or enabled state.
public struct CleaningSchedule: Codable, Equatable, Identifiable, Sendable {
    public var id: String?
    public var enabled: Bool
    public var days: [ScheduleDay]
    public var time: String
    public var command: JSONValue
    public init(id: String? = nil, enabled: Bool = true, days: [ScheduleDay], time: String, command: JSONValue) {
        self.id = id; self.enabled = enabled; self.days = days; self.time = time; self.command = command
    }
    public var repeatDescription: String {
        days.count == 7 ? "Every day" : ScheduleDay.allCases.filter { days.contains($0) }.map { String($0.title.prefix(3)) }.joined(separator: ", ")
    }
    public func validate() throws {
        let parts = time.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isNumber) }),
              let hour = Int(parts[0]), let minute = Int(parts[1]), (0...23).contains(hour), (0...59).contains(minute) else {
            throw ClientError.message("Choose a valid cleaning time.")
        }
        guard !days.isEmpty, Set(days).count == days.count else { throw ClientError.message("Choose at least one repeat day.") }
    }
    public func updatePayload() throws -> [String: Any] {
        try validate()
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self))
        return ["ability": "scheduling.update", "event": object]
    }
    public static func create(days: [ScheduleDay], time: String, mode: String, gentle: Bool, mapID: String?, zoneIDs: [String] = []) throws -> CleaningSchedule {
        var command = try RobotCommand.build(.start, generation: "neato.gen4", mode: mode, gentle: gentle, mapID: mapID, zoneIDs: zoneIDs)
        command["auto_localization"] = false
        command["force_floorplan"] = false
        let value = try JSONDecoder().decode(JSONValue.self, from: JSONSerialization.data(withJSONObject: command))
        let event = CleaningSchedule(days: days, time: time, command: value)
        try event.validate()
        return event
    }
    private var comparableCommand: JSONValue {
        guard case .object(var value) = command else { return command }
        // Firmware reports these global/legacy fields independently of the saved event.
        value.removeValue(forKey: "force_floorplan")
        value.removeValue(forKey: "auto_localization")
        return .object(value)
    }
    /// Require a robot-assigned ID and matching saved timing and cleaning runs.
    public func matches(_ other: CleaningSchedule) -> Bool {
        other.id?.isEmpty == false && (id == nil || id == other.id) && enabled == other.enabled && Set(days) == Set(other.days) && time == other.time && comparableCommand == other.comparableCommand
    }
}
public struct RobotSchedule: Decodable, Sendable {
    public let enabled: Bool
    public let events: [CleaningSchedule]
}

extension VacuulaAPI {
    public func schedule(_ robot: Robot) async throws -> RobotSchedule {
        guard robot.type == "neato.gen4" else { throw ClientError.message("Scheduling is currently available for Gen4 robots.") }
        struct Envelope: Decodable { let body: RobotSchedule }
        return try JSONDecoder().decode(Envelope.self, from: await data(["robot", robot.id, "command"], payload: ["ability": "scheduling.show"], timeout: 40)).body
    }
}
