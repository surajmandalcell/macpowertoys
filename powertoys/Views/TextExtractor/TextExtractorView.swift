import SwiftUI

struct TextExtractorView: View {
    @State private var service = TextExtractorService.shared
    @State private var languages = ""
    @State private var showOptions = false

    private var windowHeight: CGFloat {
        250 + (showOptions ? 130 : 0) + (service.lastText.isEmpty ? 0 : 140)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                capturePrompt
                statusRow
                if !service.lastText.isEmpty { result }
                options
            }
            .padding(16)
        }
        .frame(width: 480, height: windowHeight, alignment: .top)
        .background(VisualEffectBackground(material: .hudWindow))
        .animation(.easeInOut(duration: 0.16), value: showOptions)
        .animation(.easeInOut(duration: 0.16), value: service.lastText.isEmpty)
        .onAppear { languages = service.settings.preferredLanguages.joined(separator: ", ") }
        .onReceive(NotificationCenter.default.publisher(for: .commandOpenSettings)) { _ in
            guard NSApp.keyWindow?.identifier?.rawValue.hasPrefix("text-extractor") == true else { return }
            showOptions = true
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.viewfinder")
                .foregroundStyle(Color.accentColor)
            Text("Text Extractor")
                .font(.system(size: 13, weight: .medium))
            Spacer()
            GlobalShortcutMenu(action: .textExtractor)
            Button("Extract Text") { service.begin() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .contentShape(Rectangle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var capturePrompt: some View {
        HStack(spacing: 12) {
            Image(systemName: "viewfinder")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text("Select text anywhere")
                    .font(.system(size: 13, weight: .medium))
                Text("Drag a region. Text is recognized locally and copied automatically.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statusRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: stateIcon)
                .foregroundStyle(stateTint)
            Text(stateText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if case .failed = service.state {
                Button("Privacy Settings") { openPrivacySettings() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 2)
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LAST RESULT").utilitySectionHeader()
                Spacer()
                Button("Copy Again") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(service.lastText, forType: .string)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .contentShape(Rectangle())
            }
            ScrollView {
                Text(service.lastText)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 108)
            .padding(12)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                showOptions.toggle()
            } label: {
                HStack {
                    Text("Recognition options")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(showOptions ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()

            if showOptions {
                VStack(spacing: 10) {
                    HStack {
                        Text("Recognition")
                        Spacer()
                        Picker("Recognition", selection: $service.settings.speed) {
                            ForEach(TextRecognitionSpeed.allCases) { speed in
                                Text(speed.title).tag(speed)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                    Toggle("Use language correction", isOn: $service.settings.languageCorrection)
                    HStack {
                        TextField("Languages: automatic, en-US, fr-FR", text: $languages)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .onSubmit(applyLanguages)
                        Button("Apply", action: applyLanguages)
                            .controlSize(.small)
                    }
                }
                .font(.system(size: 12))
                .padding(14)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.opacity)
            }
        }
    }

    private func applyLanguages() {
        service.settings.preferredLanguages = languages
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private var stateText: String {
        switch service.state {
        case .idle: "Ready"
        case .selecting: "Drag around text. Press Escape to cancel."
        case .recognizing: "Recognizing on this Mac…"
        case .copied: "Copied to the clipboard"
        case .failed(let message): message
        }
    }

    private var stateIcon: String {
        switch service.state {
        case .idle: "checkmark.circle"
        case .selecting: "viewfinder"
        case .recognizing: "text.magnifyingglass"
        case .copied: "doc.on.clipboard.fill"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var stateTint: Color {
        if case .failed = service.state { return .red }
        if case .copied = service.state { return .green }
        return .secondary
    }
}
