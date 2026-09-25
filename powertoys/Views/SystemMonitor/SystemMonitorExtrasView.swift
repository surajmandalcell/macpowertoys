import IOBluetooth
import SwiftUI

nonisolated struct SystemMonitorBluetoothDevice: Identifiable, Sendable {
    let id: String
    let name: String
    let connected: Bool

    static func paired() -> [Self] {
        (IOBluetoothDevice.pairedDevices() ?? []).compactMap { item in
            guard let device = item as? IOBluetoothDevice,
                  let address = device.addressString else { return nil }
            return Self(id: address, name: device.nameOrAddress ?? address, connected: device.isConnected())
        }
        .sorted { $0.connected == $1.connected ? $0.name < $1.name : $0.connected }
    }
}

struct SystemMonitorBluetoothView: View {
    @State private var devices: [SystemMonitorBluetoothDevice] = []
    @State private var didLoad = false

    var body: some View {
        WorkspacePage("Bluetooth") {
            Text("Paired devices")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } content: {
            if !didLoad {
                ProgressView("Reading paired devices…")
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if devices.isEmpty {
                ContentUnavailableView(
                    "No paired Bluetooth devices",
                    systemImage: "wave.3.right",
                    description: Text("Pair a device in System Settings to see it here.")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                VStack(spacing: 0) {
                    ForEach(devices) { device in
                        HStack(spacing: 10) {
                            Image(systemName: "wave.3.right")
                                .foregroundStyle(device.connected ? Color.accentColor : Color.secondary)
                            Text(device.name).lineLimit(1)
                            Spacer()
                            Text(device.connected ? "Connected" : "Disconnected")
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12))
                        .frame(minHeight: 40)
                        if device.id != devices.last?.id { QuietDivider() }
                    }
                }
                .utilitySectionCard()
            }
        }
        .task {
            while !Task.isCancelled {
                let snapshot = await Task.detached(priority: .utility) {
                    SystemMonitorBluetoothDevice.paired()
                }.value
                guard !Task.isCancelled else { return }
                devices = snapshot
                didLoad = true
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}

struct SystemMonitorWorldClocksView: View {
    @AppStorage("systemMonitor.worldClocks") private var savedZones = "UTC,America/New_York,Asia/Tokyo"
    @State private var newZone = ""
    @State private var errorMessage: String?

    private var zones: [String] {
        savedZones.split(separator: ",").map(String.init).filter { TimeZone(identifier: $0) != nil }
    }

    var body: some View {
        WorkspacePage("World Clocks") {} content: {
            HStack(spacing: 8) {
                TextField("Time zone", text: $newZone, prompt: Text("Europe/London"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addZone)
                Button("Add") { addZone() }
                    .disabled(newZone.isEmpty || zones.count >= 6)
            }
            .controlSize(.small)
            if let errorMessage {
                Text(errorMessage).font(.system(size: 11)).foregroundStyle(.orange)
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    clock("Local", zone: .current, date: context.date)
                    ForEach(zones, id: \.self) { identifier in
                        if let zone = TimeZone(identifier: identifier) {
                            clock(identifier.replacingOccurrences(of: "_", with: " "), zone: zone, date: context.date) {
                                savedZones = zones.filter { $0 != identifier }.joined(separator: ",")
                            }
                        }
                    }
                }
            }
            Text("Add up to six IANA time zones. Clocks update once a minute while this page is open.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func clock(_ title: String, zone: TimeZone, date: Date, remove: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                if let remove {
                    Button("Remove", systemImage: "xmark", action: remove)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                        .accessibilityLabel("Remove \(title)")
                        .help("Remove \(title)")
                }
            }
            Text(date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))
                .font(.system(size: 25, weight: .semibold))
                .monospacedDigit()
            Text(date.formatted(Date.FormatStyle(date: .complete, time: .omitted, timeZone: zone)))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .utilitySectionCard()
    }

    private func addZone() {
        let candidate = newZone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TimeZone(identifier: candidate) != nil else {
            errorMessage = "Enter a valid time zone such as Europe/London."
            return
        }
        guard !zones.contains(candidate), zones.count < 6 else {
            errorMessage = "That time zone is already listed, or the six-clock limit is reached."
            return
        }
        savedZones = (zones + [candidate]).joined(separator: ",")
        newZone = ""
        errorMessage = nil
    }
}
