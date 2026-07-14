import SwiftUI

struct ColorHistoryView: View {
    @State private var service = ColorPickerService.shared
    @State private var shortcuts = GlobalShortcutManager.shared
    @State private var page = ColorPickerPage.history
    @State private var search = ""
    @State private var isCreatingProject = false
    @State private var newProjectName = ""
    @FocusState private var isProjectNameFocused: Bool

    private var samples: [ColorSample] {
        let samples = service.samples(in: service.selectedProjectID)
        guard !search.isEmpty else { return samples }
        return samples.filter { sample in
            ColorCopyFormat.allCases.contains { sample.string($0).localizedCaseInsensitiveContains(search) }
        }
    }

    private var selectedProjectName: String {
        service.projects.first { $0.id == service.selectedProjectID }?.name ?? "Unfiled"
    }

    private var windowHeight: CGFloat {
        switch page {
        case .history: 210 + CGFloat(max(0, min(samples.count, 5) - 1) * 56)
        case .projects: min(420, 230 + CGFloat(min(service.projects.count, 4) * 48) + (isCreatingProject ? 40 : 0))
        case .settings: 280
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            switch page {
            case .history: history
            case .projects: projects
            case .settings: settings
            }
        }
        .frame(width: 420, height: windowHeight)
        .utilityWindowBackground()
        .toolbar { titlebarActions }
        .animation(.easeInOut(duration: 0.16), value: windowHeight)
        .alert("Couldn’t Export Project", isPresented: Binding(
            get: { service.exportError != nil },
            set: { if !$0 { service.exportError = nil } }
        )) {
            Button("OK") { service.exportError = nil }
        } message: {
            Text(service.exportError ?? "The project could not be written.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandOpenSettings)) { _ in
            guard NSApp.keyWindow?.identifier?.rawValue.hasPrefix("color-picker") == true else { return }
            page = .settings
        }
    }

    @ToolbarContentBuilder
    private var titlebarActions: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if page == .history && !samples.isEmpty {
                Button(role: .destructive) {
                    service.clearUnpinned(in: service.selectedProjectID)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Clear unpinned colors in \(selectedProjectName)")
                .accessibilityIdentifier("color-picker.clear")
            }
            Button("Pick Color") { service.pick() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Pick a color for \(selectedProjectName)")
                .accessibilityIdentifier("color-picker.pick")
            Button {
                page = page == .settings ? .history : .settings
            } label: {
                Image(systemName: page == .settings ? "gearshape.fill" : "gearshape")
            }
            .help(page == .settings ? "Close Settings" : "Settings")
            .accessibilityIdentifier("color-picker.settings")
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton("History", icon: "clock", page: .history)
            tabButton("Projects", icon: "folder", page: .projects)
            Spacer()
            Text(page == .settings ? "Settings" : selectedProjectName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, UtilityLayout.horizontalInset)
        .frame(height: 36)
    }

    private func tabButton(_ title: String, icon: String, page target: ColorPickerPage) -> some View {
        Button {
            page = target
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: page == target ? .medium : .regular))
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(page == target ? Color.primary.opacity(0.06) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    private var history: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ColorSearchField(text: $search)
                ColorFormatSelect(selection: $service.defaultFormat)
            }
            .padding(.horizontal, UtilityLayout.horizontalInset)
            .padding(.vertical, 12)

            if samples.isEmpty {
                EmptyStateView(
                    icon: search.isEmpty ? "eyedropper" : "magnifyingglass",
                    message: search.isEmpty ? "Pick a color for \(selectedProjectName)" : "No matching colors"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(samples) { sample in
                            ColorSampleRow(sample: sample)
                        }
                    }
                    .padding(.horizontal, UtilityLayout.horizontalInset)
                    .padding(.bottom, UtilityLayout.contentBottomInset)
                }
                .thinScrollIndicators()
            }
        }
    }

    private var projects: some View {
        VStack(spacing: 0) {
            HStack {
                Text("COLOR PROJECTS").utilitySectionHeader()
                Spacer()
                Button {
                    isCreatingProject.toggle()
                    if isCreatingProject {
                        Task { isProjectNameFocused = true }
                    }
                } label: {
                    Label("New Project", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .contentShape(Rectangle())
            }
            .padding(.horizontal, UtilityLayout.horizontalInset)
            .padding(.vertical, 12)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    if isCreatingProject { newProjectField }
                    projectRow(id: nil, name: "Unfiled", project: nil)
                    ForEach(service.projects) { project in
                        projectRow(id: project.id, name: project.name, project: project)
                    }
                }
                .padding(.horizontal, UtilityLayout.horizontalInset)
                .padding(.bottom, UtilityLayout.contentBottomInset)
            }
            .thinScrollIndicators()
        }
    }

    private var newProjectField: some View {
        HStack(spacing: 8) {
            TextField("Project name", text: $newProjectName)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isProjectNameFocused)
                .onSubmit(createProject)
            Button("Create", action: createProject)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canCreateProject)
            Button {
                isCreatingProject = false
                newProjectName = ""
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Cancel")
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var canCreateProject: Bool {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !service.projects.contains {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func createProject() {
        guard service.createProject(named: newProjectName) != nil else { return }
        newProjectName = ""
        isCreatingProject = false
        page = .history
    }

    private func projectRow(id: UUID?, name: String, project: ColorProject?) -> some View {
        let count = service.samples(in: id).count
        let isSelected = service.selectedProjectID == id
        return HStack(spacing: 0) {
            Button {
                service.selectProject(id)
                search = ""
                page = .history
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "folder.fill" : "folder")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text("\(count) \(count == 1 ? "color" : "colors")")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()

            if let project {
                Button { service.export(project) } label: {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .contentShape(Rectangle())
                .disabled(count == 0)
                .help("Export \(name) as CSS")
                .padding(.trailing, 7)
            }
        }
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var settings: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                Text("GLOBAL SHORTCUT").utilitySectionHeader()
                VStack(spacing: 0) {
                    Toggle("Enable Pick Color shortcut", isOn: Binding(
                        get: { shortcuts.isEnabled(.colorPicker) },
                        set: { shortcuts.setEnabled($0, for: .colorPicker) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .padding(.bottom, 12)

                    Divider()

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Keyboard shortcut")
                                .font(.system(size: 12, weight: .medium))
                            Text("Works anywhere while MacPowerToys is running")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        shortcutEditor
                    }
                    .padding(.top, 12)
                }
                .padding(14)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, UtilityLayout.horizontalInset)
            .padding(.top, UtilityLayout.contentTopInset)
            .padding(.bottom, UtilityLayout.contentBottomInset)
        }
        .thinScrollIndicators()
    }

    private var shortcutEditor: some View {
        HStack(spacing: 4) {
            ForEach(["⌃", "⌥", "⌘"], id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Picker("Shortcut key", selection: Binding(
                get: { shortcuts.key(for: .colorPicker) },
                set: { shortcuts.setKey($0, for: .colorPicker) }
            )) {
                ForEach(GlobalShortcutKey.allCases) { key in
                    Text(key.title).tag(key)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 54)
        }
        .disabled(!shortcuts.isEnabled(.colorPicker))
    }
}

private enum ColorPickerPage {
    case history, projects, settings
}

private struct ColorSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Search colors", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("color-picker.search")
    }
}

private struct ColorFormatSelect: View {
    @Binding var selection: ColorCopyFormat

    var body: some View {
        Menu {
            ForEach(ColorCopyFormat.allCases) { format in
                Button(format.title) { selection = format }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selection.title).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 9)
            .frame(width: 112, height: 28)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .help("Copy format")
        .accessibilityIdentifier("color-picker.format")
    }
}

private struct ColorSampleRow: View {
    let sample: ColorSample
    @State private var service = ColorPickerService.shared
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: sample.color))
                .frame(width: 32, height: 32)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1)))
            VStack(alignment: .leading, spacing: 3) {
                Text(sample.string(service.defaultFormat))
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(sample.createdAt, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Menu {
                ForEach(ColorCopyFormat.allCases) { format in
                    Button(format.title) { service.copy(sample, as: format) }
                }
            } label: {
                Image(systemName: "doc.on.doc").frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .contentShape(Rectangle())
            .help("Copy as")
            Button { service.togglePin(sample.id) } label: {
                Image(systemName: sample.isPinned ? "pin.fill" : "pin").frame(width: 24, height: 24)
            }
            .contentShape(Rectangle())
            .help(sample.isPinned ? "Unpin" : "Pin")
            Button(role: .destructive) { service.remove(sample.id) } label: {
                Image(systemName: "trash").frame(width: 24, height: 24)
            }
            .contentShape(Rectangle())
            .help("Delete")
        }
        .buttonStyle(.borderless)
        .padding(9)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .focusable()
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .onKeyPress(.return) {
            service.copy(sample, as: service.defaultFormat)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "123456789")) { press in
            guard let number = Int(press.characters),
                  ColorCopyFormat.allCases.indices.contains(number - 1)
            else { return .ignored }
            service.copy(sample, as: ColorCopyFormat.allCases[number - 1])
            return .handled
        }
    }

    private var rowBackground: Color {
        if isFocused { return Color.accentColor.opacity(0.1) }
        return Color.primary.opacity(isHovering ? 0.06 : 0.03)
    }
}
