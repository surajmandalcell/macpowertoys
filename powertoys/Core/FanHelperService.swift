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

    static let shared = FanHelperService(refreshOnInit: !AppRuntime.isRunningTests)

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

    /// The root install script. It takes one argument, the helper inside this app bundle, copies it as
    /// root:wheel, checks its team signature after the copy, writes the launchd plist, and replaces any older
    /// registration (SMJobBless or an earlier run), so running it twice gives the same result.
    nonisolated static var installScript: String {
        let label = MacPowerToysHelperContract.label
        let tool = MacPowerToysHelperContract.installedPath
        let plist = "/Library/LaunchDaemons/\(label).plist"
        return """
        set -e
        /bin/launchctl bootout system/\(label) 2>/dev/null || true
        /bin/mkdir -p /Library/PrivilegedHelperTools
        /usr/bin/install -o root -g wheel -m 544 "$1" \(tool)
        /usr/bin/codesign --verify --strict -R='\(MacPowerToysHelperContract.helperRequirement)' \(tool) \
          || { /bin/rm -f \(tool); exit 3; }
        /bin/rm -f \(plist)
        /usr/bin/plutil -create xml1 \(plist)
        /usr/bin/plutil -insert Label -string \(label) \(plist)
        /usr/bin/plutil -insert Program -string \(tool) \(plist)
        /usr/bin/plutil -insert MachServices -json '{"\(MacPowerToysHelperContract.machServiceName)":true}' \(plist)
        /usr/sbin/chown root:wheel \(plist)
        /bin/chmod 644 \(plist)
        for attempt in 1 2 3 4 5; do /bin/launchctl bootstrap system \(plist) && exit 0; /bin/sleep 1; done
        exit 4
        """
    }

    /// Runs the install through /usr/bin/osascript. The admin prompt then comes from an Apple-signed requester,
    /// which macOS lets use Touch ID; our own unnotarized app gets "biometry prohibited" from SecurityAgent.
    nonisolated private static func bless() -> String? {
        let source = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchServices/" + MacPowerToysHelperContract.label).path
        let appleScript = """
        on run argv
            do shell script "/bin/sh -c " & quoted form of (item 1 of argv) & " sh " & quoted form of (item 2 of argv) \
        with administrator privileges with prompt "\(installPrompt)"
        end run
        """
        do {
            _ = try FanCommand.run("/usr/bin/osascript", ["-e", appleScript, installScript, source], seconds: 300)
            return nil
        } catch {
            let message = error.localizedDescription
            if message.contains("-128") { return "Fan helper install was canceled." }
            return "The fan helper did not install: \(message)"
        }
    }

    /// Older builds registered the helper as an SMAppService daemon and as a NetToys login item. Remove both
    /// once, so only the blessed daemon runs. Safe to call on every launch.
    nonisolated static func retireLegacyRegistrations() async {
        guard !AppRuntime.isRunningTests else { return }
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
