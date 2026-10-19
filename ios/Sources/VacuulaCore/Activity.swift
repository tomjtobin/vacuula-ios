import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let item = try? value.decode(Bool.self) { self = .bool(item) }
        else if let item = try? value.decode(String.self) { self = .string(item) }
        else if let item = try? value.decode(Double.self) { self = .number(item) }
        else if let item = try? value.decode([String: JSONValue].self) { self = .object(item) }
        else { self = .array(try value.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let item): try value.encode(item)
        case .number(let item): try value.encode(item)
        case .bool(let item): try value.encode(item)
        case .object(let item): try value.encode(item)
        case .array(let item): try value.encode(item)
        case .null: try value.encodeNil()
        }
    }
    public var string: String? { if case .string(let item) = self { return item }; return nil }
}

public struct RobotNotification: Codable, Equatable, Identifiable, Sendable {
    public let id: Int64
    public let robot: String
    public let messageCode: String
    public let payload: [String: JSONValue]?
    public let receivedAt: String
    enum CodingKeys: String, CodingKey {
        case id, robot, payload
        case messageCode = "message_code", receivedAt = "received_at"
    }
    public init(id: Int64, robot: String, messageCode: String, payload: [String: JSONValue]? = nil, receivedAt: String) {
        self.id = id; self.robot = robot; self.messageCode = messageCode; self.payload = payload; self.receivedAt = receivedAt
    }
    public var date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: receivedAt) ?? ISO8601DateFormatter().date(from: receivedAt)
    }
    public var presentation: ActivityPresentation {
        switch messageCode {
        case "routine_cleaning_start":
            return .init(title: "Scheduled clean started", detail: "The robot started its scheduled clean.", attention: false, symbol: "calendar.badge.clock")
        case "routine_cleaning_start_offbase_error":
            return .init(title: "Scheduled clean couldn’t start", detail: "The robot was off its base. Place it on the base before the next scheduled clean.", attention: true, symbol: "calendar.badge.exclamationmark")
        case "routine_cleaning_start_low_battery_error":
            return .init(title: "Scheduled clean couldn’t start", detail: "The battery was too low. Let the robot charge on its base.", attention: true, symbol: "battery.25percent")
        case "nav_floorplan_zone_unreachable":
            let name = payload?["zone_name"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .init(title: "Room couldn’t be reached", detail: name.map { $0.isEmpty ? "The robot couldn’t reach a selected room. Check its access." : "The robot couldn’t reach \($0). Check that the route is clear." } ?? "The robot couldn’t reach a selected room. Check its access.", attention: true, symbol: "door.left.hand.closed")
        case "persistent_relocalization_fail", "persistent_relocalization_fail_clean", "persistent_relocalization_fail_cancel":
            return .init(title: "Robot couldn’t locate itself", detail: "The robot couldn’t match its surroundings to the saved map. Check its current status before starting another clean.", attention: true, symbol: "map")
        case "fuel_less_than_10":
            return .init(title: "Battery was low", detail: "The robot reported a low battery. Check its current charging status.", attention: true, symbol: "battery.0percent")
        default:
            return .init(title: "Robot update", detail: messageCode.replacingOccurrences(of: "_", with: " ").capitalized, attention: false, symbol: "info.circle")
        }
    }
}

public struct ActivityPresentation: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let attention: Bool
    public let symbol: String
}

public struct NotificationPage: Decodable, Sendable {
    public let notifications: [RobotNotification]
    public let nextBefore: Int64?
    enum CodingKeys: String, CodingKey { case notifications; case nextBefore = "next_before" }
}

/// Read markers are device-local. IDs are scoped by server and robot in AppStore.
public struct ActivityTimeline: Sendable {
    public private(set) var items: [RobotNotification] = []
    public private(set) var readIDs: Set<Int64>
    public init(readIDs: Set<Int64> = []) { self.readIDs = readIDs }
    public var unreadCount: Int { items.filter { !readIDs.contains($0.id) }.count }
    public func isUnread(_ item: RobotNotification) -> Bool { !readIDs.contains(item.id) }
    @discardableResult public mutating func merge(_ incoming: [RobotNotification], robot: String) -> [RobotNotification] {
        let known = Set(items.map(\.id))
        var merged = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in incoming where item.robot == robot && item.id > 0 { merged[item.id] = item }
        items = merged.values.sorted { $0.id > $1.id }
        return items.filter { !known.contains($0.id) }
    }
    public mutating func markRead(_ id: Int64) { readIDs.insert(id) }
    public mutating func markAllRead() { readIDs.formUnion(items.map(\.id)) }
}
