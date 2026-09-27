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
            Image("MacTweaksGrain")
                .resizable()
                .interpolation(.none)
                .frame(width: min(200, proxy.size.width), height: min(125, proxy.size.height))
                .opacity(strength)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct MacTweaksHeaderDither: View {
    var body: some View {
        Image("MacTweaksRibbon")
            .resizable()
            .interpolation(.none)
            .aspectRatio(contentMode: .fill)
            .opacity(0.25)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.25),
                        .init(color: .black, location: 0.70),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
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
        case .dockReveal: 3.61
        case .minimize: 4.14
        case .layout: 6.24
        case .finder, .apps: 4.6
        case .windows: 2.60
        case .screenshots: 3.80
        case .power: 4.2
        case .menubar: 2.50
        }
    }
}

struct MacTweaksPreviewView: View {
    let kind: MacTweaksPreviewKind

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var startedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !isHovering || reduceMotion)) { timeline in
            let progress = progress(at: timeline.date)
            GeometryReader { proxy in
                let sceneHeight = max(1, proxy.size.height - 2)
                let crop = kind == .finder
                    ? CGRect(x: 98, y: 16, width: 404, height: 242)
                    : CGRect(x: 0, y: 0, width: 600, height: 304)
                let scale = min(proxy.size.width / crop.width, sceneHeight / crop.height)
                ZStack(alignment: .bottomLeading) {
                    MacTweaksFilmBackground()
                        .scaleEffect(1.08)
                        .blur(radius: 10)
                        .opacity(0.56)
                    preview(progress: progress)
                        .frame(width: 600, height: 304)
                        .scaleEffect(scale)
                        .position(
                            x: proxy.size.width / 2 + (300 - crop.midX) * scale,
                            y: sceneHeight / 2 + (152 - crop.midY) * scale
                        )
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
    private var minimizeAmount: CGFloat { clamp01(segment(p, 0.229, 0.340) - segment(p, 0.671, 0.783)) }
    private var dockHiddenAmount: CGFloat { kind == .dockReveal ? clamp01(segment(p, 0.144, 0.241) - segment(p, 0.529, 0.626)) : 0 }
    private var menuHiddenAmount: CGFloat { kind == .menubar ? clamp01(segment(p, 0.208, 0.296) - segment(p, 0.552, 0.640)) : 0 }
    private var stackAmount: CGFloat { kind == .layout ? clamp01(segment(p, 0.104, 0.139) - segment(p, 0.276, 0.316)) : 0 }
    private var switcherAmount: CGFloat { kind == .layout ? clamp01(segment(p, 0.316, 0.326) - segment(p, 0.657, 0.667)) : 0 }
    private var switcherSelection: Int { p >= 0.553 && p < 0.657 ? 2 : 1 }
    private var captureAmount: CGFloat { kind == .screenshots ? clamp01(segment(p, 0.211, 0.231) - segment(p, 0.382, 0.402)) : 0 }
    private var thumbnailAmount: CGFloat { kind == .screenshots ? clamp01(segment(p, 0.421, 0.441) - segment(p, 0.750, 0.842)) : 0 }
    private var hiddenFileAmount: CGFloat { kind == .finder ? clamp01(segment(p, 0.18, 0.32) - segment(p, 0.68, 0.82)) : 0 }
    private var appSelectionAmount: CGFloat { kind == .apps ? clamp01(segment(p, 0.18, 0.34) - segment(p, 0.68, 0.84)) : 0 }
    private var windowVisibility: CGFloat {
        guard kind == .windows else { return 1 }
        return clamp01(1 - segment(p, 0.262, 0.315) + segment(p, 0.585, 0.654))
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
        FinderPreviewWindow(hiddenFileOpacity: 0, selectionAmount: 0, title: "Documents")
        .frame(width: 92, height: 58)
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
                        PreviewFileIcon(name: item, selected: item == "Reference.pdf")
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
                ForEach(Array([PreviewApp.finder, .safari, .mail, .notes, .terminal].enumerated()), id: \.offset) { index, app in
                    VStack(spacing: 5) {
                        PreviewAppIcon(app: app, size: 43)
                        Text(["Finder", "Safari", "Mail", "Notes", "Terminal"][index])
                            .font(.system(size: 7.5))
                    }
                    .padding(5)
                    .background(index == switcherSelection ? Color.black.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 6))
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
            if p < 0.144 { return point(from: .init(x: 184, y: 269), to: .init(x: 104, y: 149), amount: segment(p, 0, 0.144)) }
            if p < 0.241 { return .init(x: 104, y: 149) }
            if p < 0.418 { return point(from: .init(x: 104, y: 149), to: .init(x: 278, y: 303), amount: segment(p, 0.241, 0.418)) }
            if p < 0.529 { return .init(x: 278, y: 303) }
            if p < 0.626 { return point(from: .init(x: 278, y: 303), to: .init(x: 278, y: 274), amount: segment(p, 0.529, 0.626)) }
            if p < 0.820 { return point(from: .init(x: 278, y: 274), to: .init(x: 184, y: 269), amount: segment(p, 0.626, 0.820)) }
            return .init(x: 184, y: 269)
        case .minimize:
            if p < 0.193 { return point(from: .init(x: 202, y: 139), to: .init(x: 148, y: 50), amount: segment(p, 0, 0.193)) }
            if p < 0.485 { return .init(x: 148, y: 50) }
            if p < 0.635 { return point(from: .init(x: 148, y: 50), to: .init(x: 408, y: 272), amount: segment(p, 0.485, 0.635)) }
            if p < 0.783 { return .init(x: 408, y: 272) }
            return point(from: .init(x: 408, y: 272), to: .init(x: 202, y: 139), amount: segment(p, 0.783, 1))
        case .layout:
            if p < 0.104 { return point(from: .init(x: 212, y: 180), to: .init(x: 408, y: 272), amount: segment(p, 0, 0.104)) }
            if p < 0.139 { return .init(x: 408, y: 272) }
            if p < 0.276 { return point(from: .init(x: 408, y: 272), to: .init(x: 401, y: 223), amount: segment(p, 0.139, 0.276)) }
            if p < 0.316 { return point(from: .init(x: 401, y: 223), to: .init(x: 250, y: 81), amount: segment(p, 0.276, 0.316)) }
            if p < 0.864 { return .init(x: 250, y: 81) }
            return point(from: .init(x: 250, y: 81), to: .init(x: 212, y: 180), amount: segment(p, 0.864, 1))
        case .windows:
            if p < 0.223 { return point(from: .init(x: 107, y: 148), to: .init(x: 136, y: 50), amount: segment(p, 0, 0.223)) }
            if p < 0.315 { return .init(x: 136, y: 50) }
            if p < 0.538 { return point(from: .init(x: 136, y: 50), to: .init(x: 155, y: 271), amount: segment(p, 0.315, 0.538)) }
            if p < 0.654 { return .init(x: 155, y: 271) }
            return point(from: .init(x: 155, y: 271), to: .init(x: 107, y: 148), amount: segment(p, 0.654, 1))
        case .screenshots:
            if p < 0.211 { return point(from: .init(x: 230, y: 111), to: .init(x: 106, y: 26), amount: segment(p, 0, 0.211)) }
            if p < 0.382 { return point(from: .init(x: 106, y: 26), to: .init(x: 488, y: 246), amount: segment(p, 0.211, 0.382)) }
            if p < 0.421 { return .init(x: 488, y: 246) }
            if p < 0.750 { return point(from: .init(x: 488, y: 246), to: .init(x: 230, y: 111), amount: segment(p, 0.421, 0.750)) }
            return .init(x: 230, y: 111)
        case .menubar:
            if p < 0.208 { return point(from: .init(x: 138, y: 10), to: .init(x: 164, y: 121), amount: segment(p, 0, 0.208)) }
            if p < 0.296 { return .init(x: 164, y: 121) }
            if p < 0.552 { return point(from: .init(x: 164, y: 121), to: .init(x: 138, y: 0), amount: segment(p, 0.296, 0.552)) }
            if p < 0.640 { return point(from: .init(x: 138, y: 0), to: .init(x: 138, y: 10), amount: segment(p, 0.552, 0.640)) }
            return .init(x: 138, y: 10)
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
            MacTweaksDither(strength: 0.32)
            RadialGradient(
                colors: [.clear, .black.opacity(0.24)],
                center: .center,
                startRadius: 110,
                endRadius: 370
            )
        }
    }
}

private enum PreviewApp: CaseIterable {
    case finder, safari, mail, notes, photos, terminal, settings, folder, trash
}

private struct PreviewAppIcon: View {
    let app: PreviewApp
    let size: CGFloat

    var body: some View {
        ZStack {
            background
            artwork
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.21, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.21, style: .continuous)
                .stroke(Color.white.opacity(app == .folder || app == .trash ? 0 : 0.24), lineWidth: 0.55)
        }
        .shadow(color: .black.opacity(0.34), radius: max(1, size * 0.07), y: max(1, size * 0.045))
    }

    @ViewBuilder private var background: some View {
        switch app {
        case .finder:
            LinearGradient(colors: [Color(red: 0.45, green: 0.72, blue: 0.90), Color(red: 0.23, green: 0.53, blue: 0.73)], startPoint: .top, endPoint: .bottom)
        case .safari:
            LinearGradient(colors: [Color(red: 0.25, green: 0.72, blue: 0.93), Color(red: 0.12, green: 0.43, blue: 0.77)], startPoint: .top, endPoint: .bottom)
        case .mail:
            LinearGradient(colors: [Color(red: 0.39, green: 0.69, blue: 0.88), Color(red: 0.22, green: 0.48, blue: 0.70)], startPoint: .top, endPoint: .bottom)
        case .notes:
            Color(red: 0.88, green: 0.87, blue: 0.82)
        case .photos:
            Color(white: 0.88)
        case .terminal:
            LinearGradient(colors: [Color(white: 0.20), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
        case .settings:
            LinearGradient(colors: [Color(white: 0.72), Color(white: 0.42)], startPoint: .top, endPoint: .bottom)
        case .folder, .trash:
            Color.clear
        }
    }

    @ViewBuilder private var artwork: some View {
        switch app {
        case .finder:
            ZStack {
                Rectangle().fill(Color(white: 0.90).opacity(0.92))
                    .frame(width: size * 0.49).frame(maxWidth: .infinity, alignment: .trailing)
                Canvas { context, canvas in
                    var divider = Path()
                    divider.move(to: .init(x: canvas.width * 0.55, y: canvas.height * 0.08))
                    divider.addCurve(
                        to: .init(x: canvas.width * 0.48, y: canvas.height * 0.88),
                        control1: .init(x: canvas.width * 0.58, y: canvas.height * 0.38),
                        control2: .init(x: canvas.width * 0.40, y: canvas.height * 0.62)
                    )
                    context.stroke(divider, with: .color(Color(red: 0.14, green: 0.31, blue: 0.43)), lineWidth: max(0.8, size * 0.038))
                    var face = Path()
                    face.move(to: .init(x: canvas.width * 0.24, y: canvas.height * 0.39))
                    face.addLine(to: .init(x: canvas.width * 0.24, y: canvas.height * 0.50))
                    face.move(to: .init(x: canvas.width * 0.76, y: canvas.height * 0.39))
                    face.addLine(to: .init(x: canvas.width * 0.76, y: canvas.height * 0.50))
                    face.move(to: .init(x: canvas.width * 0.22, y: canvas.height * 0.67))
                    face.addCurve(
                        to: .init(x: canvas.width * 0.78, y: canvas.height * 0.67),
                        control1: .init(x: canvas.width * 0.38, y: canvas.height * 0.84),
                        control2: .init(x: canvas.width * 0.64, y: canvas.height * 0.84)
                    )
                    context.stroke(face, with: .color(Color(red: 0.14, green: 0.31, blue: 0.43)), style: .init(lineWidth: max(0.75, size * 0.036), lineCap: .round))
                }
            }
        case .safari:
            ZStack {
                Circle().fill(Color.white.opacity(0.90)).padding(size * 0.09)
                Image(systemName: "safari.fill")
                    .font(.system(size: size * 0.69, weight: .regular))
                    .foregroundStyle(Color(red: 0.19, green: 0.55, blue: 0.82))
                Capsule().fill(Color(red: 0.82, green: 0.31, blue: 0.28))
                    .frame(width: size * 0.10, height: size * 0.42)
                    .offset(y: -size * 0.10).rotationEffect(.degrees(42))
            }
        case .mail:
            Image(systemName: "envelope.fill")
                .font(.system(size: size * 0.61, weight: .regular))
                .foregroundStyle(Color(white: 0.93))
        case .notes:
            VStack(spacing: 0) {
                Color(red: 0.82, green: 0.70, blue: 0.34).frame(height: size * 0.27)
                VStack(spacing: size * 0.09) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(Color.black.opacity(0.25)).frame(height: max(0.7, size * 0.025))
                    }
                }
                .padding(.horizontal, size * 0.18).frame(maxHeight: .infinity)
            }
        case .photos:
            ZStack {
                ForEach(0..<8, id: \.self) { index in
                    Capsule()
                        .fill([Color.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink][index].opacity(0.72))
                        .frame(width: size * 0.18, height: size * 0.39)
                        .offset(y: -size * 0.15)
                        .rotationEffect(.degrees(Double(index) * 45))
                }
                Circle().fill(Color(red: 0.91, green: 0.82, blue: 0.46).opacity(0.88))
                    .frame(width: size * 0.19, height: size * 0.19)
            }
        case .terminal:
            Image(systemName: "terminal.fill")
                .font(.system(size: size * 0.64, weight: .regular))
                .foregroundStyle(Color(white: 0.82))
        case .settings:
            Image(systemName: "gearshape.fill")
                .font(.system(size: size * 0.70, weight: .regular))
                .foregroundStyle(Color(white: 0.25))
        case .folder:
            Image(systemName: "folder.fill")
                .font(.system(size: size * 0.88, weight: .regular))
                .foregroundStyle(Color(red: 0.38, green: 0.66, blue: 0.82))
        case .trash:
            Image(systemName: "trash.fill")
                .font(.system(size: size * 0.77, weight: .regular))
                .foregroundStyle(Color(white: 0.72))
        }
    }
}

private struct PreviewFileIcon: View {
    let name: String
    let selected: Bool

    private var symbol: String {
        if name == "Screenshots" || name == "Archive" { return "folder.fill" }
        if name.hasSuffix(".pdf") { return "doc.richtext.fill" }
        return "doc.fill"
    }

    private var color: Color {
        if selected { return Color.white.opacity(0.94) }
        if name == "Screenshots" || name == "Archive" { return Color(red: 0.43, green: 0.67, blue: 0.81) }
        if name.hasSuffix(".pdf") { return Color(red: 0.78, green: 0.38, blue: 0.36) }
        if name.hasSuffix(".fig") { return Color(red: 0.62, green: 0.48, blue: 0.72) }
        return Color.white.opacity(0.72)
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 8, weight: .regular))
            .foregroundStyle(color)
            .frame(width: 9, height: 10)
    }
}

private struct FinderPreviewWindow: View {
    let hiddenFileOpacity: CGFloat
    let selectionAmount: CGFloat
    let title: String

    private let files = ["Project notes.md", "Interface.fig", ".env", "Screenshots", "Reference.pdf", "Archive"]
    private let sidebarItems = [
        ("Recents", "clock"),
        ("Desktop", "display"),
        ("Documents", "doc.text"),
        ("Downloads", "arrow.down.circle")
    ]

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
                        ForEach(Array(sidebarItems.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 5) {
                                Image(systemName: item.1)
                                    .font(.system(size: 6.5, weight: .medium))
                                    .foregroundStyle(Color(red: 0.47, green: 0.68, blue: 0.82))
                                    .frame(width: 9)
                                Text(item.0)
                            }
                            .font(.system(size: 7.5))
                            .foregroundStyle(item.0 == "Documents" ? MacTweaksPalette.text : MacTweaksPalette.secondary)
                        }
                        Spacer()
                        HStack(spacing: 5) {
                            Image(systemName: "internaldrive").font(.system(size: 6.5)).frame(width: 9)
                            Text("Macintosh HD")
                        }
                        .font(.system(size: 7.5)).foregroundStyle(MacTweaksPalette.secondary)
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
                                PreviewFileIcon(name: name, selected: selected > 0.5)
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
            .overlay(alignment: .topTrailing) { MacTweaksDither(strength: 0.16).frame(width: 150, height: 68) }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.20), lineWidth: 0.8))
        }
    }
}

private struct DockPreviewBar: View {
    let highlighted: CGFloat
    let minimized: CGFloat

    private let apps = PreviewApp.allCases

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(apps.enumerated()), id: \.offset) { index, app in
                if index == 7 {
                    Rectangle().fill(Color.white.opacity(0.24)).frame(width: 1, height: 29)
                        .padding(.horizontal, 2)
                }
                PreviewAppIcon(app: app, size: app == .trash ? 29 : 31)
                    .overlay {
                        if index == 7 {
                            VStack(spacing: 2) {
                                HStack(spacing: 2) {
                                    Circle().fill(Color.red.opacity(0.75)).frame(width: 2.5, height: 2.5)
                                    Circle().fill(Color.yellow.opacity(0.75)).frame(width: 2.5, height: 2.5)
                                    Spacer()
                                }
                                ForEach(0..<3, id: \.self) { _ in
                                    Capsule().fill(Color.white.opacity(0.34)).frame(height: 1.5)
                                }
                            }
                            .padding(4)
                            .background(Color(white: 0.16).opacity(0.96), in: RoundedRectangle(cornerRadius: 4))
                            .padding(2)
                            .opacity(Double(minimized))
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if index < 4 {
                            Circle().fill(Color.white.opacity(0.70)).frame(width: 2, height: 2).offset(y: 4)
                        }
                    }
                    .scaleEffect(index == 7 ? mix(1, 1.15, highlighted) : 1)
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
