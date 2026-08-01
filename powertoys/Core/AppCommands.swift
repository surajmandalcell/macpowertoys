//
//  AppCommands.swift
//  powertoys
//

import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    static let commandOpenSettings = Notification.Name("commandOpenSettings")
    static let commandNewTransfer = Notification.Name("commandNewTransfer")
}

@MainActor
final class FreeRulerCommandContext: ObservableObject {
    struct Snapshot: Equatable {
        var hasRuler = false
        var horizontalVisible = false
        var verticalVisible = false
        var unit: Unit = .pixels
        var floatRulers = true
        var rulerShadow = false
        var groupRulers = false
    }

    static let shared = FreeRulerCommandContext()

    @Published private var snapshot = Snapshot()
    @Published private(set) var isActive = false

    var hasRuler: Bool { snapshot.hasRuler }
    var horizontalVisible: Bool { snapshot.horizontalVisible }
    var verticalVisible: Bool { snapshot.verticalVisible }
    var unit: Unit { snapshot.unit }
    var floatRulers: Bool { snapshot.floatRulers }
    var rulerShadow: Bool { snapshot.rulerShadow }
    var groupRulers: Bool { snapshot.groupRulers }

    var showsHostCommands: Bool { !isActive }

    func update(_ snapshot: Snapshot) {
        guard self.snapshot != snapshot else { return }
        self.snapshot = snapshot
    }

    func update(isActive: Bool) {
        guard self.isActive != isActive else { return }
        self.isActive = isActive
    }
}

struct FreeRulerCommandShortcut: Equatable {
    let key: Character
    let modifiers: EventModifiers

    init(_ key: Character, modifiers: EventModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

@MainActor
enum FreeRulerCommand: CaseIterable {
    case newRuler
    case horizontalWing
    case verticalWing
    case rulerSettings
    case pixels
    case millimeters
    case inches
    case cycleUnits
    case flipHorizontal
    case flipVertical
    case floatRuler
    case rulerShadow
    case groupRulers
    case alignAtMouse
    case resetPosition

    static let rulerMenu: [Self] = [.newRuler, .horizontalWing, .verticalWing, .rulerSettings]
    static let unitMenu: [Self] = [.pixels, .millimeters, .inches, .cycleUnits]
    static let optionsMenu: [Self] = [
        .flipHorizontal,
        .flipVertical,
        .floatRuler,
        .rulerShadow,
        .groupRulers,
        .alignAtMouse,
        .resetPosition,
    ]

    static func localizedTitle(id: String, fallback: String) -> String {
        Bundle.main.localizedString(forKey: "\(id).title", value: fallback, table: "MainMenu")
    }

    var action: Selector {
        switch self {
        case .newRuler: #selector(AppDelegate.newRuler(_:))
        case .horizontalWing: #selector(AppDelegate.toggleHorizontalRuler(_:))
        case .verticalWing: #selector(AppDelegate.toggleVerticalRuler(_:))
        case .rulerSettings: #selector(AppDelegate.openRulerSettings(_:))
        case .pixels: #selector(AppDelegate.setUnitPixels(_:))
        case .millimeters: #selector(AppDelegate.setUnitMillimetres(_:))
        case .inches: #selector(AppDelegate.setUnitInches(_:))
        case .cycleUnits: #selector(AppDelegate.cycleUnits(_:))
        case .flipHorizontal: #selector(AppDelegate.flipHorizontalRuler(_:))
        case .flipVertical: #selector(AppDelegate.flipVerticalRuler(_:))
        case .floatRuler: #selector(AppDelegate.toggleFloatRulers(_:))
        case .rulerShadow: #selector(AppDelegate.toggleRulerShadow(_:))
        case .groupRulers: #selector(AppDelegate.toggleGroupRulers(_:))
        case .alignAtMouse: #selector(AppDelegate.alignRulersAtMouseLocation(_:))
        case .resetPosition: #selector(AppDelegate.resetRulerPositions(_:))
        }
    }

    var shortcut: FreeRulerCommandShortcut? {
        switch self {
        case .newRuler: .init("n", modifiers: .command)
        case .horizontalWing: .init("h")
        case .verticalWing: .init("v")
        case .rulerSettings: .init(",", modifiers: .command)
        case .pixels, .millimeters, .inches: nil
        case .cycleUnits: .init("u")
        case .flipHorizontal: .init("h", modifiers: .shift)
        case .flipVertical: .init("v", modifiers: .shift)
        case .floatRuler: .init("f")
        case .rulerShadow: .init("s")
        case .groupRulers: .init("g")
        case .alignAtMouse: .init("o")
        case .resetPosition: .init("r", modifiers: .command)
        }
    }

    func title(in context: FreeRulerCommandContext) -> String {
        let title: (id: String, fallback: String)
        switch self {
        case .newRuler: title = ("rWt-KM-qSf", "New Ruler")
        case .horizontalWing where context.horizontalVisible:
            title = ("fLB-gk-0Jy", "Hide Horizontal Ruler")
        case .horizontalWing:
            return NSLocalizedString("Show Horizontal Ruler", comment: "Menu item title to show the horizontal ruler")
        case .verticalWing where context.verticalVisible:
            title = ("NgD-7h-fjO", "Hide Vertical Ruler")
        case .verticalWing:
            return NSLocalizedString("Show Vertical Ruler", comment: "Menu item title to show the vertical ruler")
        case .rulerSettings: title = ("rSt-Tg-232", "Ruler Settings…")
        case .pixels: title = ("pYR-Ba-kKi", "Pixels")
        case .millimeters: title = ("B6Y-Hi-AkN", "Millimeters")
        case .inches: title = ("lt1-Hj-2TR", "Inches")
        case .cycleUnits: title = ("2nm-aL-kZd", "Cycle Units")
        case .flipHorizontal: title = ("GZl-Zd-Ad4", "Flip Horizontal")
        case .flipVertical: title = ("IQD-xF-keq", "Flip Vertical")
        case .floatRuler: title = ("GDK-AC-uC8", "Float Ruler")
        case .rulerShadow: title = ("a8D-hN-A59", "Show Ruler Shadow")
        case .groupRulers: title = ("7Ga-Fb-LLc", "Group Rulers")
        case .alignAtMouse: title = ("iKV-uW-hwy", "Align Ruler at Mouse Location")
        case .resetPosition: title = ("6ph-5N-O9R", "Reset Ruler Position")
        }
        return Self.localizedTitle(id: title.id, fallback: title.fallback)
    }

    func isEnabled(in context: FreeRulerCommandContext) -> Bool {
        switch self {
        case .horizontalWing:
            !context.horizontalVisible || context.verticalVisible
        case .verticalWing:
            !context.verticalVisible || context.horizontalVisible
        case .rulerSettings:
            context.hasRuler
        default:
            true
        }
    }

    func selection(in context: FreeRulerCommandContext) -> Bool? {
        switch self {
        case .pixels: context.unit == .pixels
        case .millimeters: context.unit == .millimeters
        case .inches: context.unit == .inches
        case .floatRuler: context.floatRulers
        case .rulerShadow: context.rulerShadow
        case .groupRulers: context.groupRulers
        default: nil
        }
    }

    func perform() {
        NSApp.sendAction(action, to: AppDelegate.current, from: NSApplication.shared)
    }
}

struct AppCommands: Commands {
    @ObservedObject private var ruler = FreeRulerCommandContext.shared

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            if ruler.showsHostCommands {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .commandOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            } else {
                Button("Ruler Settings…") {
                    AppDelegate.current?.openRulerSettings(NSApplication.shared)
                }
                .keyboardShortcut(",", modifiers: .command)

                Button("Ruler Defaults…") {
                    AppDelegate.current?.openPreferences(NSApplication.shared)
                }
                .keyboardShortcut(",", modifiers: [.option, .command])
            }
        }

        CommandGroup(replacing: .newItem) {
            if ruler.showsHostCommands {
                Button("New Transfer") {
                    NotificationCenter.default.post(name: .commandNewTransfer, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        CommandMenu("Utilities") {
            Button("Toggle Awake") {
                ToolActionRouter.shared.execute(ToolActionRequest(action: .awakeToggle))
            }
            .keyboardShortcut("a", modifiers: [.command, .option, .control])

            Button("Pick Color") {
                ToolActionRouter.shared.execute(ToolActionRequest(action: .colorPickerPick))
            }
            .keyboardShortcut("c", modifiers: [.command, .option, .control])

            Button("Extract Text") {
                ToolActionRouter.shared.execute(ToolActionRequest(action: .textExtractorCapture))
            }
            .keyboardShortcut("t", modifiers: [.command, .option, .control])
        }
    }
}

struct FreeRulerCommands: Commands {
    @ObservedObject private var ruler = FreeRulerCommandContext.shared

    var body: some Commands {
        if ruler.isActive {
            CommandMenu(FreeRulerCommand.localizedTitle(id: "dMs-cI-mzQ", fallback: "Ruler")) {
                commandButton(.newRuler)
                Divider()
                commandButton(.horizontalWing)
                commandButton(.verticalWing)
                Divider()
                commandButton(.rulerSettings)
            }

            CommandMenu(FreeRulerCommand.localizedTitle(id: "iDP-2z-irv", fallback: "Unit")) {
                commandToggle(.pixels)
                commandToggle(.millimeters)
                commandToggle(.inches)
                Divider()
                commandButton(.cycleUnits)
            }

            CommandMenu(FreeRulerCommand.localizedTitle(id: "H8h-7b-M4v", fallback: "Options")) {
                Menu(FreeRulerCommand.localizedTitle(id: "TkR-03-X6l", fallback: "Flip")) {
                    commandButton(.flipHorizontal)
                    commandButton(.flipVertical)
                }
                commandToggle(.floatRuler)
                commandToggle(.rulerShadow)
                Divider()
                commandToggle(.groupRulers)
                commandButton(.alignAtMouse)
                commandButton(.resetPosition)
            }
        }
    }

    private func commandButton(_ command: FreeRulerCommand) -> some View {
        Button(command.title(in: ruler)) { command.perform() }
            .freeRulerShortcut(command.shortcut)
            .disabled(!command.isEnabled(in: ruler))
    }

    private func commandToggle(_ command: FreeRulerCommand) -> some View {
        Toggle(command.title(in: ruler), isOn: selectionBinding(command))
            .freeRulerShortcut(command.shortcut)
            .disabled(!command.isEnabled(in: ruler))
    }

    private func selectionBinding(_ command: FreeRulerCommand) -> Binding<Bool> {
        let isSelected = command.selection(in: ruler) ?? false
        return Binding(
            get: { isSelected },
            set: { selected in
                if selected != isSelected { command.perform() }
            }
        )
    }
}

private extension View {
    @ViewBuilder
    func freeRulerShortcut(_ shortcut: FreeRulerCommandShortcut?) -> some View {
        if let shortcut {
            keyboardShortcut(KeyEquivalent(shortcut.key), modifiers: shortcut.modifiers)
        } else {
            self
        }
    }
}
