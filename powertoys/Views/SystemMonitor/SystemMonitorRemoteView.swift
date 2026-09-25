import AppKit
import SwiftUI

struct SystemMonitorRemoteView: View {
    @AppStorage("systemMonitor.remoteHost") private var host = ""
    @AppStorage("systemMonitor.remoteInterval") private var interval = 30
    @State private var poller = SystemMonitorRemotePoller()
    @State private var connected = false
    @State private var reading: SystemMonitorRemoteReading?
    @State private var lastUpdated: Date?
    @State private var errorMessage: String?
    @State private var copiedCommand = false

    var body: some View {
        WorkspacePage("Remote Linux") {
            Button(connected ? "Disconnect" : "Connect", systemImage: connected ? "link.slash" : "link") {
                if connected {
                    disconnect()
                } else if SystemMonitorRemoteProtocol.validHost(host) {
                    poller = SystemMonitorRemotePoller()
                    reading = nil
                    errorMessage = nil
                    connected = true
                } else {
                    errorMessage = SystemMonitorRemoteError.unsafeHost.localizedDescription
                }
            }
            .accessibilityIdentifier("system-monitor.remote.connection")
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                Text("CONNECTION").utilitySectionHeader()
                HStack(spacing: 10) {
                    TextField("SSH host", text: $host, prompt: Text("Host or alias from SSH config"))
                        .textFieldStyle(.roundedBorder)
                        .disabled(connected)
                        .accessibilityIdentifier("system-monitor.remote.host")
                    Picker("Refresh", selection: $interval) {
                        Text("15 seconds").tag(15)
                        Text("30 seconds").tag(30)
                        Text("60 seconds").tag(60)
                    }
                    .frame(width: 170)
                    .disabled(connected)
                }
                Text("Use a Linux host you can already reach with SSH.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Open Terminal", systemImage: "terminal") { openTerminal() }
                        .disabled(!SystemMonitorRemoteProtocol.validHost(host))
                    if copiedCommand {
                        Text("SSH command copied. Paste it in Terminal.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .controlSize(.small)
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
                        metric("CPU", value: reading.cpuPercent.map { percent($0) } ?? "Measuring…", detail: "All cores")
                        metric("Memory", value: bytes(reading.memoryUsed), detail: "of \(bytes(reading.memoryTotal))")
                        metric("Load", value: reading.load.map { $0.formatted(.number.precision(.fractionLength(2))) }.joined(separator: " · "), detail: "1, 5, and 15 minutes")
                        metric("Download", value: reading.download.map { bytes(UInt64($0)) + "/s" } ?? "Measuring…", detail: "Non-loopback interfaces")
                        metric("Upload", value: reading.upload.map { bytes(UInt64($0)) + "/s" } ?? "Measuring…", detail: "Non-loopback interfaces")
                        if let diskUsed = reading.diskUsed, let diskTotal = reading.diskTotal {
                            metric("Disk", value: bytes(diskUsed), detail: "of \(bytes(diskTotal)) on /")
                        }
                    }
                } else {
                    ProgressView("Reading Linux system data…")
                        .frame(maxWidth: .infinity)
                        .padding(30)
                }
            } else if errorMessage == nil {
                ContentUnavailableView(
                    "No remote host connected",
                    systemImage: "server.rack",
                    description: Text("Connect to read usage. Sampling stops when you disconnect or close this page.")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .task(id: connected) {
            guard connected else { return }
            while !Task.isCancelled {
                do {
                    let sample = try await poller.sample(host: host)
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
                try? await Task.sleep(for: .seconds(max(interval, 15)))
            }
        }
        .onDisappear { disconnect() }
    }

    private func metric(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 19, weight: .semibold)).monospacedDigit()
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .utilitySectionCard()
    }

    private func disconnect() {
        connected = false
        reading = nil
        lastUpdated = nil
    }

    private func openTerminal() {
        guard SystemMonitorRemoteProtocol.validHost(host) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("ssh \(host)", forType: .string)
        copiedCommand = true
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }

    private func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }
    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(value, UInt64(Int64.max))), countStyle: .file)
    }
}
