import OnePlusUI

extension OnePlusWindowCanvas {
    // ponytail: input-devices keeps the Mac Tweaks canvas here until OnePlusUI after 1.0.2 sets its own to 820 x 660; then delete this file and call tool(_:) again
    static func appTool(_ id: String) -> Self? {
        id == "input-devices" ? .macTweaks : tool(id)
    }
}
