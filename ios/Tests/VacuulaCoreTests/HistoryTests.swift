import Foundation
import Testing
@testable import VacuulaCore

struct HistoryTests {
    private func record(id: String = "a", start: String = "2026-10-19T08:40:00Z", end: String = "2026-10-19T08:42:00Z", state: String = "done", area: String = "22", track: String = "", complete: Bool = true) throws -> CleaningRecord {
        try JSONDecoder().decode(CleaningRecord.self, from: Data("""
        {"id":"\(id)","robot":"r","started_by":"schedule","cleaning_complete":\(complete),"battery_consumed":12,"timing":{"start":"\(start)","end":"\(end)"},"runs":[{"track_uuid":"\(track)","state":"\(state)","stats":{"area":\(area)}}]}
        """.utf8))
    }
    @Test func exampleSnapshotsBecomeSixDistinctCleans() throws {
        let url = try #require(Bundle.module.url(forResource: "gen4-runs", withExtension: "json", subdirectory: "Fixtures"))
        let raw = try JSONDecoder().decode([CleaningRecord].self, from: Data(contentsOf: url))
        #expect(raw.count == 10)
        let sessions = CleaningRecord.sessions(raw, robot: "EXAMPLE-ROBOT-001")
        #expect(sessions.count == 6)
        #expect(sessions.first?.id == "00000000-0000-4000-8000-000000000010")
        #expect(sessions.first?.outcome == "Cancelled")
        #expect(sessions.first?.source == "Schedule")
        let turbo = try #require(sessions.first { $0.id == "00000000-0000-4000-8000-000000000006" })
        #expect(abs(try #require(turbo.squareFeet) - 236.8753) < 0.01)
        #expect(turbo.timing?.duration == 1722)
        #expect(turbo.batteryUsed == 12)
        #expect(CleaningRecord.sessions(raw, robot: "other").isEmpty)
    }
    @Test func cancelledIsNotCompletedEvenWhenFirmwareClosesTheClean() throws {
        #expect(try record(state: "canceled", complete: true).outcome == "Cancelled")
        #expect(try record(state: "not_reachable", complete: true).outcome == "Needs attention")
        #expect(try record(state: "paused", complete: false).outcome == "Paused snapshot")
        #expect(try record(state: "done").outcome == "Completed")
    }
    @Test func snapshotSelectionIsStableAndDoesNotAddAreasTogether() throws {
        let partial = try record(id: "partial", end: "2026-10-19T08:41:00Z", state: "paused", area: "1", complete: false)
        let final = try record(id: "final", area: "2")
        #expect(CleaningRecord.sessions([partial, final], robot: "r").map(\.id) == ["final"])
        #expect(CleaningRecord.sessions([final, partial], robot: "r").map(\.id) == ["final"])
        #expect(CleaningRecord.sessions([partial, final], robot: "r").first?.squareMetres == 2)
        #expect(try record(start: "bad").timing?.duration == nil)
        #expect(try record(end: "2026-10-19T08:39:00Z").timing?.duration == nil)
    }
    @Test func cancelledRequestsAreNotUserFacingErrors() {
        #expect(RequestFailure.isCancellation(CancellationError()))
        #expect(RequestFailure.isCancellation(URLError(.cancelled)))
        #expect(!RequestFailure.isCancellation(URLError(.timedOut)))
    }
}
