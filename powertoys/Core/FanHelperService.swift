import Foundation
import Observation
import Security
import ServiceManagement

/// Installs the privileged helper daemon (fan presets and Restart audio) with SMJobBless. macOS asks for an
/// admin password once, copies the helper to /Library/PrivilegedHelperTools, and loads it as a launch daemon.
/// An app update reinstalls it only when the bundled helper's CFBundleVersion is newer than the running one.
@Observable
@MainActor
final class FanHelperService {
    nonisolated enum Status: Equatable, Sendable {
        case unknown
        /// This build is not signed by the team, so SMJobBless and the helper's caller check would refuse it.
        case unsupported
        case notInstalled
        case outdated
        /// The helper file exists but did not answer the version check; reinstalling reloads it.
        case notResponding
        case ready
    }

    #if MPT_DEMO
    static let shared = FanHelperService(refreshOnInit: true) { _ in .ready }
    #else
    static let shared = FanHelperService(refreshOnInit: !AppRuntime.isRunningTests)
    #endif

    private(set) var status = Status.unknown
    @ObservationIgnored private let readStatus: @Sendable (Status) -> Status
    @ObservationIgnored private var statusGeneration = 0
    nonisolated static let legacyLoginItemIdentifier = "com.surajmandal.macpowertoys.nettoys-helper"

    init(refreshOnInit: Bool, readStatus: (@Sendable (Status) -> Status)? = nil) {
        self.readStatus = readStatus ?? Self.readStatus(previous:)
        if refreshOnInit { Task { await refresh() } }
    }

    var isEnabled: Bool { status == .ready }
    /// Only a missing or older helper asks for the password. A helper that did not answer shows an error and a
    /// Retry, never a new prompt.
    var canInstall: Bool { [.notInstalled, .outdated].contains(status) }

    func refresh() async {
        let generation = statusGeneration
        let previous = status
        let next = await Task.detached(priority: .utility) { [readStatus] in readStatus(previous) }.value
        guard generation == statusGeneration else { return }
        if status != next { status = next }
    }

    /// Shows the macOS admin password prompt and installs the helper. Returns an error message, or nil on success.
    func install() async -> String? {
        guard !AppRuntime.isRunningTests else { return "Tests never install the fan helper." }
        if DemoMode.blocks("fan.helper.install") { return nil }
        guard status != .unsupported else { return Self.unsupportedMessage }
        statusGeneration &+= 1
        let message = await Task.detached(priority: .userInitiated) { Self.bless() }.value
        if let message { LogManager.shared.warning("Fan helper install failed: \(message)", source: "FanHelper") }
        statusGeneration &+= 1
        status = .unknown
        await refresh()
        if message == nil, status != .ready { return "The fan helper was installed but did not answer. Try again." }
        return message
    }

    nonisolated static let unsupportedMessage = "This build is not signed by the MacPowerToys team, so fans stay read only."

    nonisolated private static func readStatus(previous: Status) -> Status {
        guard isTeamSigned() else { return .unsupported }
        guard FileManager.default.fileExists(atPath: MacPowerToysHelperContract.installedPath) else { return .notInstalled }
        // A helper confirmed in this launch stays confirmed; only an install changes it.
        if previous == .ready { return .ready }
        guard let bundled = bundledHelperVersion() else { return .unsupported }
        guard let running = FanCommand.helperVersion() else { return .notResponding }
        return running >= bundled ? .ready : .outdated
    }

    nonisolated private static func isTeamSigned() -> Bool {
        var code: SecCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(MacPowerToysHelperContract.mainAppRequirement as CFString, [], &requirement)
                == errSecSuccess, let requirement else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    nonisolated static func bundledHelperVersion() -> Int? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchServices/" + MacPowerToysHelperContract.label)
        guard let info = CFBundleCopyInfoDictionaryForURL(url as CFURL) as? [String: Any] else { return nil }
        return (info["CFBundleVersion"] as? String).flatMap(Int.init)
    }

    nonisolated static let installPrompt = "MacPowerToys needs your approval once to control fan speed."

    // SMJobBless is deprecated since macOS 13 but still installs helpers; SMAppService needs a Login Items trip.
    // Touch ID: SecurityAgent allows biometry only for a notarized requester (`make install NOTARIZE=1`).
    nonisolated private static func bless() -> String? {
        if DemoMode.blocks("fan.helper.bless") { return "The demo build does not install the fan helper." }
        var authorization: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &authorization) == errAuthorizationSuccess, let authorization else {
            return "macOS could not start the fan helper install."
        }
        defer { AuthorizationFree(authorization, []) }
        let icon = Bundle.main.path(forResource: "AppIcon", ofType: "icns")
        // C copies that outlive every AuthorizationItem pointing at them.
        let strings = [kSMRightBlessPrivilegedHelper, kAuthorizationEnvironmentPrompt, installPrompt,
                       kAuthorizationEnvironmentIcon, icon ?? ""].map { strdup($0)! }
        defer { strings.forEach { free($0) } }
        var right = AuthorizationItem(name: strings[0], valueLength: 0, value: nil, flags: 0)
        var environment = [
            AuthorizationItem(name: strings[1], valueLength: strlen(strings[2]), value: strings[2], flags: 0),
            AuthorizationItem(name: strings[3], valueLength: strlen(strings[4]), value: strings[4], flags: 0)
        ]
        let created = withUnsafeMutablePointer(to: &right) { rightPointer in
            environment.withUnsafeMutableBufferPointer { items in
                var rights = AuthorizationRights(count: 1, items: rightPointer)
                var context = AuthorizationEnvironment(count: icon == nil ? 1 : 2, items: items.baseAddress)
                return AuthorizationCopyRights(authorization, &rights, &context,
                                               [.interactionAllowed, .extendRights, .preAuthorize], nil)
            }
        }
        if created == errAuthorizationCanceled { return "Fan helper install was canceled." }
        guard created == errAuthorizationSuccess else {
            return "macOS did not authorize the fan helper install (\(created))."
        }
        var error: Unmanaged<CFError>?
        guard SMJobBless(kSMDomainSystemLaunchd, MacPowerToysHelperContract.label as CFString, authorization, &error) else {
            return error?.takeRetainedValue().localizedDescription ?? "macOS could not install the fan helper."
        }
        return nil
    }

    /// Older builds registered the helper as an SMAppService daemon and as a NetToys login item. Remove both
    /// once, so only the blessed daemon runs. Safe to call on every launch.
    nonisolated static func retireLegacyRegistrations() async {
        guard !AppRuntime.isRunningTests else { return }
        if DemoMode.blocks("fan.helper.retire") { return }
        let items = [SMAppService.daemon(plistName: MacPowerToysHelperContract.legacyDaemonPlistName),
                     SMAppService.loginItem(identifier: legacyLoginItemIdentifier)]
        for item in items where item.status == .enabled || item.status == .requiresApproval {
            do { try await item.unregister() } catch {
                await LogManager.shared.warning("Old helper registration stays: \(error.localizedDescription)",
                                                source: "FanHelper")
            }
        }
    }
}
