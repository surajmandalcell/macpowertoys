import SwiftUI
import OnePlusUI

enum TextExtractorLayout {
    static let windowWidth = OnePlusWindowCanvas.textExtractor.size.width
    static let historyBaseHeight = OnePlusWindowCanvas.textExtractor.size.height - OnePlusMetrics.appletTitlebar
    static let maximumWindowHeight = OnePlusWindowCanvas.textExtractor.heightRange!.upperBound
    static let settingsHeight = maximumWindowHeight - OnePlusMetrics.appletTitlebar
    static let historyRowHeight = OnePlusMetrics.captionedSettingRow

    static func historyHeight(count: Int) -> CGFloat {
        min(maximumWindowHeight, historyBaseHeight + OnePlusMetrics.appletTitlebar
            + CGFloat(max(0, min(count, 5) - 1)) * historyRowHeight)
    }
}

struct TextExtractorView: View {
    @State private var service = TextExtractorService.shared
    @State private var shortcuts = GlobalShortcutManager.shared
    @State private var page = TextExtractorPage.history
    @State private var selectedExtraction: TextExtraction?
    @State private var confirmingClear = false

    var body: some View {
        OnePlusWindowRoot(canvas: .textExtractor, sidebar: { EmptyView() }) {
            VStack(spacing: 0) {
                titlebar
                Group {
                    switch page {
                    case .history: history
                    case .settings:
                        OnePlusPage(layout: .applet, header: { EmptyView() }) {
                            TextExtractorSettingsView()
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .onePlusFloatingSettingsInset()
                .overlay(alignment: .bottomTrailing) {
                    OnePlusFloatingSettingsButton(isActive: page == .settings, help: page == .settings ? "Back to History" : "Recognition Settings") {
                        page = page == .settings ? .history : .settings
                    }
                    .keyboardShortcut(",")
                    .accessibilityIdentifier("text-extractor.settings")
                    .padding(OnePlusMetrics.actionSpacing)
                }
            }
        }
        .frame(height: page == .settings ? TextExtractorLayout.maximumWindowHeight
               : TextExtractorLayout.historyHeight(count: service.history.count))
        .sheet(item: $selectedExtraction) { TextExtractionDetailView(extraction: $0) }
        .confirmationDialog("Clear text extraction history?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { service.clearHistory() }
        }
        .onOpenToolPage("text-extractor") { id in
            if let destination = TextExtractorPage(rawValue: id) { page = destination }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandOpenSettings)) { _ in
            guard NSApp.keyWindow?.identifier?.rawValue.hasPrefix("text-extractor") == true else { return }
            page = .settings
        }
    }

    private var titlebar: some View {
        OnePlusAppletTitlebar(title: "Text Extractor") {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                Menu {
                    Toggle("Enable Extract Text shortcut", isOn: Binding(
                        get: { shortcuts.isEnabled(.textExtractor) },
                        set: { shortcuts.setEnabled($0, for: .textExtractor) }
                    ))
                    Button("Change shortcut…") { page = .settings }
                } label: {
                    OnePlusControlLabel(variant: .ghost, size: .small) {
                        Text(shortcuts.shortcut(for: .textExtractor).display)
                    }
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .help("Extract Text shortcut").accessibilityLabel("Extract Text shortcut")
                Button("Extract Text") { service.begin() }
                    .buttonStyle(OnePlusButtonStyle(.primary))
                    .disabled(isExtracting).help("Select text anywhere on screen")
                    .accessibilityIdentifier("text-extractor.extract")
            }
        }
    }

    private var history: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                statusBanner
                if service.history.isEmpty {
                    OnePlusEmptyState("Select text anywhere", systemImage: "viewfinder",
                                      caption: "Drag a region. Recognized text is copied automatically.")
                } else {
                    OnePlusSectionTitle("History", actionTitle: "Clear") { confirmingClear = true }
                    LazyVStack(spacing: OnePlusMetrics.actionSpacing) {
                        ForEach(service.history) { extraction in
                            TextExtractionRow(extraction: extraction) { selectedExtraction = extraction }
                        }
                    }
                }
            }
            .padding(.horizontal, OnePlusMetrics.appletGutter)
            .padding(.top, OnePlusMetrics.contentTop)
        }.onePlusScrollIndicators()
    }

    @ViewBuilder private var statusBanner: some View {
        switch service.state {
        case .selecting:
            OnePlusBanner("Drag to select text. Press Escape to cancel.")
        case .recognizing:
            OnePlusBanner("Recognizing text on this Mac…") {
                ProgressView().controlSize(.small).accessibilityLabel("Recognizing text")
            }
        case .permissionDenied(let message):
            OnePlusBanner(message, tone: .warning) {
                Button("Privacy Settings", action: openPrivacySettings)
            }
        case .failed(let message): OnePlusBanner(message, tone: .error)
        default: EmptyView()
        }
    }

    private var isExtracting: Bool {
        switch service.state {
        case .selecting, .recognizing: true
        default: false
        }
    }

    private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct TextExtractorSettingsView: View {
    @State private var service = TextExtractorService.shared
    @State private var shortcuts = GlobalShortcutManager.shared
    @State private var languages = ""

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            shortcutSettings
            recognitionSettings
            OnePlusCard {
                OnePlusCardHeader("Languages", systemImage: "globe")
                OnePlusSettingRow("Preferred languages", caption: "Empty means automatic.", separator: false) {
                    OnePlusTextField("en-US, fr-FR", text: $languages, onSubmit: applyLanguages)
                        .accessibilityLabel("Preferred languages")
                        .onChange(of: languages) { applyLanguages() }
                }
            }
        }
        .onAppear { languages = service.settings.preferredLanguages.joined(separator: ", ") }
    }

    private var shortcutSettings: some View {
        OnePlusCard {
            OnePlusCardHeader("Global shortcut", systemImage: "keyboard")
            OnePlusSettingRow("Enable shortcut") {
                Toggle("Enable Extract Text shortcut", isOn: Binding(
                    get: { shortcuts.isEnabled(.textExtractor) }, set: { shortcuts.setEnabled($0, for: .textExtractor) }
                )).labelsHidden().toggleStyle(OnePlusSwitchStyle())
            }
            OnePlusSettingRow("Keyboard shortcut", caption: "Works in every app.", separator: false) {
                ShortcutRecorderField(action: .textExtractor).disabled(!shortcuts.isEnabled(.textExtractor))
            }
            ShortcutPermissionNotice(action: .textExtractor)
        }
    }

    private var recognitionSettings: some View {
        OnePlusCard {
            OnePlusCardHeader("Recognition", systemImage: "text.viewfinder")
            OnePlusSettingRow("Recognition quality") {
                OnePlusSegmented(choices: TextRecognitionSpeed.allCases.map { ($0, $0.title) },
                                 selection: $service.settings.speed, accessibilityLabel: "Recognition quality")
            }
            OnePlusSettingRow("Language correction") {
                Toggle("Use language correction", isOn: $service.settings.languageCorrection)
                    .labelsHidden().toggleStyle(OnePlusSwitchStyle())
            }
            OnePlusSettingRow("QR codes and barcodes", separator: false) {
                Toggle("Detect QR codes and barcodes", isOn: $service.settings.detectCodes)
                    .labelsHidden().toggleStyle(OnePlusSwitchStyle())
            }
        }
    }

    private func applyLanguages() {
        service.settings.preferredLanguages = languages.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

private enum TextExtractorPage: String { case history, settings }

private struct TextExtractionRow: View {
    let extraction: TextExtraction
    let onOpen: () -> Void
    @State private var service = TextExtractorService.shared
    @State private var confirmingDelete = false

    var body: some View {
        OnePlusCard {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[0]) {
                        HStack(alignment: .firstTextBaseline, spacing: OnePlusMetrics.actionSpacing) {
                            Text(extraction.text).onePlusText(.row).lineLimit(1).help(extraction.text)
                            Spacer(minLength: 0)
                            Text(extraction.relativeTimestamp()).onePlusText(.caption).fixedSize()
                        }
                        Text("Screen selection").onePlusText(.caption)
                    }.frame(maxWidth: .infinity, minHeight: TextExtractorLayout.historyRowHeight, alignment: .leading)
                        .contentShape(Rectangle())
                }.buttonStyle(OnePlusInteractionStyle()).help("Open full text")
                Button { service.copy(extraction) } label: { Image(systemName: "doc.on.doc") }
                    .help("Copy text").accessibilityLabel("Copy text")
                if let url = extraction.openableURL {
                    Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.right.square") }
                        .help("Open link").accessibilityLabel("Open link")
                }
                Button { confirmingDelete = true } label: { Image(systemName: "trash") }
                    .help("Delete").accessibilityLabel("Delete extraction")
            }
            .padding(.horizontal, OnePlusMetrics.actionSpacing)
            .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
        }
        .contextMenu {
            Button("Open full text", action: onOpen)
            Button("Copy text") { service.copy(extraction) }
            if let url = extraction.openableURL { Button("Open link") { NSWorkspace.shared.open(url) } }
            Button("Delete", role: .destructive) { confirmingDelete = true }
        }
        .confirmationDialog("Delete this extraction?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { service.remove(extraction.id) }
        }
    }
}

private struct TextExtractionDetailView: View {
    let extraction: TextExtraction
    @State private var service = TextExtractorService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        OnePlusSheet("Extracted Text", close: { dismiss() }) {
            ScrollView {
                Text(extraction.text).onePlusText(.row).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.onePlusScrollIndicators().frame(height: OnePlusWindowCanvas.textExtractor.size.height)
        } footer: {
            Button("Copy") { service.copy(extraction) }.buttonStyle(OnePlusButtonStyle(.primary))
        }
        .onExitCommand { dismiss() }
    }
}
