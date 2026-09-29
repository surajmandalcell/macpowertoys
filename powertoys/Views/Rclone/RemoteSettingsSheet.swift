import OnePlusUI
import SwiftUI

struct RemoteSettingsSheet: View {
    let remote: RcloneRemote
    @Environment(\.dismiss) private var dismiss
    @State private var transfers = 0
    @State private var checkers = 0

    private var globalTransfers: Int {
        UserDefaults.standard.object(forKey: RcloneDefaults.transfersKey) != nil
            ? UserDefaults.standard.integer(forKey: RcloneDefaults.transfersKey)
            : RcloneDefaults.transfers
    }
    private var globalCheckers: Int {
        UserDefaults.standard.object(forKey: RcloneDefaults.checkersKey) != nil
            ? UserDefaults.standard.integer(forKey: RcloneDefaults.checkersKey)
            : RcloneDefaults.checkers
    }

    var body: some View {
        OnePlusSheet("\(remote.displayName) Settings", width: .small, close: { dismiss() }) {
            OnePlusCard {
                OnePlusSettingRow("Parallel transfers", caption: caption(transfers, global: globalTransfers)) {
                    OnePlusStepperField("Parallel transfers", value: $transfers, in: 0...64)
                }
                OnePlusSettingRow("Checkers", caption: caption(checkers, global: globalCheckers), separator: false) {
                    OnePlusStepperField("Checkers", value: $checkers, in: 0...128)
                }
            }
            Text("0 uses the app-wide value. Overrides apply when the next transfer starts.")
                .onePlusText(.caption)
                .padding(.top, OnePlusMetrics.spacing[2])
        } footer: {
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(OnePlusButtonStyle(.primary))
        }
        .onAppear {
            transfers = UserDefaults.standard.integer(forKey: RcloneDefaults.remoteTransfersKey(remote.name))
            checkers = UserDefaults.standard.integer(forKey: RcloneDefaults.remoteCheckersKey(remote.name))
        }
        .onChange(of: transfers) { _, value in
            UserDefaults.standard.set(value, forKey: RcloneDefaults.remoteTransfersKey(remote.name))
        }
        .onChange(of: checkers) { _, value in
            UserDefaults.standard.set(value, forKey: RcloneDefaults.remoteCheckersKey(remote.name))
        }
    }

    private func caption(_ value: Int, global: Int) -> String {
        value == 0 ? "Using global (\(global))" : "0 uses global (\(global))"
    }
}
