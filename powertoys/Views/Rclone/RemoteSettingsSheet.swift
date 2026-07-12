//
//  RemoteSettingsSheet.swift
//  powertoys
//

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
        VStack(spacing: 0) {
            header
            Divider()

            Form {
                Section {
                    Stepper(value: $transfers, in: 0...64) {
                        LabeledContent("Parallel transfers", value: transfers == 0 ? "Global (\(globalTransfers))" : "\(transfers)")
                    }
                    Stepper(value: $checkers, in: 0...128) {
                        LabeledContent("Checkers", value: checkers == 0 ? "Global (\(globalCheckers))" : "\(checkers)")
                    }
                } header: {
                    Text("Overrides")
                } footer: {
                    Text("Set to Global to inherit the app-wide value. Overrides apply to new transfers using this remote. Bandwidth limit stays global — it throttles the whole engine.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 440, height: 260)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            transfers = UserDefaults.standard.integer(forKey: RcloneDefaults.remoteTransfersKey(remote.name))
            checkers = UserDefaults.standard.integer(forKey: RcloneDefaults.remoteCheckersKey(remote.name))
        }
        .onChange(of: transfers) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: RcloneDefaults.remoteTransfersKey(remote.name))
        }
        .onChange(of: checkers) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: RcloneDefaults.remoteCheckersKey(remote.name))
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: remote.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tint)

            Text("\(remote.name) Settings")
                .font(.system(size: 15, weight: .semibold))

            Spacer()

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
