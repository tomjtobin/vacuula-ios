import Foundation

public struct CleaningPreferences: Codable, Equatable, Sendable {
    public let mode: String
    public let gentle: Bool
    public init(mode: String = "eco", gentle: Bool = false) {
        self.mode = ["eco", "turbo"].contains(mode) ? mode : "eco"
        self.gentle = gentle
    }
    private static func key(server: URL, robotID: String) -> String {
        "cleaning-options:" + server.absoluteString + ":" + robotID
    }
    public static func load(defaults: UserDefaults, server: URL, robotID: String) -> CleaningPreferences {
        guard let data = defaults.data(forKey: key(server: server, robotID: robotID)),
              let saved = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return .init(mode: saved.mode, gentle: saved.gentle)
    }
    public func save(defaults: UserDefaults, server: URL, robotID: String) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key(server: server, robotID: robotID)) }
    }
}
