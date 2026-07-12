import SwiftUI

struct AwakeView: View {
    @State private var service = AwakeService.shared
    @State private var hours = 0
    @State private var minutes = 30
    @State private var expiration = Date().addingTimeInterval(3600)
    @State private var processID = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    status
                    modes
                    options
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Image(systemName: service.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .foregroundStyle(service.isActive ? Color.accentColor : .secondary)
            Text("Awake").font(.system(size: 13, weight: .medium))
            Spacer()
            Toggle("Keep Display On", isOn: Binding(
                get: { service.configuration.keepDisplayOn },
                set: service.setKeepDisplayOn
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(service.configuration.mode == .passive)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STATUS").utilitySectionHeader()
            HStack(spacing: 10) {
                Circle().fill(service.isActive ? Color.green : Color.secondary).frame(width: 8, height: 8)
                Text(service.statusText).font(.system(size: 13)).monospacedDigit()
                Spacer()
                if service.configuration.mode != .passive {
                    Button("Turn Off") { service.setMode(.passive) }
                }
            }
            .utilitySectionCard()
            if let error = service.assertionError { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
        }
    }

    private var modes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MODE").utilitySectionHeader()
            VStack(alignment: .leading, spacing: 12) {
                modeButton(.passive)
                modeButton(.indefinite)
                HStack {
                    modeButton(.timed)
                    Stepper("\(hours) h", value: $hours, in: 0...168)
                    Stepper("\(minutes) min", value: $minutes, in: 0...59, step: 5)
                    Button("Start") { service.setMode(.timed, duration: TimeInterval(hours * 3600 + minutes * 60)) }
                        .disabled(hours == 0 && minutes == 0)
                }
                HStack {
                    modeButton(.until)
                    DatePicker("", selection: $expiration, in: Date()...)
                        .labelsHidden()
                    Button("Start") { service.setMode(.until, until: expiration) }
                }
            }
            .utilitySectionCard()
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUICK TIMES AND PROCESS").utilitySectionHeader()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ForEach(service.configuration.presets, id: \.self) { seconds in
                        Button(AwakeService.duration(seconds)) { service.setMode(.timed, duration: seconds) }
                            .contextMenu {
                                Button("Remove Preset") {
                                    service.setPresets(service.configuration.presets.filter { $0 != seconds })
                                }
                            }
                    }
                    Button {
                        service.setPresets(service.configuration.presets + [TimeInterval(hours * 3600 + minutes * 60)])
                    } label: { Image(systemName: "plus") }
                    .help("Add the current interval as a preset")
                    .disabled(hours == 0 && minutes == 0)
                }
                Divider()
                HStack {
                    TextField("Process ID", text: $processID).frame(width: 110)
                    Button("Attach") {
                        guard let id = Int32(processID) else { return }
                        service.attach(to: id)
                        if service.configuration.mode == .passive { service.setMode(.indefinite) }
                    }
                    if let id = service.configuration.attachedProcessID {
                        Text("Stops when PID \(id) exits").foregroundStyle(.secondary)
                        Button("Detach") { service.attach(to: nil) }
                    }
                }
            }
            .font(.system(size: 12))
            .utilitySectionCard()
        }
    }

    private func modeButton(_ mode: AwakeMode) -> some View {
        Button {
            if mode == .passive || mode == .indefinite { service.setMode(mode) }
        } label: {
            HStack {
                Image(systemName: service.configuration.mode == mode ? "record.circle.fill" : "circle")
                Text(mode.title)
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 180, alignment: .leading)
    }
}
