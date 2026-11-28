import SwiftUI

#if !MPT_PRO
/// The free build has no Pro tools. With the private macpowertoys-pro checkout next to this repo, the Makefile copies
/// its sources into the ignored `powertoys/Pro` folder and sets `MPT_PRO`; that code supplies the real `ProPackage`.
enum ProPackage {
    static let tools: [any Tool] = []
    static func start() {}
    static func setEnabled(_ enabled: Bool, toolID: String) {}
    static func settingsView(for toolID: String) -> AnyView? { nil }
    static func marketplaceCard() -> AnyView? { nil }
}
#endif
