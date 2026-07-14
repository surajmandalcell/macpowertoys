import SwiftUI

enum TextExtractorLayout {
    static let windowWidth: CGFloat = 480
    static let historyBaseHeight: CGFloat = 230
    static let maximumWindowHeight: CGFloat = 422
    static let settingsHeight: CGFloat = 280
    static let maximumVisibleItems = 4
    static let historyRowHeight: CGFloat = 64
}

struct TextExtractorView: View {
    @State private var service = TextExtractorService.shared
    @State private var languages = ""
    @State private var page = TextExtractorPage.history
    @State private var selectedExtraction: TextExtraction?

    private var windowHeight: CGFloat {
        switch page {
        case .history:
            min(
                TextExtractorLayout.maximumWindowHeight,
                TextExtractorLayout.historyBaseHeight
                    + CGFloat(max(0, min(service.history.count, TextExtractorLayout.maximumVisibleItems) - 1))
                    * TextExtractorLayout.historyRowHeight
            )
        case .settings:
            TextExtractorLayout.settingsHeight
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            titlebar
            ZStack(alignment: .bottomLeading) {
                switch page {
                case .history: history
                case .settings: settings
                }

                FloatingSettingsButton(
                    isActive: page == .settings,
                    helpText: page == .settings ? "Back to History" : "Recognition Settings"
                ) {
                    page = page == .settings ? .history : .settings
                }
                .accessibilityIdentifier("text-extractor.settings")
            }
        }
        .frame(
            width: TextExtractorLayout.windowWidth,
            height: windowHeight + UtilityLayout.compactTitlebarHeight
        )
        .ignoresSafeArea(.container, edges: .top)
        .utilityWindowBackground()
        .animation(.easeInOut(duration: 0.16), value: windowHeight)
        .sheet(item: $selectedExtraction) { extraction in
            TextExtractionDetailView(extraction: extraction)
        }
        .onAppear {
            languages = service.settings.preferredLanguages.joined(separator: ", ")
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandOpenSettings)) { _ in
            guard NSApp.keyWindow?.identifier?.rawValue.hasPrefix("text-extractor") == true else { return }
            page = .settings
        }
    }

    private var titlebar: some View {
        CompactTitlebar {
            CompactTitlebarTitle(title: "Text Extractor")
        } actions: {
            HStack(spacing: 8) {
                GlobalShortcutMenu(action: .textExtractor)
                CompactTitlebarButton(title: "Extract Text", isPrimary: true) { service.begin() }
                    .disabled(isExtracting)
                    .help("Select text anywhere on screen")
                    .accessibilityIdentifier("text-extractor.extract")
            }
        }
    }

    private var history: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("HISTORY").utilitySectionHeader()
                if !service.history.isEmpty {
                    Text("\(service.history.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if !service.history.isEmpty {
                    Button("Clear") { service.clearHistory() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                        .help("Clear text extraction history")
                }
            }
            .padding(.horizontal, UtilityLayout.horizontalInset)
            .frame(height: 40)

            statusBanner

            if service.history.isEmpty {
                capturePrompt
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(service.history) { extraction in
                            TextExtractionRow(extraction: extraction) {
                                selectedExtraction = extraction
                            }
                        }
                    }
                    .padding(.horizontal, UtilityLayout.horizontalInset)
                    .padding(.bottom, UtilityLayout.floatingButtonContentInset)
                }
                .thinScrollIndicators()
            }
        }
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
                Text("Drag a region. Recognized text is copied automatically.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, UtilityLayout.horizontalInset)
        .frame(maxHeight: .infinity, alignment: .center)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch service.state {
        case .recognizing:
            TextExtractorStatusBanner(
                icon: "text.magnifyingglass",
                message: "Recognizing text on this Mac…",
                tint: .accentColor
            )
        case .failed(let message):
            TextExtractorStatusBanner(
                icon: "exclamationmark.triangle",
                message: message,
                tint: .red,
                actionTitle: "Privacy Settings",
                action: openPrivacySettings
            )
        default:
            EmptyView()
        }
    }

    private var settings: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                Text("RECOGNITION OPTIONS").utilitySectionHeader()
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recognition quality")
                                .font(.system(size: 12, weight: .medium))
                            Text("Accurate is best for smaller or styled text.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Recognition quality", selection: $service.settings.speed) {
                            ForEach(TextRecognitionSpeed.allCases) { speed in
                                Text(speed.title).tag(speed)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                    .padding(.bottom, 12)

                    Divider()

                    Toggle("Use language correction", isOn: $service.settings.languageCorrection)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .padding(.vertical, 12)

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preferred languages")
                            .font(.system(size: 12, weight: .medium))
                        HStack(spacing: 8) {
                            TextField("Automatic, en-US, fr-FR", text: $languages)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 8)
                                .frame(height: 28)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .onSubmit(applyLanguages)
                            Button("Apply", action: applyLanguages)
                                .controlSize(.small)
                        }
                        Text("Leave empty to detect languages automatically.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)
                }
                .font(.system(size: 12))
                .utilitySectionCard()
            }
            .padding(.horizontal, UtilityLayout.horizontalInset)
            .padding(.top, 14)
            .padding(.bottom, UtilityLayout.floatingButtonContentInset)
        }
        .thinScrollIndicators()
    }

    private var isExtracting: Bool {
        switch service.state {
        case .selecting, .recognizing: true
        default: false
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
}

private enum TextExtractorPage {
    case history, settings
}

private struct TextExtractorStatusBanner: View {
    let icon: String
    let message: String
    let tint: Color
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .contentShape(Rectangle())
            }
        }
        .padding(10)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, UtilityLayout.horizontalInset)
        .padding(.bottom, 8)
    }
}

private struct TextExtractionRow: View {
    let extraction: TextExtraction
    let onOpen: () -> Void
    @State private var service = TextExtractorService.shared
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            if extraction.needsExpandedView {
                Button(action: onOpen) { summary }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .help("Open full text")
            } else {
                summary
            }

            Button { service.copy(extraction) } label: {
                Image(systemName: "doc.on.doc").frame(width: 24, height: 24)
            }
            .help("Copy text")

            if extraction.needsExpandedView {
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .frame(width: 24, height: 24)
                }
                .help("Open full text")
            }

            Button(role: .destructive) { service.remove(extraction.id) } label: {
                Image(systemName: "trash").frame(width: 24, height: 24)
            }
            .help("Delete")
        }
        .buttonStyle(.borderless)
        .padding(9)
        .background(Color.primary.opacity(isHovering ? 0.06 : 0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(extraction.text)
                .font(.system(size: 12))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(extraction.relativeTimestamp())
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct TextExtractionDetailView: View {
    let extraction: TextExtraction
    @State private var service = TextExtractorService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            CompactTitlebar(clearsTrafficLights: false) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Extracted Text")
                        .font(.system(size: 13, weight: .medium))
                    Text(extraction.relativeTimestamp())
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            } actions: {
                HStack(spacing: 6) {
                    CompactTitlebarButton(title: "Copy") { service.copy(extraction) }
                    CompactTitlebarButton(title: "Done", isPrimary: true) { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }

            ScrollView {
                Text(extraction.text)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .thinScrollIndicators()
            .background(Color.primary.opacity(0.03))
        }
        .frame(width: 520, height: 360)
        .utilityWindowBackground()
        .onExitCommand { dismiss() }
    }
}
