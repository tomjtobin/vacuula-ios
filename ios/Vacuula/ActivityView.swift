import SwiftUI
import VacuulaCore

struct ActivityView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                if store.robot?.type != "neato.gen4" {
                    ContentUnavailableView("Activity isn’t available for this robot", systemImage: "bell.slash")
                } else if store.activity.items.isEmpty {
                    if store.activityLoading {
                        ProgressView("Loading activity…")
                    } else if let error = store.activityError {
                        ContentUnavailableView("Activity unavailable", systemImage: "wifi.exclamationmark", description: Text(error))
                        Button("Try again") { Task { await store.refreshActivity() } }
                    } else {
                        ContentUnavailableView("No activity yet", systemImage: "bell", description: Text("Scheduled cleans and robot alerts will appear here."))
                            .accessibilityIdentifier("activity-empty")
                    }
                } else {
                    Text("\(store.activity.items.count) events · \(store.activity.unreadCount) unread")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("activity-unread-count")
                }
            } footer: {
                Text("Past events. Times are recorded by the server.")
            }

            if !store.activity.items.isEmpty {
                Section("Recent activity") {
                    ForEach(store.activity.items) { item in
                        Button { store.markActivityRead(item.id) } label: {
                            ActivityRow(item: item, unread: store.activity.isUnread(item))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(store.activity.isUnread(item) ? "Marks this event as read." : "")
                    }
                }
                if let error = store.activityError {
                    Section { Text(error).foregroundStyle(.secondary) }
                }
            }
            if store.nextActivityCursor != nil {
                Section {
                    Button {
                        Task { await store.refreshActivity(older: true) }
                    } label: {
                        HStack {
                            Text("Load earlier activity")
                            Spacer()
                            if store.activityLoading { ProgressView() }
                        }
                    }.disabled(store.activityLoading)
                }
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                Button("Mark all read", systemImage: "checkmark") { store.markActivityRead() }
                    .disabled(store.activity.unreadCount == 0)
                    .accessibilityIdentifier("mark-all-activity-read")
            }
        }
        .refreshable { await store.refreshActivity() }
        .task { await store.refreshActivity() }
    }
}

private struct ActivityRow: View {
    let item: RobotNotification
    let unread: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.presentation.symbol)
                .foregroundStyle(item.presentation.attention ? Color.orange : Color.teal)
                .font(.title3).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.presentation.title).font(.headline)
                Text(item.presentation.detail).font(.subheadline).foregroundStyle(.secondary)
                if let date = item.date {
                    Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                } else { Text("Time unavailable").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            if unread { Circle().fill(.teal).frame(width: 7, height: 7).accessibilityLabel("Unread") }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("activity-event-\(item.id)")
    }
}

struct ActivityBanner: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: RobotNotification
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { store.openActivity() } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.presentation.symbol)
                        .foregroundStyle(item.presentation.attention ? Color.orange : Color.teal)
                        .font(.title3).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.presentation.title).font(.headline)
                        Text(item.presentation.detail).font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        Text("View activity").font(.caption.weight(.semibold)).foregroundStyle(.teal)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("activity-banner")
            Button("Dismiss", systemImage: "xmark") { store.dismissActivityBanner() }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("dismiss-activity-banner")
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(0.08), lineWidth: 1) }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}
