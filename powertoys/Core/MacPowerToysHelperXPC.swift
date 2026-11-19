import Foundation

/// The privileged helper, installed once with SMJobBless. The label is also the Mach service, the
/// helper's code-signing identifier, and its file name in Contents/Library/LaunchServices and
/// /Library/PrivilegedHelperTools. The same requirement strings sit in the app's
/// SMPrivilegedExecutables and the helper's SMAuthorizedClients.
nonisolated enum MacPowerToysHelperContract {
    static let label = "com.surajmandal.macpowertoys.helper"
    static let machServiceName = label
    static let installedPath = "/Library/PrivilegedHelperTools/" + label
    static let teamIdentifier = "GF57JXJF5A"
    static let teamRequirement = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    static let mainAppRequirement = signedRequirement("com.surajmandal.macpowertoys")
    static let helperRequirement = signedRequirement(label)
    /// The SMAppService daemon that older builds registered. Its plist stays in the bundle only so the
    /// launch migration can unregister it.
    static let legacyDaemonPlistName = "com.surajmandal.macpowertoys.nettoys-neighbor.plist"

    private static func signedRequirement(_ identifier: String) -> String {
        "identifier \"\(identifier)\" and \(teamRequirement)"
    }
}

@objc nonisolated protocol MacPowerToysHelperXPCProtocol {
    /// Replies with the helper's CFBundleVersion. The data is always nil; the selector stays for older helpers.
    func neighborSnapshot(reply: @escaping (Data?, String) -> Void)
    func applyFanPreset(_ preset: String, reply: @escaping (String) -> Void)
    /// Restarts coreaudiod. Takes no input, so no caller can choose a command or path. Replies "" on success.
    func restartAudio(reply: @escaping (String) -> Void)
}
