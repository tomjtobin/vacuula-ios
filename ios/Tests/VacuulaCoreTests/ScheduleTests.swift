import Foundation
import Testing
@testable import VacuulaCore

struct ScheduleTests {
    @Test func createWholeFloorAndRooms() throws {
        let floor = try CleaningSchedule.create(days: [.mon, .fri], time: "09:05", mode: "eco", gentle: true, mapID: "floor")
        let payload = try floor.updatePayload()
        #expect(payload["ability"] as? String == "scheduling.update")
        let event = try #require(payload["event"] as? [String: Any])
        #expect(event["id"] == nil)
        let command = try #require(event["command"] as? [String: Any])
        let runs = try #require(command["runs"] as? [[String: Any]])
        let map = try #require(runs[0]["map"] as? [String: Any])
        #expect(map["rank_id"] as? String == "floor")
        #expect(map["track_id"] is NSNull)
        #expect(map["nogo_enabled"] as? Bool == true)
        #expect((runs[0]["settings"] as? [String: String])?["navigation_mode"] == "gentle")
        let rooms = try CleaningSchedule.create(days: [.sun], time: "23:59", mode: "turbo", gentle: false, mapID: "floor", zoneIDs: ["kitchen", "hall"])
        let roomEvent = try #require(try rooms.updatePayload()["event"] as? [String: Any])
        let roomRuns = try #require((roomEvent["command"] as? [String: Any])?["runs"] as? [[String: Any]])
        #expect(roomRuns.count == 2)
        #expect((roomRuns[1]["map"] as? [String: Any])?["track_id"] as? String == "hall")
    }
    @Test func editsPreserveExistingCommandAndID() throws {
        let data = Data("""
        {"id":"42","enabled":true,"days":["tue"],"time":"10:00","command":{"ability":"cleaning.start","force_floorplan":true,"future":{"value":[null,3]},"runs":[{"settings":{"mode":"max"},"map":null}]}}
        """.utf8)
        let original = try JSONDecoder().decode(CleaningSchedule.self, from: data)
        var edited = original
        edited.enabled = false; edited.time = "11:30"; edited.days = [.wed]
        let event = try #require(try edited.updatePayload()["event"] as? [String: Any])
        let roundTrip = try JSONDecoder().decode(CleaningSchedule.self, from: JSONSerialization.data(withJSONObject: event))
        #expect(roundTrip.command == original.command)
        #expect(roundTrip.id == "42")
        #expect(!roundTrip.enabled)
    }
    @Test func rejectsInvalidTimesAndDays() throws {
        for time in ["24:00", "12:60", "9:00", "-1:30", "12:3", "12:30:00"] {
            #expect(throws: (any Error).self) { try CleaningSchedule.create(days: [.mon], time: time, mode: "eco", gentle: false, mapID: nil) }
        }
        #expect(throws: (any Error).self) { try CleaningSchedule.create(days: [], time: "09:00", mode: "eco", gentle: false, mapID: nil) }
        #expect(throws: (any Error).self) { try CleaningSchedule.create(days: [.mon, .mon], time: "09:00", mode: "eco", gentle: false, mapID: nil) }
        #expect(throws: (any Error).self) { try CleaningSchedule.create(days: [.mon], time: "09:00", mode: "eco", gentle: false, mapID: nil, zoneIDs: ["zone"]) }
    }
    @Test func confirmsAssignedIDsAndDetectsMismatches() throws {
        let draft = try CleaningSchedule.create(days: [.mon, .fri], time: "09:00", mode: "eco", gentle: false, mapID: nil)
        var saved = draft; saved.id = "new-id"; saved.days = [.fri, .mon]
        #expect(draft.matches(saved))
        if case .object(var fields) = saved.command {
            fields["force_floorplan"] = .bool(true)
            fields["auto_localization"] = .bool(true)
            saved.command = .object(fields)
        }
        #expect(draft.matches(saved))
        #expect(!draft.matches(draft)) // A newly created event needs an assigned ID.
        saved.time = "09:01"
        #expect(!draft.matches(saved))
        #expect(!saved.matches(draft))
    }
}
