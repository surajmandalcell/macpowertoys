import SwiftUI
import OnePlusUI

/// The host owns the page, scrolling, and gutters. Each tool supplies only cards.
struct ToolSettingsContent: View {
    let toolID: String

    @ViewBuilder
    var body: some View {
        switch toolID {
        case "rclone": RcloneSettingsView()
        case "ruler": RulerLauncherSettingsView()
        case "awake": AwakeSettingsView()
        case "color-picker": ColorPickerSettingsView()
        case "text-extractor": TextExtractorSettingsView()
        case "mac-tweaks": MacTweaksSettingsContent()
        case "input-devices": InputDevicesSettingsContent()
        case "portman": PortmanSettingsView()
        case "logs": LogsSettingsView()
        default:
            if let settings = ProPackage.settingsView(for: toolID) { settings }
            else { OnePlusEmptyState("No settings available", systemImage: "slider.horizontal.3") }
        }
    }
}

/// Ruler defaults inline on the tool page. Reads and writes the FreeRuler `prefs`, so the Defaults window and
/// this page stay in step through KVO and UserDefaults.
struct RulerLauncherSettingsView: View {
    @State private var settings = SettingsManager.shared
    @State private var revision = 0

    var body: some View {
        let _ = revision
        VStack(alignment: .leading, spacing: OnePlusLinearEditorialMetrics.blockGap) {
            OnePlusLinearAppletSection("Defaults for new rulers") {
                OnePlusLinearAppletRow("Unit", systemImage: "ruler") {
                    OnePlusLinearSegmented(choices: [(Unit.pixels, "px"), (.millimeters, "mm"), (.inches, "in")],
                                           selection: binding(\.unit), accessibilityLabel: "Unit")
                }
                OnePlusLinearAppletRow("Dimensions", systemImage: "arrow.up.left.and.arrow.down.right") {
                    HStack(spacing: 6) {
                        OnePlusStepperField("Width", value: length(horizontal: true), in: 1...10000)
                        Text("×").linearText(color: OnePlusLinearColor.muted)
                        OnePlusStepperField("Height", value: length(horizontal: false), in: 1...10000)
                    }
                }
                OnePlusLinearAppletRow("Ruler color", systemImage: "paintpalette") { OnePlusLinearColorWell("Ruler color", color: binding(\.rulerColor)) }
                OnePlusLinearAppletSliderRow("Foreground opacity", value: percent(\.foregroundOpacity), in: 0.05...1, systemImage: "circle.lefthalf.filled")
                OnePlusLinearAppletSliderRow("Background opacity", value: percent(\.backgroundOpacity), in: 0.05...1, systemImage: "square.lefthalf.filled")
                OnePlusLinearAppletSliderRow("Border opacity", value: percent(\.borderOpacity), systemImage: "square.dashed")
            }
            OnePlusLinearAppletSection("Behavior") {
                toggleRow("Float ruler above other applications", \.floatRulers, glyph: "square.stack.3d.up")
                toggleRow("Show ruler shadow", \.rulerShadow, glyph: "shadow")
                toggleRow("Move both wings together", \.groupRulers, glyph: "link")
            }
            OnePlusLinearAppletGroup {
                OnePlusLinearAppletRow("Settings for the active rulers", detail: "Each ruler keeps its own color, size, and opacity.",
                                       systemImage: "rectangle.on.rectangle") {
                    Button("Open Ruler Settings") {
                        ToolActionRouter.shared.execute(ToolActionRequest(action: .rulerSettings))
                    }
                    .buttonStyle(OnePlusLinearButtonStyle(.raised))
                }
            }
            Button("Reset to Factory Defaults", role: .destructive) { prefs.resetRulerDefaultsToFactoryDefaults() }
                .buttonStyle(OnePlusLinearButtonStyle(.resetBlock))
        }
        .transformEnvironment(\.onePlusLinearControlLook) { if $0 == nil { $0 = .quietRaised } }
        .disabled(!settings.isToolEnabled("ruler") || settings.isToolTransitioning("ruler"))
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in revision &+= 1 }
    }

    private func toggleRow(_ label: String, _ key: ReferenceWritableKeyPath<Prefs, Bool>, glyph: String) -> some View {
        OnePlusLinearAppletRow(label, systemImage: glyph) {
            Toggle(label, isOn: binding(key)).toggleStyle(OnePlusLinearSwitchStyle()).labelsHidden()
        }
    }

    private func binding<Value>(_ key: ReferenceWritableKeyPath<Prefs, Value>) -> Binding<Value> {
        Binding(get: { prefs[keyPath: key] }, set: { prefs[keyPath: key] = $0; revision &+= 1 })
    }

    private func percent(_ key: ReferenceWritableKeyPath<Prefs, Int>) -> Binding<Double> {
        Binding(get: { Double(prefs[keyPath: key]) / 100 },
                set: { prefs[keyPath: key] = Int(($0 * 100).rounded()); revision &+= 1 })
    }

    // shortcut: whole units only (1 in steps for inches); the Defaults window keeps decimals. Upgrade if asked.
    private func length(horizontal: Bool) -> Binding<Int> {
        Binding(get: {
            let pixels = horizontal ? prefs.effectiveDefaultHorizontalLength() : prefs.effectiveDefaultVerticalLength()
            return Int(rulerDimensionValue(fromPixelLength: pixels, unit: prefs.unit, screen: NSScreen.main).rounded())
        }, set: { value in
            let pixels = Double(rulerPixelLength(fromDimensionValue: CGFloat(value), unit: prefs.unit, screen: NSScreen.main))
            if horizontal { prefs.defaultHorizontalLength = pixels } else { prefs.defaultVerticalLength = pixels }
            revision &+= 1
        })
    }
}
