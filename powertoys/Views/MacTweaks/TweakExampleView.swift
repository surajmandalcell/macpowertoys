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
    static let purple = Color(red: 0.67, green: 0.53, blue: 0.91)
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
        Canvas { context, size in
            let startX = max(0, size.width * 0.48)
            for y in stride(from: 3.0, through: min(size.height, 112), by: 3.0) {
                for x in stride(from: startX, through: size.width, by: 3.0) {
                    let seed = Int(x * 7 + y * 13)
                    guard seed % 17 == 0 || seed % 29 == 0 else { continue }
                    let fade = max(0, 1 - y / 116) * max(0, (x - startX) / max(1, size.width - startX))
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 0.65, height: 0.65)),
                        with: .color(.white.opacity(strength * fade))
                    )
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
        case .layout: "Dock layout and app switcher"
        case .finder: "Finder settings"
        case .windows: "window behavior"
        case .screenshots: "screenshot capture"
        case .apps: "application behavior"
        case .power: "keep awake"
        case .menubar: "menu bar spacing"
        }
    }
}

struct MacTweaksPreviewView: View {
    let kind: MacTweaksPreviewKind

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var phase = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                preview(size: proxy.size)
                Rectangle()
                    .fill(MacTweaksPalette.purple.opacity(isHovering ? 0.72 : 0.18))
                    .frame(width: proxy.size.width * progress, height: 2)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: phase)
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if !hovering { phase = 0 }
        }
        .task(id: isHovering) {
            guard isHovering, !reduceMotion else { phase = reduceMotion ? 1 : 0; return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(850)) } catch { return }
                withAnimation(.easeInOut(duration: 0.24)) { phase = (phase + 1) % 3 }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of \(kind.accessibilityName)")
        .accessibilityValue(isHovering && !reduceMotion ? "Playing" : "At rest")
    }

    private var progress: CGFloat {
        guard isHovering, !reduceMotion else { return 0 }
        return [0.34, 0.67, 1][phase]
    }

    @ViewBuilder
    private func preview(size: CGSize) -> some View {
        if kind == .power {
            PowerPreviewScene(phase: phase, active: isHovering || reduceMotion)
        } else {
            DesktopPreviewScene(kind: kind, phase: phase, active: isHovering || reduceMotion, size: size)
        }
    }
}

private struct DesktopPreviewScene: View {
    let kind: MacTweaksPreviewKind
    let phase: Int
    let active: Bool
    let size: CGSize

    private var effectivePhase: Int { active ? phase : 0 }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.10, green: 0.11, blue: 0.14), Color(red: 0.13, green: 0.14, blue: 0.17)], startPoint: .top, endPoint: .bottom)
            hills
            menuBar
            FinderPreviewWindow(showHidden: kind == .finder && effectivePhase > 0)
                .frame(width: min(252, size.width * 0.68), height: min(145, size.height * 0.62))
                .scaleEffect(windowScale)
                .opacity(windowOpacity)
                .offset(y: windowOffset)
                .shadow(color: .black.opacity(kind == .screenshots && effectivePhase == 1 ? 0.48 : 0.24), radius: kind == .screenshots && effectivePhase == 1 ? 14 : 7, y: 5)
            if kind == .screenshots {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(MacTweaksPalette.text.opacity(effectivePhase == 1 ? 0.84 : 0.22), style: .init(lineWidth: 1, dash: [4, 3]))
                    .frame(width: min(274, size.width * 0.74), height: min(163, size.height * 0.69))
                    .offset(y: max(24, size.height * 0.16))
            }
            if kind == .layout && effectivePhase == 2 {
                appSwitcher.transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            dock
        }
        .animation(.easeInOut(duration: 0.24), value: effectivePhase)
    }

    private var hills: some View {
        ZStack(alignment: .bottom) {
            Ellipse().fill(Color.white.opacity(0.025)).frame(width: size.width * 0.9, height: size.height * 0.46).offset(x: -size.width * 0.22, y: size.height * 0.29)
            Ellipse().fill(Color.black.opacity(0.12)).frame(width: size.width * 0.82, height: size.height * 0.42).offset(x: size.width * 0.3, y: size.height * 0.33)
        }
        .clipped()
    }

    private var menuBar: some View {
        HStack(spacing: kind == .menubar && effectivePhase > 0 ? 9 : 5) {
            Text("◆").font(.system(size: 4, weight: .bold))
            Text("Finder").font(.system(size: 4.5, weight: .semibold))
            ForEach(["File", "Edit", "View", "Go", "Window"], id: \.self) { Text($0).font(.system(size: 4)) }
            Spacer()
            ForEach(0..<3, id: \.self) { _ in Circle().fill(MacTweaksPalette.secondary).frame(width: 3, height: 3) }
            Text("Tue 10:24").font(.system(size: 4))
        }
        .foregroundStyle(MacTweaksPalette.secondary)
        .padding(.horizontal, 7)
        .frame(height: 14)
        .background(Color.black.opacity(0.46))
    }

    private var windowScale: CGFloat {
        if kind == .minimize && effectivePhase == 2 { return 0.18 }
        if kind == .windows && effectivePhase == 1 { return 0.88 }
        return 1
    }

    private var windowOpacity: Double { kind == .minimize && effectivePhase == 2 ? 0.38 : 1 }

    private var windowOffset: CGFloat {
        if kind == .minimize && effectivePhase == 2 { return size.height * 0.69 }
        return max(24, size.height * 0.16)
    }

    private var dock: some View {
        DockPreviewBar(highlighted: kind == .layout && effectivePhase == 1)
            .frame(width: min(228, size.width * 0.63), height: 37)
            .offset(y: kind == .dockReveal && effectivePhase == 0 ? 29 : 0)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 7)
    }

    private var appSwitcher: some View {
        HStack(spacing: 9) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(index == 2 ? MacTweaksPalette.purple : Color.white.opacity(0.22))
                    .frame(width: 24, height: 24)
            }
        }
        .padding(10)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 9))
        .offset(y: size.height * 0.35)
    }
}

private struct FinderPreviewWindow: View {
    let showHidden: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Circle().fill(Color(red: 1, green: 0.35, blue: 0.32)).frame(width: 6, height: 6)
                Circle().fill(Color(red: 1, green: 0.75, blue: 0.25)).frame(width: 6, height: 6)
                Circle().fill(Color(red: 0.25, green: 0.78, blue: 0.39)).frame(width: 6, height: 6)
                Spacer()
                Text("‹  ›   Documents").font(.system(size: 6, weight: .medium))
                Spacer()
                Text("☰  ⤴  ◇  ···  ⌕").font(.system(size: 6))
            }
            .foregroundStyle(MacTweaksPalette.secondary)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(Color.white.opacity(0.08))
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("FAVORITES").font(.system(size: 4.5, weight: .medium)).foregroundStyle(MacTweaksPalette.muted)
                    ForEach(["◉  Recents", "▣  Desktop", "▣  Documents", "◉  Downloads"], id: \.self) { item in
                        Text(item).font(.system(size: 5.5)).foregroundStyle(item.contains("Documents") ? MacTweaksPalette.text : MacTweaksPalette.secondary)
                    }
                    Spacer()
                    Text("▱  Macintosh HD").font(.system(size: 5.5)).foregroundStyle(MacTweaksPalette.secondary)
                }
                .padding(8)
                .frame(width: 72, alignment: .leading)
                .background(Color.white.opacity(0.035))
                VStack(spacing: 0) {
                    HStack { Text("Name"); Spacer(); Text("Date Modified") }
                        .font(.system(size: 4.5)).foregroundStyle(MacTweaksPalette.muted)
                        .padding(.horizontal, 7).frame(height: 13)
                    ForEach(Array(["Project notes.md", "Interface.fig", ".env", "Screenshots", "Reference.pdf", "Archive"].enumerated()), id: \.offset) { index, name in
                        if name != ".env" || showHidden {
                            HStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 1).fill(index == 1 ? Color.blue.opacity(0.9) : Color.white.opacity(0.65)).frame(width: 7, height: 8)
                                Text(name).lineLimit(1)
                                Spacer()
                                Text(index < 2 ? "Today" : "Yesterday")
                            }
                            .font(.system(size: 5.5))
                            .foregroundStyle(index == 1 ? Color.white : MacTweaksPalette.text.opacity(0.88))
                            .padding(.horizontal, 7).frame(height: 15)
                            .background(index == 1 ? Color.blue.opacity(0.52) : .clear)
                        }
                    }
                    Spacer(minLength: 0)
                    Text("5 items, 184 GB available").font(.system(size: 4.5)).foregroundStyle(MacTweaksPalette.muted)
                        .frame(maxWidth: .infinity, minHeight: 14).background(Color.white.opacity(0.025))
                }
            }
        }
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.18), lineWidth: 0.7))
    }
}

private struct DockPreviewBar: View {
    let highlighted: Bool
    private let colors: [Color] = [
        .blue.opacity(0.85), .cyan.opacity(0.78), .blue.opacity(0.68), .yellow.opacity(0.72),
        .pink.opacity(0.68), .black.opacity(0.78), .gray.opacity(0.7), .blue.opacity(0.65), .gray.opacity(0.62)
    ]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<9, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(colors[index])
                    .frame(width: index == 8 ? 18 : 20, height: index == 8 ? 21 : 20)
                    .scaleEffect(highlighted && index == 5 ? 1.17 : 1)
                    .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(.ultraThinMaterial.opacity(0.75), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.18), lineWidth: 0.6))
    }
}

private struct PowerPreviewScene: View {
    let phase: Int
    let active: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.08, blue: 0.12), Color(red: 0.14, green: 0.13, blue: 0.19)], startPoint: .top, endPoint: .bottom)
            Circle().fill(Color.white.opacity(0.82)).frame(width: 50, height: 50)
                .overlay(Circle().fill(Color(red: 0.09, green: 0.09, blue: 0.14)).offset(x: active && phase > 0 ? 18 : 9, y: -7))
                .shadow(color: MacTweaksPalette.purple.opacity(active ? 0.38 : 0.14), radius: active ? 24 : 10)
                .offset(y: -14)
            HStack(spacing: 7) {
                Circle().fill(active ? Color.green.opacity(0.8) : MacTweaksPalette.muted).frame(width: 6, height: 6)
                Text(active ? "Keeping this Mac awake" : "Hover to preview")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(MacTweaksPalette.secondary)
            }
            .padding(.horizontal, 12).frame(height: 28)
            .background(Color.black.opacity(0.34), in: Capsule()).offset(y: 62)
        }
    }
}
