import SwiftUI
import VacuulaCore

struct RoomsView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            if store.maps.isEmpty {
                ContentUnavailableView("No saved maps yet", systemImage: "map", description: Text("Save a floor map in the web app, then configure cleaning zones to choose rooms here. Whole-house cleaning is available in Robot."))
                if !store.demo, let url = store.server?.origin.appendingPathComponent("web/map") { Link("Open maps in web app", destination: url) }
            } else {
                Section {
                    ForEach(store.maps) { map in
                        NavigationLink {
                            FloorDetailView(map: map)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(map.displayName)
                                    Text(map.canClean(generation: store.robot?.type ?? "") ? "Active map" : "View only")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }.padding(.vertical, 6)
                            } icon: { Image(systemName: "map").foregroundStyle(.teal) }
                        }
                        .accessibilityIdentifier("floor.\(map.id)")
                    }
                } footer: { Text("Rooms are cleaning zones configured on a saved map.") }
            }
        }.navigationTitle("Rooms")
            .refreshable { await store.refresh() }
    }
}

struct FloorDetailView: View {
    @EnvironmentObject private var store: AppStore
    let map: FloorMap
    @State private var rendered: RenderedMap?
    @State private var boundaries = [Boundary]()
    @State private var selected = Set<String>()
    @State private var error: String?
    @State private var loading = true
    @State private var reload = UUID()
    @State private var scale: CGFloat = 1
    @State private var offset = CGSize.zero
    @GestureState private var drag = CGSize.zero
    @GestureState private var pinch: CGFloat = 1
    private var rooms: [Boundary] { boundaries.filter(\.isRoom) }

    var body: some View {
        List {
            Section {
                if let rendered {
                    MapCanvas(rendered: rendered, boundaries: boundaries, selected: selected)
                        .scaleEffect(min(6, max(1, scale * pinch)))
                        .offset(x: offset.width + drag.width, y: offset.height + drag.height)
                        .frame(height: 300)
                        .gesture(MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification }
                            .onEnded { scale = min(6, max(1, scale * $0.magnification)); if scale == 1 { offset = .zero } })
                        .simultaneousGesture(DragGesture().updating($drag) { value, state, _ in if scale > 1 { state = value.translation } }
                            .onEnded { if scale > 1 { offset.width += $0.translation.width; offset.height += $0.translation.height } })
                        .clipped().accessibilityLabel("Saved floor map. Rooms can be selected in the list below.")
                        .accessibilityElement(children: .ignore)
                        .accessibilityValue("\(store.mapRotation.rawValue)° clockwise")
                        .accessibilityIdentifier("floor-map-image")
                    HStack {
                        Button("Zoom in", systemImage: "plus.magnifyingglass") { scale = min(6, scale + 0.5) }
                        Spacer()
                        Button("Reset view", systemImage: "arrow.up.left.and.arrow.down.right") { scale = 1; offset = .zero }
                    }.buttonStyle(.borderless).frame(minHeight: 44)
                    if boundaries.contains(where: { $0.function == "nogo" }) {
                        Label("Dashed outlines mark no-go areas", systemImage: "hand.raised")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if loading {
                    ProgressView("Loading map…").frame(maxWidth: .infinity, minHeight: 240)
                }
                if let error { Text(error).foregroundStyle(.secondary); Button("Try again") { reload = UUID() } }
            } footer: { if rendered != nil { Text("Saved map · Base location shown when available. This map doesn’t show the robot’s live position.") } }
            if !loading && error == nil {
                Section {
                    if rooms.isEmpty {
                        ContentUnavailableView("No rooms configured", systemImage: "square.dashed", description: Text("Add cleaning zones to this map in the web app. They’ll appear here after you refresh."))
                        if !store.demo, let url = store.server?.origin.appendingPathComponent("web/map") { Link("Configure rooms in web app", destination: url) }
                    } else {
                        ForEach(rooms) { room in
                            Button {
                                if selected.contains(room.id) { selected.remove(room.id) } else { selected.insert(room.id) }
                            } label: {
                                HStack {
                                    Text(room.name.isEmpty ? "Unnamed room" : room.name).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: selected.contains(room.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(.teal)
                                }.frame(minHeight: 44)
                            }.accessibilityAddTraits(selected.contains(room.id) ? [.isSelected] : [])
                                .disabled(store.pending != nil)
                        }
                    }
                } header: { Text("Rooms") }
                if !rooms.isEmpty {
                    Section {
                        Button { store.perform(.start, map: map, zones: selected) } label: {
                            Label(selected.isEmpty ? "Select rooms to clean" : "Clean selected rooms", systemImage: "play.fill")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.borderedProminent)
                            .disabled(selected.isEmpty || !store.canControl || store.state?.commands.contains(.start) != true || store.state?.docked != true || !map.canClean(generation: store.robot?.type ?? ""))
                    } footer: {
                        if !map.canClean(generation: store.robot?.type ?? "") { Text("Activate this map in the web app before cleaning its rooms.") }
                        else if store.state?.docked != true { Text("Place the robot on its base before starting room cleaning.") }
                        else { Text("Uses the power and navigation options selected in Robot.") }
                    }
                }
            }
            if let pending = store.pending { Section { ProgressView(pending) } }
            if let notice = store.notice { Section { Text(notice).font(.subheadline).foregroundStyle(.secondary) } }
        }.navigationTitle(map.displayName)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Refresh", systemImage: "arrow.clockwise") { reload = UUID() }.disabled(loading || store.pending != nil) } }
            .task(id: reload) { await load() }
            .onChange(of: store.mapRotation) { _, _ in scale = 1; offset = .zero }
    }
    private func load() async {
        if store.demo {
            defer { loading = false }
            do {
                let raster = try DemoContent.raster()
                let zones = try DemoContent.boundaries()
                rendered = try RenderedMap.make(raster, boundaries: zones); boundaries = zones
            } catch { self.error = error.localizedDescription }
            return
        }
        guard let api = store.api, let robot = store.robot else { loading = false; return }
        loading = true; error = nil; selected.removeAll()
        do {
            let raster = try await api.map(robot, map: map)
            let zones = try await api.boundaries(robot, map: map)
            let image = try await Task.detached(priority: .userInitiated) { try RenderedMap.make(raster, boundaries: zones) }.value
            try Task.checkCancellation()
            rendered = image; boundaries = zones
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}

struct RenderedMap: @unchecked Sendable {
    let image: CGImage
    let viewport: CGRect
    let dock: CGPoint?
    static func make(_ raster: MapRaster, boundaries: [Boundary]) throws -> RenderedMap {
        let pixels = try raster.pixels()
        var rgba = [UInt8](); rgba.reserveCapacity(pixels.count * 4)
        var minX = raster.width, minY = raster.height, maxX = 0, maxY = 0
        for (index, value) in pixels.enumerated() {
            let kind = raster.legend[String(value)] ?? "unknown"
            let color: [UInt8]
            switch kind {
            case "free": color = [243, 247, 246, 255]
            case "wall": color = [61, 78, 76, 255]
            default: color = [224, 232, 230, 255]
            }
            rgba.append(contentsOf: color)
            if kind != "unknown" {
                let x = index % raster.width, y = index / raster.width
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        if minX > maxX || minY > maxY { minX = 0; minY = 0; maxX = raster.width - 1; maxY = raster.height - 1 }
        if let dock = raster.dock {
            minX = min(minX, Int(dock.x * Double(raster.width))); maxX = max(maxX, Int(dock.x * Double(raster.width)))
            minY = min(minY, Int(dock.y * Double(raster.height))); maxY = max(maxY, Int(dock.y * Double(raster.height)))
        }
        for boundary in boundaries {
            for vertex in boundary.vertices where vertex.count == 2 && vertex.allSatisfy({ $0.isFinite && (0...1).contains($0) }) {
                let x = min(raster.width - 1, Int(vertex[0] * Double(raster.width)))
                let y = min(raster.height - 1, Int(vertex[1] * Double(raster.height)))
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        let margin = max(12, max(maxX - minX, maxY - minY) / 12)
        let crop = CGRect(x: max(0, minX - margin), y: max(0, minY - margin),
                          width: min(raster.width - 1, maxX + margin) - max(0, minX - margin) + 1,
                          height: min(raster.height - 1, maxY + margin) - max(0, minY - margin) + 1)
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let full = CGImage(width: raster.width, height: raster.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                 bytesPerRow: raster.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                                 decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let image = full.cropping(to: crop) else { throw ClientError.invalidResponse }
        let viewport = CGRect(x: crop.minX / Double(raster.width), y: crop.minY / Double(raster.height), width: crop.width / Double(raster.width), height: crop.height / Double(raster.height))
        return RenderedMap(image: image, viewport: viewport, dock: raster.dock.map { CGPoint(x: $0.x, y: $0.y) })
    }
}

struct MapCanvas: View {
    @EnvironmentObject private var store: AppStore
    let rendered: RenderedMap
    let boundaries: [Boundary]
    let selected: Set<String>
    var body: some View {
        Canvas { context, size in
            let rotation = store.mapRotation
            let ratio = CGFloat(rotation.fittedScale(imageWidth: Double(rendered.image.width), imageHeight: Double(rendered.image.height), canvasWidth: Double(size.width), canvasHeight: Double(size.height)))
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.rotate(by: .degrees(Double(rotation.rawValue)))
            let rect = CGRect(x: -CGFloat(rendered.image.width) * ratio / 2,
                              y: -CGFloat(rendered.image.height) * ratio / 2,
                              width: CGFloat(rendered.image.width) * ratio, height: CGFloat(rendered.image.height) * ratio)
            context.draw(Image(decorative: rendered.image, scale: 1), in: rect)
            func project(_ point: CGPoint) -> CGPoint {
                CGPoint(x: rect.minX + (point.x - rendered.viewport.minX) / rendered.viewport.width * rect.width,
                        y: rect.minY + (point.y - rendered.viewport.minY) / rendered.viewport.height * rect.height)
            }
            for boundary in boundaries where boundary.vertices.count >= 2 {
                guard boundary.vertices.allSatisfy({ $0.count == 2 && $0.allSatisfy { $0.isFinite && (0...1).contains($0) } }) else { continue }
                let points = boundary.vertices.compactMap { $0.count == 2 ? project(CGPoint(x: $0[0], y: $0[1])) : nil }
                guard let first = points.first else { continue }
                let path = Path { path in
                    path.move(to: first); for point in points.dropFirst() { path.addLine(to: point) }
                    if boundary.type == "polygon" { path.closeSubpath() }
                }
                let color: Color = boundary.function == "nogo" ? .red : zoneColor(boundary.color)
                if boundary.type == "polygon" { context.fill(path, with: .color(color.opacity(selected.contains(boundary.id) ? 0.40 : 0.12))) }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: selected.contains(boundary.id) ? 3 : 1.5, dash: boundary.function == "nogo" ? [5, 3] : []))
            }
            if let dock = rendered.dock {
                let p = project(dock)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24)), with: .color(.teal))
                // Rotate the marker's position with the map, keeping its glyph readable.
                var markerContext = context
                markerContext.translateBy(x: p.x, y: p.y)
                markerContext.rotate(by: .degrees(-Double(rotation.rawValue)))
                markerContext.draw(Text(Image(systemName: "house.fill")).font(.caption2).foregroundColor(.white), at: .zero)
            }
        }
    }
    private func zoneColor(_ value: String?) -> Color {
        guard let value, value.hasPrefix("#"), value.count == 7,
              let rgb = UInt32(value.dropFirst(), radix: 16) else { return .teal }
        return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}
