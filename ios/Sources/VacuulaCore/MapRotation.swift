import Foundation

/// Display-only quarter turns, clockwise in the screen's coordinate system.
public enum MapRotation: Int, CaseIterable, Identifiable, Sendable {
    case degrees0 = 0, degrees90 = 90, degrees180 = 180, degrees270 = 270
    public var id: Int { rawValue }
    public var title: String { self == .degrees0 ? "0° (Default)" : "\(rawValue)° clockwise" }
    public var swapsAxes: Bool { self == .degrees90 || self == .degrees270 }
    public func fittedScale(imageWidth: Double, imageHeight: Double, canvasWidth: Double, canvasHeight: Double) -> Double {
        let values = [imageWidth, imageHeight, canvasWidth, canvasHeight]
        guard values.allSatisfy({ $0.isFinite && $0 > 0 }) else { return 0 }
        let width = swapsAxes ? canvasHeight : canvasWidth
        let height = swapsAxes ? canvasWidth : canvasHeight
        return min(width / imageWidth, height / imageHeight)
    }
    public static func load(defaults: UserDefaults) -> Self {
        Self(rawValue: defaults.integer(forKey: "map-display-rotation")) ?? .degrees0
    }
    public func save(defaults: UserDefaults) { defaults.set(rawValue, forKey: "map-display-rotation") }
}
