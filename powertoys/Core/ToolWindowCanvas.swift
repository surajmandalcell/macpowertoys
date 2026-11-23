import Foundation
import OnePlusUI

extension OnePlusWindowCanvas {
    // ponytail: input-devices keeps the Mac Tweaks size here until OnePlusUI after 1.0.2 sets its own to 820 x 660; then call tool(_:) again
    static var inputDevicesWindow: Self {
        let size = DemoMode.inputDevicesSize ?? macTweaks.size
        return Self(width: size.width, height: size.height).linear
    }

    /// Sidebar windows use their `linear` form, so the lights share the 44 pt toolbar centerline with the sidebar title.
    static func appTool(_ id: String) -> Self? {
        switch id {
        case "input-devices": .inputDevicesWindow
        case "main": .mainWindow
        case "rclone", "logs", "mac-tweaks": tool(id)?.linear
        default: tool(id)
        }
    }
}
