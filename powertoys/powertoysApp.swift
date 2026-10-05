//
//  powertoysApp.swift
//  powertoys
//

import SwiftUI
import SwiftData
import AppIntents
import OnePlusUI

@main
struct MacPowerToysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    @AppStorage("app.showTray") private var showTray = true
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.dark

    init() {
        if AppRuntime.isRunningUnitTests {
            NSApplication.shared.setActivationPolicy(.prohibited)
        }
        if !AppRuntime.isRunningTests {
            let started = ContinuousClock.now
            AppIdentity.migrateLegacyPreferences()
            NSLog("Startup preferences migrated in %@", String(describing: started.duration(to: .now)))
        }
        PortmanShortcuts.updateAppShortcutParameters()
    }

    @MainActor
    private func configureApplication() {
        if !AppRuntime.isRunningTests || AppRuntime.isUITesting {
            MainMenuBarController.shared.configure(isInserted: showTray) {
                AnyView(TrayPopoverView().modifier(AppStorageRecovery()).utilityMotionPolicy())
            }
        }
        if DiagnosticsMenuPanels.shared.makeCaptureContent == nil {
            DiagnosticsMenuPanels.shared.makeCaptureContent = { panel, profiles, resize in
                switch panel {
                case .main:
                    AnyView(TrayPopoverView(diagnostic: true).utilityMotionPolicy())
                case .systemMonitor:
                    AnyView(SystemMonitorMenuPopoverView(remoteProfiles: profiles, diagnostic: true, onPreferredHeight: resize))
                case .portman: nil
                }
            }
        }
        appearance.apply()
        appDelegate.configureApplication {
            if AppRuntime.isUITesting {
                await AppInitializer.shared.openStorage()
                DeepLinkHandler.shared.setOpenWindowAction(openWindow)
                DeepLinkHandler.shared.handleCLIArguments()
                return
            }
            guard !AppRuntime.isRunningTests else {
                await AppInitializer.shared.openStorage()
                DeepLinkHandler.shared.setOpenWindowAction(openWindow)
                return
            }
            await AppInitializer.shared.initialize {
                appearance.apply()
                DeepLinkHandler.shared.setOpenWindowAction(openWindow)
                DeepLinkHandler.shared.handleCLIArguments()
            }
        }
    }

    @MainActor
    static func makeBackgroundWindow(id: String) -> NSWindow? {
        guard let canvas = OnePlusWindowCanvas.tool(id) else { return nil }
        let window = BackgroundToolWindow(contentRect: .init(origin: .zero, size: canvas.size),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.identifier = .init(id)
        window.title = id == "main" ? "MacPowerToys" : ToolRegistry.tool(for: id)?.name ?? id
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.animationBehavior = .none
        window.setFrame(.init(origin: window.frame.origin, size: canvas.size), display: false)
        window.center()
        window.prepareContent()
        WindowStateManager.shared.restoreState(for: window)
        return window
    }

    @ViewBuilder
    static func windowContent(id: String) -> some View {
        switch id {
        case "main":
            OnePlusWindowContent {
                MainWindowView()
                    .modifier(AppStorageRecovery())
                    .utilityMotionPolicy()
                    .environment(\.toolWindowID, "main")
                    .onePlusFixedCanvas(.main)
                    .onToolWindowURL("main")
            }
        case "rclone":
            OnePlusWindowContent {
                AppStorageContent {
                    RcloneWindowView()
                        .utilityMotionPolicy()
                }
                .onToolWindowURL("rclone")
            }
        case "logs":
            OnePlusWindowContent {
                LogsWindowView()
                    .utilityMotionPolicy()
                    .onePlusFixedCanvas(.logs)
                    .onToolWindowURL("logs")
            }
        case "awake":
            OnePlusWindowContent {
                AwakeView()
                    .utilityMotionPolicy()
                    .background(WindowAccessor(identifier: "awake"))
                    .onePlusFixedCanvas(.awake)
                    .onToolWindowURL("awake")
            }
        case "color-picker":
            OnePlusWindowContent {
                ColorHistoryView()
                    .utilityMotionPolicy()
                    .background(WindowAccessor(identifier: "color-picker"))
                    .onePlusFixedCanvas(.colorPicker)
                    .onToolWindowURL("color-picker")
            }
        case "text-extractor":
            OnePlusWindowContent {
                TextExtractorView()
                    .utilityMotionPolicy()
                    .background(WindowAccessor(identifier: "text-extractor"))
                    .onePlusFixedCanvas(.textExtractor)
                    .onToolWindowURL("text-extractor")
            }
        case "input-devices":
            OnePlusWindowContent {
                InputDevicesWindowView()
                    .utilityMotionPolicy()
                    .onePlusFixedCanvas(.inputDevices)
                    .onToolWindowURL("input-devices")
            }
        case "system-care":
            OnePlusWindowContent {
                SystemCareWindowView()
                    .utilityMotionPolicy()
                    .onePlusFixedCanvas(.systemCare)
                    .onToolWindowURL("system-care")
            }
        case "disk-explorer":
            OnePlusWindowContent {
                DiskExplorerWindowView()
                    .utilityMotionPolicy()
                    .onePlusFixedCanvas(.diskExplorer)
                    .onToolWindowURL("disk-explorer")
            }
        case "system-monitor":
            OnePlusWindowContent {
                SystemMonitorWindowView()
                    .utilityMotionPolicy()
                    .onePlusFixedCanvas(.systemMonitor)
                    .onToolWindowURL("system-monitor")
            }
        case "nettoys":
            OnePlusWindowContent {
                MacPowerToysNetToysView()
                    .utilityMotionPolicy()
                    .onePlusFixedCanvas(.netToys)
                    .onToolWindowURL("nettoys")
            }
        case "mac-tweaks":
            OnePlusWindowContent {
                MacTweaksWindowView()
                    .utilityMotionPolicy()
                    .onePlusFixedCanvas(.macTweaks)
                    .onToolWindowURL("mac-tweaks")
            }
        default: EmptyView()
        }
    }

    var body: some Scene {
        let _ = configureApplication()

        Window("MacPowerToys", id: "main") {
            Self.windowContent(id: "main")
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(OnePlusWindowCanvas.main.size)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .handlesExternalEvents(matching: [])
        .commands {
            AppCommands()
            FreeRulerCommands()
        }

        Window("RSync UI", id: "rclone") {
            Self.windowContent(id: "rclone")
        }
        .defaultSize(OnePlusWindowCanvas.rclone.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("Event Viewer", id: "logs") {
            Self.windowContent(id: "logs")
        }
        .defaultSize(OnePlusWindowCanvas.logs.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("Kwake", id: "awake") {
            Self.windowContent(id: "awake")
        }
        .defaultSize(OnePlusWindowCanvas.awake.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("Color Picker", id: "color-picker") {
            Self.windowContent(id: "color-picker")
        }
        .defaultSize(
            width: OnePlusWindowCanvas.colorPicker.size.width,
            height: ColorPickerLayout.historyBaseHeight + UtilityLayout.compactTitlebarHeight
        )
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("Text Extractor", id: "text-extractor") {
            Self.windowContent(id: "text-extractor")
        }
        .defaultSize(
            width: OnePlusWindowCanvas.textExtractor.size.width,
            height: TextExtractorLayout.historyBaseHeight + UtilityLayout.compactTitlebarHeight
        )
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("Input Devices", id: "input-devices") {
            Self.windowContent(id: "input-devices")
        }
        .defaultSize(OnePlusWindowCanvas.inputDevices.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("System Cleaner", id: "system-care") {
            Self.windowContent(id: "system-care")
        }
        .defaultSize(OnePlusWindowCanvas.systemCare.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("Partition Manager", id: "disk-explorer") {
            Self.windowContent(id: "disk-explorer")
        }
        .defaultSize(OnePlusWindowCanvas.diskExplorer.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("Task Manager", id: "system-monitor") {
            Self.windowContent(id: "system-monitor")
        }
        .defaultSize(OnePlusWindowCanvas.systemMonitor.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("NetToys", id: "nettoys") {
            Self.windowContent(id: "nettoys")
        }
        .defaultSize(OnePlusWindowCanvas.netToys.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("Mac Tweaks", id: "mac-tweaks") {
            Self.windowContent(id: "mac-tweaks")
        }
        .defaultSize(OnePlusWindowCanvas.macTweaks.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

    }
}

final class BackgroundToolWindow: NSWindow {
    private var allowsForegroundOrdering = false

    func prepareContent() {
        guard contentViewController == nil, let id = identifier?.rawValue else { return }
        Self.mountContent(id: id, in: self)
    }

    private static func mountContent(id: String, in window: BackgroundToolWindow) {
        guard let canvas = OnePlusWindowCanvas.tool(id) else { return }
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.styleMask = window.styleMask.union(.fullSizeContentView).subtracting(.resizable)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        let host = NSHostingController(rootView: MacPowerToysApp.windowContent(id: id)
            .environment(\.toolWindowID, id))
        host.sizingOptions = canvas.heightRange == nil ? [] : [.intrinsicContentSize]
        window.contentViewController = host
        host.view.layoutSubtreeIfNeeded()
        var size = canvas.size
        if let range = canvas.heightRange {
            let height = host.view.fittingSize.height - host.view.safeAreaInsets.top
            size.height = min(max(height, range.lowerBound), range.upperBound)
        }
        window.setFrame(NSRect(x: topLeft.x, y: topLeft.y - size.height,
                               width: size.width, height: size.height), display: false)
        host.view.layoutSubtreeIfNeeded()
    }

    override func close() {
        let size = contentView?.frame.size ?? .zero
        let frame = frame
        super.close()
        contentViewController = nil
        contentView = NSView(frame: .init(origin: .zero, size: size))
        setFrame(frame, display: false)
    }

    override func orderFrontRegardless() {
        prepareContent()
        guard isOnActiveSpace else { return }
        if NSApp.isActive || allowsForegroundOrdering {
            ActivationDiagnostics.noteOrdering("orderFrontRegardless", window: self)
            super.orderFrontRegardless()
        } else {
            orderBack(nil)
        }
    }

    override func orderFront(_ sender: Any?) {
        prepareContent()
        guard isOnActiveSpace || allowsForegroundOrdering else { return }
        if NSApp.isActive || allowsForegroundOrdering {
            ActivationDiagnostics.noteOrdering("orderFront", window: self)
            super.orderFront(sender)
        } else {
            orderBack(sender)
        }
    }

    override func orderBack(_ sender: Any?) {
        prepareContent()
        ActivationDiagnostics.noteOrdering("orderBack", window: self)
        super.orderBack(sender)
    }

    override func makeKey() {
        ActivationDiagnostics.noteOrdering("makeKey", window: self)
        super.makeKey()
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        prepareContent()
        ActivationDiagnostics.noteOrdering("makeKeyAndOrderFront", window: self)
        allowsForegroundOrdering = true
        defer { allowsForegroundOrdering = false }
        super.makeKeyAndOrderFront(sender)
    }
}

private struct AppStorageRecovery: ViewModifier {
    @Environment(\.appearsActive) private var appearsActive
    private var store: AppModelStore { AppInitializer.shared.modelStore }

    func body(content: Content) -> some View {
        content.alert("Cannot open saved data", isPresented: Binding(
            get: { appearsActive && NSApp.isActive && store.showsRecovery },
            set: { if appearsActive && NSApp.isActive { store.showsRecovery = $0 } }
        )) {
            Button("Retry") { Task { await AppInitializer.shared.openStorage() } }
            Button("Reveal Data Folder") { NSWorkspace.shared.open(AppDataLocation.directory) }
            Button("Keep open", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "The data store could not be opened.")
        }
    }
}

private struct AppStorageContent<Content: View>: View {
    @ViewBuilder let content: () -> Content
    private var store: AppModelStore { AppInitializer.shared.modelStore }

    var body: some View {
        Group {
            if let container = store.container {
                content().modelContainer(container)
            } else if let error = store.errorMessage {
                VStack(spacing: OnePlusMetrics.contentGap) {
                    Text("Cannot open saved data").onePlusText(.sectionTitle)
                    Text(error).onePlusText(.row).textSelection(.enabled)
                    HStack {
                        Button("Retry") { Task { await AppInitializer.shared.openStorage() } }
                        Button("Reveal Data Folder") { NSWorkspace.shared.open(AppDataLocation.directory) }
                    }
                    .buttonStyle(OnePlusButtonStyle(.neutral))
                }
                .padding(OnePlusMetrics.gutter)
            } else {
                ProgressView("Opening saved data")
            }
        }
        .modifier(AppStorageRecovery())
        .onePlusFixedCanvas(.rclone)
    }
}

extension MacPowerToysApp {
    static func handleIncomingURL(_ url: URL) {
        ActivationDiagnostics.noteURL(url)
        DeepLinkHandler.shared.handle(url: url)
    }
}

struct OpenPortmanIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Portman"
    static let description = IntentDescription("Show Portman in the menu bar.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { PortmanMenuController.shared.show() }
        return .result()
    }
}

struct PortmanShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenPortmanIntent(),
            phrases: ["Open Portman in \(.applicationName)", "Show Portman in \(.applicationName)"],
            shortTitle: "Portman",
            systemImageName: "circle.grid.2x2.fill"
        )
    }
}

extension Notification.Name {
    static let navigateToCategory = Notification.Name("navigateToCategory")
    static let globalSearch = Notification.Name("globalSearch")
    static let conversationSearch = Notification.Name("conversationSearch")
    static let copySelected = Notification.Name("copySelected")
    static let selectMainTab = Notification.Name("selectMainTab")
    static let openToolSettings = Notification.Name("openToolSettings")
    static let newTransferRequested = Notification.Name("newTransferRequested")
}
