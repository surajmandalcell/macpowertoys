import Foundation
import IndieCrumbCore
import IndieCrumbUsage

/// The opt-in daily count to IndieCrumb: Settings > General "Share anonymous daily counts", off by default.
enum DailyCounts {
    static let storageKey = "app.shareDailyCounts"

    private static let core = IndieCrumb(endpoint: URL(string: "https://crumb.samhq.app")!,
                                         key: "ic_pub_c72a4c8bc723ee3f44cc057c104e94e2",
                                         enabled: UserDefaults.standard.bool(forKey: storageKey))
    private static let usage = Usage(core)

    /// Pings when due and checks every hour; sends nothing while the switch is off.
    static func start() { usage.start() }

    static func setEnabled(_ on: Bool) { core.isEnabled = on }
}
