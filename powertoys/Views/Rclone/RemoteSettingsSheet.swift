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
            QuietDivider()

            Form {
                Section {
                    overrideRow(label: "Parallel transfers", value: $transfers, range: 0...64, globalValue: globalTransfers)
                    overrideRow(label: "Checkers", value: $checkers, range: 0...128, globalValue: globalCheckers)
                } header: {
                    Text("Overrides")
                } footer: {
                    Text("0 uses the app-wide value. Overrides apply when a transfer starts. Pause a running transfer. Resume it to apply changes. The bandwidth limit applies to the full engine.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .thinScrollIndicators()
        }
        .frame(width: 440, height: 300)
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

    private func overrideRow(label: String, value: Binding<Int>, range: ClosedRange<Int>, globalValue: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            StepperField(label: label, value: value, range: range, format: .number)
            Text(value.wrappedValue == 0 ? "Using Global (\(globalValue))" : "0 = Global (\(globalValue))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
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
