import Foundation
import Testing
@testable import powertoys

struct ToolPageRouterTests {
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

    @MainActor @Test func nativeSceneRoutesKeepPendingPagesWithoutReopening() throws {
        let router = ToolPageRouter()
        let url = try #require(URL(string: "macpowertoys://open/rclone/remote/My%20Drive"))
        router.handleNativeURL(url, tool: "main")
        #expect(router.take(tool: "rclone") == nil)
        router.handleNativeURL(url, tool: "rclone")
        #expect(router.take(tool: "rclone")?.page == "remote/My Drive")
        #expect(router.take(tool: "rclone") == nil)
        router.handleNativeURL(try #require(URL(string: "powertoys://open/rclone")), tool: "rclone")
        #expect(router.take(tool: "rclone") == nil)
        router.handleNativeURL(try #require(URL(string: "powertoys://open/nettoys/scan?targets=localhost")), tool: "nettoys")
        #expect(router.take(tool: "nettoys") == nil, "The app delegate owns scan-prefill URLs.")
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

    @Test func parsesCaptureDiagnosticsOnlyUnderDiagnosticsHost() throws {
        for scheme in ["macpowertoys", "powertoys"] {
            for appearance in AppAppearance.allCases {
                #expect(DiagnosticsRoute.parse(try #require(URL(string: "\(scheme)://diagnostics/appearance/\(appearance.rawValue)")))
                    == .appearance(appearance))
            }
            #expect(DiagnosticsRoute.parse(try #require(URL(string: "\(scheme)://diagnostics/close-panels"))) == .closePanels)
        }
        for value in ["https://diagnostics/close-panels", "powertoys://open/close-panels",
                      "powertoys://open/appearance/dark", "powertoys://diagnostics/appearance/unknown",
                      "powertoys://diagnostics/appearance/Dark", "powertoys://diagnostics/appearance/dark/extra",
                      "powertoys://diagnostics/close-panels/", "powertoys://diagnostics/close-panels?extra=1",
                      "powertoys://diagnostics/appearance/light#extra", "powertoys://user@diagnostics/close-panels",
                      "powertoys://diagnostics:123/appearance/automatic"] {
            #expect(DiagnosticsRoute.parse(try #require(URL(string: value))) == nil)
        }
    }
}
