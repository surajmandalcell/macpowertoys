import CoreLocation
import Darwin
import Foundation

@main
struct NetToysHelperApp {
    static func main() async {
        if geteuid() == 0 {
            NetToysNeighborDaemon.run()
        }
        let runtime = NetToysHelperRuntime()
        let locationAccess = await MainActor.run {
            NetToysHelperLocationAccess { state in
                Task { await runtime.setSSIDAccess(state) }
            }
        }
        await MainActor.run { locationAccess.start() }
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

    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        guard manager.authorizationStatus != .denied,
              manager.authorizationStatus != .restricted
        else { return }
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        publish()
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            manager.stopUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        publish()
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
