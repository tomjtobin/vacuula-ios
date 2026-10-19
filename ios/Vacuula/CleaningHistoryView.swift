import SwiftUI
import VacuulaCore

struct CleaningHistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var settingTarget = false
    var scheduledOnly = false
    private var records: [CleaningRecord] { scheduledOnly ? store.cleaningHistory.filter(\.isScheduled) : store.cleaningHistory }
    var body: some View {
        List {
            if store.robot?.type != "neato.gen4" {
                ContentUnavailableView("History unavailable", systemImage: "clock", description: Text("Cleaning history is currently available for Gen4 robots."))
            } else {
                if store.historyLoading { ProgressView("Loading cleaning history…") }
                if let error = store.historyError {
                    Section {
                        Label("History unavailable", systemImage: "wifi.exclamationmark")
                        Text(error).foregroundStyle(.secondary)
                        Button("Try again") { Task { await store.refreshHistory() } }
                    }
                } else if !store.historyLoaded && !store.historyLoading {
                    Text("Previous cleans will appear when the server answers.").foregroundStyle(.secondary)
                }
                if store.historyLoaded {
                    if records.isEmpty {
                        ContentUnavailableView("No previous cleans", systemImage: "clock", description: Text("Run statistics appear after the robot uploads them to the server."))
                    } else {
                        Section {
                            LabeledContent("Cleans recorded", value: records.count.formatted())
                            if let last = records.first {
                                LabeledContent("Latest cleaned area", value: areaText(last.squareFeet))
                                if let percent = last.areaPercentage(expectedSquareFeet: store.expectedAreaSquareFeet) {
                                    LabeledContent("Latest area vs target", value: percentText(percent))
                                }
                            }
                        } footer: { Text(scheduledOnly ? "Runs started by any schedule. The robot’s records do not identify the individual schedule." : "Intermediate snapshots of the same clean are combined. Statistics reflect the latest uploaded record, not live progress.") }
                        Section("Previous cleans") {
                            ForEach(records) { record in
                                NavigationLink {
                                    CleaningRecordView(record: record)
                                } label: {
                                    CleaningRecordRow(record: record, target: store.expectedAreaSquareFeet)
                                }.accessibilityIdentifier("cleaning-record-" + record.id)
                            }
                        }
                    }
                }
                Section {
                    Button { settingTarget = true } label: {
                        LabeledContent("Whole-floor target", value: store.expectedAreaSquareFeet.map { areaText($0) } ?? "Set area")
                    }.accessibilityIdentifier("expected-area-button")
                } footer: { Text("The robot reports cleaned area in square metres, shown here in square feet. Set the expected cleanable whole-floor area to compare runs. Room cleans are not compared with this target.") }
            }
        }
        .navigationTitle(scheduledOnly ? "Scheduled cleans" : "Cleaning history")
        .onAppear { Task { await store.refreshHistory() } }
        .onChange(of: store.isActive) { _, active in if active { Task { await store.refreshHistory() } } }
        .refreshable { await store.refreshHistory() }
        .toolbar {
            Button("Refresh history", systemImage: "arrow.clockwise") { Task { await store.refreshHistory() } }
                .disabled(store.historyLoading)
        }
        .sheet(isPresented: $settingTarget) { NavigationStack { ExpectedAreaEditor() } }
    }
}

struct CleaningRecordRow: View {
    let record: CleaningRecord
    let target: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let date = record.startDate { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.headline) }
            else { Text("Date unavailable").font(.headline) }
            Label(record.outcome + " · " + record.source, systemImage: record.sourceSymbol)
                .font(.subheadline).foregroundStyle(.secondary)
            Text(areaText(record.squareFeet) + " · " + durationText(record.timing?.duration)).font(.subheadline)
            if let percent = record.areaPercentage(expectedSquareFeet: target) {
                Text(percentText(percent) + " of expected area").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text(record.isWholeFloor ? "Set expected area to show %" : "Whole-floor % unavailable for this scope")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}

struct RecentRunsSection: View {
    @EnvironmentObject private var store: AppStore
    var scheduledOnly = false
    private var records: [CleaningRecord] { scheduledOnly ? store.cleaningHistory.filter(\.isScheduled) : store.cleaningHistory }
    var body: some View {
        if store.robot?.type == "neato.gen4" {
            Section {
                if store.historyLoading && !store.historyLoaded { ProgressView("Loading previous cleans…") }
                else if let error = store.historyError {
                    Text(error).font(.subheadline).foregroundStyle(.secondary)
                    Button("Try again") { Task { await store.refreshHistory() } }
                } else if !store.historyLoaded { Text("Previous cleans haven’t loaded yet.").foregroundStyle(.secondary) }
                else if records.isEmpty { Text(scheduledOnly ? "No scheduled runs recorded yet." : "No previous cleans recorded yet.").foregroundStyle(.secondary) }
                ForEach(Array(records.prefix(3))) { record in
                    NavigationLink { CleaningRecordView(record: record) } label: {
                        CleaningRecordRow(record: record, target: store.expectedAreaSquareFeet)
                    }.accessibilityIdentifier((scheduledOnly ? "scheduled-recent-" : "home-recent-") + record.id)
                }
                NavigationLink { CleaningHistoryView(scheduledOnly: scheduledOnly) } label: {
                    Text(scheduledOnly ? "All scheduled cleans and area target" : "All cleans and area target")
                }
            } header: { Text(scheduledOnly ? "Scheduled runs" : "Recent cleans") } footer: {
                Text(scheduledOnly ? "Includes runs started by any schedule; records do not identify which one. Percentages compare reported area with your whole-floor target." : "Start source, elapsed time and reported area. Percentages compare with your whole-floor target, rather than measuring unique map coverage.")
            }
        }
    }
}

struct CleaningRecordView: View {
    @EnvironmentObject private var store: AppStore
    let record: CleaningRecord
    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Outcome", value: record.outcome)
                if let date = record.startDate { LabeledContent("Started", value: date.formatted(date: .abbreviated, time: .shortened)) }
                if let date = record.timing?.endDate { LabeledContent("Last recorded", value: date.formatted(date: .abbreviated, time: .shortened)) }
                LabeledContent("Started by", value: record.source)
                LabeledContent("Elapsed time", value: durationText(record.timing?.duration))
                LabeledContent("Cleaned area", value: areaText(record.squareFeet))
                    .accessibilityIdentifier("run-cleaned-area")
                LabeledContent("Battery used", value: record.batteryUsed.map { percentText($0) } ?? "Unavailable")
            }
            Section {
                if let percent = record.areaPercentage(expectedSquareFeet: store.expectedAreaSquareFeet) {
                    LabeledContent("Area vs target", value: percentText(percent)).accessibilityIdentifier("run-area-comparison")
                    LabeledContent("Whole-floor target", value: areaText(store.expectedAreaSquareFeet))
                } else {
                    Text(record.isWholeFloor ? "Set a whole-floor area target in History to compare cleaned area." : "Whole-floor comparison is unavailable for room cleans or records without a cleaning scope.")
                        .foregroundStyle(.secondary)
                }
            } header: { Text("Area comparison") } footer: {
                Text("This compares reported area with your target. It is not measured coverage of every part of the floor: overlapping passes may count more than once, so values can exceed 100%. A cancelled clean is not treated as completed.")
            }
            Section("Cleaning segments") {
                ForEach(Array((record.runs ?? []).enumerated()), id: \.offset) { index, pass in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Segment \(index + 1)").font(.headline)
                        Text((pass.state ?? "Unknown").replacingOccurrences(of: "_", with: " ").capitalized)
                        LabeledContent("Area", value: areaText(pass.stats?.area.map { $0 * 10.7639104167 }))
                        LabeledContent("Elapsed time", value: durationText(pass.timing?.duration))
                        if let mode = pass.settings?.mode { LabeledContent("Power", value: mode.capitalized) }
                        if let mode = pass.settings?.navigation_mode { LabeledContent("Navigation", value: mode.capitalized) }
                        if let docked = pass.autonomous_dock { LabeledContent("Returned to base", value: docked ? "Yes" : "No") }
                        if let pickups = pass.stats?.pickup_count { LabeledContent("Times picked up", value: pickups.formatted()) }
                    }.padding(.vertical, 4)
                }
            }
        }.navigationTitle("Clean details").navigationBarTitleDisplayMode(.inline)
    }
}

struct ExpectedAreaEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    private var value: Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite, value > 0, value <= 1_000_000 else { return nil }
        return value
    }
    var body: some View {
        Form {
            Section {
                TextField("Square feet", text: $text).keyboardType(.decimalPad).accessibilityIdentifier("expected-area-input")
            } header: { Text("Expected cleanable area (sq ft)") } footer: {
                Text("Enter the whole-floor area you expect the robot to clean, excluding areas it cannot reach. This target is saved on this device for this robot and server. It does not change the robot’s map or schedule.")
            }
            if store.expectedAreaSquareFeet != nil { Button("Remove target", role: .destructive) { store.setExpectedArea(nil); dismiss() } }
        }
        .navigationTitle("Area target").navigationBarTitleDisplayMode(.inline)
        .onAppear { text = store.expectedAreaSquareFeet.map { String($0) } ?? "" }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { store.setExpectedArea(value); dismiss() }
                    .foregroundStyle(value == nil ? Color.secondary : Color.teal).disabled(value == nil)
                    .accessibilityIdentifier("save-area-target")
            }
        }
    }
}

private func areaText(_ value: Double?) -> String {
    guard let value, value.isFinite, value >= 0 else { return "Unavailable" }
    return value.formatted(.number.precision(.fractionLength(0))) + " sq ft"
}
private func percentText(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) + "%" }
private func durationText(_ value: TimeInterval?) -> String {
    guard let value, value.isFinite, value >= 0 else { return "Time unavailable" }
    let seconds = Int(min(value, 315_360_000))
    if seconds >= 3600 { return "\(seconds / 3600) hr \((seconds % 3600) / 60) min" }
    return "\(seconds / 60) min \(seconds % 60) sec"
}
