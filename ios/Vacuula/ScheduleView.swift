import SwiftUI
import VacuulaCore

struct ScheduleView: View {
    @EnvironmentObject private var store: AppStore
    @State private var adding = false
    @State private var editing: CleaningSchedule?
    @State private var deleting: CleaningSchedule?
    var body: some View {
        List {
            if store.robot?.type != "neato.gen4" {
                ContentUnavailableView("Scheduling unavailable", systemImage: "calendar", description: Text("Scheduling is currently available for Gen4 robots."))
            } else {
                if store.robot?.connected != true { Text("Connect the robot to view or change its schedule.").foregroundStyle(.secondary) }
                if store.scheduleLoading {
                    Section {
                        ProgressView("Loading schedule…")
                        Text("Checking the robot’s saved times before changes are available.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.accessibilityIdentifier("schedule-loading")
                } else if let error = store.scheduleError {
                    Section {
                        Label("Schedule unavailable", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                        Text(error).font(.subheadline).foregroundStyle(.secondary)
                        Button("Try again") { store.loadSchedule() }.disabled(store.robot?.connected != true)
                    }.accessibilityIdentifier("schedule-error")
                } else if !store.scheduleLoaded || store.scheduleNeedsRefresh {
                    Section {
                        Label(store.scheduleLoaded ? "Schedule needs refreshing" : "Schedule not loaded", systemImage: "calendar.badge.clock")
                        Text("Saved times will appear after the robot answers. Schedule changes are unavailable until then.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Load schedule") { store.loadSchedule() }.disabled(store.robot?.connected != true)
                    }.accessibilityIdentifier("schedule-incomplete")
                }
                if store.scheduleLoaded {
                    if store.schedules.isEmpty {
                        ContentUnavailableView("No scheduled cleans", systemImage: "calendar", description: Text("Add a time and repeat days to clean automatically."))
                    } else {
                        Section {
                            ForEach(store.schedules, id: \.id) { event in
                                VStack(alignment: .leading, spacing: 8) {
                                    Toggle(isOn: Binding(get: { event.enabled }, set: { enabled in
                                        var changed = event; changed.enabled = enabled
                                        Task { _ = await store.saveSchedule(changed) }
                                    })) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(event.time).font(.title2.bold()).monospacedDigit()
                                            Text(event.repeatDescription).font(.subheadline).foregroundStyle(.secondary)
                                        }
                                    }.tint(store.canEditSchedule ? .teal : .gray).disabled(!store.canEditSchedule || event.id == nil)
                                    HStack {
                                        Button { editing = event } label: { Label("Edit", systemImage: "pencil").foregroundStyle(store.canEditSchedule ? Color.teal : Color.secondary) }
                                        Spacer()
                                        Button(role: .destructive) { deleting = event } label: { Label("Delete", systemImage: "trash").foregroundStyle(store.canEditSchedule ? Color.red : Color.secondary) }
                                    }.buttonStyle(.borderless).disabled(!store.canEditSchedule || event.id == nil)
                                }.padding(.vertical, 4)
                            }
                        } footer: { if !store.scheduleEnabled { Text("The robot reports scheduling is disabled.") } }
                    }
                }
                Section {
                    Button { adding = true } label: {
                        Label("Add schedule", systemImage: "plus")
                            .foregroundStyle(store.canEditSchedule ? Color.teal : Color.secondary)
                    }
                        .disabled(!store.canEditSchedule).accessibilityIdentifier("add-schedule")
                } footer: {
                    Text(store.demo ? "Preview schedules stay in this session. The robot is not changed." : store.readOnly ? "Read-only preview. Schedule changes are disabled." : "Schedules repeat every week. Leave the robot charged on its base before the scheduled time.")
                }
                RecentRunsSection(scheduledOnly: true)
                Section {
                    LabeledContent("Time zone", value: store.serverInfo?.timezone ?? "Robot’s configured time zone")
                } footer: { Text("Choose the time at the robot’s location. Saving a schedule does not start cleaning immediately. Scheduled outcomes appear in Activity when the robot reports them.") }
            }
        }
        .navigationTitle("Schedule")
        .onAppear { store.loadSchedule(); Task { await store.refreshHistory() } }
        .refreshable { await store.refreshSchedule(); await store.refreshHistory() }
        .onChange(of: store.isActive) { _, active in
            if active { store.loadSchedule(); Task { await store.refreshHistory() } }
        }
        .toolbar {
            Button { store.loadSchedule() } label: {
                Label("Refresh schedule", systemImage: "arrow.clockwise")
                    .foregroundStyle(store.scheduleLoading || store.pending != nil || store.robot?.connected != true ? Color.secondary : Color.teal)
            }
                .disabled(store.scheduleLoading || store.pending != nil || store.robot?.connected != true)
        }
        .sheet(isPresented: $adding) { NavigationStack { ScheduleEditor() } }
        .sheet(item: $editing) { event in NavigationStack { ScheduleEditor(original: event) } }
        .confirmationDialog("Delete this repeating schedule?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete schedule", role: .destructive) {
                if let id = deleting?.id { Task { _ = await store.saveSchedule(nil, deleting: id) } }
                deleting = nil
            }
        }
    }
}

struct ScheduleEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var original: CleaningSchedule? = nil
    @State private var time = Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: 9))!
    @State private var days = Set<ScheduleDay>()
    @State private var enabled = true
    @State private var mode = "eco"
    @State private var gentle = false
    @State private var floors = [FloorMap]()
    @State private var mapID = ""
    @State private var rooms = [Boundary]()
    @State private var zones = Set<String>()
    @State private var mapsReady = false
    @State private var roomsLoading = false
    @State private var roomsError: String?
    @State private var error: String?
    @State private var saving = false
    private var canSave: Bool { !days.isEmpty && mapsReady && !roomsLoading && !saving && store.canEditSchedule }
    var body: some View {
        Form {
            Section {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                Toggle("Enabled", isOn: $enabled)
            } footer: { Text("Time at the robot’s location: \(store.serverInfo?.timezone ?? "robot’s configured time zone").") }
            Section("Repeat") {
                ForEach(ScheduleDay.allCases) { day in
                    Button {
                        days = days.contains(day) ? days.subtracting([day]) : days.union([day])
                    } label: {
                        HStack {
                            Text(day.title).foregroundStyle(.primary)
                            Spacer()
                            if days.contains(day) { Image(systemName: "checkmark").foregroundStyle(.teal) }
                        }.frame(maxWidth: .infinity, minHeight: 28).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("schedule-day-" + day.rawValue)
                    .accessibilityValue(days.contains(day) ? "Selected" : "Not selected")
                }
            }
            if original == nil {
                Section {
                    Picker("Power", selection: $mode) { Text("Eco").tag("eco"); Text("Turbo").tag("turbo") }
                    Toggle("Gentle navigation", isOn: $gentle)
                    if !mapsReady { ProgressView("Loading saved maps…") }
                    else {
                        Picker("Saved map", selection: $mapID) {
                            Text("Without a map").tag("")
                            ForEach(floors) { floor in Text(floor.displayName).tag(floor.id) }
                        }
                    }
                } header: { Text("Cleaning options") } footer: { Text(mapID.isEmpty ? "Cleaning without a saved map cannot use saved no-go areas or rooms." : "Saved no-go areas are applied. Leave all rooms unselected to clean the whole floor.") }
                if !mapID.isEmpty {
                    Section("Rooms") {
                        if roomsLoading { ProgressView("Loading rooms…") }
                        else if let roomsError { Text(roomsError).foregroundStyle(.secondary) }
                        else if rooms.isEmpty { Text("No cleaning zones configured. The whole floor will be cleaned.").foregroundStyle(.secondary) }
                        else {
                            ForEach(rooms) { room in
                                Toggle(room.name, isOn: Binding(get: { zones.contains(room.id) }, set: { selected in
                                    if selected { zones.insert(room.id) } else { zones.remove(room.id) }
                                }))
                            }
                        }
                    }
                }
            } else {
                Section { Text("This edit keeps the schedule’s existing map, rooms, power and navigation settings. To change those options, create a replacement schedule.").foregroundStyle(.secondary) }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if let error = store.scheduleError { Section { Text(error).foregroundStyle(.secondary) } }
            if store.scheduleNeedsRefresh {
                Button("Refresh saved schedules") { Task { await store.refreshSchedule(); if !store.scheduleNeedsRefresh { dismiss() } } }.disabled(saving || store.pending != nil)
            }
            Section { Text("Repeats weekly on the selected days. You can turn it off or delete it after testing Activity.").foregroundStyle(.secondary) }
        }
        .disabled(saving)
        .navigationTitle(original == nil ? "New schedule" : "Edit schedule")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(saving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .foregroundStyle(canSave ? Color.teal : Color.secondary)
                    .disabled(!canSave)
                    .accessibilityIdentifier("save-schedule")
            }
        }
        .task {
            if let original {
                days = Set(original.days); enabled = original.enabled
                let parts = original.time.split(separator: ":").compactMap { Int($0) }
                if parts.count == 2, let value = Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: parts[0], minute: parts[1])) { time = value }
                mapsReady = true
            } else {
                mode = store.mode; gentle = store.gentle
                if store.demo {
                    floors = store.maps
                    mapID = floors.first?.id ?? ""; mapsReady = true
                    return
                }
                guard let api = store.api, let robot = store.robot else { return }
                do {
                    floors = try await api.maps(robot).filter { $0.canClean(generation: robot.type) }
                    mapID = floors.first?.id ?? ""; mapsReady = true
                } catch { self.error = "Couldn’t load maps. Close this form and try again. " + error.localizedDescription }
            }
        }
        .task(id: mapID) { await loadRooms() }
    }
    private func loadRooms() async {
        zones = []; rooms = []; roomsError = nil; roomsLoading = false
        if store.demo {
            if !mapID.isEmpty { rooms = (try? DemoContent.boundaries().filter(\.isRoom)) ?? [] }
            return
        }
        guard let floor = floors.first(where: { $0.id == mapID }), let robot = store.robot, let api = store.api else { return }
        roomsLoading = true
        defer { if !Task.isCancelled { roomsLoading = false } }
        do {
            let value = try await api.boundaries(robot, map: floor)
            guard !Task.isCancelled else { return }
            rooms = value.filter(\.isRoom)
        } catch { if !Task.isCancelled { roomsError = "Rooms couldn’t be loaded. This schedule will clean the whole floor." } }
    }
    private func save() async {
        let selectedRobot = store.selectedID
        let selectedServer = store.server?.origin
        saving = true; error = nil
        defer { saving = false }
        do {
            let components = Calendar.current.dateComponents([.hour, .minute], from: time)
            let text = String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
            let ordered = ScheduleDay.allCases.filter { days.contains($0) }
            var event: CleaningSchedule
            if let original { event = original; event.time = text; event.days = ordered }
            else {
                if !store.demo, !mapID.isEmpty, let api = store.api, let robot = store.robot {
                    let current = try await api.maps(robot)
                    guard let floor = current.first(where: { $0.id == mapID && $0.canClean(generation: robot.type) }) else {
                        throw ClientError.message("The saved map changed. Close this form and load it again.")
                    }
                    if !zones.isEmpty {
                        let boundaries = try await api.boundaries(robot, map: floor)
                        guard zones.isSubset(of: Set(boundaries.filter(\.isRoom).map(\.id))) else {
                            throw ClientError.message("The rooms changed. Close this form and select them again.")
                        }
                    }
                }
                event = try CleaningSchedule.create(days: ordered, time: text, mode: mode, gentle: gentle, mapID: mapID.isEmpty ? nil : mapID, zoneIDs: zones.sorted())
            }
            event.enabled = enabled
            guard store.selectedID == selectedRobot, store.server?.origin == selectedServer else {
                throw ClientError.message("The selected robot changed. Close this form and try again.")
            }
            if await store.saveSchedule(event) { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}
