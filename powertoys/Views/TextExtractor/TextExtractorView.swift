import SwiftUI
import OnePlusUI

enum TextExtractorLayout {
    static let windowWidth = OnePlusWindowCanvas.textExtractor.size.width
    static let historyBaseHeight = OnePlusWindowCanvas.textExtractor.size.height - OnePlusMetrics.appletTitlebar
    static let maximumWindowHeight = OnePlusWindowCanvas.textExtractor.heightRange!.upperBound
    static let historyRowHeight = OnePlusLinearMetrics.appletRow
    /// Title area and the History caption above the rows; the bottom gutter below them.
    static let historyChrome = OnePlusLinearMetrics.appletTitlebar + OnePlusLinearMetrics.appletCaptionHeight
        + OnePlusLinearMetrics.appletCaptionBelow + OnePlusLinearMetrics.appletBottom

    static func clamped(_ height: CGFloat) -> CGFloat {
        let range = OnePlusWindowCanvas.textExtractor.heightRange!
        return min(range.upperBound, max(range.lowerBound, height))
    }

    static func historyHeight(count: Int) -> CGFloat {
        clamped(historyChrome + CGFloat(max(0, count)) * historyRowHeight)
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
    @State private var selectedExtraction: TextExtraction?
    @State private var historyRows: [TextExtractionPresentation] = []

    var body: some View {
        OnePlusLinearApplet("Text Extractor", canvas: .textExtractor) {
            OnePlusLinearAppletSettingsButton(isActive: false) {
                ToolActionRouter.shared.openMainPage(toolID: "text-extractor")
            }
            .accessibilityIdentifier("text-extractor.settings")
            Button { service.begin() } label: { Label("Extract Text", systemImage: "text.viewfinder") }
                .buttonStyle(OnePlusLinearButtonStyle(.soft))
                .disabled(isExtracting)
                .help("Select text anywhere on screen (\(shortcuts.shortcut(for: .textExtractor).display))")
                .accessibilityIdentifier("text-extractor.extract")
        } content: {
            history
        }
        .onePlusLinearMotion(.quiet)
        .onePlusNeutralControls()
        .frame(height: TextExtractorLayout.historyHeight(count: service.history.count))
        .sheet(item: $selectedExtraction) { TextExtractionDetailView(extraction: $0) }
        .onOpenToolPage("text-extractor") { _ in }
        .onReceive(NotificationCenter.default.publisher(for: .commandOpenSettings)) { _ in
            guard NSApp.keyWindow?.identifier?.rawValue.hasPrefix("text-extractor") == true else { return }
            ToolActionRouter.shared.openMainPage(toolID: "text-extractor")
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

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusBanner
            if service.history.isEmpty {
                OnePlusLinearEmptyState("Select text anywhere", systemImage: "viewfinder")
                    .help("Drag a region. Recognized text is copied automatically.")
                    .frame(maxHeight: .infinity)
            } else {
                OnePlusLinearAppletForm {
                    OnePlusLinearAppletSection("History") {
                        ForEach(historyRows) { row in
                            TextExtractionRow(
                                row: row,
                                onOpen: { selectedExtraction = row.extraction },
                                onCopy: { service.copy(row.extraction) },
                                onDelete: { service.remove(row.id, undoManager: undoManager) }
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var statusBanner: some View {
        switch service.state {
        case .selecting:
            OnePlusLinearBanner(.info, title: "Drag to select text. Press Escape to cancel.").modifier(AppletBannerInset())
        case .recognizing:
            OnePlusLinearBanner(.info, title: "Recognizing text on this Mac…") {
                ProgressView().controlSize(.small).accessibilityLabel("Recognizing text")
            }.modifier(AppletBannerInset())
        case .permissionDenied(let message):
            OnePlusLinearBanner(.warning, title: message) {
                Button("Privacy Settings", action: openPrivacySettings)
            }.modifier(AppletBannerInset())
        case .failed(let message): OnePlusBanner(message, tone: .error).modifier(AppletBannerInset())
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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: OnePlusLinearMetrics.appletSectionGap) {
                shortcutSettings
                recognitionSettings
            }
            Button("Clear History", role: .destructive) { confirmingClear = true }
                .buttonStyle(OnePlusLinearButtonStyle(.resetBlock))
                .disabled(service.history.isEmpty).help("Removes saved extracted text.")
                .accessibilityIdentifier("text-extractor.clear-history")
                .padding(.top, OnePlusLinearMetrics.appletFooterGap)
        }
        .transformEnvironment(\.onePlusLinearControlLook) { if $0 == nil { $0 = .quietRaised } }
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

    @ViewBuilder private var shortcutSettings: some View {
        OnePlusLinearAppletSection("Global shortcut") {
            OnePlusLinearAppletRow("Enable shortcut") {
                Toggle("Enable Extract Text shortcut", isOn: Binding(
                    get: { shortcuts.isEnabled(.textExtractor) }, set: { shortcuts.setEnabled($0, for: .textExtractor) }
                )).toggleStyle(OnePlusLinearSwitchStyle())
            }
            OnePlusLinearAppletRow("Keyboard shortcut", detail: "Works in every app.") {
                ShortcutRecorderField(action: .textExtractor)
                    .disabled(!shortcuts.isEnabled(.textExtractor))
            }
        }
        ShortcutPermissionNotice(action: .textExtractor)
            .padding(.horizontal, OnePlusLinearMetrics.appletRowPadding)
    }

    private var recognitionSettings: some View {
        OnePlusLinearAppletSection("Recognition") {
            OnePlusLinearAppletRow("Recognition quality") {
                OnePlusLinearSegmented(choices: TextRecognitionSpeed.allCases.map { ($0, $0.title) },
                                       selection: $service.settings.speed, accessibilityLabel: "Recognition quality",
                                       sizing: .fitted)
            }
            OnePlusLinearAppletRow("Language correction") {
                Toggle("Use language correction", isOn: $service.settings.languageCorrection)
                    .toggleStyle(OnePlusLinearSwitchStyle())
            }
            OnePlusLinearAppletRow("QR codes and barcodes") {
                Toggle("Detect QR codes and barcodes", isOn: $service.settings.detectCodes)
                    .toggleStyle(OnePlusLinearSwitchStyle())
            }
            OnePlusLinearAppletRow("Preferred languages", detail: "Empty means automatic.") {
                OnePlusLinearTextField("en-US, fr-FR", text: $languages, onSubmit: applyLanguages)
                    .frame(width: OnePlusMetrics.controlColumn)
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


/// A banner above an applet body sits on the 16 pt gutter, one section gap above the first group.
struct AppletBannerInset: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.horizontal, OnePlusLinearMetrics.appletGutter).padding(.bottom, OnePlusLinearMetrics.appletSectionGap)
    }
}

private struct TextExtractionRow: View {
    let row: TextExtractionPresentation
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        let extraction = row.extraction
        var actions = [OnePlusLinearAction("Copy text", systemImage: "doc.on.doc", id: "copy", action: onCopy)]
        if let url = row.openableURL {
            actions.append(OnePlusLinearAction("Open link", systemImage: "arrow.up.right.square", id: "link") {
                NSWorkspace.shared.open(url)
            })
        }
        actions.append(OnePlusLinearAction("Delete extraction", systemImage: "trash", id: "delete") { confirmingDelete = true })
        return OnePlusLinearAppletListRow(extraction.text, metadata: row.timestamp, actions: actions) {
            Image(systemName: "text.alignleft")
                .font(.system(size: OnePlusLinearMetrics.body))
                .foregroundStyle(OnePlusLinearColor.appletSecondary)
                .frame(width: OnePlusLinearMetrics.appletSwatch)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityAction(named: "Open full text", onOpen)
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
