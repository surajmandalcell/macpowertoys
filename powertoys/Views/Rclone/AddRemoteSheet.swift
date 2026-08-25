import AppKit
import SwiftUI

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
        VStack(spacing: 0) {
            header
            QuietDivider()

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

            QuietDivider()
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
            selectedAuthenticationMode = .browser
            if name.isEmpty, let provider = selectedProvider {
                name = provider.name
            }
        }
        .onChange(of: selectedAuthenticationMode) {
            applyAuthenticationMode()
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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
                    TextField("my-cloud", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))

                    if !visibleOptions.isEmpty {
                        fieldTitle("CONNECTION OPTIONS")
                        ForEach(visibleOptions) { option in
                            optionField(option)
                        }
                    }

                    if hasAdditionalOptions {
                        Toggle(authenticationModes.isEmpty ? "Show advanced options" : "Show provider options", isOn: $showAdvanced)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .font(.system(size: 12))
                    }
                }
                .padding(20)
                .animation(.easeInOut(duration: 0.16), value: selectedAuthenticationMode)
            }
            .thinScrollIndicators()
        }
    }

    private var authenticationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldTitle("SIGN IN")
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(authenticationModes) { mode in
                        AuthenticationModeTab(
                            title: mode.title,
                            isSelected: selectedAuthenticationMode == mode
                        ) {
                            selectedAuthenticationMode = mode
                        }
                    }
                }
            }
            .thinScrollIndicators()
            Text(selectedAuthenticationMode.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                .font(.system(size: 12, weight: .medium))

            if option.type == "bool" {
                Toggle("Enabled", isOn: boolBinding(option))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            } else if option.usesExclusivePicker {
                Picker(option.label, selection: valueBinding(option)) {
                    if !option.defaultValue.isEmpty,
                       !option.examples.contains(where: { $0.value == option.defaultValue }) {
                        Text(option.defaultValue).tag(option.defaultValue)
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

            if prompt.option.type == "bool" {
                Toggle("Enabled", isOn: promptBoolBinding(prompt.option))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            } else if prompt.option.usesExclusivePicker {
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
            promptAnswer = prompt.option.defaultValue.isEmpty
                ? (prompt.option.examples.first?.value ?? "")
                : prompt.option.defaultValue
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
                Button(connectButtonTitle) {
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

    private var connectButtonTitle: String {
        selectedAuthenticationMode == .browser && !authenticationModes.isEmpty
            ? "Sign In with Browser"
            : "Connect"
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

private extension RcloneProviderOption {
    var isDeprecated: Bool {
        help.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveContains("deprecated:")
    }
}

private struct AuthenticationModeTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(isSelected || isHovering ? 0.06 : 0))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .accessibilityValue(isSelected ? "Selected" : "")
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
    @State private var isHoveringButton = false
    @State private var hoveredProviderID: String?

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
            HStack(spacing: 8) {
                TickerText(text: selectedName)
                    .frame(maxWidth: .infinity)
                    .id(selectedName)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(width: width, height: Self.controlHeight)
            .background(Color.primary.opacity(isHoveringButton ? 0.1 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHoveringButton = $0 }
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
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
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
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func providerRow(_ provider: RcloneProvider) -> some View {
        Button {
            selection = provider.id
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .medium))
                    .opacity(selection == provider.id ? 1 : 0)
                    .frame(width: 12)
                TickerText(text: provider.displayName)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 10)
            .frame(height: Self.rowHeight)
            .background(rowBackground(provider.id))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hoveredProviderID = $0 ? provider.id : nil }
        .help(provider.displayName)
    }

    private var listHeight: CGFloat {
        min(max(CGFloat(providers.count), 1) * Self.rowHeight, Self.maximumListHeight)
    }

    private func rowBackground(_ providerID: String) -> Color {
        if hoveredProviderID == providerID { return Color.primary.opacity(0.06) }
        if selection == providerID { return Color.accentColor.opacity(0.1) }
        return .clear
    }
}

private struct TickerText: View {
    private static let gap: CGFloat = 24
    private static let pointsPerSecond: CGFloat = 24

    let text: String
    @State private var isScrolling = false

    var body: some View {
        GeometryReader { geometry in
            if textWidth > geometry.size.width {
                HStack(spacing: Self.gap) {
                    label
                    label.accessibilityHidden(true)
                }
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: isScrolling ? -(textWidth + Self.gap) : 0)
                .animation(
                    .linear(duration: Double((textWidth + Self.gap) / Self.pointsPerSecond))
                        .repeatForever(autoreverses: false),
                    value: isScrolling
                )
                .onAppear { isScrolling = true }
            } else {
                label
            }
        }
        .frame(height: 16)
        .clipped()
        .accessibilityLabel(text)
    }

    private var label: some View {
        Text(text)
            .font(.system(size: 12))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var textWidth: CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width)
    }
}
