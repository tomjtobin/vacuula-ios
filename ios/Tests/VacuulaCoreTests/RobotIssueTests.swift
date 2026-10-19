import Foundation
import Testing
@testable import VacuulaCore

struct RobotIssueTests {
    @Test func liveBinErrorIsDecodedForBothStatusAndPeerState() throws {
        let body: [String: Any] = ["state": "error", "action": "cleaning", "errors": [["code": "dustbin_missing", "severity": "error"]], "available_commands": ["resume": false, "cancel": true]]
        let poll = try RobotState.decode(JSONSerialization.data(withJSONObject: ["body": body]), generation: "neato.gen4")
        let event = try RobotState.decode(JSONSerialization.data(withJSONObject: ["data": ["to": ["service": "peer.state"], "body": body]]), generation: "neato.gen4", event: true)
        for state in [poll, event] {
            #expect(state.errors == ["dustbin_missing"])
            #expect(state.title == "Dirt bin missing")
            #expect(state.primaryIssue?.detail.contains("Put the dirt bin back in") == true)
            #expect(!state.commands.contains(.resume))
        }
    }
    @Test func clearedErrorReturnsToPausedWithoutClaimingPhysicalCause() throws {
        let paused = try RobotState.decode(Data(#"{"body":{"state":"paused","action":"cleaning","errors":null,"available_commands":{"resume":true}}}"#.utf8), generation: "neato.gen4")
        #expect(paused.title == "Cleaning paused")
        #expect(paused.primaryIssue == nil)
        #expect(paused.commands.contains(.resume))
        let unknown = RobotIssue(code: "new_future_error")
        #expect(unknown.title == "New Future Error")
    }
}
