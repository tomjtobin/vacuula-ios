import Foundation
import Testing
@testable import VacuulaCore

struct RequestedAreaTests {
    func decode<T: Decodable>(_ json: String) throws -> T { try JSONDecoder().decode(T.self, from: Data(json.utf8)) }
    func saved(id: String = "floor", promoted: Bool = true, zones: String = "[]", raster: String? = nil) throws -> SavedMapArea {
        try SavedMapArea(map: decode("{\"id\":\"\(id)\",\"name\":\"Floor\",\"promoted\":\(promoted)}"), raster: decode(raster ?? #"{"width":4,"height":2,"legend":{"0":"unknown","1":"free","2":"wall"},"rle":[[1,8]],"metadata":{"resolution":1000},"img_size":[4,2]}"#), boundaries: decode(zones))
    }
    func record(tracks: [String?], map: String? = nil) throws -> CleaningRecord {
        var json: [String: Any] = ["id":"run", "robot":"r", "floorplan":"run-result", "runs":tracks.map { value -> [String: Any] in
            var pass: [String: Any] = ["stats":["area":4.0]]
            if let value { pass["track_uuid"] = value }
            return pass
        }]
        if let map { json["persistent_rank_uuid"] = map }
        return try JSONDecoder().decode(CleaningRecord.self, from: JSONSerialization.data(withJSONObject: json))
    }
    @Test func freeCellsOnlyAndPhysicalScale() throws {
        let raster = #"{"width":2,"height":2,"legend":{"0":"unknown","1":"free","2":"wall"},"rle":[[1,2],[2,1],[0,1]],"metadata":{"resolution":40},"img_size":[4,4]}"#
        let area = try #require(saved(raster:raster).estimate())
        #expect(abs(area.squareMetres - 0.0128) < 1e-10)
        #expect(abs(area.squareFeet - 0.1377780533) < 1e-8)
    }
    @Test func roomsUnionClippedToFreeSpaceMinusNoGo() throws {
        let zones = #"[{"id":"left","name":"Left","type":"polygon","function":"cleaning","enabled":true,"vertices":[[0,0],[0.75,0],[0.75,1],[0,1]]},{"id":"right","name":"Right","type":"polygon","function":"cleaning","enabled":true,"vertices":[[0.25,0],[1,0],[1,1],[0.25,1]]},{"id":"avoid","name":"Avoid","type":"polygon","function":"nogo","enabled":true,"vertices":[[0,0],[0.25,0],[0.25,1],[0,1]]}]"#
        let map = try saved(zones:zones)
        #expect(map.estimate()?.squareMetres == 6)
        #expect(map.estimate(roomIDs:["left"])?.squareMetres == 4)
        #expect(map.estimate(roomIDs:["left","right"])?.squareMetres == 6)
        #expect(map.estimate(roomIDs:["missing"]) == nil)
    }
    @Test func noGoPolylineUsesOriginalPixelWidth() throws {
        let map = try saved(zones:#"[{"id":"avoid","name":"Line","type":"polyline","function":"nogo","enabled":true,"vertices":[[0.5,0],[0.5,1]]}]"#)
        #expect(map.estimate() == nil) // A 9-pixel no-go line covers this tiny 4-pixel floor.
    }
    @Test func disabledNoGoDoesNotExcludeSpace() throws {
        let map = try saved(zones:#"[{"id":"avoid","name":"Disabled","type":"polygon","function":"nogo","enabled":false,"vertices":[[0,0],[1,0],[1,1],[0,1]]}]"#)
        #expect(map.estimate()?.squareMetres == 8)
    }
    @Test func missingScopeAndAmbiguousMapsNeverInventTargets() throws {
        let a = try saved(), b = try saved(id:"other")
        #expect(SavedMapArea.estimate(record:try record(tracks:[""]), maps:[a])?.squareMetres == 8)
        #expect(SavedMapArea.estimate(record:try record(tracks:[""]), maps:[a,b]) == nil)
        #expect(SavedMapArea.estimate(record:try record(tracks:[nil]), maps:[a]) == nil)
        #expect(SavedMapArea.estimate(record:try record(tracks:["","room"]), maps:[a]) == nil)
        #expect(SavedMapArea.estimate(record:try record(tracks:[""],map:"missing"), maps:[a]) == nil)
        #expect(SavedMapArea.estimate(record:try record(tracks:[""],map:"floor"), maps:[a,b]) != nil)
    }
    @Test func roomTracksIdentifyOneMapWithoutUsingScheduleGuess() throws {
        let zones = #"[{"id":"room","name":"Room","type":"polygon","function":"cleaning","enabled":true,"vertices":[[0,0],[0.5,0],[0.5,1],[0,1]]}]"#
        let map = try saved(promoted:false,zones:zones)
        let run = try record(tracks:["room","room"])
        #expect(SavedMapArea.estimate(record:run,maps:[map])?.squareMetres == 4)
        #expect(SavedMapArea.estimate(record:run,maps:[map,try saved(id:"other",zones:zones)]) == nil)
    }
    @Test func invalidScaleAndMalformedActiveExclusionsFailClosed() throws {
        #expect(throws:(any Error).self) { try saved(raster:#"{"width":1,"height":1,"legend":{"1":"free"},"rle":[[1,1]],"metadata":{"resolution":0},"img_size":[1,1]}"#) }
        #expect(throws:(any Error).self) { try saved(zones:#"[{"id":"bad","name":"Bad","type":"polygon","function":"nogo","enabled":true,"vertices":[[0,0],[2,0],[0,1]]}]"#) }
    }
    @Test func estimatesCanExceed100WithoutChangingOutcome() throws {
        let estimate = try #require(saved().estimate())
        #expect(estimate.percentage(cleanedSquareMetres:12) == 150)
        #expect(estimate.percentage(cleanedSquareMetres:nil) == nil)
        #expect(estimate.percentage(cleanedSquareMetres: -1) == nil)
    }
}
