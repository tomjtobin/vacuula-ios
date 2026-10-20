import Foundation

/// Shared sample data for the in-app demo and offline tests. No server address,
/// credentials or real floor geometry is stored in these fixtures.
public enum DemoContent {
    public static func floor() throws -> FloorMap {
        try JSONDecoder().decode(FloorMap.self, from: Data(#"{"id":"preview-map","name":"Preview floor","promoted":true}"#.utf8))
    }
    public static func raster() throws -> MapRaster {
        // Seven-by-seven grid: wall border around a 25 m² open room.
        var cells = [Int]()
        for y in 0..<7 { for x in 0..<7 { cells.append(x == 0 || x == 6 || y == 0 || y == 6 ? 2 : 1) } }
        var runs = [[Int]]()
        for cell in cells {
            if runs.last?.first == cell { runs[runs.count - 1][1] += 1 }
            else { runs.append([cell, 1]) }
        }
        let data = try JSONSerialization.data(withJSONObject: ["width":7,"height":7,"legend":["0":"unknown","1":"free","2":"wall"],"rle":runs,"metadata":["origin_x":0,"origin_y":0,"resolution":1000],"img_size":[7,7],"base":[1500,3500,0]] as [String:Any])
        return try JSONDecoder().decode(MapRaster.self, from:data)
    }
    public static func boundaries() throws -> [Boundary] {
        try JSONDecoder().decode([Boundary].self, from: Data(##"[{"id":"room","name":"Preview room","type":"polygon","function":"cleaning","enabled":true,"color":"#00aabb","vertices":[[0.14,0.14],[0.5,0.14],[0.5,0.86],[0.14,0.86]]},{"id":"nogo","name":"No-go","type":"polygon","function":"nogo","enabled":true,"vertices":[[0.72,0.72],[0.86,0.72],[0.86,0.86],[0.72,0.86]]}]"##.utf8))
    }
    public static func history() throws -> [CleaningRecord] {
        try JSONDecoder().decode([CleaningRecord].self, from: Data(#"[{"id":"preview-done","robot":"preview","started_by":"app","cleaning_complete":true,"battery_consumed":12,"timing":{"start":"2026-10-18T16:00:00Z","end":"2026-10-18T16:28:00Z"},"runs":[{"track_uuid":"","state":"done","stats":{"area":22},"settings":{"mode":"turbo","navigation_mode":"normal"}}]},{"id":"preview-cancelled","robot":"preview","started_by":"schedule","cleaning_complete":true,"timing":{"start":"2026-10-19T08:40:00Z","end":"2026-10-19T08:42:32Z"},"runs":[{"track_uuid":"","state":"canceled","stats":{"area":1.28}}]},{"id":"preview-room","robot":"preview","started_by":"schedule","cleaning_complete":true,"timing":{"start":"2026-10-18T13:00:00Z","end":"2026-10-18T13:15:00Z"},"runs":[{"track_uuid":"room","state":"done","stats":{"area":8},"settings":{"mode":"eco","navigation_mode":"gentle"}}]}]"#.utf8))
    }
    public static func schedules() throws -> [CleaningSchedule] {
        var event = try CleaningSchedule.create(days:[.mon,.wed,.fri],time:"09:00",mode:"eco",gentle:true,mapID:"preview-map",zoneIDs:["room"])
        event.id = "preview-schedule"
        return [event]
    }
}
