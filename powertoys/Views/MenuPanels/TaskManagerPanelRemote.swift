import OnePlusUI
import SwiftUI

struct TaskManagerRemoteMenuCard: View {
    let profiles: [SystemMonitorRemoteProfile]

    @ViewBuilder
    var body: some View {
        if profiles.isEmpty {
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
                ForEach(profiles) { profile in
                    remoteCard(profile)
                }
            }
        }
    }

    private func remoteCard(_ profile: SystemMonitorRemoteProfile) -> some View {
        OnePlusMenuItemCard(
            profile.name,
            systemImage: "server.rack",
            status: "Offline",
            online: false,
            metrics: [
                OnePlusMenuMetric("CPU", systemImage: "cpu", value: "—"),
                OnePlusMenuMetric("RAM", systemImage: "memorychip", value: "—"),
                OnePlusMenuMetric("Network", systemImage: "arrow.up.arrow.down", value: "—"),
            ]
        ) {
            Text("No disk data").onePlusText(.caption)
        } actions: {
            Button { SystemMonitorRemoteTerminal.open(profile) } label: {
                remoteActionLabel("Open SSH", symbol: "arrow.up.right.square")
            }
                .buttonStyle(OnePlusInteractionStyle(radius: 0))
                .accessibilityLabel("Open SSH for \(profile.name)")
                .help("Open SSH for \(profile.name)")
            OnePlusColor.lineSoft.frame(height: 1)
            Button(action: openRemoteStats) {
                remoteActionLabel("Open App", symbol: "arrow.right")
            }
                .buttonStyle(OnePlusInteractionStyle(radius: 0))
                .accessibilityLabel("Open Task Manager for \(profile.name)")
                .help("Open \(profile.name) in Task Manager")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(profile.name), \(profile.platform.rawValue), offline")
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
