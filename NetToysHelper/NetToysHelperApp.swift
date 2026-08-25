import CoreLocation
import Foundation

@main
struct NetToysHelperApp {
    static func main() async {
        let runtime = NetToysHelperRuntime()
        let locationAccess = await MainActor.run {
            NetToysHelperLocationAccess { state in
                Task { await runtime.setSSIDAccess(state) }
            }
        }
        await MainActor.run { locationAccess.requestIfNeeded() }
        await runtime.run()
    }
}

@MainActor
private final class NetToysHelperLocationAccess: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let onChange: @Sendable (NetToysSSIDAccessState) -> Void

    init(onChange: @escaping @Sendable (NetToysSSIDAccessState) -> Void) {
        self.onChange = onChange
        super.init()
        manager.delegate = self
        publish()
    }

    func requestIfNeeded() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        publish()
        if manager.authorizationStatus != .notDetermined { manager.stopUpdatingLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        publish()
        manager.stopUpdatingLocation()
    }

    private func publish() {
        let state: NetToysSSIDAccessState = switch manager.authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .authorized, .authorizedAlways: .allowed
        @unknown default: .restricted
        }
        onChange(state)
    }
}
