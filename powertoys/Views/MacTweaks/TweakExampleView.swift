import SwiftUI

struct TweakExample {
    let before: String
    let after: String
    let beforeSymbol: String
    let afterSymbol: String

    static func forID(_ id: String) -> Self? {
        switch id {
        case "mic-lock": .init(before: "Headset takes input", after: "Preferred mic returns", beforeSymbol: "headphones", afterSymbol: "mic")
        case "dock.reveal-delay": .init(before: "Dock waits", after: "Dock reveals sooner", beforeSymbol: "clock", afterSymbol: "dock.rectangle")
        case "dock.animation-duration": .init(before: "Long transition", after: "Short transition", beforeSymbol: "clock", afterSymbol: "dock.rectangle")
        case "dock.hidden-app-dimming": .init(before: "Icons look alike", after: "Hidden app dims", beforeSymbol: "square.grid.2x2", afterSymbol: "square.dashed")
        case "dock.lock-size": .init(before: "Drag to resize", after: "Size stays fixed", beforeSymbol: "arrow.left.and.right", afterSymbol: "lock")
        case "dock.lock-contents": .init(before: "Icons can move", after: "Layout stays put", beforeSymbol: "square.grid.2x2", afterSymbol: "lock")
        case "dock.stack-selection": .init(before: "Plain stack grid", after: "Hovered item marked", beforeSymbol: "square.grid.3x3", afterSymbol: "cursorarrow")
        case "dock.minimize-effect": .init(before: "Genie or Scale", after: "Suck effect", beforeSymbol: "macwindow", afterSymbol: "dock.rectangle")
        case "dock.slow-motion": .init(before: "Normal minimize", after: "Shift slows it", beforeSymbol: "macwindow", afterSymbol: "shift")
        case "dock.switcher-displays": .init(before: "One display", after: "Every display", beforeSymbol: "display", afterSymbol: "display.2")
        case "finder.hidden-files": .init(before: ".env hidden", after: ".env visible", beforeSymbol: "eye.slash", afterSymbol: "eye")
        case "finder.quit": .init(before: "No Quit command", after: "Quit Finder shown", beforeSymbol: "menubar.rectangle", afterSymbol: "power")
        case "finder.path-title": .init(before: "Projects", after: "…/Work/Projects", beforeSymbol: "folder", afterSymbol: "folder")
        case "finder.sounds": .init(before: "Finder chime", after: "Quiet Finder", beforeSymbol: "speaker.wave.2", afterSymbol: "speaker.slash")
        case "finder.network-metadata": .init(before: "Network metadata", after: "Fewer SMB writes", beforeSymbol: "network", afterSymbol: "externaldrive")
        case "finder.column-sizing": .init(before: "Fixed columns", after: "Names fit", beforeSymbol: "rectangle.split.3x1", afterSymbol: "text.alignleft")
        case "input.press-hold": .init(before: "Accent popup", after: "eeee repeats", beforeSymbol: "character.cursor.ibeam", afterSymbol: "keyboard")
        case "dialogs.expanded-save": .init(before: "Compact Save", after: "Expanded Save", beforeSymbol: "square", afterSymbol: "sidebar.left")
        case "windows.scroll-animation": .init(before: "Page jumps", after: "Page glides", beforeSymbol: "doc.text", afterSymbol: "scroll")
        case "menubar.spacing": .init(before: "Wide item gaps", after: "Compact item gaps", beforeSymbol: "menubar.rectangle", afterSymbol: "menubar.rectangle")
        case "screenshots.format": .init(before: "PNG capture", after: "Chosen format", beforeSymbol: "photo", afterSymbol: "doc")
        case "screenshots.shadow": .init(before: "Window shadow", after: "Clean window edge", beforeSymbol: "macwindow", afterSymbol: "square")
        case "screenshots.date": .init(before: "Plain filename", after: "Dated filename", beforeSymbol: "doc", afterSymbol: "calendar")
        case "terminal.pointer-focus": .init(before: "Click to focus", after: "Point to focus", beforeSymbol: "terminal", afterSymbol: "cursorarrow")
        case "music.half-stars": .init(before: "Whole stars", after: "Half stars", beforeSymbol: "star", afterSymbol: "star.leadinghalf.filled")
        case "apps.automatic-termination": .init(before: "Idle app may exit", after: "Native auto-exit off", beforeSymbol: "app", afterSymbol: "lock.open")
        case "helper.keep-awake": .init(before: "Mac can sleep", after: "Timer holds awake", beforeSymbol: "moon.zzz", afterSymbol: "sun.max")
        default: nil
        }
    }
}

struct TweakExampleView: View {
    let item: TweakItem

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0
    @State private var replay = 0

    var body: some View {
        if let example = TweakExample.forID(item.id) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Example")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !reduceMotion {
                        Button("Replay", systemImage: "arrow.clockwise") { replay += 1 }
                            .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 6))
                            .controlSize(.small)
                            .help("Replay the example for \(item.title)")
                    }
                }
                HStack(spacing: 8) {
                    state("Before", text: example.before, symbol: example.beforeSymbol, active: phase < 2)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(phase == 1 ? Color.accentColor : Color.secondary)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    state("With change", text: example.after, symbol: example.afterSymbol, active: phase == 2)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityIdentifier("mac-tweaks.example.\(item.id)")
            .task(id: replay) {
                phase = reduceMotion ? 2 : 0
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.16)) { phase = 1 }
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.16)) { phase = 2 }
            }
            .onChange(of: reduceMotion) { _, _ in replay += 1 }
        }
    }

    private func state(_ label: String, text: String, symbol: String, active: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .frame(width: 23)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(active ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03),
                    in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(text)")
    }
}
