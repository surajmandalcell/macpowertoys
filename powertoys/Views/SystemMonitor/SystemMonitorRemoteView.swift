import AppKit
import OnePlusUI
import SwiftUI

struct SystemMonitorRemoteView: View {
    let addRequest: Int
    private let loadsProfiles: Bool
    private let suppliedProfiles: [SystemMonitorRemoteProfile]?
    private let onProfilesChange: ([SystemMonitorRemoteProfile]) -> Void
    @State private var profiles: [SystemMonitorRemoteProfile]
    @ObservedObject private var sessions = SystemMonitorRemoteSessions.shared
    @State private var editor: SystemMonitorRemoteProfile?
    @State private var errorMessage: String?

    init(addRequest: Int = 0, initialProfiles: [SystemMonitorRemoteProfile]? = nil,
         onProfilesChange: @escaping ([SystemMonitorRemoteProfile]) -> Void = { _ in }) {
        self.addRequest = addRequest
        let preparedProfiles = initialProfiles ?? SystemMonitorRemoteSessions.shared.savedProfiles
        loadsProfiles = preparedProfiles == nil
        suppliedProfiles = initialProfiles
        self.onProfilesChange = onProfilesChange
        _profiles = State(initialValue: preparedProfiles ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            if let errorMessage { OnePlusBanner(errorMessage, tone: .error) }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                        if profiles.isEmpty {
                            OnePlusEmptyState("No remote hosts", systemImage: "server.rack",
                                              caption: "Add a Linux, macOS, or Windows SSH host.") {
                                Button("Add host") { editor = SystemMonitorRemoteProfile(name: "", host: "") }
                            }
                        }
                        ForEach(profiles) { profile in
                            remoteCard(profile).id(profile.id)
                        }
                    }
                }.thinScrollIndicators()
                    .onReceive(sessions.$selectedID) { id in
                        if let id { proxy.scrollTo(id, anchor: .top) }
                    }
                    .onChange(of: profiles.map(\.id)) { _, _ in
                        if let id = sessions.selectedID { proxy.scrollTo(id, anchor: .top) }
                    }
            }
        }
        .task {
            if loadsProfiles {
                let loaded = await Task.detached(priority: .userInitiated) { SystemMonitorRemoteProfiles.load() }.value
                guard !Task.isCancelled else { return }
                sessions.savedProfiles = loaded
                profiles = loaded
                onProfilesChange(loaded)
            }
        }
        .onChange(of: addRequest) { _, _ in editor = SystemMonitorRemoteProfile(name: "", host: "") }
        .onChange(of: suppliedProfiles) { _, loaded in
            if let loaded { profiles = loaded }
        }
        .sheet(item: $editor) { profile in
            TaskManagerRemoteEditor(profile: profile, canDelete: profiles.contains { $0.id == profile.id },
                                    onSave: { save($0, connect: $1) },
                                    onDelete: { remove(profile.id) }, onCancel: { editor = nil })
        }
    }

    private func remoteCard(_ profile: SystemMonitorRemoteProfile) -> some View {
        let state = sessions.state(for: profile.id)
        return VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            TaskManagerRemoteCard(profile: profile, reading: state.reading, state: state.phase.rawValue,
                                  history: state.history, onTerminal: { openTerminal(profile) },
                                  primaryTitle: state.phase == .offline ? "Connect" : "Disconnect",
                                  primarySymbol: state.phase == .offline ? "play.circle" : "stop.circle",
                                  onPrimary: { state.phase == .offline ? sessions.connect(profile) : sessions.disconnect(profile.id) },
                                  onConfigure: { editor = profile }, onRefresh: { sessions.refresh(profile) })
            if let reading = state.reading, !reading.disks.isEmpty {
                OnePlusCard {
                    OnePlusCardHeader("Disks")
                    ForEach(reading.disks) { disk in
                        OnePlusKeyValueRow(disk.id, value: "\(TrayPopoverLayout.diskBytes(Int64(clamping: disk.used))) / \(TrayPopoverLayout.diskBytes(Int64(clamping: disk.total)))")
                    }
                }
            }
        }
    }

    private func save(_ profile: SystemMonitorRemoteProfile, connect shouldConnect: Bool) {
        if let message = profile.validationMessage { errorMessage = message; return }
        let wasConnected = sessions.state(for: profile.id).phase != .offline
        sessions.disconnect(profile.id)
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
        else { profiles.append(profile) }
        SystemMonitorRemoteProfiles.save(profiles)
        sessions.savedProfiles = profiles
        onProfilesChange(profiles)
        editor = nil
        errorMessage = nil
        if wasConnected || shouldConnect { sessions.connect(profile) }
    }

    private func remove(_ id: String) {
        sessions.remove(id)
        profiles.removeAll { $0.id == id }
        SystemMonitorRemoteProfiles.save(profiles)
        sessions.savedProfiles = profiles
        onProfilesChange(profiles)
        editor = nil
    }

    private func openTerminal(_ profile: SystemMonitorRemoteProfile) {
        SystemMonitorRemoteTerminal.open(profile) { error in
            if let error { errorMessage = error.localizedDescription }
        }
    }
}

struct SystemMonitorRemoteHeader: View {
    let profiles: [SystemMonitorRemoteProfile]
    let addHost: () -> Void
    @ObservedObject private var sessions = SystemMonitorRemoteSessions.shared

    var body: some View {
        HStack(spacing: OnePlusMetrics.actionSpacing) {
            Text("\(profiles.filter { sessions.state(for: $0.id).phase == .connected }.count) connected · \(profiles.count) \(profiles.count == 1 ? "host" : "hosts")")
                .onePlusText(.caption)
            Button(action: addHost) { Label("Add host", systemImage: "plus") }
                .buttonStyle(OnePlusButtonStyle(.neutral, size: .small))
                .accessibilityIdentifier("system-monitor.remote.add-host")
        }
    }
}

enum SystemMonitorRemoteTerminal {
    static func command(_ profile: SystemMonitorRemoteProfile) throws -> String {
        if let message = profile.validationMessage { throw SystemMonitorRemoteError.invalidProfile(message) }
        var args = ["/usr/bin/ssh"]
        if !profile.user.isEmpty { args += ["-l", profile.user] }
        if let port = profile.port { args += ["-p", String(port)] }
        args += ["--", profile.host]
        return args.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
    }

    static func open(_ profile: SystemMonitorRemoteProfile, completion: (@MainActor @Sendable (Error?) -> Void)? = nil) {
        Task {
            do {
                let command = try command(profile)
                let file = try await Task.detached(priority: .userInitiated) {
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mpt-terminal-\(UUID().uuidString)")
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                           attributes: [.posixPermissions: 0o700])
                    let file = directory.appendingPathComponent("SSH.command")
                    let script = "#!/bin/sh\n/bin/rm -- \"$0\"\n/bin/rmdir -- \"$(/usr/bin/dirname \"$0\")\"\nexec \(command)\n"
                    do {
                        try script.write(to: file, atomically: true, encoding: .utf8)
                        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
                    } catch {
                        try? FileManager.default.removeItem(at: directory)
                        throw error
                    }
                    return file
                }.value
                NSWorkspace.shared.open([file], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                        configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if error != nil { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
                    Task { @MainActor in
                        if let error { SystemMonitorRemoteSessions.shared.report(error, for: profile.id) }
                        completion?(error)
                    }
                }
            } catch {
                SystemMonitorRemoteSessions.shared.report(error, for: profile.id)
                completion?(error)
            }
        }
    }
}

private struct SystemMonitorRemoteWindowOwner: NSViewRepresentable {
    let profileID: String
    func makeNSView(context: Context) -> OwnerView { OwnerView(profileID: profileID) }
    func updateNSView(_ view: OwnerView, context: Context) {
        view.profileID = profileID
        if let window = view.window { SystemMonitorRemoteSessions.shared.register(profileID, window: window) }
    }
    final class OwnerView: NSView {
        var profileID: String
        init(profileID: String) { self.profileID = profileID; super.init(frame: .zero) }
        required init?(coder: NSCoder) { return nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { SystemMonitorRemoteSessions.shared.register(profileID, window: window) }
        }
    }
}

struct TaskManagerRemoteCard: View {
    let profile: SystemMonitorRemoteProfile
    private let fallbackReading: SystemMonitorRemoteReading?
    private let fallbackState: String
    private let fallbackHistory: [SystemMonitorRemoteReading]
    @ObservedObject private var sessions = SystemMonitorRemoteSessions.shared
    private var reading: SystemMonitorRemoteReading? {
        if let state = sessions.states[profile.id] { return state.reading }
        return fallbackReading
    }
    private var state: String { sessions.states[profile.id]?.phase.rawValue ?? fallbackState }
    private var history: [SystemMonitorRemoteReading] { sessions.states[profile.id]?.history ?? fallbackHistory }

    init(profile: SystemMonitorRemoteProfile, reading: SystemMonitorRemoteReading?, state: String,
         history: [SystemMonitorRemoteReading] = [], onTerminal: (() -> Void)? = nil,
         primaryTitle: String, primarySymbol: String, onPrimary: @escaping () -> Void,
         onConfigure: (() -> Void)? = nil, onRefresh: (() -> Void)? = nil) {
        self.profile = profile; fallbackReading = reading; fallbackState = state; fallbackHistory = history
        self.onTerminal = onTerminal; self.primaryTitle = primaryTitle; self.primarySymbol = primarySymbol; self.onPrimary = onPrimary
        self.onConfigure = onConfigure; self.onRefresh = onRefresh
    }
    var onTerminal: (() -> Void)?
    let primaryTitle: String
    let primarySymbol: String
    let onPrimary: () -> Void
    let onConfigure: (() -> Void)?
    let onRefresh: (() -> Void)?

    var body: some View {
        TaskManagerPanel(textured: true) {
            VStack(spacing: 0) {
                header
                if let reason = sessions.state(for: profile.id).reason {
                    Text(reason).onePlusText(.caption).textSelection(.enabled)
                        .padding(OnePlusMetrics.cardGap).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 0) {
                    stat("CPU", symbol: "cpu", value: reading?.cpuPercent.map { "\(Int($0.rounded()))%" } ?? "—")
                    divider
                    stat("RAM", symbol: "memorychip", value: memoryReading)
                    divider
                    stat("Network", symbol: "network", value: networkReading)
                }
                if hasDiskReading {
                    Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1)
                    diskSummary
                }
                if !history.isEmpty {
                    TaskManagerHistoryChart(values: history.compactMap(\.cpuPercent), range: 0...100, compact: true)
                        .frame(height: 38)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                actions
                    .padding(.horizontal, OnePlusMetrics.compactCardPadding)
                    .padding(.vertical, OnePlusMetrics.actionSpacing)
            }
        }
        .background(SystemMonitorRemoteWindowOwner(profileID: profile.id).frame(width: 0, height: 0))
    }

    private var header: some View {
        OnePlusCardHeader(profile.name, systemImage: "server.rack") {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                Text("\(profile.destination) · \(profile.platform.rawValue)")
                    .onePlusText(.mono).lineLimit(1).help("\(profile.destination) · \(profile.platform.rawValue)")
                OnePlusStatus(state, state: reading == nil ? .offline : .online)
            }
        }
    }

    private var hasDiskReading: Bool { reading?.diskUsed != nil && reading?.diskTotal != nil }

    private func stat(_ title: String, symbol: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).onePlusText(.caption).foregroundStyle(TaskManagerTheme.secondary)
            Text(value).font(.system(size: 18)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65).help(value)
                .foregroundStyle(reading == nil ? TaskManagerTheme.muted : TaskManagerTheme.ink)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
    }

    private var divider: some View { Rectangle().fill(TaskManagerTheme.lineSoft).frame(width: 1, height: 66) }

    private var diskSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("System").onePlusText(.caption).foregroundStyle(TaskManagerTheme.secondary)
                Spacer()
                Text(diskFree).onePlusText(.caption)
                Text(diskPercent).onePlusText(.mono)
            }
            OnePlusUsageBar(value: Double(diskFraction))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, OnePlusMetrics.actionSpacing)
        .frame(maxWidth: .infinity)
    }

    private var actions: some View {
        HStack(spacing: OnePlusMetrics.actionSpacing) {
            if let onConfigure {
                Button("Configure", action: onConfigure)
                    .accessibilityIdentifier("system-monitor.remote.configure.\(profile.id)")
            }
            if let onRefresh {
                Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }
                    .help("Refresh now").accessibilityLabel("Refresh \(profile.name) now")
                    .disabled(state != "Connected")
            }
            Spacer(minLength: 0)
            if let onTerminal {
                action("Open SSH", symbol: "terminal", perform: onTerminal)
            }
            action(primaryTitle, symbol: primarySymbol, perform: onPrimary)
                .accessibilityIdentifier("system-monitor.remote.connect.\(profile.id)")
        }
        .buttonStyle(OnePlusButtonStyle(.neutral, size: .small))
    }

    private func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
        Button {
            if title == "Open App" { sessions.selectedID = profile.id }
            perform()
        } label: {
            Label(title, systemImage: symbol)
        }
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
        return TrayPopoverLayout.diskBytes(Int64(clamping: total - min(used, total))) + " free"
    }

    nonisolated static func shortRate(_ value: Double) -> String {
        SystemMonitorDisplayFormat.byteRate(value)
            .replacingOccurrences(of: "/s", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    nonisolated static func shortBytes(_ value: UInt64) -> String {
        guard value > 0 else { return "0B" }
        return ByteCountFormatter.string(fromByteCount: Int64(min(value, UInt64(Int64.max))), countStyle: .memory)
            .replacingOccurrences(of: " ", with: "")
    }
}

private struct TaskManagerRemoteEditor: View {
    @State private var profile: SystemMonitorRemoteProfile
    @State private var port: String
    @State private var errorMessage: String?
    @State private var confirmsRemoval = false
    let canDelete: Bool
    let onSave: (SystemMonitorRemoteProfile, Bool) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    init(profile: SystemMonitorRemoteProfile, canDelete: Bool,
         onSave: @escaping (SystemMonitorRemoteProfile, Bool) -> Void,
         onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        var profile = profile
        let address = profile.host.split(separator: "@")
        if address.count == 2, profile.user.isEmpty {
            profile.user = String(address[0]); profile.host = String(address[1])
        }
        _profile = State(initialValue: profile)
        _port = State(initialValue: profile.port.map(String.init) ?? "")
        self.canDelete = canDelete; self.onSave = onSave; self.onDelete = onDelete; self.onCancel = onCancel
    }

    var body: some View {
        OnePlusSheet(canDelete ? "Configure remote host" : "Add remote host", close: onCancel) {
            VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                field("Name", placeholder: "Build server", text: $profile.name)
                field("SSH host or alias", placeholder: "oci2", text: $profile.host)
                    .accessibilityIdentifier("system-monitor.remote.host")
                field("User", placeholder: "Use SSH config", text: $profile.user)
                field("Port", placeholder: "Use SSH config", text: $port)
                HStack {
                    Text("Operating system").onePlusText(.row)
                    Spacer()
                    OnePlusSelect(choices: SystemMonitorRemotePlatform.allCases.map { ($0, $0.rawValue) },
                                  selection: $profile.platform, width: OnePlusMetrics.controlColumn,
                                  accessibilityLabel: "Operating system")
                }
                HStack {
                    Text("Refresh interval").onePlusText(.row)
                    Spacer()
                    OnePlusSelect(choices: [(0, "Manual only"), (5, "5 seconds"), (10, "10 seconds"),
                                           (30, "30 seconds"), (60, "1 minute"), (120, "2 minutes"), (300, "5 minutes")],
                                  selection: $profile.interval, width: OnePlusMetrics.controlColumn,
                                  accessibilityLabel: "Refresh interval")
                }
                if let errorMessage { OnePlusBanner(errorMessage, tone: .error) }
            }
        } footer: {
            if canDelete {
                Button("Remove", role: .destructive) { confirmsRemoval = true }
                    .buttonStyle(OnePlusButtonStyle(.destructive))
            }
            Button("Cancel", action: onCancel).buttonStyle(OnePlusButtonStyle(.ghost))
            Button("Save") { submit(connect: false) }.buttonStyle(OnePlusButtonStyle(.neutral))
            Button("Save & Connect") { submit(connect: true) }
                .buttonStyle(OnePlusButtonStyle(.primary)).keyboardShortcut(.defaultAction)
        }
        .confirmationDialog("Remove \(profile.name)?", isPresented: $confirmsRemoval) {
            Button("Remove host", role: .destructive, action: onDelete)
        } message: { Text("This removes the saved host and disconnects its SSH session.") }
    }

    private func field(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        HStack {
            Text(title).onePlusText(.row)
            Spacer()
            OnePlusTextField(placeholder, text: text, onSubmit: { submit(connect: true) })
                .accessibilityLabel(title).frame(width: OnePlusMetrics.controlColumn)
        }
    }

    private func submit(connect: Bool) {
        profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.host = profile.host.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.user = profile.user.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = port.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty && (Int(value) == nil || !value.utf8.allSatisfy({ (48...57).contains($0) })) {
            errorMessage = "Enter a port from 1 to 65535, or leave it blank to use SSH config."
            return
        }
        profile.port = value.isEmpty ? nil : Int(value)
        if let message = profile.validationMessage { errorMessage = message; return }
        errorMessage = nil
        onSave(profile, connect)
    }
}
