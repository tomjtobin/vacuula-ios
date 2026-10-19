import Foundation

/// An estimate from current saved-map geometry, never from the uploaded result map.
public struct RequestedAreaEstimate: Sendable {
    public let squareMetres: Double
    public let scope: String
    public let mapName: String
    public var squareFeet: Double { squareMetres * 10.7639104167 }
    public func percentage(cleanedSquareMetres: Double?) -> Double? {
        guard let area = cleanedSquareMetres, area.isFinite, area >= 0, squareMetres > 0 else { return nil }
        let result = area / squareMetres * 100
        return result.isFinite ? result : nil
    }
}

public struct SavedMapArea: Sendable {
    public let map: FloorMap
    private let raster: MapRaster
    private let cells: [UInt8]
    private let boundaries: [Boundary]
    private let cellArea: Double
    public init(map: FloorMap, raster: MapRaster, boundaries: [Boundary]) throws {
        guard let resolution = raster.metadata?["resolution"], resolution.isFinite, resolution > 0,
              let size = raster.img_size, size.count == 2, size[0] > 0, size[1] > 0,
              raster.width > 0, raster.height > 0,
              size[0] >= raster.width, size[1] >= raster.height,
              raster.legend.values.contains("free") else { throw ClientError.invalidResponse }
        // Gen4 PGM resolution is millimetres per original cell. Scale both axes
        // from img_size, not the cropped display or its orientation.
        cellArea = pow(resolution / 1000, 2) * Double(size[0]) / Double(raster.width) * Double(size[1]) / Double(raster.height)
        guard cellArea.isFinite, cellArea > 0 else { throw ClientError.invalidResponse }
        for b in boundaries where b.enabled == true && b.function == "nogo" {
            guard Self.valid(b), b.type == "polygon" || b.type == "polyline" else { throw ClientError.invalidResponse }
        }
        self.map = map; self.raster = raster; self.boundaries = boundaries
        cells = try raster.pixels()
    }
    private static func valid(_ b: Boundary) -> Bool {
        b.vertices.count >= (b.type == "polyline" ? 2 : 3) && b.vertices.allSatisfy { $0.count == 2 && $0.allSatisfy { $0.isFinite && (0...1).contains($0) } }
    }
    public func hasRooms(_ ids: Set<String>) -> Bool {
        !ids.isEmpty && ids.allSatisfy { id in boundaries.contains { $0.id == id && $0.isRoom } }
    }
    public func estimate(roomIDs: Set<String>? = nil) -> RequestedAreaEstimate? {
        if let roomIDs, !hasRooms(roomIDs) { return nil }
        let rooms = boundaries.filter { roomIDs?.contains($0.id) == true }
        let excluded = boundaries.filter { $0.enabled == true && $0.function == "nogo" }
        let free = Set(raster.legend.compactMap { $0.value == "free" ? UInt8($0.key) : nil })
        var count = 0
        for (index, cell) in cells.enumerated() where free.contains(cell) {
            let x = (Double(index % raster.width) + 0.5) / Double(raster.width)
            let y = (Double(index / raster.width) + 0.5) / Double(raster.height)
            if !excluded.contains(where: { contains($0, x: x, y: y) }) && (roomIDs == nil || rooms.contains(where: { contains($0, x: x, y: y) })) { count += 1 }
        }
        let area = Double(count) * cellArea
        guard area.isFinite, area > 0 else { return nil }
        return RequestedAreaEstimate(squareMetres: area, scope: roomIDs == nil ? "Whole floor" : rooms.map { $0.name.isEmpty ? "Unnamed room" : $0.name }.sorted().joined(separator: ", "), mapName: map.displayName)
    }
    private func contains(_ b: Boundary, x: Double, y: Double) -> Bool {
        let points = b.vertices
        if b.type == "polyline" {
            // Server Gen4 promotion rasterizes no-go lines at 9 original pixels.
            let size = raster.img_size!
            let px = x * Double(size[0]), py = y * Double(size[1])
            for i in 1..<points.count {
                let ax = points[i-1][0] * Double(size[0]), ay = points[i-1][1] * Double(size[1])
                let dx = points[i][0] * Double(size[0]) - ax, dy = points[i][1] * Double(size[1]) - ay
                let length = dx*dx + dy*dy
                let t = length > 0 ? min(1, max(0, ((px-ax)*dx + (py-ay)*dy)/length)) : 0
                if hypot(px-ax-t*dx, py-ay-t*dy) <= 4.5 { return true }
            }
            return false
        }
        var inside = false
        var j = points.count - 1
        for i in points.indices {
            let a = points[i], b = points[j]
            if (a[1] > y) != (b[1] > y), x < (b[0]-a[0]) * (y-a[1]) / (b[1]-a[1]) + a[0] { inside.toggle() }
            j = i
        }
        return inside
    }
    public static func estimate(record: CleaningRecord, maps: [SavedMapArea]) -> RequestedAreaEstimate? {
        guard let passes = record.runs, !passes.isEmpty, passes.allSatisfy({ $0.track_uuid != nil }) else { return nil }
        let tracks = Set(passes.compactMap(\.track_uuid).filter { !$0.isEmpty })
        // Mixed whole-floor/room passes have no unambiguous requested-area union.
        guard tracks.isEmpty || !passes.contains(where: { $0.track_uuid == "" }) else { return nil }
        let explicit = record.persistent_rank_uuid ?? record.floorplan.flatMap { id in maps.contains(where: { $0.map.id == id }) ? id : nil }
        let candidates: [SavedMapArea]
        if let explicit { candidates = maps.filter { $0.map.id == explicit && (tracks.isEmpty || $0.hasRooms(tracks)) } }
        else if !tracks.isEmpty { candidates = maps.filter { $0.hasRooms(tracks) } }
        else { candidates = maps.filter { $0.map.promoted == true } }
        guard candidates.count == 1 else { return nil }
        return candidates[0].estimate(roomIDs: tracks.isEmpty ? nil : tracks)
    }
}
