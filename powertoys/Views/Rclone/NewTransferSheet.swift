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
        source.isValid && destination.isValid && source.fs != destination.fs
    }

    var body: some View {
        OnePlusSheet("New Transfer", width: .medium, close: { dismiss() }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    operationSection
                    EndpointCard(title: "Source", config: $source, remotes: manager.remotes, chooseDirectoriesOnly: false)

                    EndpointCard(title: "Destination", config: $destination, remotes: manager.remotes, chooseDirectoriesOnly: true)
                    Label("The exact transfer size is calculated by comparing both sides before data moves.", systemImage: "checkmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    excludesSection
                }
            }
            .onePlusScrollIndicators()
            .frame(height: OnePlusMetrics.spacing[8] * 17)
        } footer: {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(OnePlusButtonStyle(.ghost))
            Button("Start Transfer") { start() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(OnePlusButtonStyle(.primary))
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
            SectionLabel(title: "Operation")

            Picker("Operation", selection: $operation) {
                ForEach(RcloneOperation.allCases) { op in
                    Text(op.displayName).tag(op)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Text(operation.summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if operation.isDestructive {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    Text(operation == .sync
                         ? "Sync deletes files at the destination that no longer exist in the source."
                         : "Move removes files from the source after they are transferred.")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.12))
                )
            }
        }
    }

    // MARK: Excludes

    private var excludesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: "Ignore Patterns")

            if manager.settings.ignorePatterns.isEmpty {
                Text("No global ignore patterns configured.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 6) {
                        ForEach(manager.settings.ignorePatterns, id: \.self) { pattern in
                            Text(pattern)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(Capsule())
                        }
                    }
                }
                .thinScrollIndicators()
                Text("From settings · applied to every transfer")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Text("Additional excludes for this transfer")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            OnePlusTextEditor("Additional ignore patterns", text: $extraExcludesText)
                .frame(height: 76)
            Text("One glob per line. Used as an exclude rule for this transfer.")
                .onePlusText(.caption)
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
            sourceFs: source.fs,
            destinationFs: destination.fs,
            sourceDisplay: source.display,
            destinationDisplay: destination.display,
            extraExcludes: parsedExtraExcludes
        )
        dismiss()
    }
}

// MARK: - Endpoint Config

private struct EndpointConfig {
    var kind: EndpointKind = .local
    var localPath: String = ""
    var remoteName: String = ""
    var remotePath: String = ""

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
        OnePlusCard {
            VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(title: title)
                Spacer()
                Picker("Endpoint kind", selection: $config.kind) {
                    Text("Local").tag(EndpointKind.local)
                    Text("Remote").tag(EndpointKind.remote)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            switch config.kind {
            case .local: localSelector
            case .remote: remoteSelector
            }

            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text(config.fs.isEmpty ? "Not selected" : config.fs)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(config.isValid ? .secondary : .tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            }
            .padding(OnePlusMetrics.cardPadding)
        }
    }

    private var localSelector: some View {
        HStack(spacing: 10) {
            Text(config.localPath.isEmpty ? "No path selected" : config.localPath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(config.localPath.isEmpty ? .tertiary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Choose…") { chooseLocalPath() }
        }
    }

    private var remoteSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            if remotes.isEmpty {
                Text("No remotes configured. Add one with rclone config.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                OnePlusSelect(
                    choices: remotes.map { ($0.name, "\($0.name) · \($0.typeLabel)") },
                    selection: $config.remoteName,
                    width: OnePlusMetrics.wideControlColumn,
                    accessibilityLabel: "Remote"
                )

                TextField("Path within remote (optional)", text: $config.remotePath)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
        }
    }

    private func chooseLocalPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = !chooseDirectoriesOnly
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        if panel.runModal() == .OK, let path = panel.url?.path {
            config.localPath = path
        }
    }
}

// MARK: - Section Label

private struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
    }
}
