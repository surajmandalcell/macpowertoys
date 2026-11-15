//
//  NewTransferSheet.swift
//  powertoys
//

import SwiftUI
import AppKit
import OnePlusUI

struct NewTransferSheet: View {
    @Environment(RcloneJobManager.self) private var manager
    @Environment(\.dismiss) private var dismiss

    @State private var operation: RcloneOperation = .copy
    @State private var source = EndpointConfig()
    @State private var destination = EndpointConfig()
    @State private var extraExcludesText = ""
    @State private var didInitialize = false

    private var parsedExtraExcludes: [String] {
        extraExcludesText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var canStart: Bool {
        source.isValid && destination.isValid && source.fs != destination.transferDestination(for: source)
            && !(source.isFile && operation == .sync)
    }

    var body: some View {
        OnePlusSheet("New Transfer", width: .medium, close: { dismiss() }) {
            ScrollView {
                VStack(alignment: .leading, spacing: OnePlusLinearMetrics.appletSectionGap) {
                    operationSection
                    EndpointCard(title: "Source", config: $source, remotes: manager.remotes, chooseDirectoriesOnly: false)

                    EndpointCard(title: "Destination", config: $destination, remotes: manager.remotes, chooseDirectoriesOnly: true)
                    excludesSection
                }
            }
            .onePlusScrollIndicators()
            .frame(height: OnePlusMetrics.spacing[8] * 17)
        } footer: {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(OnePlusLinearButtonStyle(.soft))
            Button("Start Transfer") { start() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(OnePlusLinearButtonStyle(.soft))
                .disabled(!canStart)
        }
        .onAppear {
            guard !didInitialize else { return }
            operation = manager.settings.defaultOperation
            applyDefaultDestination()
            didInitialize = true
        }
        .onChange(of: manager.remotes.count) {
            guard destination.kind == .local, destination.localPath.isEmpty else { return }
            applyDefaultDestination()
        }
    }

    // MARK: Operation

    private var operationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            OnePlusLinearAppletGroup {
                OnePlusLinearAppletRow(
                    "Operation",
                    detail: source.isFile && operation == .sync
                        ? "Sync needs a source folder. Choose Copy or Move for a file."
                        : "The exact size is calculated by comparing both sides before files move."
                ) {
                    OnePlusLinearSelect(choices: RcloneOperation.allCases.map { ($0, $0.displayName) },
                                        selection: $operation, accessibilityLabel: "Operation",
                                        width: OnePlusMetrics.wideControlColumn)
                }
            }

            if operation.isDestructive {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .onePlusText(.row)
                        .foregroundStyle(OnePlusColor.warn)
                    Text(operation == .sync
                         ? "Sync deletes files at the destination that no longer exist in the source."
                         : "Move removes files from the source after they are transferred.")
                        .onePlusText(.caption)
                        .foregroundStyle(OnePlusColor.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(OnePlusColor.warn.opacity(0.12))
                )
            }
        }
    }

    // MARK: Excludes

    private var excludesSection: some View {
        OnePlusLinearAppletSection("Ignore patterns") {
            OnePlusLinearAppletRow("Global patterns") {
                LinearCaption(
                    manager.settings.ignorePatterns.isEmpty ? "None configured" : manager.settings.ignorePatterns.joined(separator: ", "),
                    monospaced: !manager.settings.ignorePatterns.isEmpty
                )
            }
            OnePlusLinearAppletRow("Additional excludes for this transfer", detail: "One glob per line. Used as an exclude rule for this transfer.") {
                EmptyView()
            }
            OnePlusTextEditor("Additional ignore patterns", text: $extraExcludesText)
                .frame(height: 76)
                .padding(OnePlusLinearMetrics.appletRowPadding)
        }
    }

    private func applyDefaultDestination() {
        guard let firstRemote = manager.remotes.first else { return }
        destination.kind = .remote
        if destination.remoteName.isEmpty {
            destination.remoteName = firstRemote.name
        }
    }

    private func start() {
        guard canStart else { return }
        manager.createTransfer(
            operation: operation,
            kind: source.isFile ? .file : .directory,
            sourceFs: source.fs,
            destinationFs: destination.transferDestination(for: source),
            sourceDisplay: source.display,
            destinationDisplay: destination.display,
            extraExcludes: parsedExtraExcludes
        )
        dismiss()
    }
}

// MARK: - Endpoint Config

struct EndpointConfig {
    var kind: EndpointKind = .local
    var localPath: String = ""
    var localIsFile = false
    var remoteName: String = ""
    var remotePath: String = ""

    var isFile: Bool { kind == .local && localIsFile }

    func transferDestination(for source: EndpointConfig) -> String {
        guard source.isFile else { return fs }
        let name = (source.localPath as NSString).lastPathComponent
        if kind == .local { return URL(fileURLWithPath: localPath).appendingPathComponent(name).path }
        return fs + (remotePath.isEmpty || remotePath.hasSuffix("/") ? "" : "/") + name
    }

    var fs: String {
        switch kind {
        case .local: return localPath
        case .remote: return "\(remoteName):\(remotePath)"
        }
    }

    var display: String {
        switch kind {
        case .local:
            let name = (localPath as NSString).lastPathComponent
            return name.isEmpty ? localPath : "\(name) (local)"
        case .remote:
            return remotePath.isEmpty ? "\(remoteName):" : "\(remoteName):\(remotePath)"
        }
    }

    var isValid: Bool {
        switch kind {
        case .local: return !localPath.trimmingCharacters(in: .whitespaces).isEmpty
        case .remote: return !remoteName.isEmpty
        }
    }
}

// MARK: - Endpoint Card

private struct EndpointCard: View {
    let title: String
    @Binding var config: EndpointConfig
    let remotes: [RcloneRemote]
    let chooseDirectoriesOnly: Bool

    var body: some View {
        OnePlusLinearAppletSection(title) {
            OnePlusLinearAppletRow("Location") {
                // shortcut: a Select until the applet segmented control fits "Remote"; switch back when it sizes segments to labels.
                OnePlusLinearSelect(choices: [(EndpointKind.local, "Local"), (.remote, "Remote")],
                                    selection: $config.kind, accessibilityLabel: "\(title) location",
                                    width: OnePlusMetrics.wideControlColumn)
            }
            switch config.kind {
            case .local:
                OnePlusLinearAppletRow("Path") {
                    LinearCaption(config.localPath.isEmpty ? "No path selected" : config.localPath, monospaced: !config.localPath.isEmpty)
                    Button("Choose…") { chooseLocalPath() }
                        .buttonStyle(OnePlusLinearButtonStyle(.soft))
                }
            case .remote:
                if remotes.isEmpty {
                    OnePlusLinearAppletRow("Remote", value: "No remotes configured. Add one from the sidebar.")
                } else {
                    OnePlusLinearAppletRow("Remote") {
                        OnePlusLinearSelect(
                            choices: remotes.map { ($0.name, "\($0.name) · \($0.typeLabel)") },
                            selection: $config.remoteName,
                            accessibilityLabel: "Remote",
                            width: OnePlusMetrics.wideControlColumn
                        )
                    }
                    OnePlusLinearAppletRow("Path within remote") {
                        OnePlusTextField("Optional", text: $config.remotePath)
                            .frame(width: OnePlusMetrics.wideControlColumn)
                    }
                }
            }
            OnePlusLinearAppletRow("rclone path") {
                LinearCaption(config.fs.isEmpty ? "Not selected" : config.fs, monospaced: true)
            }
        }
    }

    private func chooseLocalPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = !chooseDirectoriesOnly
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            config.localPath = url.path
            config.localIsFile = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false
        }
    }
}
