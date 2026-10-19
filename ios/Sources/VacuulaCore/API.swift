import Foundation

public struct SSEFrame: Equatable, Sendable {
    public let event: String
    public let data: String
}
public struct SSEParser {
    private var event = "message"
    private var data = [String]()
    public init() {}
    public mutating func receive(line: String) -> SSEFrame? {
        if line.isEmpty {
            defer { event = "message"; data.removeAll(keepingCapacity: true) }
            return data.isEmpty ? nil : SSEFrame(event: event, data: data.joined(separator: "\n"))
        }
        guard !line.hasPrefix(":") else { return nil }
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(parts[0]); var value = parts.count == 2 ? String(parts[1]) : ""
        if value.first == " " { value.removeFirst() }
        if field == "data" { data.append(value) }
        if field == "event" { event = value }
        return nil
    }
}

public struct VacuulaAPI: Sendable {
    public let origin: URL
    public init(origin: URL) { self.origin = origin }
    public func url(_ components: [String]) -> URL {
        components.reduce(origin.appendingPathComponent("api")) { $0.appendingPathComponent($1) }
    }
    public func data(_ path: [String], payload: [String: Any]? = nil, timeout: TimeInterval = 10, query: [URLQueryItem] = []) async throws -> Data {
        var target = URLComponents(url: url(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { target.queryItems = query }
        var request = URLRequest(url: target.url!, timeoutInterval: timeout)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let payload {
            request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(data: data, response: response)
        return data
    }
    public static func validate(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 504 { throw ClientError.message("The robot didn’t answer in time. Its action may have started. Refresh its status before trying again.") }
            throw ClientError.message(object?["error"] as? String ?? "The server couldn’t complete the request (\(http.statusCode)). Try refreshing.")
        }
        if let code = object?["code"] as? Int, !(200..<300).contains(code) { throw ClientError.message("The robot declined the request (\(code)). Refresh its status and try again.") }
        if let result = object?["result"] as? String, result != "ok" { throw ClientError.message("The robot declined the request: \(result).") }
    }
    public func server() async throws -> ServerInfo { try JSONDecoder().decode(ServerInfo.self, from: await data(["server"], timeout: 5)) }
    public func robots() async throws -> [Robot] { try Robot.inventory(await data(["robots"])) }
    public func state(_ robot: Robot) async throws -> RobotState {
        try RobotState.decode(await data(["robot", robot.id, "command"], payload: RobotCommand.state(generation: robot.type), timeout: 40), generation: robot.type)
    }
    public func command(_ robot: Robot, payload: [String: Any]) async throws {
        _ = try await data(["robot", robot.id, "command"], payload: payload, timeout: 40)
    }
    public func maps(_ robot: Robot) async throws -> [FloorMap] { try JSONDecoder().decode([FloorMap].self, from: await data(["robot", robot.id, "maps"])) }
    public func boundaries(_ robot: Robot, map: FloorMap) async throws -> [Boundary] {
        guard robot.type == "neato.gen4" else { throw ClientError.message("Room selection for this model is coming in a later version.") }
        return try JSONDecoder().decode([Boundary].self, from: await data(["robot", robot.id, "maps", map.id, "boundaries"]))
    }
    public func map(_ robot: Robot, map: FloorMap) async throws -> MapRaster { try JSONDecoder().decode(MapRaster.self, from: await data(["robot", robot.id, "maps", map.id], timeout: 20)) }
    public func notifications(_ robot: Robot, before: Int64? = nil) async throws -> NotificationPage {
        var query = [URLQueryItem(name: "limit", value: "50")]
        if let before { query.append(URLQueryItem(name: "before", value: String(before))) }
        return try JSONDecoder().decode(NotificationPage.self, from: await data(["robot", robot.id, "notifications"], query: query))
    }
    public func events(_ path: [String], connected: @escaping @Sendable () async -> Void = {}, receive: @escaping @Sendable (SSEFrame) async -> Void) async throws {
        var request = URLRequest(url: url(path), timeoutInterval: 60)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true else { throw ClientError.invalidResponse }
        await connected()
        var parser = SSEParser()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if let frame = parser.receive(line: line) { await receive(frame) }
        }
    }
}
