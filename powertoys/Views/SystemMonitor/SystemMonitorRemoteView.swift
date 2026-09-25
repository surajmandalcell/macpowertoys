import AppKit
import SwiftUI

struct SystemMonitorRemoteView: View {
    @AppStorage("systemMonitor.remoteHost") private var host = ""
    @AppStorage("systemMonitor.remotePlatform") private var platformName = SystemMonitorRemotePlatform.linux.rawValue
    @AppStorage("systemMonitor.remoteInterval") private var interval = 30
    @State private var poller = SystemMonitorRemotePoller()
    @State private var connected = false
    @State private var reading: SystemMonitorRemoteReading?
    @State private var lastUpdated: Date?
    @State private var errorMessage: String?
    @State private var refreshGeneration = 0
    @Environment(\.colorScheme) private var colorScheme
    private var platform: SystemMonitorRemotePlatform {
        SystemMonitorRemotePlatform(rawValue: platformName) ?? .linux
    }

    var body: some View {
        WorkspacePage("Remote Stats") {} content: {
            VStack(alignment: .leading, spacing: 10) {
                Text("CONNECTION").utilitySectionHeader()
                HStack(spacing: 10) {
                    TextField("SSH host", text: $host, prompt: Text("Host or alias from SSH config"))
                        .textFieldStyle(.roundedBorder)
                        .disabled(connected)
                        .onSubmit { if !connected { connect() } }
                        .accessibilityIdentifier("system-monitor.remote.host")
                    Picker("Refresh", selection: $interval) {
                        Text("Manual only").tag(0)
                        Text("5 seconds").tag(5)
                        Text("10 seconds").tag(10)
                        Text("30 seconds").tag(30)
                        Text("60 seconds").tag(60)
                        Text("2 minutes").tag(120)
                        Text("5 minutes").tag(300)
                    }
                    .frame(width: 170)
                }
                Picker("System", selection: $platformName) {
                    ForEach(SystemMonitorRemotePlatform.allCases) { system in
                        Text(system.rawValue).tag(system.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 290)
                .disabled(connected)
                Text(connected
                     ? "Refresh changes apply now. Disconnect to change the host or system."
                     : "Use an SSH host you can already reach. Readings stop on disconnect or when you leave this page.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button {
                        connected ? disconnect() : connect()
                    } label: {
                        Text(connected ? "Disconnect" : "Connect")
                            .utilityActionLabel()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(connected ? .gray : .accentColor)
                    .accessibilityIdentifier("system-monitor.remote.connection")
                    if connected {
                        Button { refreshGeneration += 1 } label: {
                            Label("Refresh Now", systemImage: "arrow.clockwise")
                                .utilityActionLabel()
                        }
                    }
                    Button { openTerminal() } label: {
                        Label("Open Terminal", systemImage: "terminal")
                            .utilityActionLabel()
                    }
                    .disabled(!SystemMonitorRemoteProtocol.validHost(host))
                }
                .controlSize(.large)
            }
            .utilitySectionCard()

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .utilitySectionCard()
            }

            if connected {
                HStack(spacing: 8) {
                    Image(systemName: reading == nil ? "circle.dotted" : "checkmark.circle")
                    Text(reading == nil ? "Connecting to \(host)…" : "Connected to \(host)")
                    Spacer()
                    if let lastUpdated {
                        Text(lastUpdated, style: .time)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 12))

                if let reading {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                        metric("CPU", value: reading.cpuPercent.map { percent($0) } ?? "Measuring…", detail: "All cores", tint: SystemMonitorPalette.teal)
                        metric("Memory", value: bytes(reading.memoryUsed), detail: "of \(bytes(reading.memoryTotal))", tint: SystemMonitorPalette.coral)
                        if !reading.load.isEmpty {
                            metric("Load · 1 min", value: reading.load[0].formatted(.number.precision(.fractionLength(2))), detail: "Average CPU demand", tint: SystemMonitorPalette.blue)
                                .help("Load is the average number of processes running or ready for a CPU. It is not a percent.")
                        }
                        metric("Download", value: reading.download.map { bytes(UInt64($0)) + "/s" } ?? "Measuring…", detail: "Non-loopback interfaces", tint: SystemMonitorPalette.cyan)
                        metric("Upload", value: reading.upload.map { bytes(UInt64($0)) + "/s" } ?? "Measuring…", detail: "Non-loopback interfaces", tint: SystemMonitorPalette.cyan)
                        if let diskUsed = reading.diskUsed, let diskTotal = reading.diskTotal {
                            metric("Disk", value: bytes(diskUsed), detail: "of \(bytes(diskTotal)) on /", tint: SystemMonitorPalette.orange)
                        }
                    }
                } else {
                    ProgressView("Reading remote system data…")
                        .frame(maxWidth: .infinity)
                        .padding(30)
                }
            } else if errorMessage == nil {
                ContentUnavailableView(
                    "No remote host connected",
                    systemImage: "server.rack",
                    description: Text("Enter an SSH host or alias, choose its system, and press Return. Remote sampling stops when you disconnect or leave this page.")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .task(id: "\(connected):\(interval):\(refreshGeneration)") {
            guard connected else { return }
            while !Task.isCancelled {
                do {
                    let sample = try await poller.sample(host: host, platform: platform)
                    guard !Task.isCancelled else { return }
                    reading = sample
                    lastUpdated = Date()
                    errorMessage = nil
                } catch {
                    guard !Task.isCancelled else { return }
                    errorMessage = error.localizedDescription
                    connected = false
                    return
                }
                guard interval > 0 else { return }
                try? await Task.sleep(for: .seconds(max(interval, 5)))
            }
        }
        .onDisappear { disconnect() }
    }

    private func metric(_ title: String, value: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .medium))
                .foregroundStyle(colorScheme == .dark ? tint : .primary)
            Text(value).font(.system(size: 19, weight: .semibold)).monospacedDigit()
                .contentTransition(.numericText())
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .padding(14)
        .background(SystemMonitorPalette.gradient(tint))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.25)) }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func disconnect() {
        connected = false
        reading = nil
        lastUpdated = nil
    }

    private func connect() {
        guard SystemMonitorRemoteProtocol.validHost(host) else {
            errorMessage = SystemMonitorRemoteError.unsafeHost.localizedDescription
            return
        }
        poller = SystemMonitorRemotePoller()
        reading = nil
        lastUpdated = nil
        errorMessage = nil
        connected = true
    }

    private func openTerminal() {
        guard SystemMonitorRemoteProtocol.validHost(host),
              let address = URL(string: "ssh://\(host)") else { return }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([address], withApplicationAt: terminal,
                                configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Task { @MainActor in errorMessage = "Could not open Terminal: \(error.localizedDescription)" }
            }
        }
    }

    private func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }
    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(value, UInt64(Int64.max))), countStyle: .file)
    }
}
