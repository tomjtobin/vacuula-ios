import Foundation
import Testing
@testable import VacuulaCore

struct CleaningPreferencesTests {
    @Test func remembersBothOptionsAcrossPreferenceStoreInstances() throws {
        let suite = "VacuulaPreferencesTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let server = try #require(URL(string: "http://vacuula.local"))
        let turbo = CleaningPreferences(mode: "turbo", gentle: true)
        turbo.save(defaults: defaults, server: server, robotID: "robot-a")
        let reopened = try #require(UserDefaults(suiteName: suite))
        #expect(CleaningPreferences.load(defaults: reopened, server: server, robotID: "robot-a") == turbo)
        CleaningPreferences(mode: "eco", gentle: false).save(defaults: reopened, server: server, robotID: "robot-a")
        #expect(CleaningPreferences.load(defaults: defaults, server: server, robotID: "robot-a") == .init())
    }
    @Test func choicesAreIsolatedByRobotAndServer() throws {
        let suite = "VacuulaPreferencesTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = try #require(URL(string: "http://one.local"))
        let second = try #require(URL(string: "http://two.local"))
        CleaningPreferences(mode: "turbo", gentle: true).save(defaults: defaults, server: first, robotID: "a")
        #expect(CleaningPreferences.load(defaults: defaults, server: first, robotID: "b") == .init())
        #expect(CleaningPreferences.load(defaults: defaults, server: second, robotID: "a") == .init())
        #expect(CleaningPreferences(mode: "invalid", gentle: true).mode == "eco")
    }
    @Test func startSourcesAreReportedWithoutGuessingScheduleIdentity() throws {
        for (source, symbol) in [("app", "iphone"), ("button", "hand.tap"), ("schedule", "calendar"), ("internal", "robotic.vacuum"), ("future", "questionmark.circle")] {
            let run = try JSONDecoder().decode(CleaningRecord.self, from: Data("{\"id\":\"a\",\"robot\":\"r\",\"started_by\":\"\(source)\"}".utf8))
            #expect(run.sourceSymbol == symbol)
            #expect(run.isScheduled == (source == "schedule"))
        }
    }
}
