import AppKit
import OnePlusUI
import SwiftUI

struct SystemMonitorRemoteView: View {
    @State private var profiles = SystemMonitorRemoteProfiles.load()
    @State private var poller = SystemMonitorRemotePoller()
    @State private var connectedID: String?
    @State private var reading: SystemMonitorRemoteReading?
    @State private var history: [SystemMonitorRemoteReading] = []
    @State private var lastUpdated: Date?
    @State private var errorMessage: String?
    @State private var refreshGeneration = 0
    @State private var editor: SystemMonitorRemoteProfile?

    private var activeProfile: SystemMonitorRemoteProfile? {
        profiles.first { $0.id == connectedID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                remoteHeader
                if profiles.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                        spacing: 12
                    ) {
                        ForEach(profiles) { profile in remoteCard(profile) }
                    }
                    connectionSettings
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundStyle(TaskManagerTheme.accent)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(TaskManagerTheme.card,
                                    in: RoundedRectangle(cornerRadius: TaskManagerTheme.panelRadius))
                }
            }
        }
        .thinScrollIndicators()
        .foregroundStyle(TaskManagerTheme.ink)
        .environment(\.colorScheme, .dark)
        .task(id: taskID) { await poll() }
        .onDisappear { disconnect() }
        .sheet(item: $editor) { profile in
            TaskManagerRemoteEditor(
                profile: profile,
                canDelete: profiles.contains { $0.id == profile.id },
                onSave: { updated, connect in save(updated, connect: connect) },
                onDelete: { remove(profile.id) },
                onCancel: { editor = nil }
            )
        }
    }

    private var remoteHeader: some View {
        HStack {
            Text("\(connectedID == nil ? 0 : 1) connected · \(profiles.count) \(profiles.count == 1 ? "host" : "hosts")")
                .font(.system(size: 9))
                .foregroundStyle(TaskManagerTheme.secondary)
            Spacer()
            Button {
                editor = SystemMonitorRemoteProfile(name: "", host: "")
            } label: {
                Label("Add host", systemImage: "plus")
            }
            .taskManagerControl()
            .accessibilityIdentifier("system-monitor.remote.add-host")
        }
    }

    private var emptyState: some View {
        TaskManagerPanel(textured: true) {
            VStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 25))
                    .foregroundStyle(TaskManagerTheme.secondary)
                Text("No remote hosts")
                    .font(.system(size: 13, weight: .medium))
                Text("Add a Linux, macOS, or Windows SSH host. Task Manager connects only when you ask it to.")
                    .font(.system(size: 10))
                    .foregroundStyle(TaskManagerTheme.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Button("Add host") {
                    editor = SystemMonitorRemoteProfile(name: "", host: "")
                }
                .taskManagerControl()
            }
            .frame(maxWidth: .infinity, minHeight: 230)
        }
    }

    private func remoteCard(_ profile: SystemMonitorRemoteProfile) -> some View {
        let active = profile.id == connectedID
        return TaskManagerRemoteCard(
            profile: profile,
            reading: active ? reading : nil,
            state: active ? (reading == nil ? "Connecting" : "Connected") : "Offline",
            history: active ? history : [],
            onTerminal: { openTerminal(profile) },
            primaryTitle: active ? "Disconnect" : "Connect",
            primarySymbol: active ? "stop.circle" : "play.circle",
            onPrimary: { active ? disconnect() : connect(profile.id) }
        )
    }

    private var connectionSettings: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Connection settings")
                .font(.system(size: 11, weight: .medium))
            TaskManagerPanel {
                VStack(spacing: 0) {
                    ForEach(profiles) { profile in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name)
                                    .font(.system(size: 10.5, weight: .medium))
                                Text("\(profile.host) · \(profile.platform.rawValue) · \(intervalTitle(profile.interval))")
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundStyle(TaskManagerTheme.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 12)
                            HStack(spacing: 8) {
                                Button("Configure") { editor = profile }
                                    .taskManagerRemoteButton()
                                    .accessibilityIdentifier("system-monitor.remote.configure.\(profile.id)")
                                Button(profile.id == connectedID ? "Disconnect" : "Connect") {
                                    profile.id == connectedID ? disconnect() : connect(profile.id)
                                }
                                .taskManagerRemoteButton(primary: profile.id != connectedID)
                                .accessibilityIdentifier("system-monitor.remote.connect.\(profile.id)")
                            }
                            .fixedSize()
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 53)
                        if profile.id != profiles.last?.id {
                            Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1)
                        }
                    }

                    if connectedID != nil {
                        Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1)
                        HStack(spacing: 8) {
                            Button {
                                refreshGeneration += 1
                            } label: {
                                Label("Refresh now", systemImage: "arrow.clockwise")
                            }
                            .taskManagerRemoteButton()
                            if let activeProfile {
                                Button {
                                    openTerminal(activeProfile)
                                } label: {
                                    Label("Open Terminal", systemImage: "terminal")
                                }
                                .taskManagerRemoteButton()
                            }
                            Spacer()
                            if let lastUpdated {
                                Text("Updated \(lastUpdated, style: .time)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(TaskManagerTheme.muted)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                    }
                }
            }
        }
    }

    private var taskID: String {
        guard let activeProfile else { return "disconnected" }
        return "\(activeProfile.id):\(activeProfile.host):\(activeProfile.platform.rawValue):\(activeProfile.interval):\(refreshGeneration)"
    }

    private func poll() async {
        guard let activeProfile else { return }
        while !Task.isCancelled {
            do {
                let sample = try await poller.sample(host: activeProfile.host, platform: activeProfile.platform)
                guard !Task.isCancelled, connectedID == activeProfile.id else { return }
                reading = sample
                history.append(sample)
                if history.count > 120 { history.removeFirst(history.count - 120) }
                lastUpdated = Date()
                errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                disconnect()
                return
            }
            guard activeProfile.interval > 0 else { return }
            try? await Task.sleep(for: .seconds(max(activeProfile.interval, 5)))
        }
    }

    private func connect(_ id: String) {
        guard let profile = profiles.first(where: { $0.id == id }),
              SystemMonitorRemoteProtocol.validHost(profile.host) else {
            errorMessage = SystemMonitorRemoteError.unsafeHost.localizedDescription
            return
        }
        if connectedID != nil { disconnect() }
        poller = SystemMonitorRemotePoller()
        connectedID = id
        reading = nil
        history = []
        lastUpdated = nil
        errorMessage = nil
    }

    private func disconnect() {
        let stoppedPoller = poller
        Task { await stoppedPoller.close() }
        connectedID = nil
        reading = nil
        history = []
        lastUpdated = nil
    }

    private func save(_ profile: SystemMonitorRemoteProfile, connect shouldConnect: Bool) {
        guard SystemMonitorRemoteProtocol.validHost(profile.host) else {
            errorMessage = SystemMonitorRemoteError.unsafeHost.localizedDescription
            return
        }
        var profile = profile
        let wasConnected = connectedID == profile.id
        profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if profile.name.isEmpty { profile.name = profile.host }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        SystemMonitorRemoteProfiles.save(profiles)
        editor = nil
        errorMessage = nil
        if wasConnected || shouldConnect { connect(profile.id) }
    }

    private func remove(_ id: String) {
        if connectedID == id { disconnect() }
        profiles.removeAll { $0.id == id }
        SystemMonitorRemoteProfiles.save(profiles)
        editor = nil
    }

    private func openTerminal(_ profile: SystemMonitorRemoteProfile) {
        SystemMonitorRemoteTerminal.open(profile) { error in
            guard let error else { return }
            Task { @MainActor in
                errorMessage = "Could not open Terminal: \(error.localizedDescription)"
            }
        }
    }

    private func intervalTitle(_ seconds: Int) -> String {
        switch seconds {
        case 0: "Manual"
        case 60: "1 minute"
        case 120: "2 minutes"
        case 300: "5 minutes"
        default: "\(seconds) seconds"
        }
    }

}

enum SystemMonitorRemoteTerminal {
    static func open(
        _ profile: SystemMonitorRemoteProfile,
        completion: ((Error?) -> Void)? = nil
    ) {
        guard SystemMonitorRemoteProtocol.validHost(profile.host),
              let address = URL(string: "ssh://\(profile.host)") else { return }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open(
            [address],
            withApplicationAt: terminal,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in completion?(error) }
    }
}

struct TaskManagerRemoteCard: View {
    let profile: SystemMonitorRemoteProfile
    let reading: SystemMonitorRemoteReading?
    let state: String
    var history: [SystemMonitorRemoteReading] = []
    var onTerminal: (() -> Void)?
    let primaryTitle: String
    let primarySymbol: String
    let onPrimary: () -> Void

    var body: some View {
        TaskManagerPanel(textured: true) {
            VStack(spacing: 0) {
                header
                Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1)
                HStack(spacing: 0) {
                    stat("CPU", symbol: "cpu", value: reading?.cpuPercent.map { "\(Int($0.rounded()))%" } ?? "—")
                    divider
                    stat("RAM", symbol: "memorychip", value: memoryReading)
                    divider
                    stat("Network", symbol: "network", value: networkReading)
                }
                Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1)
                HStack(spacing: 0) {
                    diskSummary
                    Rectangle().fill(TaskManagerTheme.lineSoft).frame(width: 1)
                    actions.frame(width: 92)
                }
                if !history.isEmpty {
                    TaskManagerHistoryChart(values: history.compactMap(\.cpuPercent), range: 0...100, compact: true)
                        .frame(height: 38)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "server.rack").font(.system(size: 10)).foregroundStyle(TaskManagerTheme.secondary)
            Text(profile.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
            Spacer()
            Circle().fill(reading == nil ? TaskManagerTheme.muted : TaskManagerTheme.ink).frame(width: 4, height: 4)
            Text(state).font(.system(size: 8.5)).foregroundStyle(TaskManagerTheme.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color.white.opacity(0.025))
    }

    private func stat(_ title: String, symbol: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.system(size: 8.5)).foregroundStyle(TaskManagerTheme.secondary)
            Text(value).font(.system(size: 15, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
    }

    private var divider: some View { Rectangle().fill(TaskManagerTheme.lineSoft).frame(width: 1, height: 66) }

    private var diskSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("System").font(.system(size: 8.5)).foregroundStyle(TaskManagerTheme.secondary)
                Spacer()
                Text(diskPercent).font(.system(size: 8.5, design: .monospaced))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(TaskManagerTheme.lineSoft)
                    Rectangle().fill(TaskManagerTheme.ink.opacity(0.7))
                        .frame(width: proxy.size.width * diskFraction)
                }
            }
            .frame(height: 4)
            Text(diskFree).font(.system(size: 8)).foregroundStyle(TaskManagerTheme.muted)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 67)
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 0) {
            if let onTerminal {
                action("Open SSH", symbol: "terminal", height: 33, perform: onTerminal)
                Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1)
            }
            action(primaryTitle, symbol: primarySymbol, height: onTerminal == nil ? 67 : 33, perform: onPrimary)
        }
    }

    private func action(_ title: String, symbol: String, height: CGFloat, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: symbol)
            }
            .font(.system(size: 8.5))
            .foregroundStyle(TaskManagerTheme.secondary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 0))
        .focusEffectDisabled()
    }

    private var memoryReading: String {
        guard let reading else { return "—" }
        return "\(Self.shortBytes(reading.memoryUsed))/\(Self.shortBytes(reading.memoryTotal))"
    }

    private var networkReading: String {
        guard let reading else { return "—" }
        return "↓\(reading.download.map(Self.shortRate) ?? "—") ↑\(reading.upload.map(Self.shortRate) ?? "—")"
    }

    private var diskFraction: CGFloat {
        guard let used = reading?.diskUsed, let total = reading?.diskTotal, total > 0 else { return 0 }
        return CGFloat(min(max(Double(used) / Double(total), 0), 1))
    }

    private var diskPercent: String { reading == nil ? "—" : "\(Int((diskFraction * 100).rounded()))%" }
    private var diskFree: String {
        guard let used = reading?.diskUsed, let total = reading?.diskTotal else { return "No current reading" }
        return Self.bytes(total - min(used, total)) + " free"
    }

    nonisolated private static func shortRate(_ value: Double) -> String {
        SystemMonitorDisplayFormat.byteRate(value)
            .replacingOccurrences(of: "/s", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    nonisolated private static func shortBytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(value, UInt64(Int64.max))), countStyle: .memory)
            .replacingOccurrences(of: " ", with: "")
    }

    nonisolated private static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(value, UInt64(Int64.max))), countStyle: .file)
    }
}

private struct TaskManagerRemoteEditor: View {
    @State private var profile: SystemMonitorRemoteProfile
    let canDelete: Bool
    let onSave: (SystemMonitorRemoteProfile, Bool) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    init(
        profile: SystemMonitorRemoteProfile,
        canDelete: Bool,
        onSave: @escaping (SystemMonitorRemoteProfile, Bool) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        _profile = State(initialValue: profile)
        self.canDelete = canDelete
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(canDelete ? "Configure remote host" : "Add remote host")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 23, height: 23)
                }
                .taskManagerControl(.quiet, minWidth: 23, minHeight: 23, horizontalPadding: 0)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(TaskManagerTheme.window)
            .overlay(alignment: .bottom) { Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1) }

            VStack(spacing: 0) {
                editorRow("Name", detail: "A label shown in Task Manager.") {
                    TextField("Build server", text: $profile.name)
                        .taskManagerRemoteField()
                }
                divider
                editorRow("SSH host", detail: "Host or alias from ~/.ssh/config.") {
                    TextField("user@host", text: $profile.host)
                        .taskManagerRemoteField()
                        .onSubmit { submit(connect: true) }
                        .accessibilityIdentifier("system-monitor.remote.host")
                }
                divider
                editorRow("System", detail: "The operating system on this host.") {
                    TaskManagerSegments(
                        choices: SystemMonitorRemotePlatform.allCases.map { ($0, $0.rawValue) },
                        selection: $profile.platform
                    )
                }
                divider
                editorRow("Refresh", detail: "No sampling occurs while disconnected.") {
                    TaskManagerSelect(
                        choices: [
                            (0, "Manual only"), (5, "5 seconds"), (10, "10 seconds"),
                            (30, "30 seconds"), (60, "1 minute"),
                            (120, "2 minutes"), (300, "5 minutes"),
                        ],
                        selection: $profile.interval,
                        width: 128,
                        accessibilityLabel: "Refresh interval"
                    )
                }
            }

            HStack(spacing: 8) {
                if canDelete {
                    Button("Remove", role: .destructive, action: onDelete)
                        .taskManagerControl(.destructive)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .taskManagerControl(.quiet)
                Button("Save") { submit(connect: false) }
                    .taskManagerControl()
                Button("Save & Connect") { submit(connect: true) }
                    .taskManagerControl(.primary)
                    .disabled(!SystemMonitorRemoteProtocol.validHost(profile.host))
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(TaskManagerTheme.window)
            .overlay(alignment: .top) { Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1) }
        }
        .frame(width: 530)
        .background(TaskManagerTheme.window)
        .foregroundStyle(TaskManagerTheme.ink)
        .environment(\.colorScheme, .dark)
    }

    private func editorRow<Content: View>(
        _ title: String,
        detail: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 11))
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(TaskManagerTheme.secondary)
            }
            Spacer(minLength: 16)
            control()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
    }

    private var divider: some View {
        Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1)
    }

    private func submit(connect: Bool) {
        onSave(profile, connect)
    }
}

private extension View {
    func taskManagerRemoteButton(primary: Bool = false) -> some View {
        taskManagerControl(
            primary ? .primary : .standard,
            minWidth: 88,
            minHeight: 36,
            horizontalPadding: 14
        )
    }

    func taskManagerRemoteField() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 10, design: .monospaced))
            .padding(.horizontal, 10)
            .frame(width: 220, height: 31)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 5))
            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(TaskManagerTheme.line) }
    }
}
