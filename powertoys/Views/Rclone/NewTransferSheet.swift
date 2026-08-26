//
//  NewTransferSheet.swift
//  powertoys
//

import SwiftUI
import AppKit

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
        VStack(spacing: 0) {
            header
            QuietDivider()

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
                .padding(20)
            }
            .thinScrollIndicators()

            QuietDivider()
            footer
        }
        .frame(width: 560, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
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

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.tint)
            Text("New Transfer")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            UtilityModalCloseButton { dismiss() }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
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
                    HStack(spacing: 6) {
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

            TextEditor(text: $extraExcludesText)
                .thinScrollIndicators()
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 76)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(alignment: .topLeading) {
                    if extraExcludesText.isEmpty {
                        Text("One glob per line, e.g. *.log")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button {
                start()
            } label: {
                Text("Start Transfer")
                    .fontWeight(.semibold)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canStart)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.03))
        )
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
                Menu {
                    ForEach(remotes) { remote in
                        Button {
                            config.remoteName = remote.name
                        } label: {
                            Label("\(remote.name)  ·  \(remote.typeLabel)", systemImage: remote.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selectedRemote?.icon ?? "cloud")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(config.remoteName.isEmpty ? "Choose remote" : config.remoteName)
                            .font(.system(size: 13))
                            .foregroundStyle(config.remoteName.isEmpty ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.06))
                    )
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .focusEffectDisabled()
                .menuIndicator(.hidden)

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

    private var selectedRemote: RcloneRemote? {
        remotes.first { $0.name == config.remoteName }
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
