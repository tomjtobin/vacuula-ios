import SwiftUI
import VacuulaCore

@main
struct VacuulaApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(.teal)
                .preferredColorScheme(store.demo && ProcessInfo.processInfo.arguments.contains("--dark-preview") ? .dark : nil)
                .task { store.start() }
                .task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(20))
                        guard !Task.isCancelled else { return }
                        await store.tick()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.resume() }
                    else if phase == .background { store.suspend() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        if store.demo && ProcessInfo.processInfo.arguments.contains("--button-preview") {
            NavigationStack {
                List {
                    Section("Enabled") {
                        CleaningActionButton(title: "Start cleaning", symbol: "play.fill", enabled: true) {}
                    }
                    Section("Disabled") {
                        CleaningActionButton(title: "Start cleaning", symbol: "play.fill", enabled: false) {}
                    }
                }.navigationTitle("Button appearance")
            }
        } else if store.connection == .connected {
            TabView {
                NavigationStack { RobotView() }
                    .tabItem { Label("Robot", image: "RobotVacuum") }
                NavigationStack { RoomsView() }
                    .id(store.selectedID)
                    .tabItem { Label("Rooms", systemImage: "square.grid.2x2") }
                NavigationStack { ScheduleView() }
                    .id("schedule:" + (store.selectedID ?? ""))
                    .tabItem { Label("Schedule", systemImage: "calendar") }
                NavigationStack { CleaningHistoryView() }
                    .id("history:" + (store.selectedID ?? ""))
                    .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                NavigationStack { SettingsView() }
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if store.demo {
                        HStack {
                            Label("Demo · Sample data", systemImage: "play.rectangle")
                            Spacer()
                            Button("Exit demo") { store.exitDemo() }.accessibilityIdentifier("exit-demo")
                        }.font(.footnote).padding(.horizontal).padding(.vertical, 8)
                            .background(.thinMaterial)
                    }
                    if let item = store.activityBanner { ActivityBanner(item: item) }
                }
            }
            .sheet(isPresented: $store.showActivity) { NavigationStack { ActivityView() } }
        } else {
            NavigationStack { ConnectionView() }
        }
    }
}

struct ConnectionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openURL) private var openURL
    @State private var address = ""
    var body: some View {
        Group {
            switch store.connection {
            case .searching, .connecting:
                VStack(spacing: 24) {
                    Image("RobotVacuum").resizable().scaledToFit().frame(width: 64, height: 64).foregroundStyle(.teal).accessibilityHidden(true)
                    VStack(spacing: 8) {
                        Text(store.connection == .searching ? "Finding your server" : "Connecting to Vacuula")
                            .font(.title2.bold())
                        Text(store.connection == .searching ? "Keep iPhone on the same Wi-Fi network as the server." : "Checking the server and loading your robots.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    ProgressView().accessibilityLabel("Connecting")
                }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .choose:
                List {
                    Section {
                        ForEach(store.candidates, id: \.origin) { server in
                            Button { store.choose(server) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(server.name, systemImage: "server.rack").foregroundStyle(.primary)
                                    Text(server.origin.absoluteString).font(.subheadline).foregroundStyle(.secondary)
                                    if let error = store.candidateErrors[server.origin.absoluteString] { Text(error).font(.caption).foregroundStyle(.secondary) }
                                }.padding(.vertical, 6)
                            }
                        }
                    } header: { Text("Choose a server") } footer: { Text("More than one server may be available on this network. Choose the one that manages your robot.") }
                    if let error = store.connectionMessage { Section { Text(error).foregroundStyle(.secondary) } }
                    Section { Button("Search again", systemImage: "arrow.clockwise") { store.findServers() } }
                }
            case .manual:
                Form {
                    Section {
                        ContentUnavailableView("No servers found", systemImage: "wifi.exclamationmark", description: Text("Check that the server is running and iPhone is on the same Wi-Fi network. Search again or enter the server address."))
                        Button("Search again", systemImage: "arrow.clockwise") { store.findServers() }
                    }
                    Section("Server address") {
                        TextField("vacuula.local or 192.168.1.100", text: $address)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityLabel("Server address")
                            .onSubmit { store.manual(address) }
                        Button("Connect") { store.manual(address) }.disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let error = store.connectionMessage { Section { Text(error).foregroundStyle(.secondary) } }
                }
            case .failed:
                ContentUnavailableView {
                    Label("Discovery unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(store.connectionMessage ?? "Check Wi-Fi and local network access, then try again.")
                } actions: {
                    Button("Try again") { store.findServers() }.buttonStyle(.borderedProminent)
                    Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                }
            case .connected: EmptyView()
            }
        }
        .navigationTitle("Vacuula")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Try demo") { store.enterDemo() }
                    .accessibilityIdentifier("try-demo").disabled(store.pending != nil)
            }
        }
    }
}

struct RobotView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 740 && !dynamicTypeSize.isAccessibilitySize
            List {
                if store.robots.isEmpty {
                    ContentUnavailableView {
                        Label("No robots yet", image: "RobotVacuum")
                    } description: {
                        Text("Connect a robot to this server to see its status here.")
                    }
                    if !store.demo, let url = store.server?.origin.appendingPathComponent("web") { Link("Open server setup", destination: url) }
                } else if let robot = store.robot {
                    if store.robots.count > 1 {
                        Section {
                            Picker("Robot", selection: Binding(get: { store.selectedID ?? "" }, set: { store.select($0) })) {
                                ForEach(store.robots) { robot in Text(robot.name).tag(robot.id) }
                            }.disabled(store.pending != nil)
                        }
                    }
                    Section {
                        let layout = compact ? AnyLayout(HStackLayout(spacing: 16)) : AnyLayout(VStackLayout(spacing: 12))
                        layout {
                            if !dynamicTypeSize.isAccessibilitySize && store.state?.primaryIssue == nil {
                                RobotArtwork(charging: store.state?.charging == true)
                                    .scaleEffect(compact ? 0.58 : 0.8)
                                    .frame(width: compact ? 104 : nil, height: compact ? 88 : 112)
                                    .accessibilityHidden(true)
                            }
                            VStack(alignment: compact ? .leading : .center, spacing: 8) {
                                Text(!robot.connected ? "Robot offline" : store.state?.title ?? "Checking status")
                                    .font(compact ? .title2.bold() : .title.bold())
                                    .multilineTextAlignment(compact ? .leading : .center)
                                if robot.connected, let issue = store.state?.primaryIssue {
                                    if store.state?.state != "error" { Text(issue.title).font(.headline) }
                                    Text(issue.detail).font(.subheadline)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("robot-issue-detail")
                                }
                                if let state = store.state {
                                    Label(state.battery.map { "\($0)% battery" } ?? "Battery unavailable", systemImage: state.charging ? "battery.100percent.bolt" : "battery.75percent")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Status will appear when the robot connects.").foregroundStyle(.secondary)
                                }
                                if let pending = store.pending {
                                    ProgressView(pending).font(.subheadline)
                                } else if robot.connected && !store.isFresh {
                                    Label("Refresh to check the latest status", systemImage: "arrow.clockwise")
                                        .font(.footnote).foregroundStyle(.secondary)
                                } else if let date = store.observedAt {
                                    TimelineView(.periodic(from: .now, by: 15)) { _ in
                                        Text("Updated \(date, style: .relative) ago").font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: compact ? .leading : .center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, compact ? 4 : 10)
                    }.listRowBackground(Color.teal.opacity(0.07))

                    if robot.supported {
                        Section {
                            if let state = store.state {
                                if state.commands.contains(.pause) {
                                    primary("Pause cleaning", symbol: "pause.fill", action: .pause)
                                } else if state.commands.contains(.resume) {
                                    primary("Resume cleaning", symbol: "play.fill", action: .resume)
                                } else {
                                    primary("Start cleaning", symbol: "play.fill", action: .start)
                                }
                                if state.commands.contains(.stop) {
                                    Button(role: .destructive) { store.perform(.stop) } label: { Label("Stop cleaning", systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 44) }
                                        .buttonStyle(.bordered).disabled(!store.canControl)
                                }
                                if !state.docked {
                                    Button { store.perform(.returnToBase) } label: { Label("Return to base", systemImage: "house.fill").frame(maxWidth: .infinity, minHeight: 44) }
                                        .buttonStyle(.bordered).disabled(!store.canControl || !(state.commands.contains(.returnToBase) || state.commands.contains(.pause)))
                                }
                            }
                        } footer: {
                            if store.demo { Text("Preview data. Controls are disabled.") }
                            else if store.readOnly { Text("Read-only preview. Robot controls are disabled.") }
                            else if !robot.connected { Text("The server is available. The robot needs to reconnect before cleaning can start.") }
                            else if store.requiresReconciliation { Text("Refresh the robot’s status before sending another action.") }
                        }
                        Section("Cleaning options") {
                            Picker("Power", selection: $store.mode) {
                                Text("Eco").tag("eco")
                                Text(robot.type == "neato.gen4" ? "Turbo" : "Normal").tag("turbo")
                            }
                            Toggle("Gentle navigation", isOn: $store.gentle)
                                .accessibilityIdentifier("gentle-navigation")
                        }.disabled(store.pending != nil)
                    } else {
                        Section { Text("Controls for this robot model aren’t available in this version.") }
                    }
                    RecentRunsSection()
                    if robot.connected, let issues = store.state?.issues, issues.count > 1 {
                        Section("Also needs attention") {
                            ForEach(Array(issues.dropFirst())) { issue in
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(issue.title, systemImage: "exclamationmark.triangle")
                                    Text(issue.detail).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if let notice = store.notice {
                    Section { Text(notice).font(.subheadline).foregroundStyle(.secondary).accessibilityAddTraits(.updatesFrequently) }
                }
            }
            .listSectionSpacing(16)
        }
        .navigationTitle(store.robot?.name.hasPrefix("gen4-") == true ? "Vacuula" : store.robot?.name ?? "Robot")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await store.refreshHistory() } }
        .onChange(of: store.selectedID) { _, _ in Task { await store.refreshHistory() } }
        .refreshable { await store.refreshInventory(); await store.refresh(); await store.refreshHistory() }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { store.openActivity() } label: {
                    Image(systemName: store.activity.unreadCount > 0 ? "bell.badge" : "bell")
                }
                .accessibilityLabel(store.activity.unreadCount > 0 ? "Activity, \(store.activity.unreadCount) unread" : "Activity")
                .accessibilityIdentifier("activity-button")
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refreshInventory(); await store.refresh(); await store.refreshActivity(); await store.refreshHistory() } }
                    .disabled(store.refreshing || store.pending != nil)
            }
        }
    }
    private func primary(_ title: String, symbol: String, action: RobotAction) -> some View {
        CleaningActionButton(title: title, symbol: symbol,
                             enabled: store.canControl && store.state?.commands.contains(action) == true) {
            store.perform(action)
        }
    }
}

/// Give the symbol and title the same contrast in enabled and disabled states.
struct CleaningActionButton: View {
    let title: String
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(enabled ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(!enabled)
    }
}

struct RobotArtwork: View {
    let charging: Bool
    var body: some View {
        ZStack {
            Ellipse().fill(.teal.opacity(0.10)).frame(width: 180, height: 28).offset(y: 56)
            RoundedRectangle(cornerRadius: 14).fill(.secondary.opacity(0.18)).frame(width: 90, height: 34).offset(y: -51)
            UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 58, bottomTrailingRadius: 58, topTrailingRadius: 24)
                .fill(.background).overlay {
                    UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 58, bottomTrailingRadius: 58, topTrailingRadius: 24)
                        .stroke(.primary.opacity(0.12), lineWidth: 1)
                }.frame(width: 148, height: 126)
            VStack(spacing: 12) {
                Capsule().fill(.primary.opacity(0.12)).frame(width: 92, height: 4)
                Circle().fill(.teal.opacity(0.15)).frame(width: 45, height: 45)
                    .overlay { Circle().stroke(.teal.opacity(0.5), lineWidth: 2).padding(7) }
                Image(systemName: charging ? "bolt.fill" : "power").font(.system(size: 12, weight: .semibold)).foregroundStyle(.teal)
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openURL) private var openURL
    var body: some View {
        Form {
            Section {
                if store.demo { Text("Sample data only. Robot controls are disabled; schedule edits stay in this session.").foregroundStyle(.secondary) }
                Button(store.demo ? "Exit demo" : "Try demo", systemImage: "play.rectangle") {
                    if store.demo { store.exitDemo() } else { store.enterDemo() }
                }.disabled(store.pending != nil)
            } header: { Text("Demo") }
            Section {
                Picker("Rotation", selection: $store.mapRotation) {
                    ForEach(MapRotation.allCases) { rotation in
                        Text(rotation.title).tag(rotation)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Map rotation")
                .accessibilityIdentifier("map-rotation-picker")
            } header: { Text("Maps") } footer: {
                Text("Choose the orientation that matches how you think of your rooms. Applies to all maps on this device.")
            }
            Section("Server") {
                LabeledContent("Name", value: store.server?.name ?? "Vacuula Server")
                    .accessibilityIdentifier("server-name")
                LabeledContent("Address", value: store.server?.origin.host ?? "—")
                if let version = store.serverInfo?.version { LabeledContent("Version", value: version) }
                if let timezone = store.serverInfo?.timezone { LabeledContent("Time zone", value: timezone) }
                Button("Find another server", systemImage: "network") { store.findServers() }.disabled(store.pending != nil || store.demo)
                if !store.demo, let url = store.server?.origin.appendingPathComponent("web") { Link(destination: url) { Label("Open web app", systemImage: "safari") } }
            }
            if let robot = store.robot {
                Section("Robot") {
                    LabeledContent("Name", value: robot.name)
                    LabeledContent("Serial number", value: robot.labelSerial ?? robot.id)
                    LabeledContent("Connection", value: robot.connected ? "Online" : "Offline")
                    if robot.type == "neato.gen3" { Text("Gen3 support needs hardware validation.").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            Section {
                Text("Vacuula connects directly to a server on the local network. Keep iPhone on the same Wi-Fi network as the server.")
                    .foregroundStyle(.secondary)
                Button("Open app settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
            } header: { Text("Local network") }
            Section { LabeledContent("App version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))") }
        }.navigationTitle("Settings")
    }
}
