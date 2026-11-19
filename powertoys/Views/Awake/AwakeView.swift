import SwiftUI
import OnePlusUI

enum AwakeLayout {
    static let selectWidth: CGFloat = 140
    static let processFieldWidth: CGFloat = 100
}

enum SleepTimerPreset: Hashable, CaseIterable {
    case quarterHour, halfHour, oneHour, twoHours, custom

    var minutes: Int? {
        switch self {
        case .quarterHour: 15
        case .halfHour: 30
        case .oneHour: 60
        case .twoHours: 120
        case .custom: nil
        }
    }

    var title: String {
        switch self {
        case .quarterHour: "15m"
        case .halfHour: "30m"
        case .oneHour: "1h"
        case .twoHours: "2h"
        case .custom: "Custom"
        }
    }
}

struct SleepTimerCard: View {
    var service = SleepTimerService.shared
    @State private var awake = AwakeService.shared
    @State private var preset = SleepTimerPreset.halfHour
    @State private var customMinutes = 45

    private var minutes: Int { preset.minutes ?? customMinutes }

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusLinearMetrics.appletCaptionBelow) {
            OnePlusLinearAppletSection("Sleep timer") {
                if let deadline = service.deadline {
                    running(until: deadline)
                } else {
                    idle
                }
            }
            if service.deadline != nil {
                OnePlusLinearBanner(awake.isActive ? .warning : .info,
                                    title: awake.isActive
                                        ? "Keep awake is on. The Mac still sleeps when the timer ends."
                                        : "Keep awake is off while the sleep timer runs.")
            }
        }
        .buttonStyle(OnePlusLinearButtonStyle(.soft))
        .environment(\.onePlusLinearControlLook, .quietRaised)
    }

    @ViewBuilder
    private var idle: some View {
        OnePlusLinearAppletRow("Sleep after") {
            OnePlusLinearSegmented(choices: SleepTimerPreset.allCases.map { ($0, $0.title) },
                                   selection: $preset, accessibilityLabel: "Sleep after", sizing: .fitted)
                .accessibilityIdentifier("awake.sleep-timer.preset")
        }
        if preset == .custom {
            OnePlusLinearAppletRow("Custom time") {
                OnePlusStepperField("Minutes", value: $customMinutes,
                                    in: 1...SleepTimerService.maximumMinutes, step: 5, unit: "min")
            }
        }
        OnePlusLinearAppletRow("Sleep the Mac",
                               detail: awake.isActive ? "Starting this turns keep awake off." : "The Mac sleeps when the time ends.") {
            Button("Start Timer") { service.start(minutes: minutes) }
                .accessibilityIdentifier("awake.sleep-timer.start")
        }
    }

    private func running(until deadline: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            OnePlusLinearAppletRow(AwakeService.duration(service.remaining(at: context.date) ?? 0),
                                   detail: "Mac sleeps at \(deadline.formatted(date: .omitted, time: .shortened))") {
                Button("Cancel") { service.cancel() }
                    .accessibilityIdentifier("awake.sleep-timer.cancel")
            }
        }
    }
}

private struct AwakeStatusRow: View {
    @State private var service = AwakeService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusLinearMetrics.appletCaptionBelow) {
            OnePlusLinearAppletSection("Status") {
                // shortcut: OnePlusLinearAppletRow 1.2.1 has a String label only; use it once it takes a status dot.
                HStack(spacing: OnePlusLinearMetrics.appletRowGap) {
                    OnePlusStatus(service.statusText, state: service.isActive ? .online : .offline, textRole: .row)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Turn Off") { service.setMode(.passive) }
                        .disabled(service.configuration.mode == .passive)
                }
                .padding(.horizontal, OnePlusLinearMetrics.appletRowPadding)
                .frame(minHeight: OnePlusLinearMetrics.appletRow)
            }
            if let error = service.assertionError { OnePlusBanner(error, tone: .error) }
        }
        .buttonStyle(OnePlusLinearButtonStyle(.soft))
    }
}

/// The whole Awake tool: the main window page hosts it, since Awake has no window.
struct AwakeSettingsView: View {
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
        VStack(alignment: .leading, spacing: OnePlusLinearMetrics.appletSectionGap) {
            AwakeStatusRow()
            modes
            quickTimes
            SleepTimerCard()
            process
        }
        .buttonStyle(OnePlusLinearButtonStyle(.soft))
        .environment(\.onePlusLinearControlLook, .quietRaised)
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

    private var modes: some View {
        OnePlusLinearAppletSection("Session") {
            OnePlusLinearAppletRow("Keep awake") {
                OnePlusLinearSelect(choices: [(AwakeMode.passive, "Off"), (.indefinite, "Indefinitely"),
                                              (.timed, "For a duration"), (.until, "Until a time")],
                                    selection: Binding(get: { service.configuration.mode }, set: selectMode),
                                    accessibilityLabel: "Keep awake", width: AwakeLayout.selectWidth)
                    .accessibilityIdentifier("awake.mode")
            }
            OnePlusLinearAppletRow("Keep display on") {
                Toggle("Keep Display On", isOn: Binding(
                    get: { service.configuration.keepDisplayOn }, set: service.setKeepDisplayOn
                )).toggleStyle(OnePlusLinearSwitchStyle())
                .accessibilityIdentifier("awake.keep-display-on")
            }
            if service.configuration.mode == .timed || duration == 0 {
                OnePlusLinearAppletRow("Duration") {
                    HStack(spacing: OnePlusLinearMetrics.appletActionGap) {
                        OnePlusStepperField("Hours", value: $hours, in: 0...168, unit: "h")
                        OnePlusStepperField("Minutes", value: $minutes, in: 0...59, step: 5, unit: "min")
                        Button("Start") { selectMode(.timed) }.disabled(duration == 0)
                    }
                }
            }
            if service.configuration.mode == .until {
                OnePlusLinearAppletRow("End time") {
                    HStack(spacing: OnePlusLinearMetrics.appletActionGap) {
                        DatePicker("End time", selection: $expiration, in: Date()...)
                            .labelsHidden().datePickerStyle(.field).controlSize(.small)
                        Button("Start") { selectMode(.until) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var quickTimes: some View {
        OnePlusLinearAppletSection("Quick times") {
            ScrollView(.horizontal) {
                HStack(spacing: OnePlusLinearMetrics.appletActionGap) {
                    ForEach(service.configuration.presets, id: \.self) { seconds in
                        Button(quickTimeLabel(seconds)) { service.setMode(.timed, duration: seconds) }
                            .fixedSize()
                            .contextMenu { Button("Remove Preset", role: .destructive) { presetToRemove = seconds } }
                    }
                }
                .padding(.horizontal, OnePlusLinearMetrics.appletRowPadding)
                .frame(minHeight: OnePlusLinearMetrics.appletRow)
            }
            .onePlusScrollIndicators()
            OnePlusLinearAppletRow("New preset", detail: "Save up to eight durations.") {
                HStack(spacing: OnePlusLinearMetrics.appletActionGap) {
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

    private var process: some View {
        VStack(alignment: .leading, spacing: OnePlusLinearMetrics.appletCaptionBelow) {
            OnePlusLinearAppletSection("Attach to a process") {
                OnePlusLinearAppletRow("Process ID", detail: processHelp) {
                    HStack(spacing: OnePlusLinearMetrics.appletActionGap) {
                        OnePlusLinearTextField("Process ID", text: $processID, onSubmit: attach)
                            .frame(width: AwakeLayout.processFieldWidth)
                        Button("Attach", action: attach).fixedSize()
                        if service.configuration.attachedProcessID != nil {
                            Button("Detach") { service.attach(to: nil) }.fixedSize()
                        }
                    }
                }
            }
            if let processError { OnePlusBanner(processError, tone: .error) }
        }
    }

    private var processHelp: String {
        service.configuration.attachedProcessID.map { "Stops when PID \(String($0)) exits." }
            ?? "Stops when this process exits."
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
