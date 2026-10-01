import NetToysKit
import SwiftUI

struct NetToysTrayView: View {
    @Binding var snapshot: NetToysTraySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrayToolHeader(tab: .netToys)
            NetToysMenuContent(snapshot: $snapshot, host: MacPowerToysNetToys.host) { page in
                ToolActionRouter.shared.open(toolID: "nettoys", page: page.pageID)
            }
        }
    }
}
