//
//  AppCommands.swift
//  powertoys
//

import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    static let commandOpenSettings = Notification.Name("commandOpenSettings")
}

struct AppCommandAction {
    let title: String
    let perform: () -> Void
}

private struct AppNewTransferKey: FocusedValueKey { typealias Value = () -> Void }
private struct AppRefreshKey: FocusedValueKey { typealias Value = () -> Void }
private struct AppUploadKey: FocusedValueKey { typealias Value = () -> Void }
private struct AppQuickLookKey: FocusedValueKey { typealias Value = () -> Void }
private struct AppCopyPathKey: FocusedValueKey { typealias Value = () -> Void }
private struct AppInspectKey: FocusedValueKey { typealias Value = () -> Void }
private struct AppOpenSettingsKey: FocusedValueKey { typealias Value = () -> Void }
private struct AppGlobalSearchKey: FocusedValueKey { typealias Value = () -> Void }
private struct AppFindKey: FocusedValueKey { typealias Value = AppCommandAction }

extension FocusedValues {
    var appNewTransfer: (() -> Void)? {
        get { self[AppNewTransferKey.self] }
        set { self[AppNewTransferKey.self] = newValue }
    }
    var appRefresh: (() -> Void)? {
        get { self[AppRefreshKey.self] }
        set { self[AppRefreshKey.self] = newValue }
    }
    var appUpload: (() -> Void)? {
        get { self[AppUploadKey.self] }
        set { self[AppUploadKey.self] = newValue }
    }
    var appQuickLook: (() -> Void)? {
        get { self[AppQuickLookKey.self] }
        set { self[AppQuickLookKey.self] = newValue }
    }
    var appCopyPath: (() -> Void)? {
        get { self[AppCopyPathKey.self] }
        set { self[AppCopyPathKey.self] = newValue }
    }
    var appInspect: (() -> Void)? {
        get { self[AppInspectKey.self] }
        set { self[AppInspectKey.self] = newValue }
    }
    var appOpenSettings: (() -> Void)? {
        get { self[AppOpenSettingsKey.self] }
        set { self[AppOpenSettingsKey.self] = newValue }
    }
    var appGlobalSearch: (() -> Void)? {
        get { self[AppGlobalSearchKey.self] }
        set { self[AppGlobalSearchKey.self] = newValue }
    }
    var appFind: AppCommandAction? {
        get { self[AppFindKey.self] }
        set { self[AppFindKey.self] = newValue }
    }
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
    @FocusedValue(\.appNewTransfer) private var newTransfer
    @FocusedValue(\.appRefresh) private var refresh
    @FocusedValue(\.appUpload) private var upload
    @FocusedValue(\.appQuickLook) private var quickLook
    @FocusedValue(\.appCopyPath) private var copyPath
    @FocusedValue(\.appInspect) private var inspect
    @FocusedValue(\.appOpenSettings) private var openSettings
    @FocusedValue(\.appGlobalSearch) private var globalSearch
    @FocusedValue(\.appFind) private var find
    @State private var quitTitle = Self.quitMenuTitle(toolID: nil)

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            if ruler.showsHostCommands {
                Button("Settings…") {
                    if let openSettings { openSettings() }
                    else { openCurrentSettings() }
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
                    newTransfer?()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(newTransfer == nil)
            }
        }

        CommandGroup(replacing: .appInfo) {
            Button("About MacPowerToys") { openAbout() }
        }

        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                openAbout()
                HostUpdateChecker.shared.check()
            }
            .disabled(HostUpdateChecker.shared.isChecking)
        }

        CommandGroup(after: .textEditing) {
            Button(find?.title ?? "Find") { find?.perform() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(find == nil)
            Button("Global Search") { globalSearch?() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(globalSearch == nil)
        }

        CommandMenu("Actions") {
            Button("Refresh") { refresh?() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(refresh == nil)
            Button("Upload…") { upload?() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(upload == nil)
            Button("Quick Look") { quickLook?() }
                .keyboardShortcut("y", modifiers: .command)
                .disabled(quickLook == nil)
            Button("Copy Path") { copyPath?() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(copyPath == nil)
            Button("Inspect Process") { inspect?() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(inspect == nil)
        }

        CommandGroup(replacing: .appTermination) {
            Button(quitTitle) {
                AppDelegate.current?.handleQuitCommand()
            }
            .keyboardShortcut("q", modifiers: .command)
            .onAppear(perform: updateQuitTitle)
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                updateQuitTitle()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
                updateQuitTitle()
            }

            Button("Quit MacPowerToys") { AppDelegate.current?.quitFromStatusItem() }
                .keyboardShortcut("q", modifiers: [.command, .option])
        }

        CommandMenu("Utilities") {
            Toggle("Kwake", isOn: Binding(
                get: { SettingsManager.shared.isToolEnabled("awake") && AwakeService.shared.isActive },
                set: { _ in ToolActionRouter.shared.execute(ToolActionRequest(action: .awakeToggle)) }
            ))
            .keyboardShortcut("a", modifiers: [.command, .option, .control])
            .disabled(!SettingsManager.shared.isToolEnabled("awake"))

            Button("Pick Color") {
                ToolActionRouter.shared.execute(ToolActionRequest(action: .colorPickerPick))
            }
            .keyboardShortcut("c", modifiers: [.command, .option, .control])
            .disabled(!SettingsManager.shared.isToolEnabled("color-picker") || ColorPickerService.shared.isPicking)

            Button("Extract Text") {
                ToolActionRouter.shared.execute(ToolActionRequest(action: .textExtractorCapture))
            }
            .keyboardShortcut("t", modifiers: [.command, .option, .control])
            .disabled(!SettingsManager.shared.isToolEnabled("text-extractor")
                      || TextExtractorService.shared.state == .selecting
                      || TextExtractorService.shared.state == .recognizing)
        }
    }

    private func openAbout() {
        ToolActionRouter.shared.open(toolID: "main", page: "settings-about")
    }

    private func openCurrentSettings() {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        if let toolID = AppDelegate.quitCommandToolID(for: window) {
            ToolActionRouter.shared.open(toolID: toolID, page: "settings")
        } else {
            ToolActionRouter.shared.open(toolID: "main", page: "settings")
        }
    }

    private func updateQuitTitle() {
        quitTitle = Self.quitMenuTitle(toolID: AppDelegate.quitCommandToolID(for: NSApp.keyWindow ?? NSApp.mainWindow))
    }

    static func quitMenuTitle(toolID: String?) -> String {
        if let toolID, let tool = ToolRegistry.tool(for: toolID) { return "Close \(tool.name)" }
        return "Press ⌘Q again to quit"
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
