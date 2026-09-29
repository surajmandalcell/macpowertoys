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
                      "powertoys://open/main//cpu", "powertoys://open/main/cpu/extra",
                      "powertoys://open/main/bad%20page", "powertoys://user@open/main",
                      "powertoys://open:123/main", "powertoys://open/main#page"] {
            #expect(OpenToolRoute.parse(try #require(URL(string: value))) == nil)
        }
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
}
