import AppKit
import OnePlusUI
import SwiftUI

@MainActor
enum MacPowerToysAbout {
    static let info: OnePlusAboutInfo = {
        let repository = HostAppMetadata.repository
        return OnePlusAboutInfo(
            tagline: "Nine small Mac utilities in one native app.",
            website: OnePlusAboutLink("Website", title: "GitHub", url: repository),
            releaseNotes: OnePlusAboutLink("Release notes", title: "Changelog", url: HostAppMetadata.releases),
            support: HostAppMetadata.contact,
            license: OnePlusAboutLink("License and privacy", title: "MIT license",
                                      url: repository.appendingPathComponent("blob/main/LICENSE")),
            credits: [OnePlusAboutLink("RSync UI engine", title: "Powered by rclone", url: URL(string: "https://rclone.org/")!)])
    }()

    static func update(_ checker: HostUpdateChecker) -> OnePlusAboutUpdate {
        let state: OnePlusAboutUpdate.State = switch checker.state {
        case .idle: .idle
        case .checking: .checking
        case .current: .current
        case .available(let version, _): .available(version)
        case .failed: .failed
        }
        return OnePlusAboutUpdate(state, check: checker.check)
    }

    static func show() {
        OnePlusAboutWindow.show(size: OnePlusAboutColorField.size) { MacPowerToysAboutWindow() }
    }
}

private struct MacPowerToysAboutWindow: View {
    @State private var updates = HostUpdateChecker.shared
    var body: some View {
        OnePlusAboutColorField(info: MacPowerToysAbout.info, update: MacPowerToysAbout.update(updates))
    }
}
