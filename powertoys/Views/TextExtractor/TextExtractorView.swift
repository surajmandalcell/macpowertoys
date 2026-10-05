import SwiftUI
import OnePlusUI

enum TextExtractorLayout {
    static let windowWidth = OnePlusWindowCanvas.textExtractor.size.width
    static let historyBaseHeight = OnePlusWindowCanvas.textExtractor.size.height - OnePlusMetrics.appletTitlebar
    static let maximumWindowHeight = OnePlusWindowCanvas.textExtractor.heightRange!.upperBound
    static let settingsHeight = maximumWindowHeight - OnePlusMetrics.appletTitlebar
    static let historyRowHeight = OnePlusMetrics.settingRow

    static func historyHeight(count: Int) -> CGFloat {
        min(maximumWindowHeight, historyBaseHeight + OnePlusMetrics.appletTitlebar
            + CGFloat(max(0, min(count, 5) - 1)) * historyRowHeight)
    }
}

nonisolated struct TextExtractionPresentation: Identifiable, Sendable {
    let extraction: TextExtraction
    let timestamp: String
    let openableURL: URL?
    var id: UUID { extraction.id }
}

nonisolated func textExtractionPresentations(
    _ history: [TextExtraction], now: Date = Date()
) -> [TextExtractionPresentation] {
    history.map {
        TextExtractionPresentation(
            extraction: $0,
            timestamp: $0.relativeTimestamp(at: now),
            openableURL: $0.openableURL
        )
    }
}

struct TextExtractorView: View {
    @Environment(\.undoManager) private var undoManager
    @State private var service = TextExtractorService.shared
    @State private var shortcuts = GlobalShortcutManager.shared
    @State private var page = TextExtractorPage.history
    @State private var selectedExtraction: TextExtraction?
    @State private var historyRows: [TextExtractionPresentation] = []

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
        .transaction { $0.disablesAnimations = true }
        .onOpenToolPage("text-extractor") { id in
            if let destination = TextExtractorPage(rawValue: id) { page = destination }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandOpenSettings)) { _ in
            guard NSApp.keyWindow?.identifier?.rawValue.hasPrefix("text-extractor") == true else { return }
            page = .settings
        }
        .task(id: service.history.map(\.id)) {
            let history = service.history
            let task = Task.detached(priority: .userInitiated) {
                textExtractionPresentations(history)
            }
            let rows = await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
            guard !Task.isCancelled, service.history.map(\.id) == history.map(\.id) else { return }
            historyRows = rows
        }
    }

    private var titlebar: some View {
        OnePlusAppletTitlebar(title: "Text Extractor") {
            Button("Extract Text") { service.begin() }
                .buttonStyle(OnePlusButtonStyle(.primary, size: .small))
                .disabled(isExtracting)
                .help("Select text anywhere on screen (\(shortcuts.shortcut(for: .textExtractor).display))")
                .accessibilityIdentifier("text-extractor.extract")
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            statusBanner
            if service.history.isEmpty {
                OnePlusEmptyState("Select text anywhere", systemImage: "viewfinder")
                    .help("Drag a region. Recognized text is copied automatically.")
            } else {
                OnePlusSectionTitle("History")
                OnePlusCard {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(historyRows) { row in
                                TextExtractionRow(
                                    row: row,
                                    onOpen: { selectedExtraction = row.extraction },
                                    onCopy: { service.copy(row.extraction) },
                                    onDelete: { service.remove(row.id, undoManager: undoManager) }
                                )
                                .overlay(alignment: .bottom) {
                                    if row.id != historyRows.last?.id {
                                        OnePlusColor.lineSoft.frame(height: 1)
                                    }
                                }
                            }
                        }
                    }
                    .onePlusScrollIndicators()
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, OnePlusMetrics.appletGutter)
        .padding(.top, OnePlusMetrics.contentGap)
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
    @Environment(\.undoManager) private var undoManager
    @State private var service = TextExtractorService.shared
    @State private var shortcuts = GlobalShortcutManager.shared
    @State private var languages = ""
    @State private var confirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            shortcutSettings
            VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
                recognitionSettings
                Button("Clear history", role: .destructive) { confirmingClear = true }
                    .buttonStyle(OnePlusButtonStyle(.destructive))
                    .disabled(service.history.isEmpty).help("Removes saved extracted text.")
                    .accessibilityIdentifier("text-extractor.clear-history")
            }
        }
        .transaction { $0.disablesAnimations = true }
        .confirmationDialog("Clear text extraction history?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { service.clearHistory(undoManager: undoManager) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every saved text extraction.")
        }
        .task {
            let preferredLanguages = service.settings.preferredLanguages
            languages = await Task.detached(priority: .userInitiated) {
                preferredLanguages.joined(separator: ", ")
            }.value
        }
    }

    private var shortcutSettings: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            OnePlusSectionTitle("Global shortcut")
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                Text("Shortcut").onePlusText(.row).help("Works in every app.")
                Spacer(minLength: OnePlusMetrics.actionSpacing)
                Toggle("Enable Extract Text shortcut", isOn: Binding(
                    get: { shortcuts.isEnabled(.textExtractor) }, set: { shortcuts.setEnabled($0, for: .textExtractor) }
                )).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                ShortcutRecorderField(action: .textExtractor)
                    .disabled(!shortcuts.isEnabled(.textExtractor))
            }
            .frame(height: OnePlusMetrics.settingRow)
            ShortcutPermissionNotice(action: .textExtractor)
        }
    }

    private var recognitionSettings: some View {
        OnePlusCard {
            OnePlusCardHeader("Recognition", systemImage: "text.viewfinder")
            OnePlusSettingRow("Recognition quality") {
                OnePlusSegmented(choices: TextRecognitionSpeed.allCases.map { ($0, $0.title) },
                                 selection: $service.settings.speed, accessibilityLabel: "Recognition quality",
                                 width: OnePlusMetrics.controlColumn)
            }
            OnePlusSettingRow("Language correction") {
                Toggle("Use language correction", isOn: $service.settings.languageCorrection)
                    .labelsHidden().toggleStyle(OnePlusSwitchStyle())
            }
            OnePlusSettingRow("QR codes and barcodes") {
                Toggle("Detect QR codes and barcodes", isOn: $service.settings.detectCodes)
                    .labelsHidden().toggleStyle(OnePlusSwitchStyle())
            }
            OnePlusSettingRow("Preferred languages", help: "Empty means automatic.", separator: false) {
                OnePlusTextField("en-US, fr-FR", text: $languages, onSubmit: applyLanguages)
                    .accessibilityLabel("Preferred languages")
                    .onChange(of: languages) { applyLanguages() }
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
    let row: TextExtractionPresentation
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        let extraction = row.extraction
        HStack(spacing: OnePlusMetrics.actionSpacing) {
            Button(action: onOpen) {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    Text(extraction.text).onePlusText(.row).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(row.timestamp).onePlusText(.caption).fixedSize()
                }
                .frame(maxWidth: .infinity, minHeight: TextExtractorLayout.historyRowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open full text")
            Button(action: onCopy) { Image(systemName: "doc.on.doc") }
                .accessibilityLabel("Copy text")
            if let url = row.openableURL {
                Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.right.square") }
                    .accessibilityLabel("Open link")
            }
            Button { confirmingDelete = true } label: { Image(systemName: "trash") }
                .accessibilityLabel("Delete extraction")
        }
        .padding(.horizontal, OnePlusMetrics.actionSpacing)
        .onePlusRowHover()
        .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
        .contextMenu {
            Button("Open full text", action: onOpen)
            Button("Copy text", action: onCopy)
            if let url = row.openableURL { Button("Open link") { NSWorkspace.shared.open(url) } }
            Button("Delete", role: .destructive) { confirmingDelete = true }
        }
        .confirmationDialog("Delete this extraction?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive, action: onDelete)
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
