import OnePlusUI
import SwiftUI

struct TaskManagerRemoteMenuCard: View {
    let profiles: [SystemMonitorRemoteProfile]
    @ObservedObject private var sessions = SystemMonitorRemoteSessions.shared
    @Environment(\.onePlusIsVisible) private var isVisible
    @State private var owner = UUID().uuidString
    private var shownProfiles: [SystemMonitorRemoteProfile] { sessions.savedProfiles ?? profiles }

    private var hostIDs: Set<String> { Set(shownProfiles.map(\.id)) }

    var body: some View {
        content
            .onChange(of: isVisible, initial: true) { _, visible in
                sessions.setVisible(visible ? hostIDs : [], owner: owner)
            }
            .onChange(of: hostIDs) { _, ids in
                sessions.setVisible(isVisible ? ids : [], owner: owner)
            }
            .onDisappear { sessions.setVisible([], owner: owner) }
    }

    @ViewBuilder
    private var content: some View {
        if shownProfiles.isEmpty {
            OnePlusMenuTile(span: 3, height: 51, textured: false, action: openRemoteStats) {
                HStack(spacing: 9) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 10))
                        .foregroundStyle(OnePlusColor.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No remote hosts").onePlusText(.row)
                        Text("Add a Mac, Windows, or Linux computer")
                            .onePlusText(.caption)
                    }
                    Spacer()
                    Text("Add  →").onePlusText(.caption)
                }
            }
        } else {
            LazyVStack(spacing: 6) {
                ForEach(shownProfiles) { profile in
                    remoteCard(profile)
                }
            }
        }
    }

    private func remoteCard(_ profile: SystemMonitorRemoteProfile) -> some View {
        let state = sessions.state(for: profile.id)
        let reading = state.reading
        return OnePlusMenuItemCard(
            profile.name,
            systemImage: "server.rack",
            status: state.phase.rawValue,
            online: state.phase == .connected,
            metrics: [
                OnePlusMenuMetric("CPU", systemImage: "cpu", value: reading?.cpuPercent.map { "\(Int($0.rounded()))%" } ?? "—"),
                OnePlusMenuMetric("RAM", systemImage: "memorychip", value: reading.map { "\(TaskManagerRemoteCard.shortBytes($0.memoryUsed))/\(TaskManagerRemoteCard.shortBytes($0.memoryTotal))" } ?? "—"),
                OnePlusMenuMetric("Network", systemImage: "arrow.up.arrow.down", value: reading.map { "↓\($0.download.map(TaskManagerRemoteCard.shortRate) ?? "—") ↑\($0.upload.map(TaskManagerRemoteCard.shortRate) ?? "—")" } ?? "—", unit: reading == nil ? "" : "/s"),
            ]
        ) {
            VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
                if let used = reading?.diskUsed, let total = reading?.diskTotal, total > 0 {
                    OnePlusUsageBar(value: Double(used) / Double(total))
                    Text("\(TrayPopoverLayout.diskBytes(Int64(clamping: total - used))) free").onePlusText(.caption)
                } else if state.reason == nil { Text("No disk data").onePlusText(.caption) }
                if let reason = state.reason { Text(reason).onePlusText(.caption).lineLimit(2).help(reason) }
                Button(state.phase == .offline ? "Connect" : "Disconnect") {
                    if state.phase == .offline { sessions.connect(profile) } else { sessions.disconnect(profile.id) }
                }.buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
                    .accessibilityLabel("\(state.phase == .offline ? "Connect to" : "Disconnect from") \(profile.name)")
            }
        } actions: {
            Button { SystemMonitorRemoteTerminal.open(profile) } label: {
                remoteActionLabel("Open SSH", symbol: "arrow.up.right.square")
            }
                .buttonStyle(OnePlusInteractionStyle(radius: 0))
                .accessibilityLabel("Open SSH for \(profile.name)")
                .help("Open SSH for \(profile.name)")
            OnePlusColor.lineSoft.frame(height: 1)
            Button { sessions.selectedID = profile.id; openRemoteStats() } label: {
                remoteActionLabel("Open App", symbol: "arrow.right")
            }
                .buttonStyle(OnePlusInteractionStyle(radius: 0))
                .accessibilityLabel("Open Task Manager for \(profile.name)")
                .help("Open \(profile.name) in Task Manager")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(profile.name), \(profile.platform.rawValue), \(state.phase.rawValue)")
    }

    private func remoteActionLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.system(size: 8.5)).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: symbol).font(.system(size: 9)).accessibilityHidden(true)
        }
        .foregroundStyle(OnePlusColor.secondary)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openRemoteStats() {
        UserDefaults.standard.set("remote", forKey: "systemMonitor.windowPage")
        ToolActionRouter.shared.open(toolID: "system-monitor")
    }
}
