import SwiftUI
import OnePlusUI

struct AddRemoteSheet: View {
    @Environment(RcloneJobManager.self) private var manager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedProviderID = ""
    @State private var searchText = ""
    @State private var parameters: [String: String] = [:]
    @State private var showAdvanced = false
    @State private var selectedAuthenticationMode = RcloneAuthenticationMode.browser
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
        guard let provider = selectedProvider else { return [] }
        let options = provider.options.filter { !$0.hidden && !$0.isDeprecated }
        guard !provider.authenticationModes.isEmpty else {
            return options.filter { showAdvanced || !$0.advanced }
        }

        let modeOptions = selectedAuthenticationMode.optionNames(in: provider)
        let authOptions = provider.authenticationOptionNames
        return options.filter {
            $0.required || modeOptions.contains($0.name)
                || (showAdvanced && !authOptions.contains($0.name))
        }
    }

    private var authenticationModes: [RcloneAuthenticationMode] {
        selectedProvider?.authenticationModes ?? []
    }

    private var hasAdditionalOptions: Bool {
        guard let provider = selectedProvider else { return false }
        if provider.authenticationModes.isEmpty {
            return provider.options.contains { !$0.hidden && !$0.isDeprecated && $0.advanced }
        }
        return provider.options.contains {
            !$0.hidden && !$0.isDeprecated && !$0.required
                && !provider.authenticationOptionNames.contains($0.name)
        }
    }

    private var canConnect: Bool {
        guard let provider = selectedProvider,
              RcloneJobManager.isValidRemoteName(name.trimmingCharacters(in: .whitespaces)) else { return false }
        return selectedAuthenticationMode.isConfigured(parameters: parameters, provider: provider)
            && provider.options.filter { $0.required && !$0.hidden }.allSatisfy {
            !(parameters[$0.name] ?? $0.defaultValue).isEmpty
        }
    }

    var body: some View {
        OnePlusSheet("Add Remote", width: .medium, close: close) {
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
            .frame(maxWidth: .infinity, minHeight: OnePlusMetrics.spacing[8] * 18, maxHeight: .infinity)
        } footer: {
            if case .idle = manager.authState, let provider = selectedProvider {
                Button(connectButtonTitle) {
                    let supplied = parameters.filter { !$0.value.isEmpty }
                    manager.beginAddRemote(named: name, provider: provider, parameters: supplied)
                }
                .buttonStyle(OnePlusButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!canConnect)
            }
            Button(closeButtonTitle, action: close)
                .buttonStyle(OnePlusButtonStyle(.ghost))
                .keyboardShortcut(.cancelAction)
        }
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
            selectedAuthenticationMode = .browser
            if name.isEmpty, let provider = selectedProvider {
                name = provider.name
            }
        }
        .onChange(of: selectedAuthenticationMode) {
            applyAuthenticationMode()
        }
    }

    @ViewBuilder
    private var connectorForm: some View {
        if manager.isLoadingProviders {
            centeredProgress("Loading rclone connectors…")
        } else if let error = manager.providerLoadError {
            VStack(spacing: 12) {
                Text(error).onePlusText(.row).foregroundStyle(OnePlusColor.secondary)
                Button("Retry") { Task { await manager.loadProviders() } }
            }
            .padding(20)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    fieldTitle("CONNECTOR")
                    ProviderDropdown(
                        selection: $selectedProviderID,
                        searchText: $searchText,
                        providers: filteredProviders,
                        selectedName: selectedProvider?.displayName ?? "Select a connector"
                    )

                    if !authenticationModes.isEmpty {
                        authenticationSection
                    }

                    fieldTitle("REMOTE NAME")
                    OnePlusTextField("Remote name", text: $name)

                    if !visibleOptions.isEmpty {
                        fieldTitle("CONNECTION OPTIONS")
                        ForEach(visibleOptions) { option in
                            optionField(option)
                        }
                    }

                    if hasAdditionalOptions {
                        Toggle(authenticationModes.isEmpty ? "Show advanced options" : "Show provider options", isOn: $showAdvanced)
                            .toggleStyle(OnePlusSwitchStyle())
                            .controlSize(.small)
                            .onePlusText(.row)
                    }
                }
                .padding(20)
            }
            .thinScrollIndicators()
        }
    }

    private var authenticationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldTitle("SIGN IN")
            ScrollView(.horizontal) {
                OnePlusSegmented(choices: authenticationModes.map { ($0, $0.title) },
                                 selection: $selectedAuthenticationMode, accessibilityLabel: "Sign-in method")
            }
            .thinScrollIndicators()
            .help(selectedAuthenticationMode.detail)
        }
    }

    private func applyAuthenticationMode() {
        guard let provider = selectedProvider else { return }
        for name in provider.authenticationOptionNames {
            parameters.removeValue(forKey: name)
        }
        parameters.merge(selectedAuthenticationMode.parameterOverrides) { _, selected in selected }
    }

    @ViewBuilder
    private func optionField(_ option: RcloneProviderOption) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(option.label + (option.required ? " *" : ""))
                .onePlusText(.cardTitle)

            if option.type == "bool" {
                Toggle("Enabled", isOn: boolBinding(option))
                    .toggleStyle(OnePlusSwitchStyle())
                    .controlSize(.small)
                    .labelsHidden()
            } else if option.usesExclusivePicker {
                OnePlusSelect(
                    choices: exclusiveChoices(for: option),
                    selection: valueBinding(option),
                    width: OnePlusMetrics.wideControlColumn,
                    accessibilityLabel: option.label
                )
            } else if option.isPassword {
                SecureField(option.defaultValue, text: valueBinding(option))
                    .textFieldStyle(.roundedBorder)
            } else {
                OnePlusTextField(option.label, text: valueBinding(option))
            }

            if !option.help.isEmpty {
                Image(systemName: "info.circle")
                    .foregroundStyle(OnePlusColor.secondary)
                    .help(option.help)
                    .accessibilityLabel(option.help)
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
                .onePlusText(.sectionTitle)
            Text(prompt.option.help)
                .onePlusText(.caption)
                .foregroundStyle(OnePlusColor.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if prompt.option.type == "bool" {
                Toggle("Enabled", isOn: promptBoolBinding(prompt.option))
                    .toggleStyle(OnePlusSwitchStyle())
                    .controlSize(.small)
                    .labelsHidden()
            } else if prompt.option.usesExclusivePicker {
                OnePlusSelect(
                    choices: exclusiveChoices(for: prompt.option),
                    selection: $promptAnswer,
                    width: OnePlusMetrics.wideControlColumn,
                    accessibilityLabel: prompt.option.label
                )
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
            promptAnswer = prompt.option.defaultValue.isEmpty
                ? (prompt.option.examples.first?.value ?? "")
                : prompt.option.defaultValue
        }
    }

    private func exclusiveChoices(for option: RcloneProviderOption) -> [(String, String)] {
        let defaultChoice = option.defaultValue.isEmpty || option.examples.contains(where: { $0.value == option.defaultValue })
            ? []
            : [(option.defaultValue, option.defaultValue)]
        return defaultChoice + option.examples.map {
            ($0.value, $0.help.split(separator: "\n").first.map(String.init) ?? $0.value)
        }
    }

    private func promptBoolBinding(_ option: RcloneProviderOption) -> Binding<Bool> {
        Binding(
            get: { (promptAnswer.isEmpty ? option.defaultValue : promptAnswer).lowercased() == "true" },
            set: { promptAnswer = $0 ? "true" : "false" }
        )
    }

    private func waitingView(remoteName: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Waiting for connector setup…")
                .onePlusText(.row)
            Text("If a browser opened, finish signing in as ‘\(remoteName)’. This window updates automatically.")
                .onePlusText(.caption)
                .foregroundStyle(OnePlusColor.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Cancel") { manager.cancelAuth() }
                .padding(.top, 4)
        }
        .padding(20)
    }

    private func succeededView(remoteName: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").onePlusText(.pageTitle).foregroundStyle(OnePlusColor.ok)
            Text("\(remoteName) connected").onePlusText(.cardTitle)
            Text("You can start transferring to it right away.").onePlusText(.caption).foregroundStyle(OnePlusColor.secondary)
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
            Image(systemName: "exclamationmark.triangle").onePlusText(.pageTitle).foregroundStyle(OnePlusColor.warn)
            Text(message)
                .onePlusText(.row)
                .foregroundStyle(OnePlusColor.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") { manager.acknowledgeAuthResult() }
                .padding(.top, 4)
        }
        .padding(20)
    }

    private var closeButtonTitle: String {
        switch manager.authState {
        case .idle, .waiting, .question: return "Cancel"
        case .succeeded, .failed: return "Close"
        }
    }

    private func close() {
        if manager.isAuthInProgress { manager.cancelAuth() }
        else { manager.acknowledgeAuthResult() }
        dismiss()
    }

    private var connectButtonTitle: String {
        selectedAuthenticationMode == .browser && !authenticationModes.isEmpty
            ? "Sign In with Browser"
            : "Connect"
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title).onePlusText(.caption).foregroundStyle(OnePlusColor.secondary)
    }

    private func centeredProgress(_ title: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(title).onePlusText(.row).foregroundStyle(OnePlusColor.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension RcloneProviderOption {
    var isDeprecated: Bool {
        help.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveContains("deprecated:")
    }
}

private struct ProviderDropdown: View {
    private static let controlHeight: CGFloat = 28
    private static let rowHeight: CGFloat = 28
    private static let maximumListHeight: CGFloat = 320

    @Binding var selection: String
    @Binding var searchText: String
    let providers: [RcloneProvider]
    let selectedName: String

    @State private var isPresented = false

    var body: some View {
        GeometryReader { geometry in
            trigger(width: geometry.size.width)
                .popover(isPresented: $isPresented, arrowEdge: .top) {
                    providerList(width: geometry.size.width)
                }
        }
        .frame(height: Self.controlHeight)
    }

    private func trigger(width: CGFloat) -> some View {
        Button { isPresented.toggle() } label: {
            OnePlusMenuLabel(title: selectedName, width: width, expanded: isPresented)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled(!OnePlusFocusPolicy.shared.showsFocus)
        .help(selectedName)
        .accessibilityLabel("Connector")
        .accessibilityValue(selectedName)
    }

    private func providerList(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            NativeSearchField(text: $searchText, placeholder: "Search connectors…")
                .frame(height: UtilityLayout.workspaceActionHeight)
                .padding(8)
            QuietDivider()
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: CGFloat(providers.count) * Self.rowHeight > Self.maximumListHeight) {
                    LazyVStack(spacing: 0) {
                        if providers.isEmpty {
                            Text("No connectors found")
                                .onePlusText(.row)
                                .foregroundStyle(OnePlusColor.secondary)
                                .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
                        } else {
                            ForEach(providers) { provider in
                                providerRow(provider)
                                    .id(provider.id)
                            }
                        }
                    }
                }
                .thinScrollIndicators()
                .onAppear {
                    proxy.scrollTo(selection, anchor: .center)
                }
            }
            .frame(height: listHeight)
        }
        .frame(width: width)
        .background(OnePlusColor.panel)
    }

    private func providerRow(_ provider: RcloneProvider) -> some View {
        Button {
            selection = provider.id
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .onePlusText(.caption)
                    .opacity(selection == provider.id ? 1 : 0)
                    .frame(width: 12)
                Text(provider.displayName)
                    .onePlusText(.row)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(height: Self.rowHeight)
            .onePlusRowHover(selected: selection == provider.id)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled(!OnePlusFocusPolicy.shared.showsFocus)
        .accessibilityLabel(provider.displayName)
    }

    private var listHeight: CGFloat {
        min(max(CGFloat(providers.count), 1) * Self.rowHeight, Self.maximumListHeight)
    }
}
