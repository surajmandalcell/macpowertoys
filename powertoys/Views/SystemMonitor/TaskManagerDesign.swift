import AppKit
import Darwin
import SwiftUI

enum TaskManagerTheme {
    static let desktop = Color(red: 0.043, green: 0.043, blue: 0.043)
    static let window = Color(red: 0.086, green: 0.086, blue: 0.086)
    static let sidebar = Color(red: 0.114, green: 0.114, blue: 0.114)
    static let card = Color(red: 0.125, green: 0.125, blue: 0.125)
    static let cardHover = Color(red: 0.145, green: 0.145, blue: 0.145)
    static let line = Color(red: 0.188, green: 0.188, blue: 0.188)
    static let lineSoft = Color(red: 0.157, green: 0.157, blue: 0.157)
    static let ink = Color(red: 0.929, green: 0.929, blue: 0.929)
    static let secondary = Color(red: 0.627, green: 0.627, blue: 0.627)
    static let muted = Color(red: 0.463, green: 0.463, blue: 0.463)
    static let accent = Color(red: 0.933, green: 0.357, blue: 0.314)

    static let windowContentSize = NSSize(width: 1_080, height: 660)
    static let sidebarWidth: CGFloat = 192
    static let sidebarTitleLeading: CGFloat = 84
    static let headerHeight: CGFloat = 62
    static let contentInset: CGFloat = 20
    static let panelRadius: CGFloat = 9
    static let controlRadius: CGFloat = 5
}

struct TaskManagerPanel<Content: View>: View {
    var textured = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: TaskManagerTheme.panelRadius)
                        .fill(TaskManagerTheme.card)
                    if textured {
                        TaskManagerDitherTexture()
                            .clipShape(RoundedRectangle(cornerRadius: TaskManagerTheme.panelRadius))
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: TaskManagerTheme.panelRadius)
                    .strokeBorder(TaskManagerTheme.line, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: TaskManagerTheme.panelRadius))
    }
}

struct TaskManagerDitherTexture: View {
    var strength = 0.22

    var body: some View {
        Image("TaskManagerGrain")
            .resizable()
            .interpolation(.none)
            .frame(width: 240, height: 150)
            .opacity(strength)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct TaskManagerHeaderArtwork: View {
    var body: some View {
        Image("TaskManagerRibbon")
            .resizable()
            .interpolation(.none)
            .frame(width: 285, height: 90)
            .opacity(0.27)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.26),
                        .init(color: .black, location: 0.82),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct TaskManagerWorkspaceArtwork: View {
    var body: some View {
        Image("TaskManagerRibbon")
            .resizable()
            .interpolation(.none)
            .frame(width: 950, height: 300)
            .opacity(0.09)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct TaskManagerDotTitle: View {
    let text: String
    var height: CGFloat = 17

    private static let glyphs: [Character: [String]] = [
        "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
        "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
        "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
        "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
        "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
        "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
        "G": ["01111", "10000", "10000", "10111", "10001", "10001", "01110"],
        "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
        "I": ["111", "010", "010", "010", "010", "010", "111"],
        "J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
        "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
        "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
        "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
        "N": ["10001", "10001", "11001", "10101", "10011", "10001", "10001"],
        "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
        "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
        "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
        "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
        "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
        "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
        "V": ["10001", "10001", "10001", "10001", "01010", "01010", "00100"],
        "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
        "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
        "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
        "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
        " ": ["000", "000", "000", "000", "000", "000", "000"],
    ]

    private var columns: Int {
        text.uppercased().reduce(0) { width, character in
            width + (Self.glyphs[character]?.first?.count ?? 5) + 1
        } - 1
    }

    var body: some View {
        let scale = height / 7
        Canvas { context, _ in
            var x = 0
            var path = Path()
            for character in text.uppercased() {
                let glyph = Self.glyphs[character] ?? Self.glyphs[" "]!
                for (row, line) in glyph.enumerated() {
                    for (column, bit) in line.enumerated() where bit == "1" {
                        let point = CGPoint(
                            x: (CGFloat(x + column) + 0.5) * scale,
                            y: (CGFloat(row) + 0.5) * scale
                        )
                        let diameter = max(1.15, scale * 0.58)
                        path.addEllipse(in: CGRect(
                            x: point.x - diameter / 2,
                            y: point.y - diameter / 2,
                            width: diameter,
                            height: diameter
                        ))
                    }
                }
                x += (glyph.first?.count ?? 5) + 1
            }
            context.fill(path, with: .color(TaskManagerTheme.ink))
        }
        .frame(width: CGFloat(max(columns, 1)) * scale, height: height)
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

struct TaskManagerHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        ZStack(alignment: .trailing) {
            TaskManagerHeaderArtwork()
                .offset(x: -18, y: -10)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    TaskManagerDotTitle(text: title)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(TaskManagerTheme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                trailing()
            }
            .padding(.horizontal, TaskManagerTheme.contentInset)
        }
        .frame(height: TaskManagerTheme.headerHeight)
        .clipped()
    }
}

enum TaskManagerControlTone: Equatable {
    case standard
    case primary
    case destructive
    case quiet

    var foreground: Color {
        switch self {
        case .primary: TaskManagerTheme.window
        case .destructive: Color(red: 0.937, green: 0.635, blue: 0.608)
        case .standard, .quiet: TaskManagerTheme.ink.opacity(0.88)
        }
    }

    func background(hovering: Bool, pressed: Bool) -> Color {
        switch self {
        case .primary:
            return Color.white.opacity(pressed ? 0.76 : hovering ? 0.94 : 0.86)
        case .destructive:
            return TaskManagerTheme.accent.opacity(pressed ? 0.12 : hovering ? 0.25 : 0.16)
        case .standard:
            return Color.white.opacity(pressed ? 0.045 : hovering ? 0.12 : 0.075)
        case .quiet:
            return Color.white.opacity(pressed ? 0.025 : hovering ? 0.085 : 0.035)
        }
    }

    var border: Color {
        switch self {
        case .primary: Color.white.opacity(0.72)
        case .destructive: TaskManagerTheme.accent.opacity(0.42)
        case .standard, .quiet: TaskManagerTheme.line
        }
    }
}

struct TaskManagerControlButtonStyle: ButtonStyle {
    var tone: TaskManagerControlTone = .standard
    var minHeight: CGFloat = 27
    var horizontalPadding: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        Body(
            label: configuration.label,
            pressed: configuration.isPressed,
            tone: tone,
            minHeight: minHeight,
            horizontalPadding: horizontalPadding
        )
    }

    private struct Body<Label: View>: View {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        let label: Label
        let pressed: Bool
        let tone: TaskManagerControlTone
        let minHeight: CGFloat
        let horizontalPadding: CGFloat

        var body: some View {
            label
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(tone.foreground)
                .padding(.horizontal, horizontalPadding)
                .frame(minHeight: minHeight)
                .background(
                    RoundedRectangle(cornerRadius: TaskManagerTheme.controlRadius)
                        .fill(tone.background(hovering: hovering, pressed: pressed))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: TaskManagerTheme.controlRadius)
                        .strokeBorder(tone.border, lineWidth: 1)
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(tone == .primary ? 0.08 : 0.035))
                        .frame(height: 1)
                        .padding(.horizontal, TaskManagerTheme.controlRadius)
                }
                .contentShape(RoundedRectangle(cornerRadius: TaskManagerTheme.controlRadius))
                .opacity(isEnabled ? 1 : 0.38)
                .onHover { hovering = isEnabled && $0 }
                .animation(
                    UtilityMotion.animation(
                        reduceMotion: reduceMotion,
                        duration: UtilityMotion.interactionDuration
                    ),
                    value: hovering || pressed
                )
        }
    }
}

struct TaskManagerSelect<Value: Hashable>: View {
    let choices: [(Value, String)]
    @Binding var selection: Value
    var width: CGFloat = 120
    var accessibilityLabel: String

    private var selectedTitle: String {
        choices.first { $0.0 == selection }?.1 ?? choices.first?.1 ?? ""
    }

    var body: some View {
        Menu {
            ForEach(choices.indices, id: \.self) { index in
                let choice = choices[index]
                Button {
                    selection = choice.0
                } label: {
                    if choice.0 == selection {
                        Label(choice.1, systemImage: "checkmark")
                    } else {
                        Text(choice.1)
                    }
                }
            }
        } label: {
            TaskManagerMenuLabel(title: selectedTitle, width: width)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .focusEffectDisabled()
        .environment(\.colorScheme, .dark)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct TaskManagerMenuLabel: View {
    let title: String
    let width: CGFloat
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(TaskManagerTheme.secondary)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(TaskManagerTheme.ink.opacity(0.88))
        .padding(.horizontal, 9)
        .frame(width: width, height: 27)
        .background(
            RoundedRectangle(cornerRadius: TaskManagerTheme.controlRadius)
                .fill(TaskManagerControlTone.quiet.background(hovering: hovering, pressed: false))
        )
        .overlay {
            RoundedRectangle(cornerRadius: TaskManagerTheme.controlRadius)
                .strokeBorder(TaskManagerTheme.line)
        }
        .contentShape(RoundedRectangle(cornerRadius: TaskManagerTheme.controlRadius))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

extension View {
    func taskManagerControl(
        _ tone: TaskManagerControlTone = .standard,
        minWidth: CGFloat? = nil,
        minHeight: CGFloat = 27,
        horizontalPadding: CGFloat = 10
    ) -> some View {
        buttonStyle(TaskManagerControlButtonStyle(
            tone: tone,
            minHeight: minHeight,
            horizontalPadding: horizontalPadding
        ))
        .frame(minWidth: minWidth)
        .focusEffectDisabled()
    }
}

extension TaskManagerHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
        trailing = { EmptyView() }
    }
}

struct TaskManagerSearchField: View {
    let prompt: String
    @Binding var text: String
    var width: CGFloat = 300
    var focusTrigger = 0
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(TaskManagerTheme.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 10))
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: 34)
        .background(Color(red: 0.133, green: 0.133, blue: 0.133))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(focused ? Color(red: 0.42, green: 0.36, blue: 0.35) : TaskManagerTheme.line)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear { if focusTrigger > 0 { focused = true } }
        .onChange(of: focusTrigger) { _, _ in focused = true }
    }
}

struct TaskManagerSegments<Value: Hashable>: View {
    let choices: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 1) {
            ForEach(choices.indices, id: \.self) { index in
                let (value, label) = choices[index]
                Button(label) { selection = value }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(selection == value ? TaskManagerTheme.ink : TaskManagerTheme.secondary)
                    .padding(.horizontal, 9)
                    .frame(minHeight: 24)
                    .background(selection == value ? Color.white.opacity(0.09) : .clear,
                                in: RoundedRectangle(cornerRadius: 4))
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color(red: 0.105, green: 0.105, blue: 0.105),
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(TaskManagerTheme.line) }
        .fixedSize()
    }
}

struct TaskManagerHistoryChart: View {
    let values: [Double]
    var secondary: [Double] = []
    var range: ClosedRange<Double> = 0...100
    var unit = "%"
    var compact = false
    var primaryColor = TaskManagerTheme.ink.opacity(0.76)
    var secondaryColor = TaskManagerTheme.accent
    @State private var hoverX: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawGrid(context: &context, size: size)
                    draw(values, color: primaryColor, context: &context, size: size, fills: true)
                    draw(secondary, color: secondaryColor, context: &context, size: size, fills: false)
                }
                if let hoverX, !values.isEmpty {
                    let index = min(max(Int((hoverX / max(proxy.size.width, 1)) * CGFloat(values.count - 1)), 0), values.count - 1)
                    Rectangle()
                        .fill(TaskManagerTheme.secondary.opacity(0.65))
                        .frame(width: 1)
                        .overlay(alignment: .topLeading) {
                            Text(values[index].formatted(.number.precision(.fractionLength(values[index] < 10 ? 1 : 0))) + unit)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(TaskManagerTheme.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color(red: 0.15, green: 0.15, blue: 0.15).opacity(0.97),
                                            in: RoundedRectangle(cornerRadius: 4))
                                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.18)) }
                                .offset(x: hoverX > proxy.size.width - 62 ? -58 : 4, y: 2)
                        }
                        .offset(x: hoverX)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hoverX = min(max(location.x, 0), proxy.size.width)
                case .ended: hoverX = nil
                }
            }
        }
        .frame(minHeight: compact ? 12 : 118)
        .accessibilityLabel(values.last.map { "Latest value \($0.formatted())\(unit)" } ?? "No history")
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        for fraction in [CGFloat(0), 0.5, 1] {
            var path = Path()
            let y = fraction * size.height
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(TaskManagerTheme.lineSoft), lineWidth: 0.65)
        }
    }

    private func draw(
        _ samples: [Double], color: Color, context: inout GraphicsContext,
        size: CGSize, fills: Bool
    ) {
        let samples = samples.filter(\.isFinite)
        guard !samples.isEmpty else { return }
        let span = max(range.upperBound - range.lowerBound, 0.001)
        let points = samples.enumerated().map { index, value in
            CGPoint(
                x: samples.count == 1 ? size.width : CGFloat(index) / CGFloat(samples.count - 1) * size.width,
                y: size.height - CGFloat((min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span) * size.height
            )
        }
        if fills {
            var area = Path()
            area.move(to: CGPoint(x: 0, y: size.height))
            points.forEach { area.addLine(to: $0) }
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.closeSubpath()
            context.drawLayer { layer in
                layer.clip(to: area)
                let order = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
                var dots = Path()
                let pitch: CGFloat = 4
                for row in 0..<Int(ceil(size.height / pitch)) {
                    let density = (1 - CGFloat(row) * pitch / max(size.height, 1)) * 0.55
                    for column in 0..<Int(ceil(size.width / pitch))
                    where CGFloat(order[(row % 4) * 4 + column % 4]) / 16 < density {
                        dots.addEllipse(in: CGRect(x: CGFloat(column) * pitch + 1.5,
                                                   y: CGFloat(row) * pitch + 1.5,
                                                   width: 0.8, height: 0.8))
                    }
                }
                layer.fill(dots, with: .color(Color.white.opacity(0.22)))
            }
        }
        var path = Path()
        path.addLines(points)
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: compact ? 1 : 1.2, lineCap: .round, lineJoin: .round))
    }
}

enum TaskManagerHardwareSummary {
    static let coreLayout: (performance: Int, efficiency: Int)? = {
        guard let performance = sysctlInt("hw.perflevel0.logicalcpu"),
              let efficiency = sysctlInt("hw.perflevel1.logicalcpu"),
              performance > 0, efficiency > 0 else { return nil }
        return (performance, efficiency)
    }()

    static let current: String = {
        let chip = sysctlString("machdep.cpu.brand_string") ?? sysctlString("hw.model") ?? "Mac"
        let memory = ByteCountFormatter.string(
            fromByteCount: Int64(min(ProcessInfo.processInfo.physicalMemory, UInt64(Int64.max))),
            countStyle: .memory
        )
        return "\(chip) · \(ProcessInfo.processInfo.activeProcessorCount) cores · \(memory)"
    }()

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(cString: bytes)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}
