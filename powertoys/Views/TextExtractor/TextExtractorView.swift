import SwiftUI

struct TextExtractorView: View {
    @State private var service = TextExtractorService.shared
    @State private var languages = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "text.viewfinder")
                Text("Text Extractor").font(.system(size: 13, weight: .medium))
                Spacer()
                Button("Extract Text") { service.begin() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .contentShape(Rectangle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            Divider()
            VStack(alignment: .leading, spacing: 20) {
                stateCard
                settingsCard
                if !service.lastText.isEmpty { resultCard }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.16), value: service.lastText.isEmpty)
        .onAppear { languages = service.settings.preferredLanguages.joined(separator: ", ") }
    }

    private var stateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STATUS").utilitySectionHeader()
            HStack(spacing: 10) {
                Image(systemName: stateIcon)
                Text(stateText).font(.system(size: 12))
                Spacer()
                if case .failed = service.state {
                    Button("Open Privacy Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                    }
                    .contentShape(Rectangle())
                }
            }
            .utilitySectionCard()
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECOGNITION").utilitySectionHeader()
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Speed")
                    Picker("Speed", selection: $service.settings.speed) {
                        ForEach(TextRecognitionSpeed.allCases) { speed in Text(speed.title).tag(speed) }
                    }.labelsHidden().contentShape(Rectangle())
                }
                GridRow {
                    Text("Correction")
                    Toggle("Use language correction", isOn: $service.settings.languageCorrection)
                        .contentShape(Rectangle())
                }
                GridRow {
                    Text("Languages")
                    HStack {
                        TextField("Automatic, or en-US, fr-FR", text: $languages)
                            .contentShape(Rectangle())
                        Button("Apply") {
                            service.settings.preferredLanguages = languages
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
            .font(.system(size: 12))
            .utilitySectionCard()
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LAST RESULT").utilitySectionHeader()
            ScrollView {
                Text(service.lastText).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .utilitySectionCard()
        }
    }

    private var stateText: String {
        switch service.state {
        case .idle: "Ready. Recognition runs entirely on this Mac."
        case .selecting: "Drag around the text to extract. Press Escape to cancel."
        case .recognizing: "Recognizing text locally..."
        case .copied: "Text copied to the clipboard."
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
}
