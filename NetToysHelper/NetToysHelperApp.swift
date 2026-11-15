import Darwin
import Foundation

@main
struct MacPowerToysHelperApp {
    static func main() {
        if geteuid() == 0 { FanHelperDaemon.run() }
        // A login item from an older build has no work; stay idle so launchd does not relaunch it
        // until the app unregisters it.
        dispatchMain()
    }
}
