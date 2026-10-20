import Foundation
import Testing
@testable import VacuulaCore

struct DemoContentTests {
    @Test func sharedMapAndRoomFixturesHaveConsistentAreas() throws {
        let map = try DemoContent.floor()
        let raster = try DemoContent.raster()
        let zones = try DemoContent.boundaries()
        #expect(try raster.pixels().count == 49)
        #expect(raster.dock != nil)
        #expect(map.promoted == true)
        let saved = try SavedMapArea(map:map,raster:raster,boundaries:zones)
        #expect(saved.estimate()?.squareMetres == 24)
        #expect(saved.estimate(roomIDs:["room"])?.squareMetres == 10)
    }
    @Test func historyCoversWholeFloorRoomAndCancelledOutcomes() throws {
        let map = try SavedMapArea(map:DemoContent.floor(),raster:DemoContent.raster(),boundaries:DemoContent.boundaries())
        let records = try DemoContent.history()
        #expect(records.count == 3)
        for record in records {
            let estimate = try #require(SavedMapArea.estimate(record:record,maps:[map]))
            #expect(estimate.percentage(cleanedSquareMetres:record.squareMetres) != nil)
        }
        #expect(records.first { $0.id == "preview-cancelled" }?.outcome == "Cancelled")
        let room = try #require(records.first { $0.id == "preview-room" })
        #expect(SavedMapArea.estimate(record:room,maps:[map])?.percentage(cleanedSquareMetres:room.squareMetres) == 80)
    }
    @Test func sampleScheduleReferencesTheSameMapAndRoom() throws {
        let schedules = try DemoContent.schedules()
        #expect(schedules.count == 1)
        for schedule in schedules { try schedule.validate(); _ = try schedule.updatePayload() }
        let command = String(data:try JSONEncoder().encode(schedules[0].command),encoding:.utf8)!
        #expect(command.contains("preview-map"))
        #expect(command.contains("room"))
    }
}
