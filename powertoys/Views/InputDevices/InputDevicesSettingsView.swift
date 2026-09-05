//
//  InputDevicesSettingsView.swift
//  powertoys
//

import SwiftUI

struct InputDevicesSettingsView: View {
    var showsHeader = true

    var body: some View {
        InputDevicesScrollSettings(showsHeaders: showsHeader)
            .settingsPageInsets(horizontal: UtilityLayout.horizontalInset, top: 14, bottom: 24)
            .settingsScrollContainer()
    }
}

struct InputDevicesScrollSettings: View {
    var showsHeaders = true

    @State private var manager = InputDevicesManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: UtilityLayout.sectionSpacing) {
            section("Scroll Control") {
                VStack(alignment: .leading, spacing: 10) {
                    InputSettingRow(
                        label: "Adjust scrolling system wide",
                        help: "Install the scroll event tap so these profiles apply outside MacPowerToys."
                    ) {
                        Toggle("Adjust scrolling system wide", isOn: setting(
                            get: { $0.scrollControlEnabled },
                            set: { $0.scrollControlEnabled = $1 }
                        ))
                    }
                    InputSettingRow(
                        label: "Treat scroll events as",
                        help: "Automatic sends continuous events to Trackpad and wheel notches to Mouse."
                    ) {
                        Picker("Treat scroll events as", selection: setting(
                            get: { $0.eventOverride },
                            set: { $0.eventOverride = $1 }
                        )) {
                            ForEach(InputEventOverride.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 160)
                    }
                    if !manager.permissionGranted {
                        InputSettingRow(label: "Accessibility permission") {
                            HStack(spacing: 8) {
                                Button("Grant Permission") { manager.requestPermission() }
                                Button("Open Privacy Settings") { manager.openPrivacySettings() }
                            }
                        }
                    }
                    if let errorMessage = manager.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .controlSize(.small)
                .utilitySectionCard()
            }

            section("Profiles") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 320), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    InputScrollProfileCard(
                        title: "Mouse",
                        icon: InputDeviceDescriptor.Kind.mouse.icon,
                        deviceCount: deviceCount(of: .mouse),
                        profile: profileBinding(\.mouse)
                    )
                    InputScrollProfileCard(
                        title: "Trackpad",
                        icon: InputDeviceDescriptor.Kind.trackpad.icon,
                        deviceCount: deviceCount(of: .trackpad),
                        profile: profileBinding(\.trackpad)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { manager.refresh() }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeaders {
                Text(title.uppercased()).utilitySectionHeader()
            }
            content()
        }
    }

    private func deviceCount(of kind: InputDeviceDescriptor.Kind) -> Int {
        manager.devices.filter { $0.kind == kind }.count
    }

    private func setting<Value>(
        get: @escaping (InputDevicesSettings) -> Value,
        set: @escaping (inout InputDevicesSettings, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { get(manager.settings) },
            set: { value in manager.update { set(&$0, value) } }
        )
    }

    private func profileBinding(
        _ keyPath: WritableKeyPath<InputDevicesSettings, InputScrollProfile>
    ) -> Binding<InputScrollProfile> {
        setting(get: { $0[keyPath: keyPath] }, set: { $0[keyPath: keyPath] = $1 })
    }
}
