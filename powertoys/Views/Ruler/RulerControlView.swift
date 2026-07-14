import SwiftUI

struct RulerControlView: View {
    @State private var manager = RulerManager.shared
    @State private var guides = RulerGuideController.shared
    @State private var copyFormat = RulerCopyFormat.plain
    @State private var calibrationText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
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

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "ruler")
                .foregroundStyle(Color.accentColor)
            Text("Ruler Settings").font(.system(size: 13, weight: .medium))
            Spacer()
            Menu {
                ForEach(RulerOrientation.allCases) { orientation in
                    Button(orientation.title) { manager.create(orientation) }
                }
            } label: {
                Label("New Ruler", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button("Measure Region") { MeasurementOverlayController.shared.begin() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .contentShape(Rectangle())
        }
        .padding(.horizontal, UtilityLayout.horizontalInset)
        .padding(.vertical, UtilityLayout.headerVerticalInset)
    }

    private var settingsSection: some View {
        section("APPEARANCE AND UNITS") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Units").foregroundStyle(.secondary)
                    HStack {
                        Picker("Units", selection: styleBinding(\.unit)) {
                            ForEach(RulerUnit.allCases) { unit in Text(unit.rawValue).tag(unit) }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                        .contentShape(Rectangle())
                        if manager.style.unit == .millimeters || manager.style.unit == .inches {
                            Text(manager.style.hasCalibration(for: NSScreen.main) ? "Calibrated" : "Estimated")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                GridRow {
                    Text("Zero Corner").foregroundStyle(.secondary)
                    Picker("Zero Corner", selection: styleBinding(\.zeroCorner)) {
                        ForEach(RulerZeroCorner.allCases) { corner in Text(corner.title).tag(corner) }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                    .contentShape(Rectangle())
                }
                GridRow {
                    Text("Color").foregroundStyle(.secondary)
                    ColorPicker("Ruler Color", selection: colorBinding, supportsOpacity: false)
                        .labelsHidden()
                        .contentShape(Rectangle())
                }
                GridRow {
                    Text("Opacity").foregroundStyle(.secondary)
                    Slider(value: styleBinding(\.opacity), in: 0.35...1)
                        .contentShape(Rectangle())
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
                        Text("× physical scale").foregroundStyle(.tertiary)
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
        HStack(spacing: 10) {
            Image(systemName: ruler.isVisible ? "eye" : "eye.slash")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(ruler.orientation.title).font(.system(size: 12, weight: .medium))
                Text("\(Int(ruler.width)) × \(Int(ruler.height))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Copy format", selection: $copyFormat) {
                ForEach(RulerCopyFormat.allCases) { format in Text(format.title).tag(format) }
            }
            .labelsHidden()
            .frame(width: 90)
            .contentShape(Rectangle())
            Button("Copy") { manager.copy(ruler, as: copyFormat) }
                .contentShape(Rectangle())
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
        .padding(.vertical, 4)
    }
}
