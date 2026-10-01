import Foundation
import NetToysCore

nonisolated enum MacPowerToysHelperContract {
    static let neighbor = NetToysNeighborServiceContract(host: .macPowerToys)
}

@objc nonisolated protocol MacPowerToysHelperXPCProtocol: NetToysNeighborXPCProtocol {
    func applyFanPreset(_ preset: String, reply: @escaping (String) -> Void)
}
