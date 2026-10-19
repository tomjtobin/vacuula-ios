import Foundation

public struct ServerIdentity: Codable, Equatable, Sendable {
    public var origin: URL
    public var name: String
    public var serviceName: String?
    public var serviceType: String?
    public var serviceDomain: String?
    public init(origin: URL, name: String, serviceName: String? = nil, serviceType: String? = nil, serviceDomain: String? = nil) {
        self.origin = origin; self.name = name; self.serviceName = serviceName
        self.serviceType = serviceType; self.serviceDomain = serviceDomain
    }
    public static func normalizedURL(_ input: String) throws -> URL {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = text.contains("://") ? text : "http://" + text
        guard var parts = URLComponents(string: candidate),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, !host.contains(" "),
              parts.user == nil, parts.password == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true else {
            throw ClientError.message("Enter a server address, such as vacuula.local or 192.168.1.100.")
        }
        parts.path = ""; parts.query = nil; parts.fragment = nil
        guard let url = parts.url else { throw ClientError.message("Check the server address and try again.") }
        return url
    }
}

public struct ServerInfo: Codable, Sendable {
    public let version: String
    public let timezone: String?
}

public struct Robot: Codable, Identifiable, Sendable {
    public var id: String
    public let type: String
    public var connected: Bool
    public let name: String
    public let labelSerial: String?
    public var supported: Bool { type == "neato.gen4" || type == "neato.gen3" }
    public init(id: String, type: String, connected: Bool, name: String, labelSerial: String? = nil) {
        self.id = id; self.type = type; self.connected = connected; self.name = name; self.labelSerial = labelSerial
    }
    enum CodingKeys: String, CodingKey { case id, type, connected, name; case labelSerial = "label_serial" }
    public static func inventory(_ data: Data) throws -> [Robot] {
        struct Entry: Decodable { let type: String; let connected: Bool; let name: String; let label_serial: String? }
        return try JSONDecoder().decode([String: Entry].self, from: data).map { key, value in
            Robot(id: key, type: value.type, connected: value.connected, name: value.name, labelSerial: value.label_serial)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

public struct RobotState: Sendable {
    public let state: String
    public let action: String
    public let battery: Int?
    public let docked: Bool
    public let charging: Bool
    public let commands: Set<RobotAction>
    public let errors: [String]
    public var issues: [RobotIssue] { errors.reduce(into: [RobotIssue]()) { items, code in
        if !code.isEmpty && !items.contains(where: { $0.code == code }) { items.append(RobotIssue(code: code)) }
    } }
    public var primaryIssue: RobotIssue? { issues.first }
    public var title: String {
        if state == "error" { return primaryIssue?.title ?? "Needs attention" }
        if action == "docking" { return "Returning to base" }
        if state == "paused" { return "Cleaning paused" }
        if state == "busy" { return action == "cleaning" ? "Cleaning" : "Robot is busy" }
        if docked { return charging ? "Charging" : "On the base" }
        if state == "idle" { return "Ready to clean" }
        return "Status unavailable"
    }
    public static func decode(_ data: Data, generation: String, event: Bool = false) throws -> RobotState {
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClientError.invalidResponse }
        var root = envelope
        if event {
            guard let message = envelope["data"] as? [String: Any] else { throw ClientError.invalidResponse }
            if generation == "neato.gen4" {
                guard (message["to"] as? [String: Any])?["service"] as? String == "peer.state",
                      let body = message["body"] as? [String: Any] else { throw ClientError.invalidResponse }
                root = body
            } else {
                guard message["type"] as? String == "state" || String(describing: message["eventId"] ?? "") == "77",
                      let body = message["data"] as? [String: Any] else { throw ClientError.invalidResponse }
                root = body
            }
        } else if generation == "neato.gen4" {
            guard let body = envelope["body"] as? [String: Any] else { throw ClientError.invalidResponse }
            root = body
        }
        let gen4 = generation == "neato.gen4"
        let details = root["details"] as? [String: Any] ?? [:]
        let available = root[gen4 ? "available_commands" : "availableCommands"] as? [String: Bool] ?? [:]
        guard root["state"] != nil else { throw ClientError.invalidResponse }
        let stateNames = [1: "idle", 2: "busy", 3: "paused", 4: "error"]
        let actionNames = [1: "cleaning", 2: "cleaning", 4: "docking", 11: "cleaning", 12: "exploring"]
        let state = gen4 ? root["state"] as? String ?? "unknown" : stateNames[root["state"] as? Int ?? -1] ?? "unknown"
        let action = gen4 ? root["action"] as? String ?? "unknown" : actionNames[root["action"] as? Int ?? -1] ?? "unknown"
        let keys: [(RobotAction, String)] = [(.start, "start"), (.pause, "pause"), (.resume, "resume"), (.stop, gen4 ? "cancel" : "stop"), (.returnToBase, gen4 ? "return_to_base" : "goToBase")]
        var errors = (root["errors"] as? [[String: Any]] ?? []).compactMap { $0["code"] as? String }
        if !gen4, let error = root["error"] as? String, !error.isEmpty, error != "none" { errors.append(error) }
        return RobotState(state: state, action: action, battery: (details["charge"] as? Int).map { min(100, max(0, $0)) },
                          docked: details[gen4 ? "is_docked" : "isDocked"] as? Bool ?? false,
                          charging: details[gen4 ? "is_charging" : "isCharging"] as? Bool ?? false,
                          commands: Set(keys.filter { available[$0.1] == true }.map(\.0)), errors: errors)
    }
}

/// Live state errors are independent of the robot's optional notification requests.
public struct RobotIssue: Equatable, Identifiable, Sendable {
    public let code: String
    public var id: String { code }
    public init(code: String) { self.code = code }
    public var title: String {
        switch code {
        case "dustbin_missing": return "Dirt bin missing"
        case "picked_up": return "Robot lifted"
        default: return code.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    public var detail: String {
        switch code {
        case "dustbin_missing": return "Put the dirt bin back in securely before resuming cleaning."
        case "picked_up": return "Place the robot on the floor before resuming cleaning."
        default: return "Check the robot before continuing."
        }
    }
}

public enum RobotAction: String, Sendable, CaseIterable { case start, pause, resume, stop, returnToBase }
public enum RobotCommand {
    public static func state(generation: String) -> [String: Any] {
        generation == "neato.gen4" ? ["ability": "state.show"] : ["cmd": "getRobotState"]
    }
    public static func build(_ action: RobotAction, generation: String, mode: String = "eco", gentle: Bool = false, mapID: String? = nil, zoneIDs: [String] = []) throws -> [String: Any] {
        guard generation == "neato.gen4" || generation == "neato.gen3" else { throw ClientError.message("This robot model isn’t supported yet.") }
        guard zoneIDs.isEmpty || mapID != nil else { throw ClientError.message("Select a saved map for these rooms.") }
        if generation == "neato.gen4" {
            if action != .start {
                let ability: [RobotAction: String] = [.pause: "cleaning.pause", .resume: "cleaning.resume", .stop: "cleaning.cancel", .returnToBase: "navigation.return_to_base"]
                return ["ability": ability[action]!]
            }
            guard ["eco", "turbo"].contains(mode) else { throw ClientError.message("Choose Eco or Turbo cleaning.") }
            let tracks: [String?] = zoneIDs.isEmpty ? [nil] : zoneIDs.map { Optional($0) }
            let runs: [[String: Any]] = tracks.map { track in
                let map: Any = mapID.map { ["rank_id": $0, "track_id": track as Any? ?? NSNull(), "nogo_enabled": true] as [String: Any] } ?? NSNull()
                return ["map": map, "settings": ["mode": mode, "navigation_mode": gentle ? "gentle" : "normal"]]
            }
            return ["ability": "cleaning.start", "runs": runs]
        }
        guard zoneIDs.count <= 1 else { throw ClientError.message("This robot can clean one room at a time.") }
        if action != .start {
            let commands: [RobotAction: String] = [.pause: "pauseCleaning", .resume: "resumeCleaning", .stop: "stopCleaning", .returnToBase: "sendToBase"]
            return ["cmd": commands[action]!]
        }
        var params: [String: Any] = ["category": mapID == nil ? 2 : 4, "mode": mode == "eco" ? 1 : 2, "navigationMode": gentle ? 2 : 1]
        if let mapID { params["mapId"] = mapID }
        if let zone = zoneIDs.first { params["boundaryId"] = zone }
        return ["cmd": "startCleaning", "params": params]
    }
}

public struct FloorMap: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let promoted: Bool?
    public let enabled: Bool?
    public var displayName: String { name == "(unnamed)" || name.isEmpty ? "Floor map" : name }
    public func canClean(generation: String) -> Bool { generation == "neato.gen4" ? promoted == true : enabled == true }
}
public struct Boundary: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let color: String?
    public let type: String
    public let function: String?
    public let vertices: [[Double]]
    public let enabled: Bool?
    public var isRoom: Bool { type == "polygon" && function == "cleaning" && enabled == true && vertices.count >= 3 && vertices.allSatisfy { $0.count == 2 && $0.allSatisfy { $0.isFinite && (0...1).contains($0) } } }
}
public struct MapRaster: Decodable, Sendable {
    public let width: Int
    public let height: Int
    public let legend: [String: String]
    public let rle: [[Int]]
    public let metadata: [String: Double]?
    public let img_size: [Int]?
    public let base: [Double]?
    public func pixels() throws -> [UInt8] {
        guard width > 0, height > 0, width <= 8192, height <= 8192, width <= 16_777_216 / height else { throw ClientError.message("This map is too large to display.") }
        let total = width * height
        var result = [UInt8](); result.reserveCapacity(total)
        for pair in rle {
            guard pair.count == 2, (0...255).contains(pair[0]), pair[1] > 0, pair[1] <= total - result.count else { throw ClientError.invalidResponse }
            result.append(contentsOf: repeatElement(UInt8(pair[0]), count: pair[1]))
        }
        guard result.count == total else { throw ClientError.invalidResponse }
        return result
    }
    public var dock: (x: Double, y: Double)? {
        guard let base, base.count >= 2, !base.prefix(2).contains(2_147_483_647),
              let md = metadata, let ox = md["origin_x"], let oy = md["origin_y"], let res = md["resolution"], res > 0,
              let size = img_size, size.count == 2, size.allSatisfy({ $0 > 0 }) else { return nil }
        let x = ((base[0] - ox) / res) / Double(size[0]); let y = ((base[1] - oy) / res) / Double(size[1])
        return x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) ? (x, y) : nil
    }
}
public enum ClientError: LocalizedError {
    case message(String), invalidResponse
    public var errorDescription: String? {
        switch self { case .message(let text): return text; case .invalidResponse: return "The server returned an unexpected response. Try refreshing." }
    }
}
