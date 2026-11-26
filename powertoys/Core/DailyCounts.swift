import Foundation
import IndieCrumbCore
import IndieCrumbCrash
import IndieCrumbCrashUI
import IndieCrumbFeedback
import IndieCrumbUsage

/// The daily count to IndieCrumb: Settings "Share anonymous usage", on by default. The update check never reads it.
enum DailyCounts {
    static let storageKey = "app.shareDailyCounts"

    private static let core = IndieCrumb(endpoint: URL(string: "https://crumb.samhq.app")!,
                                         key: "ic_pub_c72a4c8bc723ee3f44cc057c104e94e2",
                                         enabled: UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true)
    private static let usage = Usage(core)
    private static let crashes = CrashReporter(core)

    /// Pings when due and checks every hour; sends nothing while the switch is off.
    static func start() { usage.start() }

    /// After a crash, the next launch asks; a report is sent only when the person presses Send.
    @MainActor static func askAboutCrashes() { CrashAsk.start(crashes, core: core) }

    static func setEnabled(_ on: Bool) { core.isEnabled = on }

    /// Sent only after the person pressed Send Report.
    static func sendReport(_ text: String) { Task { _ = try? await core.sendFeedback(kind: .bug, text: text) } }
}
