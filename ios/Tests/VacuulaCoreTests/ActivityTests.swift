import Foundation
import Testing
@testable import VacuulaCore

struct ActivityTests {
    func item(_ id: Int64, robot: String = "robot-a", code: String = "routine_cleaning_start") -> RobotNotification {
        .init(id: id, robot: robot, messageCode: code, receivedAt: "2026-10-18T20:00:00Z")
    }
    @Test func historyAndLiveEventUseTheSameModel() throws {
        let json = """
        {"id":42,"robot":"robot-a","message_code":"nav_floorplan_zone_unreachable","payload":{"zone_name":"Kitchen","future":{"count":3,"enabled":true,"array":[null,"value"]}},"received_at":"2026-10-18T20:00:00.123456Z"}
        """
        let event = try JSONDecoder().decode(RobotNotification.self, from: Data(json.utf8))
        let page = try JSONDecoder().decode(NotificationPage.self, from: Data("{\"notifications\":[\(json)],\"next_before\":42}".utf8))
        #expect(page.notifications == [event])
        #expect(page.nextBefore == 42)
        #expect(event.date != nil)
        #expect(event.presentation.detail.contains("Kitchen"))
        #expect(try JSONDecoder().decode(RobotNotification.self, from: JSONEncoder().encode(event)) == event)
    }
    @Test func optionalContextAndInvalidDatesRemainReadable() throws {
        let event = try JSONDecoder().decode(RobotNotification.self, from: Data("{\"id\":1,\"robot\":\"robot-a\",\"message_code\":\"new_future_message\",\"received_at\":\"invalid\"}".utf8))
        #expect(event.date == nil)
        #expect(event.presentation.title == "Robot update")
        #expect(!event.presentation.attention)
        #expect(item(2).date != nil)
        #expect(item(3, code: "nav_floorplan_zone_unreachable").presentation.detail.contains("selected room"))
    }
    @Test func scheduleOutcomesAndMapFailuresHaveDifferentMeaning() {
        #expect(!item(1).presentation.attention)
        let offbase = item(2, code: "routine_cleaning_start_offbase_error").presentation
        let battery = item(3, code: "routine_cleaning_start_low_battery_error").presentation
        #expect(offbase.attention && battery.attention)
        #expect(offbase.detail.contains("off its base"))
        #expect(battery.detail.contains("battery was too low"))
        for code in ["persistent_relocalization_fail", "persistent_relocalization_fail_clean", "persistent_relocalization_fail_cancel"] {
            let text = item(4, code: code).presentation
            #expect(text.attention)
            #expect(text.detail.contains("current status"))
            #expect(!text.detail.contains("continues"))
        }
    }
    @Test func mergingHistoryAndSSEDeduplicatesAndSortsWithoutMixingRobots() {
        var feed = ActivityTimeline()
        #expect(feed.merge([item(2), item(1)], robot: "robot-a").count == 2)
        #expect(feed.merge([item(2)], robot: "robot-a").isEmpty)
        #expect(feed.merge([item(3), item(5, robot: "other"), item(-1)], robot: "robot-a").map(\.id) == [3])
        #expect(feed.items.map(\.id) == [3, 2, 1])
    }
    @Test func readMarkersSurviveRefreshAndOutOfOrderArrival() throws {
        var feed = ActivityTimeline()
        feed.merge([item(3), item(1)], robot: "robot-a")
        feed.markAllRead()
        #expect(feed.unreadCount == 0)
        feed.merge([item(2), item(3)], robot: "robot-a")
        #expect(feed.unreadCount == 1) // A late, smaller ID must not be silently marked read.
        let data = try JSONEncoder().encode(Array(feed.readIDs))
        var restored = ActivityTimeline(readIDs: Set(try JSONDecoder().decode([Int64].self, from: data)))
        restored.merge(feed.items, robot: "robot-a")
        #expect(restored.unreadCount == 1)
        restored.markRead(2)
        #expect(restored.unreadCount == 0)
    }
    @Test func malformedNotificationCannotBeTreatedAsStatusOrHistory() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(RobotNotification.self, from: Data("{\"body\":{\"state\":\"idle\"}}".utf8))
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(NotificationPage.self, from: Data("{\"notifications\":\"invalid\",\"next_before\":null}".utf8))
        }
    }
}
