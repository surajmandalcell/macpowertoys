import AppKit
import Foundation
import SwiftUI
import Testing
@testable import powertoys

struct ToolPageRouterTests {
    @Test func closeWindowDiagnosticsRequireOneBoundedToolID() throws {
        for scheme in ["macpowertoys", "powertoys"] {
            for tool in ["main", "system-monitor", "disk-explorer", "rclone"] {
                #expect(DiagnosticsRoute.parse(try #require(URL(string: "\(scheme)://diagnostics/close-window/\(tool)")))
                    == .closeWindow(tool))
            }
        }
        for value in ["https://diagnostics/close-window/main", "powertoys://open/close-window/main",
                      "powertoys://diagnostics/close-window/", "powertoys://diagnostics/close-window/main/",
                      "powertoys://diagnostics/close-window/main?extra=1", "powertoys://user@diagnostics/close-window/main",
                      "powertoys://diagnostics:123/close-window/main", "powertoys://diagnostics/close-window/main#extra",
                      "powertoys://diagnostics/close-window/Main", "powertoys://diagnostics/close-window/bad%20id",
                      "powertoys://diagnostics/close-window/" + String(repeating: "a", count: 81)] {
            #expect(DiagnosticsRoute.parse(try #require(URL(string: value))) == nil)
        }
    }

    @Test func timingAndIndividualPanelRoutesRequireExactPaths() throws {
        for scheme in ["macpowertoys", "powertoys"] {
            #expect(DiagnosticsRoute.parse(try #require(URL(string: "\(scheme)://diagnostics/timings"))) == .timings)
            for tool in IndividualMenuBarTool.allCases {
                #expect(DiagnosticsRoute.parse(try #require(URL(string: "\(scheme)://diagnostics/open-tool-panel/\(tool.id)")))
                    == .openIndividualPanel(tool.id))
            }
        }
        for url in ["https://diagnostics/timings", "powertoys://open/timings",
                    "powertoys://diagnostics/timings/", "powertoys://diagnostics/timings?tab=home",
                    "powertoys://user@diagnostics/timings", "powertoys://diagnostics:123/timings",
                    "powertoys://diagnostics/timings#extra", "powertoys://diagnostics/open-tool-panel/unknown",
                    "powertoys://diagnostics/open-tool-panel/awake/", "powertoys://diagnostics/open-tool-panel/awake?tab=home"] {
            #expect(DiagnosticsRoute.parse(try #require(URL(string: url))) == nil)
        }
    }

    @Test func parsesToolAndPageForBothSchemes() throws {
        for scheme in ["macpowertoys", "powertoys"] {
            #expect(OpenToolRoute.parse(try #require(URL(string: "\(scheme)://open/system-monitor/cpu")))
                == OpenToolRoute(tool: "system-monitor", page: "cpu"))
            #expect(OpenToolRoute.parse(try #require(URL(string: "\(scheme)://open/main/rclone")))
                == OpenToolRoute(tool: "main", page: "rclone"))
        }
        #expect(OpenToolRoute.parse(try #require(URL(string: "powertoys://open/nettoys?targets=localhost")))
            == OpenToolRoute(tool: "nettoys", page: nil))
    }

    @Test func rejectsMalformedRoutes() throws {
        for value in ["https://open/main", "powertoys://open", "powertoys://open/main/",
                      "powertoys://open/main//cpu", "powertoys://open/Main/cpu",
                      "powertoys://open/bad%20tool/page", "powertoys://user@open/main",
                      "powertoys://open:123/main", "powertoys://open/main#page"] {
            #expect(OpenToolRoute.parse(try #require(URL(string: value))) == nil)
        }
    }

    @Test func parsesCaseSensitiveMultiSegmentPages() throws {
        let routes = [
            ("switch/account/01234567-89AB-CDEF-0123-456789ABCDEF", "switch", "account/01234567-89AB-CDEF-0123-456789ABCDEF"),
            ("disk-explorer/device/disk4s2", "disk-explorer", "device/disk4s2"),
            ("main/tool/color-picker", "main", "tool/color-picker"),
            ("rclone/remote/My%20Drive", "rclone", "remote/My Drive"),
            ("rclone/remote/Caf%C3%A9%20%26%20Work", "rclone", "remote/Café & Work"),
            ("rclone/remote/Literal%252FName", "rclone", "remote/Literal%2FName"),
            ("main/one/Two/three/Four", "main", "one/Two/three/Four"),
        ]
        for scheme in ["macpowertoys", "powertoys"] {
            for (path, tool, page) in routes {
                #expect(OpenToolRoute.parse(try #require(URL(string: "\(scheme)://open/\(path)")))
                    == OpenToolRoute(tool: tool, page: page))
            }
        }
    }

    @Test func rejectsInvalidDecodedSegmentsAndLongValues() throws {
        for path in ["main/.", "main/..", "main/%2E", "main/%2e%2e", "main/tool/../awake",
                     "main/tool//awake", "main/tool/awake/", "rclone/remote/%2F", "rclone/remote/a%5Cb",
                     "rclone/remote/%00", "rclone/remote/%0A", "rclone/remote/%FF"] {
            #expect(OpenToolRoute.parse(try #require(URL(string: "powertoys://open/\(path)"))) == nil)
        }
        let maximumPage = Array(repeating: String(repeating: "x", count: 254), count: 8).joined(separator: "/") + "/12345678"
        for path in [String(repeating: "a", count: 80), "main/" + maximumPage,
                     "rclone/remote/" + String(repeating: "a", count: 255),
                     "rclone/remote/" + String(repeating: "é", count: 127)] {
            #expect(OpenToolRoute.parse(try #require(URL(string: "powertoys://open/\(path)"))) != nil)
        }
        for path in [String(repeating: "a", count: 81), "main/" + maximumPage + "9",
                     "rclone/remote/" + String(repeating: "a", count: 256),
                     "rclone/remote/" + String(repeating: "é", count: 128),
                     "main/" + String(repeating: "a/", count: 4_096)] {
            #expect(OpenToolRoute.parse(try #require(URL(string: "powertoys://open/\(path)"))) == nil)
        }
    }

    @MainActor @Test func pageRequestsStayScopedAndAreConsumedOnce() {
        let router = ToolPageRouter()
        router.post(tool: "rclone", page: "remote/My Drive", recordTiming: false)
        #expect(router.take(tool: "main") == nil)
        #expect(router.take(tool: "rclone")?.page == "remote/My Drive")
        #expect(router.take(tool: "rclone") == nil)
    }

    @MainActor @Test func backgroundSheetRoutesWaitWithoutLosingTheRequest() {
        let router = ToolPageRouter()
        for (tool, page) in [("rclone", "new-transfer"), ("switch", "add"), ("disk-explorer", "choose-folder")] {
            router.post(tool: tool, page: page, recordTiming: false)
            #expect(router.take(tool: tool, allowSheet: false) == nil)
            #expect(router.take(tool: tool, allowSheet: false) == nil)
            #expect(router.take(tool: tool, allowSheet: true)?.page == page)
            #expect(router.take(tool: tool) == nil)
            router.post(tool: tool, page: "settings", recordTiming: false)
            #expect(router.take(tool: tool, allowSheet: false)?.page == "settings")
        }
    }

    @MainActor @Test func externalDiagnosticsReachMeasuredBackgroundPanels() async throws {
        let panels = DiagnosticsMenuPanels.shared
        panels.close(clearCache: true)
        let factory = panels.makeCaptureContent
        let defaults = UserDefaults.standard
        let keys = ["tray.selectedTab.v2", "systemMonitor.trayPage"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            panels.close(clearCache: true)
            panels.makeCaptureContent = factory
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        var built: [DiagnosticsPanel] = []
        var resize: ((CGFloat) -> Void)?
        panels.makeCaptureContent = { panel, _, onHeightChange in
            built.append(panel)
            resize = onHeightChange
            #expect(defaults.string(forKey: panel == .main ? keys[0] : keys[1]) == "home")
            return AnyView(Text("Panel body").frame(width: 356, height: 160))
        }
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for scheme in ["macpowertoys", "powertoys"] {
            for panel in [DiagnosticsPanel.main, .systemMonitor] {
                let url = try #require(URL(string: "\(scheme)://diagnostics/open-panel/\(panel.rawValue)?tab=home"))
                defaults.set(panel == .main ? "rclone" : "memory", forKey: panel == .main ? keys[0] : keys[1])
                DeepLinkHandler.shared.handle(url: url)
                for _ in 0..<200 where panels.captureWindow == nil {
                    try await Task.sleep(for: .milliseconds(5))
                }
                #expect(built.last == panel)
                let window = try #require(panels.captureWindow)
                #expect(window.identifier?.rawValue == "diagnostics-panel.\(panel.rawValue)")
                #expect(window.isVisible)
                #expect(!window.canBecomeKey && !window.canBecomeMain)
                #expect(window.contentView?.frame.size == NSSize(width: 356, height: 160))
                let top = window.frame.maxY
                resize?(240)
                #expect(window.contentView?.frame.size == NSSize(width: 356, height: 240))
                #expect(window.frame.maxY == top)
                #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == foreground)
                #expect(ToolPageRouter.shared.take(tool: panel.rawValue) == nil)
                panels.close(clearCache: true)
            }
        }
        #expect(built == [.main, .systemMonitor, .main, .systemMonitor])
    }

    @Test func diagnosticsStayUnderDiagnosticsHost() throws {
        for panel in ["main", "system-monitor", "portman"] {
            #expect(DiagnosticsPanel.parse(try #require(URL(string: "macpowertoys://diagnostics/open-panel/\(panel)"))) != nil)
        }
        for value in ["powertoys://open/open-panel/main", "powertoys://diagnostics/open-panel/unknown",
                      "powertoys://diagnostics/open-panel/main?extra=1"] {
            #expect(DiagnosticsPanel.parse(try #require(URL(string: value))) == nil)
        }
    }

    @MainActor @Test func pendingRequestUsesLastPageAndConsumesOnce() {
        let router = ToolPageRouter()
        router.post(tool: "main", page: "rclone")
        router.post(tool: "main", page: "awake")
        router.post(tool: "system-monitor", page: "cpu")
        #expect(router.take(tool: "main", matching: "rclone") == nil)
        #expect(router.take(tool: "main")?.page == "awake")
        #expect(router.take(tool: "main") == nil)
        #expect(router.take(tool: "system-monitor")?.page == "cpu")
    }

    @MainActor @Test func diagnosticsSelectOnlyKnownPanelTabs() throws {
        let suite = "ToolPageRouterTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let panels: [(DiagnosticsPanel, String, [(String, String)])] = [
            (.main, "tray.selectedTab.v2", [("home", "home"), ("cloud-sync", "rclone"),
                ("input-devices", "input-devices"), ("system-care", "system-care"),
                ("nettoys", "nettoys"), ("switch", "switch")]),
            (.systemMonitor, "systemMonitor.trayPage", ["home", "cpu", "gpu", "memory", "network",
                "disk", "battery", "sensors", "processes"].map { ($0, $0) }),
            (.portman, "portman.selectedPage", [("servers", "Servers"), ("forward", "Forward"), ("settings", "Settings")])
        ]
        for (panel, key, tabs) in panels {
            for (id, saved) in tabs {
                let url = try #require(URL(string: "macpowertoys://diagnostics/open-panel/\(panel.rawValue)?tab=\(id)"))
                #expect(DiagnosticsRoute.parse(url) == .openPanel(panel, tab: id))
                panel.selectTab(id, defaults: defaults)
                #expect(defaults.string(forKey: key) == saved)
            }
            let saved = defaults.string(forKey: key)
            for unknown in [nil, "", "unknown", "CPU", "rclone", "../home"] as [String?] {
                panel.selectTab(unknown, defaults: defaults)
                #expect(defaults.string(forKey: key) == saved)
            }
        }
        for value in ["powertoys://open/open-panel/main?tab=home",
                      "powertoys://diagnostics/open-panel/main?tab=home&tab=switch",
                      "powertoys://diagnostics/open-panel/main?tab",
                      "powertoys://diagnostics/appearance/dark?tab=home"] {
            #expect(DiagnosticsRoute.parse(try #require(URL(string: value))) == nil)
        }
    }

    @MainActor @Test func diagnosticsFindFlattenedMainStatusLabelWithoutGuessing() {
        let main = NSStatusBarButton(frame: .zero)
        let monitor = NSStatusBarButton(frame: .zero)
        monitor.identifier = NSUserInterfaceItemIdentifier("SystemMonitorMenuBarItem")
        let portman = NSStatusBarButton(frame: .zero)
        portman.setAccessibilityIdentifier("portman.statusItem")
        let individual = NSStatusBarButton(frame: .zero)
        individual.identifier = NSUserInterfaceItemIdentifier("individual-menu.awake")
        let buttons = [individual, monitor, main, portman]
        #expect(DiagnosticsPanel.main.matchingButton(in: buttons) === main)
        #expect(DiagnosticsPanel.systemMonitor.matchingButton(in: buttons) === monitor)
        #expect(DiagnosticsPanel.portman.matchingButton(in: buttons) === portman)
        #expect(DiagnosticsPanel.main.matchingButton(in: [main, NSStatusBarButton(frame: .zero)]) == nil)
        #expect(DiagnosticsPanel.main.matchingButton(in: [monitor, portman, individual]) == nil)
    }

    @MainActor @Test func diagnosticsSelectAndMeasureBeforePresentingCaptureContent() async throws {
        let suite = "DiagnosticPanelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("home", forKey: "tray.selectedTab.v2")
        let router = DiagnosticsMenuPanels(defaults: defaults)
        defer { router.close() }
        var built: [DiagnosticsPanel] = []
        router.makeCaptureContent = { panel, _, _ in
            built.append(panel)
            #expect(defaults.string(forKey: panel == .main ? "tray.selectedTab.v2" : "systemMonitor.trayPage")
                == (panel == .main ? "rclone" : "memory"))
            return AnyView(Text("Panel body").frame(width: 356, height: 160))
        }
        let wasActive = NSApp.isActive
        router.open(.main, tab: "cloud-sync")
        #expect(built == [.main])
        #expect(router.captureWindow?.isVisible == true)
        #expect(router.captureWindow?.canBecomeKey == false)
        #expect(router.captureWindow?.contentView?.frame.height == 160)
        #expect(defaults.string(forKey: "tray.selectedTab.v2") == "rclone")
        #expect(NSApp.isActive == wasActive)
        let firstWindow = try #require(router.captureWindow)
        router.open(.systemMonitor, tab: "memory")
        for _ in 0..<200 where router.captureWindow == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(built == [.main, .systemMonitor])
        #expect(firstWindow.isVisible == false)
        #expect(firstWindow.contentViewController != nil)
        #expect(defaults.string(forKey: "systemMonitor.trayPage") == "memory")
        router.close()
        #expect(router.captureWindow == nil)
    }

    @Test func parsesCaptureDiagnosticsOnlyUnderDiagnosticsHost() throws {
        for scheme in ["macpowertoys", "powertoys"] {
            for appearance in AppAppearance.allCases {
                #expect(DiagnosticsRoute.parse(try #require(URL(string: "\(scheme)://diagnostics/appearance/\(appearance.rawValue)")))
                    == .appearance(appearance))
            }
            #expect(DiagnosticsRoute.parse(try #require(URL(string: "\(scheme)://diagnostics/close-panels"))) == .closePanels)
            #expect(DiagnosticsRoute.parse(try #require(URL(string: "\(scheme)://diagnostics/close-panels/"))) == nil)
        }
        for value in ["https://diagnostics/close-panels", "powertoys://open/close-panels",
                      "powertoys://open/appearance/dark", "powertoys://diagnostics/appearance/unknown",
                      "powertoys://diagnostics/appearance/Dark", "powertoys://diagnostics/appearance/dark/extra",
                      "powertoys://diagnostics/close-panels?extra=1",
                      "powertoys://diagnostics/appearance/light#extra", "powertoys://user@diagnostics/close-panels",
                      "powertoys://diagnostics:123/appearance/automatic"] {
            #expect(DiagnosticsRoute.parse(try #require(URL(string: value))) == nil)
        }
    }
}
