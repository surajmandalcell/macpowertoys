import SwiftUI

struct AddRemoteSheet: View {
    @Environment(RcloneJobManager.self) private var manager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedProviderID = ""
    @State private var searchText = ""
    @State private var parameters: [String: String] = [:]
    @State private var showAdvanced = false
    @State private var promptAnswer = ""

    private var selectedProvider: RcloneProvider? {
        manager.providers.first { $0.id == selectedProviderID }
    }

    private var filteredProviders: [RcloneProvider] {
        guard !searchText.isEmpty else { return manager.providers }
        return manager.providers.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var visibleOptions: [RcloneProviderOption] {
        selectedProvider?.options.filter { !$0.hidden && (showAdvanced || !$0.advanced) } ?? []
    }

    private var canConnect: Bool {
        guard let provider = selectedProvider,
              RcloneJobManager.isValidRemoteName(name.trimmingCharacters(in: .whitespaces)) else { return false }
        return provider.options.filter { $0.required && !$0.hidden }.allSatisfy {
            !(parameters[$0.name] ?? $0.defaultValue).isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                switch manager.authState {
                case .idle:
                    connectorForm
                case .waiting(let remoteName):
                    waitingView(remoteName: remoteName)
                case .question(let remoteName, let prompt):
                    questionView(remoteName: remoteName, prompt: prompt)
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
        .frame(width: 520, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await manager.loadProviders()
            if selectedProviderID.isEmpty {
                selectedProviderID = manager.providers.first(where: { $0.name == "drive" })?.id
                    ?? manager.providers.first?.id
                    ?? ""
            }
        }
        .onChange(of: selectedProviderID) {
            parameters = [:]
            showAdvanced = false
            if name.isEmpty, let provider = selectedProvider {
                name = provider.name
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: selectedProvider.map { RcloneRemote(name: "", type: $0.name).icon } ?? "cloud")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)))

            VStack(alignment: .leading, spacing: 2) {
                Text("Add Cloud Connector")
                    .font(.system(size: 15, weight: .semibold))
                Text("Powered by rclone. OAuth providers open your browser and store credentials locally.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var connectorForm: some View {
        if manager.isLoadingProviders {
            centeredProgress("Loading rclone connectors…")
        } else if let error = manager.providerLoadError {
            VStack(spacing: 12) {
                Text(error).font(.system(size: 12)).foregroundStyle(.secondary)
                Button("Retry") { Task { await manager.loadProviders() } }
            }
            .padding(20)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    fieldTitle("CONNECTOR")
                    SearchField(text: $searchText, placeholder: "Search connectors…")
                    Picker("Connector", selection: $selectedProviderID) {
                        ForEach(filteredProviders) { provider in
                            Text(provider.displayName).tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    fieldTitle("REMOTE NAME")
                    TextField("my-cloud", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))

                    if !visibleOptions.isEmpty {
                        fieldTitle("CONNECTION OPTIONS")
                        ForEach(visibleOptions) { option in
                            optionField(option)
                        }
                    }

                    if selectedProvider?.options.contains(where: { $0.advanced && !$0.hidden }) == true {
                        Toggle("Show advanced options", isOn: $showAdvanced)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .font(.system(size: 12))
                    }
                }
                .padding(20)
            }
        }
    }

    @ViewBuilder
    private func optionField(_ option: RcloneProviderOption) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(option.label + (option.required ? " *" : ""))
                .font(.system(size: 12, weight: .medium))

            if option.type == "bool" {
                Toggle("Enabled", isOn: boolBinding(option))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            } else if !option.examples.isEmpty {
                Picker(option.label, selection: valueBinding(option)) {
                    if !option.exclusive {
                        Text(option.defaultValue.isEmpty ? "Default" : option.defaultValue).tag(option.defaultValue)
                    }
                    ForEach(option.examples, id: \.value) { example in
                        Text(example.help.split(separator: "\n").first.map(String.init) ?? example.value)
                            .tag(example.value)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            } else if option.isPassword {
                SecureField(option.defaultValue, text: valueBinding(option))
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(option.defaultValue, text: valueBinding(option))
                    .textFieldStyle(.roundedBorder)
            }

            if !option.help.isEmpty {
                Text(option.help.split(separator: "\n").first.map(String.init) ?? option.help)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func valueBinding(_ option: RcloneProviderOption) -> Binding<String> {
        Binding(
            get: { parameters[option.name] ?? option.defaultValue },
            set: { parameters[option.name] = $0 }
        )
    }

    private func boolBinding(_ option: RcloneProviderOption) -> Binding<Bool> {
        Binding(
            get: { (parameters[option.name] ?? option.defaultValue).lowercased() == "true" },
            set: { parameters[option.name] = $0 ? "true" : "false" }
        )
    }

    private func questionView(remoteName: String, prompt: RemoteConfigurationPrompt) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(prompt.option.label)
                .font(.system(size: 14, weight: .semibold))
            Text(prompt.option.help)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !prompt.option.examples.isEmpty {
                Picker(prompt.option.label, selection: $promptAnswer) {
                    ForEach(prompt.option.examples, id: \.value) { example in
                        Text(example.help.split(separator: "\n").first.map(String.init) ?? example.value)
                            .tag(example.value)
                    }
                }
                .labelsHidden()
            } else if prompt.option.isPassword {
                SecureField(prompt.option.defaultValue, text: $promptAnswer)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(prompt.option.defaultValue, text: $promptAnswer)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Continue") {
                    let answer = promptAnswer.isEmpty ? prompt.option.defaultValue : promptAnswer
                    manager.answerConfigurationPrompt(answer)
                    promptAnswer = ""
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(prompt.option.required && promptAnswer.isEmpty && prompt.option.defaultValue.isEmpty)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            promptAnswer = prompt.option.examples.first?.value ?? prompt.option.defaultValue
        }
    }

    private func waitingView(remoteName: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Waiting for connector setup…")
                .font(.system(size: 13))
            Text("If a browser opened, finish signing in as ‘\(remoteName)’. This window updates automatically.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Cancel") { manager.cancelAuth() }
                .padding(.top, 4)
        }
        .padding(20)
    }

    private func succeededView(remoteName: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 32)).foregroundStyle(.green)
            Text("\(remoteName) connected").font(.system(size: 13, weight: .semibold))
            Text("You can start transferring to it right away.").font(.system(size: 11)).foregroundStyle(.secondary)
            Button("Done") {
                manager.acknowledgeAuthResult()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 4)
        }
        .padding(20)
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundStyle(.orange)
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

    private var footer: some View {
        HStack {
            if case .idle = manager.authState, let provider = selectedProvider {
                Button("Connect") {
                    let supplied = parameters.filter { !$0.value.isEmpty }
                    manager.beginAddRemote(named: name, provider: provider, parameters: supplied)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canConnect)
            }
            Spacer()
            Button(closeButtonTitle) {
                if manager.isAuthInProgress { manager.cancelAuth() }
                else { manager.acknowledgeAuthResult() }
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var closeButtonTitle: String {
        switch manager.authState {
        case .idle, .waiting, .question: return "Cancel"
        case .succeeded, .failed: return "Close"
        }
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
    }

    private func centeredProgress(_ title: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
