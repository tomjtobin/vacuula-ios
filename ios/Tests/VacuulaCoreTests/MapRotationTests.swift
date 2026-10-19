import Foundation
import Testing
@testable import VacuulaCore

struct MapRotationTests {
    @Test func defaultsToZeroAndPersistsEverySupportedRotation() throws {
        let suite = "VacuulaMapRotationTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(MapRotation.load(defaults: defaults) == .degrees0)
        for rotation in MapRotation.allCases {
            rotation.save(defaults: defaults)
            let reopened = try #require(UserDefaults(suiteName: suite))
            #expect(MapRotation.load(defaults: reopened) == rotation)
        }
        defaults.set(45, forKey: "map-display-rotation")
        #expect(MapRotation.load(defaults: defaults) == .degrees0)
    }
    @Test func rectangularMapsFitAtAllQuarterTurns() {
        for rotation in MapRotation.allCases {
            let scale = rotation.fittedScale(imageWidth: 400, imageHeight: 100, canvasWidth: 300, canvasHeight: 200)
            let width = (rotation.swapsAxes ? 100.0 : 400.0) * scale
            let height = (rotation.swapsAxes ? 400.0 : 100.0) * scale
            #expect(width <= 300 && height <= 200)
            #expect(scale == (rotation.swapsAxes ? 0.5 : 0.75))
        }
        #expect(MapRotation.degrees90.fittedScale(imageWidth: 0, imageHeight: 100, canvasWidth: 300, canvasHeight: 200) == 0)
        #expect(MapRotation.degrees270.fittedScale(imageWidth: 400, imageHeight: 100, canvasWidth: .infinity, canvasHeight: 200) == 0)
    }
}
