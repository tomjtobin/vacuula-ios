import Foundation

public struct CleaningRecord: Decodable, Identifiable, Sendable {
    public struct Timing: Decodable, Sendable {
        public let start: String?
        public let end: String?
        public let charging: Double?
        public let error: Double?
        public let pause: Double?
        public var startDate: Date? { CleaningRecord.date(start) }
        public var endDate: Date? { CleaningRecord.date(end) }
        public var duration: TimeInterval? {
            guard let startDate, let endDate, endDate >= startDate else { return nil }
            return endDate.timeIntervalSince(startDate)
        }
    }
    public struct Pass: Decodable, Sendable {
        public struct Stats: Decodable, Sendable { public let area: Double?; public let pickup_count: Int? }
        public struct Settings: Decodable, Sendable { public let mode: String?; public let navigation_mode: String? }
        public let timing: Timing?
        public let track_uuid: String?
        public let state: String?
        public let stats: Stats?
        public let settings: Settings?
        public let autonomous_dock: Bool?
    }
    public let id: String
    public let robot: String
    public let floorplan: String?
    public let started_by: String?
    public let battery_consumed: Double?
    public let cleaning_complete: Bool?
    public let timing: Timing?
    public let runs: [Pass]?
    public var startDate: Date? { timing?.startDate }
    public var squareMetres: Double? {
        guard let runs, !runs.isEmpty else { return nil }
        let areas = runs.compactMap { $0.stats?.area }
        guard areas.count == runs.count, areas.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        let sum = areas.reduce(0, +)
        return sum.isFinite ? sum : nil
    }
    public var squareFeet: Double? { squareMetres.map { $0 * 10.7639104167 } }
    public var batteryUsed: Double? { battery_consumed.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil } }
    public var isWholeFloor: Bool { !(runs ?? []).isEmpty && (runs ?? []).allSatisfy { $0.track_uuid?.isEmpty == true } }
    public var outcome: String {
        let states = (runs ?? []).compactMap(\.state)
        if states.contains("error") || states.contains("not_reachable") { return "Needs attention" }
        if states.contains("canceled") || states.contains("cancelled") { return "Cancelled" }
        if cleaning_complete == true && !states.isEmpty && states.allSatisfy({ $0 == "done" }) { return "Completed" }
        if cleaning_complete == true { return "Ended" }
        if states.contains("paused") { return "Paused snapshot" }
        if states.contains("in_progress") { return "In-progress snapshot" }
        return "Incomplete"
    }
    public var isScheduled: Bool { started_by == "schedule" }
    public var sourceSymbol: String {
        switch started_by {
        case "app": return "iphone"
        case "button": return "hand.tap"
        case "schedule": return "calendar"
        case "internal": return "robotic.vacuum"
        default: return "questionmark.circle"
        }
    }
    public var source: String {
        switch started_by {
        case "app": return "App"; case "button": return "Robot button"; case "schedule": return "Schedule"
        case "internal": return "Robot"; default: return "Unknown"
        }
    }
    public func areaPercentage(expectedSquareFeet: Double?) -> Double? {
        guard isWholeFloor, let target = expectedSquareFeet, target.isFinite, target > 0, let squareFeet else { return nil }
        let value = squareFeet / target * 100
        return value.isFinite ? value : nil
    }
    public static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
    /// Firmware uploads intermediate and final records with different IDs for one start time.
    public static func sessions(_ records: [CleaningRecord], robot: String) -> [CleaningRecord] {
        var grouped = [String: CleaningRecord]()
        for record in records where record.robot == robot {
            let key = record.startDate.map { String($0.timeIntervalSince1970) } ?? "id:" + record.id
            if let previous = grouped[key] {
                let oldEnd = previous.timing?.endDate ?? .distantPast
                let newEnd = record.timing?.endDate ?? .distantPast
                if newEnd < oldEnd { continue }
                if newEnd == oldEnd {
                    if previous.cleaning_complete == true && record.cleaning_complete != true { continue }
                    if previous.cleaning_complete == record.cleaning_complete && previous.id > record.id { continue }
                }
            }
            grouped[key] = record
        }
        return grouped.values.sorted {
            if $0.startDate == $1.startDate { return $0.id > $1.id }
            return ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast)
        }
    }
}

extension VacuulaAPI {
    public func cleaningHistory(_ robot: Robot) async throws -> [CleaningRecord] {
        guard robot.type == "neato.gen4" else { throw ClientError.message("Cleaning history is currently available for Gen4 robots.") }
        return CleaningRecord.sessions(try JSONDecoder().decode([CleaningRecord].self, from: await data(["robot", robot.id, "runs"])), robot: robot.id)
    }
}

public enum RequestFailure {
    public static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
