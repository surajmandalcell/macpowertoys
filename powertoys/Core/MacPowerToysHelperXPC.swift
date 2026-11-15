import Foundation

/// The privileged fan helper. Its names keep "nettoys" from its first use, so the owner's
/// existing macOS approval of the daemon stays valid.
nonisolated enum MacPowerToysHelperContract {
    static let machServiceName = "com.surajmandal.macpowertoys.nettoys-neighbor"
    static let daemonPlistName = machServiceName + ".plist"
    static let mainAppRequirement = signedRequirement("com.surajmandal.macpowertoys")
    static let helperRequirement = signedRequirement("com.surajmandal.macpowertoys.nettoys-helper")

    private static func signedRequirement(_ identifier: String) -> String {
        "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"GF57JXJF5A\""
    }
}

@objc nonisolated protocol MacPowerToysHelperXPCProtocol {
    /// Replies with the helper's source commit. The data is always nil; the selector stays for older helpers.
    func neighborSnapshot(reply: @escaping (Data?, String) -> Void)
    func applyFanPreset(_ preset: String, reply: @escaping (String) -> Void)
}
