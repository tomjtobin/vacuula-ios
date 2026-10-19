import Foundation
import Testing
@testable import VacuulaCore

struct ProtocolTests {
    func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
    }
    @Test func testSavedURLNormalizationAndInvalidSchemes() throws {
        #expect(try ServerIdentity.normalizedURL(" 192.168.1.100:8080/web/map?x=1#section ").absoluteString == "http://192.168.1.100:8080")
        #expect(try ServerIdentity.normalizedURL("vacuula.local").host == "vacuula.local")
        #expect(throws: (any Error).self) { try ServerIdentity.normalizedURL("ftp://vacuula.local") }
        #expect(throws: (any Error).self) { try ServerIdentity.normalizedURL("http://user:password@vacuula.local") }
        #expect(throws: (any Error).self) { try ServerIdentity.normalizedURL("") }
    }
    @Test func testExampleGen4StateUsesReportedCapabilities() throws {
        let state = try RobotState.decode(fixture("gen4-state"), generation: "neato.gen4")
        #expect(state.battery == 86)
        #expect(state.charging && state.docked)
        #expect(state.commands == [.start])
        #expect(state.title == "Charging")
    }
    @Test func testGen3StateAndUnknownValuesRemainReadable() throws {
        let json = """
        {"state":3,"action":1,"details":{"charge":42,"isDocked":false,"isCharging":false},"availableCommands":{"resume":true,"stop":true},"error":"none","extra":"future"}
        """
        let state = try RobotState.decode(Data(json.utf8), generation: "neato.gen3")
        #expect(state.title == "Cleaning paused")
        #expect(state.commands == [.resume, .stop])
        let unknown = try RobotState.decode(Data("{\"body\":{\"state\":\"new_state\",\"action\":\"new_action\"}}".utf8), generation: "neato.gen4")
        #expect(unknown.state == "new_state")
        #expect(unknown.commands.isEmpty)
    }
    @Test func testSSECommentsMultilineNamedEventsAndExtraBlanks() {
        var parser = SSEParser()
        #expect(parser.receive(line: ": keepalive") == nil)
        #expect(parser.receive(line: "event: robots") == nil)
        #expect(parser.receive(line: "data: {") == nil)
        #expect(parser.receive(line: "data: \"robot\":true}") == nil)
        #expect(parser.receive(line: "") == SSEFrame(event: "robots", data: "{\n\"robot\":true}"))
        #expect(parser.receive(line: "") == nil)
        #expect(parser.receive(line: "data: next") == nil)
        #expect(parser.receive(line: "") == SSEFrame(event: "message", data: "next"))
    }
    @Test func testOnlyPeerStateEventsAreNormalized() throws {
        let fixtureBody = try #require((JSONSerialization.jsonObject(with: fixture("gen4-state")) as? [String: Any])?["body"])
        let event: [String: Any] = ["data": ["type": "event", "to": ["service": "peer.state"], "body": fixtureBody]]
        let state = try RobotState.decode(JSONSerialization.data(withJSONObject: event), generation: "neato.gen4", event: true)
        #expect(state.docked)
        #expect(throws: (any Error).self) { try RobotState.decode(Data("{\"data\":{\"to\":{\"service\":\"peer.other\"}}}".utf8), generation: "neato.gen4", event: true) }
    }
    @Test func testWholeHouseAndMultiRoomPayloadsPreserveZoneIdentity() throws {
        let house = try RobotCommand.build(.start, generation: "neato.gen4")
        let houseData = try JSONSerialization.data(withJSONObject: house)
        let houseObject = try #require(JSONSerialization.jsonObject(with: houseData) as? [String: Any])
        let runs = try #require(houseObject["runs"] as? [[String: Any]])
        #expect(runs[0]["map"] is NSNull)
        let rooms = try RobotCommand.build(.start, generation: "neato.gen4", mapID: "floor", zoneIDs: ["kitchen", "hall"])
        let roomRuns = try #require(rooms["runs"] as? [[String: Any]])
        #expect(roomRuns.count == 2)
        #expect((roomRuns[0]["map"] as? [String: Any])?["track_id"] as? String == "kitchen")
        #expect((roomRuns[1]["map"] as? [String: Any])?["rank_id"] as? String == "floor")
        #expect(throws: (any Error).self) { try RobotCommand.build(.start, generation: "neato.gen4", zoneIDs: ["orphan"]) }
        #expect(throws: (any Error).self) { try RobotCommand.build(.start, generation: "neato.gen3", mapID: "floor", zoneIDs: ["a", "b"]) }
        #expect(try RobotCommand.build(.stop, generation: "neato.gen4")["ability"] as? String == "cleaning.cancel")
        #expect(try RobotCommand.build(.stop, generation: "neato.gen3")["cmd"] as? String == "stopCleaning")
    }
    @Test func testRLERejectsTruncationOverflowAndHugeDimensions() throws {
        func raster(_ width: Int, _ height: Int, _ rle: [[Int]]) throws -> MapRaster {
            try JSONDecoder().decode(MapRaster.self, from: JSONSerialization.data(withJSONObject: ["width":width,"height":height,"rle":rle,"legend":[:]]))
        }
        #expect(throws: (any Error).self) { try raster(2, 2, [[1, 5]]).pixels() }
        #expect(throws: (any Error).self) { try raster(2, 2, [[1, 3]]).pixels() }
        #expect(throws: (any Error).self) { try raster(Int.max, 2, []).pixels() }
        #expect(throws: (any Error).self) { try raster(2, 2, [[1, -2]]).pixels() }
        #expect(try raster(2, 2, [[1, 2], [2, 2]]).pixels() == [1, 1, 2, 2])
    }
    @Test func testSyntheticMapRasterAndDockCoordinateConversion() throws {
        let raster = try JSONDecoder().decode(MapRaster.self, from: fixture("floor-map"))
        #expect(try raster.pixels().count == 4_000_000)
        let dock = try #require(raster.dock)
        #expect(abs(dock.x - 0.5) < 0.000001)
        #expect(abs(dock.y - 0.5) < 0.000001)
    }
    @Test func testNoGoAndDisabledZonesAreNeverRooms() throws {
        let data = Data("""
        [{"id":"a","name":"Kitchen","type":"polygon","function":"cleaning","enabled":true,"vertices":[[0,0],[1,0],[1,1]]},
        {"id":"b","name":"No go","type":"polygon","function":"nogo","enabled":true,"vertices":[[0,0],[1,0],[1,1]]},
        {"id":"c","name":"Disabled","type":"polygon","function":"cleaning","enabled":false,"vertices":[[0,0],[1,0],[1,1]]},
        {"id":"d","name":"Invalid","type":"polygon","function":"cleaning","enabled":true,"vertices":[[0,0],[2,0],[1,1]]}]
        """.utf8)
        #expect(try JSONDecoder().decode([Boundary].self, from: data).filter(\.isRoom).map(\.id) == ["a"])
    }
    @Test func testHTTP200DoesNotHideRobotRejection() throws {
        let response = try #require(HTTPURLResponse(url: URL(string: "http://vacuula.local")!, statusCode: 200, httpVersion: nil, headerFields: nil))
        #expect(throws: (any Error).self) { try VacuulaAPI.validate(data: Data("{\"code\":400,\"body\":{}}".utf8), response: response) }
        #expect(throws: (any Error).self) { try VacuulaAPI.validate(data: Data("{\"result\":\"not_available\"}".utf8), response: response) }
        try VacuulaAPI.validate(data: Data("{\"code\":200,\"body\":{}}".utf8), response: response)
    }
}
