import SwiftUI

enum MacTweaksPalette {
    static let window = Color(red: 0.086, green: 0.086, blue: 0.086)
    static let sidebar = Color(red: 0.114, green: 0.114, blue: 0.114)
    static let panel = Color(red: 0.125, green: 0.125, blue: 0.125)
    static let panelRaised = Color(red: 0.145, green: 0.145, blue: 0.145)
    static let line = Color(red: 0.20, green: 0.20, blue: 0.20)
    static let text = Color(red: 0.91, green: 0.91, blue: 0.91)
    static let secondary = Color(red: 0.64, green: 0.64, blue: 0.64)
    static let muted = Color(red: 0.47, green: 0.47, blue: 0.47)
    static let accent = Color(red: 0.93, green: 0.36, blue: 0.31)
}

enum MacTweaksGlyphName: Hashable {
    case input, dock, finder, windows, screenshots, apps, power, menubar
    case motion, animation, layers
}

struct MacTweaksGlyph: View {
    let name: MacTweaksGlyphName
    var color = MacTweaksPalette.secondary
    var lineWidth: CGFloat = 1.6

    var body: some View {
        MacTweaksGlyphShape(name: name)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .accessibilityHidden(true)
    }
}

private struct MacTweaksGlyphShape: Shape {
    let name: MacTweaksGlyphName

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch name {
        case .motion:
            path.addEllipse(in: CGRect(x: 4, y: 4, width: 16, height: 16))
            path.move(to: .init(x: 12, y: 7)); path.addLine(to: .init(x: 12, y: 12)); path.addLine(to: .init(x: 15, y: 14))
        case .animation:
            path.move(to: .init(x: 4, y: 6)); path.addLine(to: .init(x: 10, y: 12)); path.addLine(to: .init(x: 4, y: 18))
            path.move(to: .init(x: 11, y: 6)); path.addLine(to: .init(x: 17, y: 12)); path.addLine(to: .init(x: 11, y: 18))
            path.move(to: .init(x: 20, y: 6)); path.addLine(to: .init(x: 20, y: 18))
        case .layers:
            path.move(to: .init(x: 12, y: 3)); path.addLine(to: .init(x: 21, y: 8)); path.addLine(to: .init(x: 12, y: 13)); path.addLine(to: .init(x: 3, y: 8)); path.closeSubpath()
            path.move(to: .init(x: 3, y: 12)); path.addLine(to: .init(x: 12, y: 17)); path.addLine(to: .init(x: 21, y: 12))
            path.move(to: .init(x: 3, y: 16)); path.addLine(to: .init(x: 12, y: 21)); path.addLine(to: .init(x: 21, y: 16))
        case .input:
            path.addRoundedRect(in: CGRect(x: 2, y: 5, width: 20, height: 14), cornerSize: .init(width: 3, height: 3))
            for y in [9.0, 13.0] {
                for x in [6.0, 10.0, 14.0, 18.0] {
                    path.move(to: .init(x: x, y: y)); path.addLine(to: .init(x: x + 0.01, y: y))
                }
            }
            path.move(to: .init(x: 8, y: 16)); path.addLine(to: .init(x: 16, y: 16))
        case .dock:
            path.addRoundedRect(in: CGRect(x: 3, y: 4, width: 18, height: 16), cornerSize: .init(width: 3, height: 3))
            path.move(to: .init(x: 7, y: 16)); path.addLine(to: .init(x: 17, y: 16))
        case .finder:
            path.move(to: .init(x: 3, y: 7)); path.addLine(to: .init(x: 3, y: 5))
            path.addCurve(to: .init(x: 5, y: 3), control1: .init(x: 3, y: 3.9), control2: .init(x: 3.9, y: 3))
            path.addLine(to: .init(x: 10, y: 3)); path.addLine(to: .init(x: 12, y: 6)); path.addLine(to: .init(x: 19, y: 6))
            path.addCurve(to: .init(x: 21, y: 8), control1: .init(x: 20.1, y: 6), control2: .init(x: 21, y: 6.9))
            path.addLine(to: .init(x: 21, y: 19)); path.addLine(to: .init(x: 3, y: 19)); path.closeSubpath()
        case .windows:
            path.addRoundedRect(in: CGRect(x: 3, y: 4, width: 18, height: 16), cornerSize: .init(width: 2, height: 2))
            path.move(to: .init(x: 3, y: 8)); path.addLine(to: .init(x: 21, y: 8))
            path.move(to: .init(x: 7, y: 6)); path.addLine(to: .init(x: 7.01, y: 6))
            path.move(to: .init(x: 10, y: 6)); path.addLine(to: .init(x: 10.01, y: 6))
        case .screenshots:
            path.move(to: .init(x: 7, y: 3)); path.addLine(to: .init(x: 3, y: 3)); path.addLine(to: .init(x: 3, y: 7))
            path.move(to: .init(x: 17, y: 3)); path.addLine(to: .init(x: 21, y: 3)); path.addLine(to: .init(x: 21, y: 7))
            path.move(to: .init(x: 3, y: 17)); path.addLine(to: .init(x: 3, y: 21)); path.addLine(to: .init(x: 7, y: 21))
            path.move(to: .init(x: 21, y: 17)); path.addLine(to: .init(x: 21, y: 21)); path.addLine(to: .init(x: 17, y: 21))
            path.addEllipse(in: CGRect(x: 8, y: 8, width: 8, height: 8))
        case .apps:
            for origin in [CGPoint(x: 3, y: 3), .init(x: 15, y: 3), .init(x: 3, y: 15), .init(x: 15, y: 15)] {
                path.addRoundedRect(in: CGRect(origin: origin, size: .init(width: 6, height: 6)), cornerSize: .init(width: 1, height: 1))
            }
        case .power:
            path.move(to: .init(x: 13, y: 2)); path.addLine(to: .init(x: 4, y: 14)); path.addLine(to: .init(x: 11, y: 14))
            path.addLine(to: .init(x: 10, y: 22)); path.addLine(to: .init(x: 20, y: 9)); path.addLine(to: .init(x: 12, y: 9)); path.closeSubpath()
        case .menubar:
            path.addRoundedRect(in: CGRect(x: 3, y: 4, width: 18, height: 16), cornerSize: .init(width: 2, height: 2))
            path.move(to: .init(x: 3, y: 8)); path.addLine(to: .init(x: 21, y: 8))
            path.move(to: .init(x: 15, y: 6)); path.addLine(to: .init(x: 15.01, y: 6))
            path.move(to: .init(x: 18, y: 6)); path.addLine(to: .init(x: 18.01, y: 6))
        }
        return path.applying(.init(scaleX: rect.width / 24, y: rect.height / 24))
    }
}

struct MacTweaksDither: View {
    var strength = 0.18

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, 240)
            ZStack(alignment: .topTrailing) {
                RadialGradient(
                    colors: [.white.opacity(strength * 0.09), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: width * 0.72
                )
                .frame(width: width, height: min(proxy.size.height, 118))
                Canvas { context, size in
                    let startX = max(0, size.width - width)
                    let matrix = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
                    for y in stride(from: 2.0, through: min(size.height, 112), by: 3.0) {
                        for x in stride(from: startX, through: size.width, by: 3.0) {
                            let row = Int(y / 3).quotientAndRemainder(dividingBy: 4).remainder
                            let column = Int(x / 3).quotientAndRemainder(dividingBy: 4).remainder
                            let threshold = Double(matrix[row * 4 + column]) / 15
                            let horizontal = max(0, (x - startX) / max(1, width))
                            let vertical = max(0, 1 - y / 116)
                            let fade = Double(horizontal * vertical)
                            guard threshold < fade * 0.72 else { continue }
                            context.fill(
                                Path(CGRect(x: x, y: y, width: 0.85, height: 0.85)),
                                with: .color(.white.opacity(strength * fade * 0.74))
                            )
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum MacTweaksPreviewKind: String {
    case dockReveal, minimize, layout, finder, windows, screenshots, apps, power, menubar

    var accessibilityName: String {
        switch self {
        case .dockReveal: "Dock reveal timing"
        case .minimize: "window minimization"
        case .layout: "Dock layout and app switching"
        case .finder: "Finder settings"
        case .windows: "window behavior"
        case .screenshots: "screenshot capture"
        case .apps: "application behavior"
        case .power: "keep awake"
        case .menubar: "menu bar spacing"
        }
    }

    var cycleDuration: TimeInterval {
        switch self {
        case .dockReveal: 5.2
        case .minimize: 6.2
        case .layout: 7.0
        case .finder, .apps: 4.6
        case .windows: 4.8
        case .screenshots: 5.4
        case .power: 4.2
        case .menubar: 4.6
        }
    }
}

struct MacTweaksPreviewView: View {
    let kind: MacTweaksPreviewKind

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var startedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isHovering || reduceMotion)) { timeline in
            let progress = progress(at: timeline.date)
            GeometryReader { proxy in
                let sceneHeight = max(1, proxy.size.height - 2)
                let scale = min(proxy.size.width / 600, sceneHeight / 304)
                ZStack(alignment: .bottomLeading) {
                    MacTweaksPalette.window
                    preview(progress: progress)
                        .frame(width: 600, height: 304)
                        .scaleEffect(scale)
                        .position(x: proxy.size.width / 2, y: sceneHeight / 2)
                        .drawingGroup(opaque: false, colorMode: .linear)
                    HStack(spacing: 2) {
                        ForEach(0..<4, id: \.self) { _ in
                            Rectangle().fill(Color.white.opacity(0.10))
                        }
                    }
                    .frame(height: 2)
                    LinearGradient(
                        colors: [Color(white: 0.60), Color(white: 0.87)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * CGFloat(progress), height: 2)
                    .opacity(isHovering && !reduceMotion ? 1 : 0)
                }
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .onHover { hovering in
            guard hovering != isHovering else { return }
            isHovering = hovering
            startedAt = hovering ? Date() : nil
        }
        .overlay(Color.white.opacity(isHovering ? 0.012 : 0).allowsHitTesting(false))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
        .transaction { transaction in
            if reduceMotion { transaction.disablesAnimations = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of \(kind.accessibilityName)")
        .accessibilityValue(isHovering && !reduceMotion ? "Playing" : "At rest")
        .accessibilityIdentifier("mac-tweaks.preview.\(kind.rawValue)")
    }

    private func progress(at date: Date) -> Double {
        guard isHovering, !reduceMotion, let startedAt else { return 0 }
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        return elapsed.truncatingRemainder(dividingBy: kind.cycleDuration) / kind.cycleDuration
    }

    @ViewBuilder
    private func preview(progress: Double) -> some View {
        if kind == .power {
            PowerPreviewScene(progress: progress, active: isHovering && !reduceMotion)
        } else {
            DesktopPreviewScene(kind: kind, progress: progress, active: isHovering && !reduceMotion)
        }
    }
}

private struct DesktopPreviewScene: View {
    let kind: MacTweaksPreviewKind
    let progress: Double
    let active: Bool

    private var p: Double { active ? progress : 0 }
    private var minimizeAmount: CGFloat { clamp01(segment(p, 0.15, 0.34) - segment(p, 0.61, 0.82)) }
    private var dockHiddenAmount: CGFloat { kind == .dockReveal ? clamp01(segment(p, 0.12, 0.24) - segment(p, 0.56, 0.69)) : 0 }
    private var menuHiddenAmount: CGFloat { kind == .menubar ? clamp01(segment(p, 0.15, 0.28) - segment(p, 0.55, 0.69)) : 0 }
    private var stackAmount: CGFloat { kind == .layout ? clamp01(segment(p, 0.08, 0.18) - segment(p, 0.34, 0.45)) : 0 }
    private var switcherAmount: CGFloat { kind == .layout ? clamp01(segment(p, 0.50, 0.60) - segment(p, 0.82, 0.92)) : 0 }
    private var captureAmount: CGFloat { kind == .screenshots ? clamp01(segment(p, 0.16, 0.27) - segment(p, 0.48, 0.58)) : 0 }
    private var thumbnailAmount: CGFloat { kind == .screenshots ? clamp01(segment(p, 0.48, 0.60) - segment(p, 0.80, 0.92)) : 0 }
    private var hiddenFileAmount: CGFloat { kind == .finder ? clamp01(segment(p, 0.18, 0.32) - segment(p, 0.68, 0.82)) : 0 }
    private var appSelectionAmount: CGFloat { kind == .apps ? clamp01(segment(p, 0.18, 0.34) - segment(p, 0.68, 0.84)) : 0 }
    private var windowVisibility: CGFloat {
        guard kind == .windows else { return 1 }
        return clamp01(1 - segment(p, 0.18, 0.30) + segment(p, 0.56, 0.70))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            MacTweaksFilmBackground()
            if kind != .finder {
                menuBar.offset(y: -18 * menuHiddenAmount)
            }
            finderWindow
            if kind == .screenshots { captureOverlay }
            if kind == .layout { layoutOverlays }
            if kind == .screenshots { captureThumbnail }
            if kind != .finder { dock }
            if kind != .finder && kind != .apps { cursor }
            LinearGradient(colors: [.clear, .black.opacity(0.18)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)
        }
        .frame(width: 600, height: 304)
        .clipped()
    }

    private var finderWindow: some View {
        let isFinderFeature = kind == .finder
        let width: CGFloat = isFinderFeature ? 404 : 350
        let height: CGFloat = isFinderFeature ? 242 : 206
        let restingY: CGFloat = isFinderFeature ? 160 : 137
        let windowScale = kind == .minimize ? mix(1, 0.087, minimizeAmount) : kind == .windows ? mix(0.985, 1, windowVisibility) : 1
        let title = kind == .apps ? "Application Settings" : "Documents"
        return FinderPreviewWindow(
            hiddenFileOpacity: hiddenFileAmount,
            selectionAmount: appSelectionAmount,
            title: title
        )
        .frame(width: width, height: height)
        .scaleEffect(windowScale)
        .opacity(Double(kind == .windows ? windowVisibility : kind == .minimize ? mix(1, 0.52, minimizeAmount) : 1))
        .position(x: 300, y: restingY)
        .offset(x: kind == .minimize ? 110 * minimizeAmount : 0,
                y: kind == .minimize ? 130 * minimizeAmount : 0)
        .shadow(color: .black.opacity(kind == .screenshots ? 0.50 : 0.34), radius: kind == .screenshots ? 20 : 12, y: 8)
    }

    private var menuBar: some View {
        HStack(spacing: kind == .menubar ? mix(9, 6, menuHiddenAmount) : 6) {
            Text("◆").font(.system(size: 6, weight: .bold))
            Text(kind == .apps ? "Settings" : "Finder").font(.system(size: 8, weight: .semibold))
            ForEach(["File", "Edit", "View", "Go", "Window"], id: \.self) { Text($0) }
            Spacer()
            ForEach(0..<3, id: \.self) { _ in Circle().fill(MacTweaksPalette.secondary).frame(width: 4, height: 4) }
            Text("Tue 10:24").font(.system(size: 7.5).monospacedDigit())
        }
        .font(.system(size: 7.5))
        .foregroundStyle(Color(white: 0.72))
        .padding(.horizontal, 9)
        .frame(width: 600, height: 18)
        .background(Color.black.opacity(0.52))
    }

    private var dock: some View {
        DockPreviewBar(highlighted: stackAmount, minimized: minimizeAmount)
            .frame(width: 360, height: 54)
            .position(x: 300, y: 271 + 53 * dockHiddenAmount)
    }

    private var captureOverlay: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.025))
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white.opacity(0.70), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .frame(width: 382, height: 220)
            .position(x: 297, y: 136)
            .opacity(Double(captureAmount))
    }

    private var captureThumbnail: some View {
        VStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach([Color.red, .yellow, .green], id: \.self) { color in
                    Circle().fill(color.opacity(0.78)).frame(width: 4, height: 4)
                }
                Spacer()
            }
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(index == 1 ? 0.24 : 0.10))
                    .frame(height: 5)
            }
        }
        .padding(7)
        .frame(width: 92, height: 58)
        .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.22), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.55), radius: 12, y: 7)
        .scaleEffect(mix(0.92, 1, thumbnailAmount))
        .position(x: 526, y: 253 + 10 * (1 - thumbnailAmount))
        .opacity(Double(thumbnailAmount))
    }

    private var layoutOverlays: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Downloads").font(.system(size: 9, weight: .semibold))
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                ForEach(["Notes.md", "Reference.pdf", "Screenshots"], id: \.self) { item in
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.45)).frame(width: 10, height: 9)
                        Text(item).font(.system(size: 8))
                    }
                    .padding(.horizontal, 4).frame(height: 17)
                    .background(item == "Reference.pdf" ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 3))
                }
            }
            .foregroundStyle(Color(white: 0.76))
            .padding(10)
            .frame(width: 126, height: 100, alignment: .topLeading)
            .background(Color(white: 0.16).opacity(0.97), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.22), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.46), radius: 14, y: 8)
            .scaleEffect(mix(0.94, 1, stackAmount), anchor: .bottom)
            .position(x: 402, y: 194 + 7 * (1 - stackAmount))
            .opacity(Double(stackAmount))

            HStack(spacing: 13) {
                ForEach(0..<5, id: \.self) { index in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(index == 1 ? Color.blue.opacity(0.72) : Color.white.opacity(0.22))
                            .frame(width: 43, height: 43)
                        Text(["Finder", "Safari", "Mail", "Notes", "Terminal"][index])
                            .font(.system(size: 7.5))
                    }
                    .padding(5)
                    .background(index == 1 ? Color.black.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .foregroundStyle(Color(white: 0.86))
            .padding(12)
            .background(Color(white: 0.30).opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.19), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.48), radius: 18, y: 9)
            .scaleEffect(mix(0.96, 1, switcherAmount))
            .position(x: 300, y: 153)
            .opacity(Double(switcherAmount))
        }
    }

    private var cursor: some View {
        let location = cursorPosition
        return Image(systemName: "cursorarrow")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(Color(white: 0.08))
            .overlay(Image(systemName: "cursorarrow").font(.system(size: 20)).foregroundStyle(Color.white.opacity(0.88)).offset(x: -0.6, y: -0.6))
            .shadow(color: .black.opacity(0.52), radius: 3, x: 1, y: 2)
            .position(location)
            .opacity(active ? 1 : 0.82)
    }

    private var cursorPosition: CGPoint {
        switch kind {
        case .dockReveal:
            if p < 0.18 { return point(from: .init(x: 184, y: 269), to: .init(x: 104, y: 149), amount: segment(p, 0, 0.18)) }
            if p < 0.45 { return point(from: .init(x: 104, y: 149), to: .init(x: 278, y: 296), amount: segment(p, 0.18, 0.45)) }
            if p < 0.72 { return .init(x: 278, y: 296) }
            return point(from: .init(x: 278, y: 274), to: .init(x: 184, y: 269), amount: segment(p, 0.72, 1))
        case .minimize:
            if p < 0.15 { return point(from: .init(x: 202, y: 139), to: .init(x: 148, y: 50), amount: segment(p, 0, 0.15)) }
            if p < 0.48 { return .init(x: 148, y: 50) }
            if p < 0.61 { return point(from: .init(x: 148, y: 50), to: .init(x: 408, y: 272), amount: segment(p, 0.48, 0.61)) }
            if p < 0.84 { return .init(x: 408, y: 272) }
            return point(from: .init(x: 408, y: 272), to: .init(x: 202, y: 139), amount: segment(p, 0.84, 1))
        case .layout:
            if p < 0.16 { return point(from: .init(x: 212, y: 180), to: .init(x: 408, y: 272), amount: segment(p, 0, 0.16)) }
            if p < 0.42 { return point(from: .init(x: 408, y: 272), to: .init(x: 402, y: 184), amount: segment(p, 0.16, 0.42)) }
            if p < 0.84 { return .init(x: 250, y: 81) }
            return point(from: .init(x: 250, y: 81), to: .init(x: 212, y: 180), amount: segment(p, 0.84, 1))
        case .windows:
            if p < 0.24 { return point(from: .init(x: 107, y: 148), to: .init(x: 136, y: 50), amount: segment(p, 0, 0.24)) }
            if p < 0.54 { return point(from: .init(x: 136, y: 50), to: .init(x: 155, y: 271), amount: segment(p, 0.30, 0.54)) }
            if p < 0.72 { return .init(x: 155, y: 271) }
            return point(from: .init(x: 155, y: 271), to: .init(x: 107, y: 148), amount: segment(p, 0.72, 1))
        case .screenshots:
            if p < 0.24 { return point(from: .init(x: 230, y: 111), to: .init(x: 106, y: 26), amount: segment(p, 0, 0.24)) }
            if p < 0.50 { return point(from: .init(x: 106, y: 26), to: .init(x: 488, y: 246), amount: segment(p, 0.24, 0.50)) }
            return point(from: .init(x: 488, y: 246), to: .init(x: 230, y: 111), amount: segment(p, 0.50, 1))
        case .menubar:
            if p < 0.35 { return point(from: .init(x: 138, y: 10), to: .init(x: 164, y: 121), amount: segment(p, 0, 0.35)) }
            if p < 0.62 { return point(from: .init(x: 164, y: 121), to: .init(x: 138, y: 2), amount: segment(p, 0.35, 0.62)) }
            return point(from: .init(x: 138, y: 2), to: .init(x: 138, y: 10), amount: segment(p, 0.62, 1))
        default:
            return .init(x: 89, y: 158)
        }
    }
}

private struct MacTweaksFilmBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.085, green: 0.09, blue: 0.115), Color(red: 0.15, green: 0.15, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(red: 0.36, green: 0.40, blue: 0.52).opacity(0.11))
                .frame(width: 310, height: 310)
                .blur(radius: 42)
                .offset(x: -210, y: 92)
            Circle()
                .fill(Color(red: 0.50, green: 0.34, blue: 0.48).opacity(0.07))
                .frame(width: 260, height: 260)
                .blur(radius: 48)
                .offset(x: 230, y: -90)
            Canvas { context, size in
                for x in stride(from: 0.0, through: size.width, by: 24.0) {
                    var path = Path()
                    path.move(to: .init(x: x, y: 0)); path.addLine(to: .init(x: x, y: size.height))
                    context.stroke(path, with: .color(.white.opacity(0.018)), lineWidth: 0.5)
                }
                for y in stride(from: 0.0, through: size.height, by: 24.0) {
                    var path = Path()
                    path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: size.width, y: y))
                    context.stroke(path, with: .color(.white.opacity(0.018)), lineWidth: 0.5)
                }
                var ribbon = Path()
                ribbon.move(to: .init(x: -80, y: 260))
                ribbon.addCurve(to: .init(x: 388, y: 123), control1: .init(x: 80, y: 28), control2: .init(x: 190, y: 352))
                ribbon.addCurve(to: .init(x: 700, y: 178), control1: .init(x: 520, y: -20), control2: .init(x: 690, y: 40))
                context.stroke(ribbon, with: .color(.white.opacity(0.028)), style: .init(lineWidth: 88, lineCap: .round))
                context.stroke(ribbon, with: .color(.white.opacity(0.065)), style: .init(lineWidth: 0.8, lineCap: .round))
            }
            MacTweaksDither(strength: 0.28)
        }
    }
}

private struct FinderPreviewWindow: View {
    let hiddenFileOpacity: CGFloat
    let selectionAmount: CGFloat
    let title: String

    private let files = ["Project notes.md", "Interface.fig", ".env", "Screenshots", "Reference.pdf", "Archive"]

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    Circle().fill(Color(red: 0.92, green: 0.42, blue: 0.39)).frame(width: 7, height: 7)
                    Circle().fill(Color(red: 0.91, green: 0.72, blue: 0.31)).frame(width: 7, height: 7)
                    Circle().fill(Color(red: 0.45, green: 0.71, blue: 0.40)).frame(width: 7, height: 7)
                    Spacer()
                    Text("‹   ›      \(title)").font(.system(size: 8.5, weight: .medium))
                    Spacer()
                    Text("☰   ⤴   ◇   ···   ⌕").font(.system(size: 8))
                }
                .foregroundStyle(Color(white: 0.65))
                .padding(.horizontal, 10)
                .frame(height: 31)
                .background(Color.white.opacity(0.075))
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("FAVORITES").font(.system(size: 6.5, weight: .medium)).foregroundStyle(MacTweaksPalette.muted)
                        ForEach(["◉  Recents", "▣  Desktop", "▣  Documents", "◉  Downloads"], id: \.self) { item in
                            Text(item).font(.system(size: 7.5)).foregroundStyle(item.contains("Documents") ? MacTweaksPalette.text : MacTweaksPalette.secondary)
                        }
                        Spacer()
                        Text("▱  Macintosh HD").font(.system(size: 7.5)).foregroundStyle(MacTweaksPalette.secondary)
                    }
                    .padding(11)
                    .frame(width: proxy.size.width * 0.28, alignment: .leading)
                    .background(Color.white.opacity(0.035))
                    VStack(spacing: 0) {
                        HStack { Text("Name"); Spacer(); Text("Date Modified") }
                            .font(.system(size: 6.5)).foregroundStyle(MacTweaksPalette.muted)
                            .padding(.horizontal, 10).frame(height: 17)
                        ForEach(Array(files.enumerated()), id: \.offset) { index, name in
                            let selected = index == 1 ? 1 - selectionAmount : index == 3 ? selectionAmount : 0
                            HStack(spacing: 7) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.white.opacity(0.58 + 0.34 * selected))
                                    .frame(width: 9, height: 10)
                                Text(name).lineLimit(1)
                                Spacer()
                                Text(index < 2 ? "Today" : "Yesterday")
                            }
                            .font(.system(size: 7.5))
                            .foregroundStyle(MacTweaksPalette.text.opacity(0.88 + 0.12 * selected))
                            .padding(.horizontal, 10)
                            .frame(height: name == ".env" ? 19 * hiddenFileOpacity : 19)
                            .background(Color.blue.opacity(0.52 * selected))
                            .opacity(name == ".env" ? Double(hiddenFileOpacity) : 1)
                            .clipped()
                        }
                        Spacer(minLength: 0)
                        ZStack {
                            Text("5 items, 184 GB available").opacity(1 - Double(hiddenFileOpacity))
                            Text("6 items, 184 GB available").opacity(Double(hiddenFileOpacity))
                        }
                            .font(.system(size: 6.5))
                            .foregroundStyle(MacTweaksPalette.muted)
                            .frame(maxWidth: .infinity, minHeight: 17)
                            .background(Color.white.opacity(0.025))
                    }
                }
            }
            .background(Color(red: 0.105, green: 0.105, blue: 0.115))
            .overlay(alignment: .topTrailing) { MacTweaksDither(strength: 0.13).frame(width: 150, height: 68) }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.20), lineWidth: 0.8))
        }
    }
}

private struct DockPreviewBar: View {
    let highlighted: CGFloat
    let minimized: CGFloat

    private let colors: [Color] = [
        .blue.opacity(0.88), .cyan.opacity(0.78), .blue.opacity(0.70), .yellow.opacity(0.75),
        .pink.opacity(0.72), .black.opacity(0.84), .gray.opacity(0.72), .blue.opacity(0.70), .gray.opacity(0.66)
    ]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<9, id: \.self) { index in
                RoundedRectangle(cornerRadius: 6)
                    .fill(colors[index])
                    .overlay {
                        if index == 7 && minimized > 0.02 {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.white.opacity(0.64), lineWidth: 1)
                                .padding(4)
                                .opacity(Double(minimized))
                        }
                    }
                    .frame(width: index == 8 ? 28 : 31, height: index == 8 ? 33 : 31)
                    .scaleEffect(index == 5 ? mix(1, 1.16, highlighted) : 1)
                    .shadow(color: .black.opacity(0.32), radius: 3, y: 2)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 49)
        .background(.ultraThinMaterial.opacity(0.82), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.20), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.36), radius: 12, y: 7)
    }
}

private struct PowerPreviewScene: View {
    let progress: Double
    let active: Bool

    private var pulse: CGFloat {
        guard active else { return 0 }
        return CGFloat((1 - cos(progress * .pi * 2)) / 2)
    }

    var body: some View {
        ZStack {
            MacTweaksFilmBackground()
            Circle()
                .fill(Color.white.opacity(0.82))
                .frame(width: 94, height: 94)
                .overlay {
                    Circle()
                        .fill(Color(red: 0.09, green: 0.09, blue: 0.14))
                        .offset(x: mix(18, 32, pulse), y: -13)
                }
                .shadow(color: Color.white.opacity(0.08 + Double(pulse) * 0.15), radius: 22 + 24 * pulse)
                .offset(y: -28)
            HStack(spacing: 10) {
                Circle()
                    .fill(active ? Color.green.opacity(0.82) : MacTweaksPalette.muted)
                    .frame(width: 8, height: 8)
                    .shadow(color: active ? Color.green.opacity(0.38) : .clear, radius: 8)
                Text(active ? "Keeping this Mac awake" : "Hover to preview")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(white: 0.68))
            }
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background(Color.black.opacity(0.38), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.7))
            .offset(y: 88)
        }
        .frame(width: 600, height: 304)
        .clipped()
    }
}

private func segment(_ progress: Double, _ start: Double, _ end: Double) -> CGFloat {
    guard end > start else { return progress >= end ? 1 : 0 }
    let value = max(0, min(1, (progress - start) / (end - start)))
    return CGFloat(value * value * (3 - 2 * value))
}

private func clamp01(_ value: CGFloat) -> CGFloat {
    min(1, max(0, value))
}

private func mix(_ start: CGFloat, _ end: CGFloat, _ amount: CGFloat) -> CGFloat {
    start + (end - start) * amount
}

private func point(from start: CGPoint, to end: CGPoint, amount: CGFloat) -> CGPoint {
    .init(x: mix(start.x, end.x, amount), y: mix(start.y, end.y, amount))
}
