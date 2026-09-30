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
                Group {
                    if settings {
                        OnePlusPage(layout: .applet, header: { EmptyView() }) {
                            AwakeSettingsView(showsDisplayToggle: false)
                        }
                    } else {
                        AwakeHomeView()
                    }
                }
                .onePlusFloatingSettingsInset()
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

private struct AwakeHomeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            AwakeStatusCard()
            ScrollView {
                AwakeSettingsView(showsDisplayToggle: false)
            }
            .onePlusScrollIndicators()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, OnePlusMetrics.appletGutter)
        .padding(.top, OnePlusMetrics.contentGap)
    }
}

private struct AwakeStatusCard: View {
    @State private var service = AwakeService.shared

    var body: some View {
        OnePlusCard {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                OnePlusStatus(service.statusText, state: service.isActive ? .success : .offline, textRole: .row)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Turn Off") { service.setMode(.passive) }
                    .disabled(service.configuration.mode == .passive)
            }.padding(OnePlusMetrics.cardPadding)
            if let error = service.assertionError { OnePlusBanner(error, tone: .error) }
        }
        .buttonStyle(OnePlusButtonStyle())
    }
}

struct AwakeSettingsView: View {
    var showsDisplayToggle = true
    @State private var service = AwakeService.shared
    @State private var hours = 0
    @State private var minutes = 30
    @State private var expiration = Date().addingTimeInterval(3600)
    @State private var processID = ""
    @State private var processError: String?
    @State private var presetToRemove: TimeInterval?
    @State private var presetMinutes = 30

    private var duration: TimeInterval { TimeInterval(hours * 3600 + minutes * 60) }

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
                    modes
                    sessionActions
                }
                .frame(minWidth: 2 * OnePlusWindowCanvas.colorPicker.size.width + OnePlusMetrics.cardGap)
                VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                    modes
                    sessionActions
                }
            }
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

    private var sessionActions: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            quickTimes
            process
        }
    }

    private var modes: some View {
        OnePlusCard {
            OnePlusCardHeader("Session", systemImage: "moon")
            OnePlusSettingRow("Keep awake", separator: showsDisplayToggle || service.configuration.mode == .timed || service.configuration.mode == .until || duration == 0) {
                OnePlusSelect(choices: [(AwakeMode.passive, "Off"), (.indefinite, "Indefinitely"),
                                        (.timed, "For a duration"), (.until, "Until a time")],
                              selection: Binding(get: { service.configuration.mode }, set: selectMode),
                              accessibilityLabel: "Keep awake")
                    .accessibilityIdentifier("awake.mode")
            }
            if showsDisplayToggle {
                OnePlusSettingRow("Keep display on", separator: service.configuration.mode == .timed || service.configuration.mode == .until || duration == 0) {
                    Toggle("Keep Display On", isOn: Binding(
                        get: { service.configuration.keepDisplayOn }, set: service.setKeepDisplayOn
                    )).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
            }
            if service.configuration.mode == .timed || service.configuration.mode == .until || duration == 0 {
                VStack(spacing: OnePlusMetrics.actionSpacing) {
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
    }

    private var quickTimes: some View {
        OnePlusCard {
            OnePlusCardHeader("Quick times", systemImage: "clock")
            ScrollView(.horizontal) {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    ForEach(service.configuration.presets, id: \.self) { seconds in
                        Button(quickTimeLabel(seconds)) { service.setMode(.timed, duration: seconds) }
                            .fixedSize()
                            .contextMenu { Button("Remove Preset", role: .destructive) { presetToRemove = seconds } }
                    }
                    if !showsDisplayToggle {
                        Button { service.setPresets(service.configuration.presets + [duration]) } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(OnePlusButtonStyle(.icon))
                        .help("Add the current interval as a preset").accessibilityLabel("Add quick time")
                        .disabled(duration == 0 || service.configuration.presets.count >= 8
                                  || service.configuration.presets.contains(duration))
                    }
                }
            }
            .onePlusScrollIndicators()
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OnePlusMetrics.cardPadding)
            if showsDisplayToggle {
                OnePlusSettingRow("New preset", caption: "Save up to eight durations.", separator: false) {
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        OnePlusStepperField("Preset minutes", value: $presetMinutes, in: 1...10_080, unit: "min")
                        Button("Add") {
                            service.setPresets(service.configuration.presets + [TimeInterval(presetMinutes * 60)])
                        }
                        .disabled(service.configuration.presets.count >= 8
                                  || service.configuration.presets.contains(TimeInterval(presetMinutes * 60)))
                    }
                }
            }
        }
    }

    private var process: some View {
        OnePlusCard {
            OnePlusCardHeader("Attach to a process", systemImage: "terminal") {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    Button("Attach", action: attach)
                    if service.configuration.attachedProcessID != nil {
                        Button("Detach") { service.attach(to: nil) }
                    }
                }
            }
            OnePlusSettingRow("Process ID", caption: service.configuration.attachedProcessID.map {
                "Stops when PID \(String($0)) exits."
            } ?? "Stops when this process exits.", separator: false) {
                OnePlusTextField("Process ID", text: $processID, error: processError, onSubmit: attach)
                    .frame(width: OnePlusMetrics.controlColumn)
            }
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

    private func quickTimeLabel(_ seconds: TimeInterval) -> String {
        AwakeService.presetLabel(seconds)
            .replacingOccurrences(of: "min", with: " min")
            .replacingOccurrences(of: "h", with: " h")
    }

    private func attach() {
        guard let id = Int32(processID.trimmingCharacters(in: .whitespaces)), id > 0 else {
            processError = "Enter a positive process ID."
            return
        }
        guard service.attach(to: id) else {
            processError = "Enter the ID of a running process."
            return
        }
        processError = nil
        if service.configuration.mode == .passive { service.setMode(.indefinite) }
    }
}
