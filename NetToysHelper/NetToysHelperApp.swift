import Darwin
import Foundation

@main
struct MacPowerToysHelperApp {
    static func main() {
        guard geteuid() == 0 else {
            fputs("This helper runs only as the MacPowerToys launch daemon.\n", stderr)
            exit(1)
        }
        FanHelperDaemon.run()
    }
}
