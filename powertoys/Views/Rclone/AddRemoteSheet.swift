//
//  AddRemoteSheet.swift
//  powertoys
//

import SwiftUI

struct AddRemoteSheet: View {
    @Environment(RcloneJobManager.self) private var manager
    @Environment(\.dismiss) private var dismiss

    @State private var name = "gdrive"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                switch manager.authState {
                case .idle:
                    idleView
                case .waiting(let remoteName):
                    waitingView(remoteName: remoteName)
                case .succeeded(let remoteName):
                    succeededView(remoteName: remoteName)
                case .failed(let message):
                    failedView(message: message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: manager.authState)

            Divider()
            footer
        }
        .frame(width: 460, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.icloud")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.1))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Connect Google Drive")
                    .font(.system(size: 15, weight: .semibold))
                Text("Your browser will open to sign in — PowerToys never sees your password.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Idle

    private var idleView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REMOTE NAME")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("gdrive", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.06))
                )

            Text("Letters, numbers, dots, dashes, and underscores. Must start with a letter or number.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button {
                    manager.beginAddGoogleDrive(named: name)
                } label: {
                    Text("Connect")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!RcloneJobManager.isValidRemoteName(name))
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Waiting

    private func waitingView(remoteName: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Waiting for Google authorization…")
                .font(.system(size: 13))
            Text("Finish signing in as ‘\(remoteName)’ in your browser. This window will update automatically.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Cancel") { manager.cancelAuth() }
                .padding(.top, 4)
        }
        .padding(20)
    }

    // MARK: Succeeded

    private func succeededView(remoteName: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)
            Text("\(remoteName) connected")
                .font(.system(size: 13, weight: .semibold))
            Text("You can start transferring to it right away.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button {
                manager.acknowledgeAuthResult()
                dismiss()
            } label: {
                Text("Done")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 4)
        }
        .padding(20)
    }

    // MARK: Failed

    private func failedView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") { manager.acknowledgeAuthResult() }
                .padding(.top, 4)
        }
        .padding(20)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button(closeButtonTitle) {
                if manager.isAuthInProgress {
                    manager.cancelAuth()
                } else {
                    manager.acknowledgeAuthResult()
                }
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var closeButtonTitle: String {
        switch manager.authState {
        case .idle, .waiting: return "Cancel"
        case .succeeded, .failed: return "Close"
        }
    }
}
