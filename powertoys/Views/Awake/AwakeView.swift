import SwiftUI
import OnePlusUI

enum AwakeLayout {
    static let windowWidth = OnePlusWindowCanvas.awake.size.width
    static let windowHeight = OnePlusWindowCanvas.awake.size.height
}

struct AwakeView: View {
    @State private var service = AwakeService.shared
    @State private var settings = false

    var body: some View {
        OnePlusWindowRoot(canvas: .awake, sidebar: { EmptyView() }) {
            VStack(spacing: 0) {
                OnePlusAppletTitlebar(title: "Awake") {
                    Toggle("Keep Display On", isOn: Binding(
                        get: { service.configuration.keepDisplayOn }, set: service.setKeepDisplayOn
                    ))
                    .toggleStyle(OnePlusSwitchStyle())
                    .fixedSize()
                    .accessibilityIdentifier("awake.keep-display-on")
                }
                ScrollView {
                    AwakeSettingsView(showsDisplayToggle: settings, showsStatus: !settings)
                        .padding(.horizontal, OnePlusMetrics.appletGutter)
                        .padding(.top, OnePlusMetrics.contentTop)
                        .padding(.bottom, OnePlusMetrics.settingRow)
                }
                .onePlusScrollIndicators()
                .overlay(alignment: .bottomTrailing) {
                    OnePlusFloatingSettingsButton(isActive: settings) { settings.toggle() }
                        .keyboardShortcut(",")
                        .accessibilityIdentifier("awake.settings")
                        .padding(OnePlusMetrics.actionSpacing)
                }
            }
        }
        .onOpenToolPage("awake") { page in
            if page == "home" { settings = false }
            if page == "settings" { settings = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandOpenSettings)) { _ in
            guard NSApp.keyWindow?.identifier?.rawValue.hasPrefix("awake") == true else { return }
            settings = true
        }
    }
}

struct AwakeSettingsView: View {
    var showsDisplayToggle = true
    var showsStatus = true
    @State private var service = AwakeService.shared
    @State private var hours = 0
    @State private var minutes = 30
    @State private var expiration = Date().addingTimeInterval(3600)
    @State private var processID = ""
    @State private var processError: String?
    @State private var presetToRemove: TimeInterval?

    private var duration: TimeInterval { TimeInterval(hours * 3600 + minutes * 60) }

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            if showsStatus { status }
            if showsDisplayToggle {
                OnePlusCard {
                    OnePlusCardHeader("Display")
                    OnePlusSettingRow("Keep display on", separator: false) {
                        Toggle("Keep Display On", isOn: Binding(
                            get: { service.configuration.keepDisplayOn }, set: service.setKeepDisplayOn
                        )).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                    }
                }
            }
            modes
            quickTimes
            process
        }
        .buttonStyle(OnePlusButtonStyle())
        .onAppear {
            let seconds = max(60, Int(service.configuration.intervalSeconds))
            hours = min(168, seconds / 3600)
            minutes = (seconds / 60) % 60
            expiration = service.configuration.expiresAt ?? Date().addingTimeInterval(3600)
        }
        .confirmationDialog("Remove this quick time?", isPresented: Binding(
            get: { presetToRemove != nil }, set: { if !$0 { presetToRemove = nil } }
        )) {
            Button("Remove", role: .destructive) {
                service.setPresets(service.configuration.presets.filter { $0 != presetToRemove })
                presetToRemove = nil
            }
        }
    }

    private var status: some View {
        OnePlusCard {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                OnePlusStatus(service.statusText, state: service.isActive ? .online : .offline)
                    .monospacedDigit()
                Spacer(minLength: OnePlusMetrics.actionSpacing)
                Button("Turn Off") { service.setMode(.passive) }
                    .disabled(service.configuration.mode == .passive)
            }.padding(OnePlusMetrics.cardPadding)
            if let error = service.assertionError { OnePlusBanner(error, tone: .error) }
        }
    }

    private var modes: some View {
        OnePlusCard {
            OnePlusCardHeader("Mode", systemImage: "moon")
            VStack(spacing: OnePlusMetrics.actionSpacing) {
                OnePlusSegmented(choices: [(AwakeMode.passive, "Off"), (.indefinite, "Indefinitely"),
                                           (.timed, "For a duration"), (.until, "Until a time")],
                                 selection: Binding(get: { service.configuration.mode }, set: selectMode),
                                 accessibilityLabel: "Awake mode")
                if service.configuration.mode == .timed || duration == 0 {
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        OnePlusStepperField("Hours", value: $hours, in: 0...168, unit: "h")
                        OnePlusStepperField("Minutes", value: $minutes, in: 0...59, step: 5, unit: "min")
                        Button("Start") { selectMode(.timed) }.disabled(duration == 0)
                    }
                }
                if service.configuration.mode == .until {
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        DatePicker("End time", selection: $expiration, in: Date()...)
                            .labelsHidden().datePickerStyle(.field).controlSize(.small)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Start") { selectMode(.until) }
                    }
                }
            }.padding(OnePlusMetrics.cardPadding)
        }
    }

    private var quickTimes: some View {
        OnePlusCard {
            OnePlusCardHeader("Quick times", systemImage: "clock")
            ScrollView(.horizontal) {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    ForEach(service.configuration.presets, id: \.self) { seconds in
                        Button(AwakeService.presetLabel(seconds)) { service.setMode(.timed, duration: seconds) }
                            .contextMenu { Button("Remove Preset", role: .destructive) { presetToRemove = seconds } }
                    }
                    Button { service.setPresets(service.configuration.presets + [duration]) } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(OnePlusButtonStyle(.icon))
                    .help("Add the current interval as a preset").accessibilityLabel("Add quick time")
                    .disabled(duration == 0)
                }.padding(OnePlusMetrics.cardPadding)
            }.onePlusScrollIndicators()
        }
    }

    private var process: some View {
        OnePlusCard {
            OnePlusCardHeader("Attach to a process", systemImage: "terminal")
            VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    OnePlusTextField("Process ID", text: $processID, error: processError, onSubmit: attach)
                    Button("Attach", action: attach)
                    if service.configuration.attachedProcessID != nil {
                        Button("Detach") { service.attach(to: nil) }
                    }
                }
                Text(service.configuration.attachedProcessID.map { "Stops when PID \(String($0)) exits." }
                     ?? "End the session when this process exits.")
                    .onePlusText(.caption)
            }.padding(OnePlusMetrics.cardPadding)
        }
    }

    private func selectMode(_ mode: AwakeMode) {
        switch mode {
        case .timed:
            guard duration > 0 else { return }
            service.setMode(mode, duration: duration)
        case .until: service.setMode(mode, until: expiration)
        default: service.setMode(mode)
        }
    }

    private func attach() {
        guard let id = Int32(processID.trimmingCharacters(in: .whitespaces)), id > 0 else {
            processError = "Enter a positive process ID."
            return
        }
        processError = nil
        service.attach(to: id)
        if service.configuration.mode == .passive { service.setMode(.indefinite) }
    }
}
