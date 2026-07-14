import SwiftUI

enum RulerSettingsLayout {
    static let windowWidth: CGFloat = 560
    static let windowHeight: CGFloat = 600
}

struct RulerControlView: View {
    @State private var manager = RulerManager.shared
    @State private var guides = RulerGuideController.shared
    @State private var copyFormat = RulerCopyFormat.plain
    @State private var calibrationText = ""
    @State private var showsCalibrationHelp = false

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(
            width: RulerSettingsLayout.windowWidth,
            height: RulerSettingsLayout.windowHeight
        )
        .ignoresSafeArea(.container, edges: .top)
        .utilityWindowBackground()
        .onAppear {
            manager.restore()
            calibrationText = manager.style.calibration(for: NSScreen.main).formatted(.number.precision(.fractionLength(2)))
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolActionRequested)) { note in
            guard let action = note.object as? ToolActionID, action == .rulerSettings else { return }
            manager.restore()
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UtilityLayout.sectionSpacing) {
                settingsSection
                guidesSection
                activeSection
                measurementsSection
            }
            .padding(.horizontal, UtilityLayout.horizontalInset)
            .padding(.top, UtilityLayout.contentTopInset)
            .padding(.bottom, UtilityLayout.contentBottomInset)
        }
        .thinScrollIndicators()
    }

    private var header: some View {
        CompactTitlebar {
            CompactTitlebarTitle(title: "Ruler Settings")
        } actions: {
            HStack(spacing: 8) {
                Menu {
                    ForEach(RulerOrientation.allCases) { orientation in
                        Button(orientation.title) { manager.create(orientation) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("New Ruler")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .medium))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Create a ruler")
                .accessibilityIdentifier("ruler.new")
                CompactTitlebarButton(title: "Measure Region", isPrimary: true) {
                    MeasurementOverlayController.shared.begin()
                }
                .contentShape(Rectangle())
                .help("Measure a screen region")
                .accessibilityIdentifier("ruler.measure")
            }
        }
    }

    private var settingsSection: some View {
        section("APPEARANCE AND UNITS") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Units")
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Picker("Units", selection: styleBinding(\.unit)) {
                        ForEach(RulerUnit.allCases) { unit in Text(unit.title).tag(unit) }
                    }
                    .labelsHidden()
                    .frame(width: 160, alignment: .leading)
                    .contentShape(Rectangle())
                    .gridColumnAlignment(.leading)
                }
                GridRow {
                    Text("Zero Corner").foregroundStyle(.secondary)
                    Picker("Zero Corner", selection: styleBinding(\.zeroCorner)) {
                        ForEach(RulerZeroCorner.allCases) { corner in Text(corner.title).tag(corner) }
                    }
                    .labelsHidden()
                    .frame(width: 160, alignment: .leading)
                    .contentShape(Rectangle())
                }
                GridRow {
                    Text("Color").foregroundStyle(.secondary)
                    ColorPicker("Ruler Color", selection: colorBinding, supportsOpacity: false)
                        .labelsHidden()
                        .contentShape(Rectangle())
                }
                GridRow {
                    Text("Background Opacity").foregroundStyle(.secondary)
                    HStack {
                        Slider(value: styleBinding(\.backgroundOpacity), in: 0.1...1)
                            .contentShape(Rectangle())
                        Text(manager.style.backgroundOpacity, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                GridRow {
                    Text("Default Size").foregroundStyle(.secondary)
                    HStack {
                        Slider(value: styleBinding(\.defaultSizeFraction), in: 0.1...0.9, step: 0.05)
                            .contentShape(Rectangle())
                        Text(manager.style.defaultSizeFraction, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                GridRow {
                    Text("Window").foregroundStyle(.secondary)
                    HStack {
                        Toggle("Float", isOn: styleBinding(\.floats))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .contentShape(Rectangle())
                        Toggle("Shadow", isOn: styleBinding(\.hasShadow))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .contentShape(Rectangle())
                    }
                }
                GridRow {
                    Text("Calibration").foregroundStyle(.secondary)
                    HStack {
                        TextField("1.00", text: $calibrationText)
                            .frame(width: 70)
                            .contentShape(Rectangle())
                        Button("Apply") {
                            guard let value = Double(calibrationText), (0.25...4).contains(value) else { return }
                            manager.setCalibration(value, for: NSScreen.main)
                        }
                        .contentShape(Rectangle())
                        Button {
                            showsCalibrationHelp.toggle()
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                        .contentShape(Rectangle())
                        .help("About automatic calibration")
                        .popover(isPresented: $showsCalibrationHelp, arrowEdge: .trailing) {
                            Text("Pixels and physical units are calculated automatically from the current display's scale and reported dimensions. Adjust this value only if a real-world measurement is off.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 240, alignment: .leading)
                                .padding(14)
                        }
                        Text(abs(manager.style.calibration(for: NSScreen.main) - 1) < 0.001 ? "Automatic" : "Adjusted")
                            .foregroundStyle(.tertiary)
                    }
                }
                GridRow {
                    Text("Aspect").foregroundStyle(.secondary)
                    HStack {
                        preset("Free", nil)
                        preset("1:1", 1)
                        preset("4:3", 4 / 3)
                        preset("16:9", 16 / 9)
                    }
                }
            }
            .font(.system(size: 12))
        }
    }

    private var guidesSection: some View {
        section("GUIDES") {
            HStack(spacing: 12) {
                Button(guides.isVisible ? "Hide Crosshair" : "Show Crosshair") {
                    guides.toggleCrosshair()
                }
                Button("Pin at Pointer") { guides.pinGuidesAtPointer() }
                if !guides.verticalGuides.isEmpty {
                    Button(guides.isEditing ? "Done Editing" : "Edit Guides") {
                        guides.toggleEditing()
                    }
                    Button("Clear", role: .destructive) { guides.clearGuides() }
                }
                Spacer()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
        }
    }

    private var activeSection: some View {
        section("ACTIVE RULERS") {
            if manager.rulers.isEmpty {
                Text("No rulers yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 54)
            } else {
                ForEach(manager.rulers) { ruler in
                    RulerRow(ruler: ruler, copyFormat: $copyFormat)
                }
                HStack {
                    Button("Group Visible") { manager.groupVisible() }
                        .contentShape(Rectangle())
                    Button("Ungroup") { manager.ungroupAll() }
                        .contentShape(Rectangle())
                    Spacer()
                    Button("Remove All", role: .destructive) { manager.removeAll() }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
            }
        }
    }

    private var measurementsSection: some View {
        section("MEASUREMENT HISTORY") {
            if manager.measurements.isEmpty {
                Text("Measured regions appear here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                ForEach(manager.measurements) { measurement in
                    HStack {
                        Text(RulerCopyFormat.plain.render(frame: measurement.frame))
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(copyFormat.render(frame: measurement.frame), forType: .string)
                        }
                        .contentShape(Rectangle())
                        Button {
                            manager.toggleMeasurementPin(measurement.id)
                        } label: {
                            Image(systemName: measurement.isPinned ? "pin.fill" : "pin")
                        }
                        Button(role: .destructive) {
                            manager.removeMeasurement(measurement.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    .buttonStyle(.borderless)
                }
                HStack {
                    Picker("Copy format", selection: $copyFormat) {
                        ForEach(RulerCopyFormat.allCases) { format in Text(format.title).tag(format) }
                    }
                    .frame(width: 130)
                    .contentShape(Rectangle())
                    Spacer()
                    Button("Clear Unpinned", role: .destructive) { manager.clearMeasurements() }
                        .contentShape(Rectangle())
                }
                .font(.system(size: 11))
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).utilitySectionHeader()
            content()
                .utilitySectionCard()
        }
    }

    private func styleBinding<T>(_ keyPath: WritableKeyPath<RulerStyle, T>) -> Binding<T> {
        Binding(get: { manager.style[keyPath: keyPath] }, set: { manager.style[keyPath: keyPath] = $0 })
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: manager.style.color) },
            set: { value in
                guard let converted = NSColor(value).usingColorSpace(.sRGB) else { return }
                manager.style.red = converted.redComponent
                manager.style.green = converted.greenComponent
                manager.style.blue = converted.blueComponent
            }
        )
    }

    private func preset(_ title: String, _ ratio: Double?) -> some View {
        let isSelected = manager.aspectRatio == ratio
        return Button(title) { manager.aspectRatio = ratio }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: isSelected ? .medium : .regular))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
    }
}

private struct RulerRow: View {
    let ruler: RulerState
    @Binding var copyFormat: RulerCopyFormat
    @State private var manager = RulerManager.shared

    var body: some View {
        VStack(spacing: 8) {
            titleRow
            controlsRow
        }
        .padding(.vertical, 4)
    }

    private var titleRow: some View {
        HStack(spacing: 10) {
            Image(systemName: ruler.isVisible ? "eye" : "eye.slash")
                .foregroundStyle(.secondary)
            Text(ruler.orientation.title).font(.system(size: 12, weight: .medium))
            Spacer()
            if ruler.orientation == .joined {
                Button("H") { manager.toggleArm(ruler.id, horizontal: true) }
                    .contentShape(Rectangle())
                    .foregroundStyle(ruler.showsHorizontalArm ? .primary : .secondary)
                    .help("Toggle horizontal arm")
                Button("V") { manager.toggleArm(ruler.id, horizontal: false) }
                    .contentShape(Rectangle())
                    .foregroundStyle(ruler.showsVerticalArm ? .primary : .secondary)
                    .help("Toggle vertical arm")
            }
            Button { manager.reset(ruler.id) } label: { Image(systemName: "arrow.counterclockwise") }
                .contentShape(Rectangle())
                .help("Reset ruler")
            Button(ruler.isVisible ? "Hide" : "Show") {
                ruler.isVisible ? manager.hide(ruler.id) : manager.show(ruler.id)
            }
            .contentShape(Rectangle())
            Button(role: .destructive) { manager.remove(ruler.id) } label: { Image(systemName: "trash") }
                .contentShape(Rectangle())
                .help("Remove ruler")
        }
        .buttonStyle(.borderless)
    }

    private var controlsRow: some View {
        HStack(spacing: 8) {
            Text("Size")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            sizeControls
            Spacer()
            Picker("Copy format", selection: $copyFormat) {
                ForEach(RulerCopyFormat.allCases) { format in Text(format.title).tag(format) }
            }
            .labelsHidden()
            .frame(width: 90)
            .contentShape(Rectangle())
            Button("Copy") { manager.copy(ruler, as: copyFormat) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var sizeControls: some View {
        switch ruler.orientation {
        case .horizontal:
            dimensionControl("W", value: widthBinding)
        case .vertical:
            dimensionControl("H", value: heightBinding)
        case .joined:
            dimensionControl("W", value: widthBinding)
            Text("×").foregroundStyle(.tertiary)
            dimensionControl("H", value: heightBinding)
        }
    }

    private func dimensionControl(_ label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            TextField(label, value: value, format: .number.precision(.fractionLength(0)))
                .labelsHidden()
                .frame(width: 52)
                .multilineTextAlignment(.trailing)
            Stepper(label, value: value, in: RulerGeometry.thickness...10_000, step: 10)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    private var widthBinding: Binding<Double> {
        Binding(
            get: { currentRuler.width },
            set: { manager.setSize(ruler.id, width: $0) }
        )
    }

    private var heightBinding: Binding<Double> {
        Binding(
            get: { currentRuler.height },
            set: { manager.setSize(ruler.id, height: $0) }
        )
    }

    private var currentRuler: RulerState {
        manager.rulers.first { $0.id == ruler.id } ?? ruler
    }
}
