//
//  Tool.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import Foundation
import NetToysKit

// MARK: - Tool Protocol

protocol Tool: Identifiable {
    var id: String { get }
    var name: String { get }
    var description: String { get }
    var summary: String { get }
    var icon: String { get }
    var logoAsset: String { get }
    var iconFileURL: URL? { get }
    var category: ToolCategory { get }
    var manual: [ToolManualSection] { get }
    var hasTrayTab: Bool { get }
    var searchKeywords: [String] { get }
}

extension Tool {
    var summary: String { description }
    var hasTrayTab: Bool { false }
    var iconFileURL: URL? { nil }
    var searchKeywords: [String] { [] }
}

// MARK: - Manual

struct ToolManualSection: Identifiable {
    let title: String
    let points: [String]

    var id: String { title }
}

// MARK: - Tool Category

enum ToolCategory: String, CaseIterable, Identifiable {
    case all = "All Tools"
    case dev = "Developer"
    case text = "Text"
    case files = "Files"
    case system = "System"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .dev: return "hammer"
        case .text: return "textformat"
        case .files: return "folder"
        case .system: return "gearshape.2"
        }
    }
}

// MARK: - Cloud Sync Tool

struct RcloneTool: Tool {
    let id = "rclone"
    let name = "RSync UI"
    let summary = "Copy, sync, and move files across cloud storage."
    let description = "Move files between your Mac and cloud storage with live progress, automatic retries, and ignore rules."
    let icon = ToolGlyph.cloudSync.symbol
    let logoAsset = "CloudSyncLogo"
    let category = ToolCategory.files
    let hasTrayTab = true

    let manual: [ToolManualSection] = [
        ToolManualSection(title: "Connect Cloud Storage", points: [
            "Click + next to Remotes in the RSync UI sidebar.",
            "Choose any connector offered by your installed rclone version, enter its required settings, and press Connect.",
            "For OAuth connectors, complete the provider's browser sign-in. rclone stores and refreshes the resulting credentials."
        ]),
        ToolManualSection(title: "Transfers", points: [
            "Press ⌘N or click New Transfer.",
            "Copy adds and updates files. Sync mirrors the source exactly, deleting extras. Move removes files from the source.",
            "Watch overall and per-file progress live. Failed transfers retry automatically with backoff."
        ]),
        ToolManualSection(title: "Browse & Preview", points: [
            "Click a remote in the sidebar to browse its files.",
            "Double-click folders to navigate. Press Space or click the eye to Quick Look a file.",
            "Drag files out to your Mac to download them, or drop local files into the folder to upload."
        ]),
        ToolManualSection(title: "Activity & Details", points: [
            "Every finished transfer is recorded in Activity with sizes and timing.",
            "Select ⓘ on a transfer to view paths, ignore rules, speed, attempts, and errors."
        ]),
        ToolManualSection(title: "Ignore Rules & Limits", points: [
            "Open Settings from the sidebar (⌘,) to edit ignore patterns. Add one glob per line. MacPowerToys applies each pattern to every transfer.",
            "System junk like .DS_Store, .fseventsd, and System Volume Information is ignored by default.",
            "Parallel transfers, bandwidth limits, and retry counts live on the same page."
        ]),
        ToolManualSection(title: "Dev Sync", points: [
            "Open Dev Sync in the sidebar and choose Set Up Dev Sync. Pick your internal dev folder and the matching folder on an external drive.",
            "Dev One-Way copies internal projects to the drive. Dev Bidirectional syncs changes both ways. Projects that live only on the drive stay there and appear as links in your internal folder.",
            "Review the preview before anything changes. Git ignore rules decide what is copied; ignored secrets such as .env files are still backed up unless you turn that off.",
            "Every overwrite and deletion is kept in the safety store for a retention period. Conflicts never pick a winner; resolve them from the pair page."
        ])
    ]

    static let shared = RcloneTool()
}

// MARK: - Logs Tool

struct LogsTool: Tool {
    let id = "logs"
    let name = "Event Viewer"
    let summary = "Read app activity and recent macOS errors."
    let description = "Inspect MacPowerToys activity and recent macOS errors and faults in clearly separated views."
    let icon = ToolGlyph.logs.symbol
    let logoAsset = "LogsLogo"
    let category = ToolCategory.system

    let manual: [ToolManualSection] = [
        ToolManualSection(title: "Reading Logs", points: [
            "Internal Logs contains MacPowerToys errors, warnings, info, and debug messages.",
            "System Issues reads recent macOS errors and faults on demand without saving them in the app.",
            "Choose a source in the sidebar, then filter internal levels or search messages and sources.",
            "Log text is fully selectable for copying into bug reports."
        ]),
        ToolManualSection(title: "Housekeeping", points: [
            "Internal logs are kept for two days, then pruned automatically.",
            "Clear Internal Logs empties the app's in-memory view.",
            "System Issues keeps at most 500 rows in memory and fetches them again when requested.",
            "Press ⌘, inside the window to change the log font size."
        ])
    ]

    static let shared = LogsTool()
}

// MARK: - Ruler Tool

struct RulerTool: Tool {
    let id = "ruler"
    let name = "Ruler"
    let summary = "Measure the screen in pixels, millimeters, or inches."
    let description = "Measure the screen with movable, resizable rulers in pixels, millimeters, or inches."
    let icon = ToolGlyph.ruler.symbol
    let logoAsset = "RulerLogo"
    let category = ToolCategory.dev

    let manual = [
        ToolManualSection(title: "Rulers", points: [
            "Drag a ruler to move it and drag an end or corner to resize it.",
            "Press ⌘N for another ruler. Use H or V to show or hide a wing, and ⌘` to cycle rulers.",
            "Use U for units, F for floating, S for shadow, G for grouping, and O to align at the pointer."
        ]),
        ToolManualSection(title: "Settings", points: [
            "Press ⌘, to edit the active ruler. Press ⌥⌘, to edit defaults for new rulers.",
            "Choose color, foreground and background opacity, dimensions, float, and shadow."
        ])
    ]

    static let shared = RulerTool()
}

// MARK: - Awake Tool

struct AwakeTool: Tool {
    let id = "awake"
    let name = "Kwake"
    let summary = "Keep your Mac awake for as long as you need."
    let description = "Keep your Mac awake indefinitely, for a duration, or until a chosen time without changing Energy settings."
    let icon = ToolGlyph.awake.symbol
    let logoAsset = "AwakeLogo"
    let category = ToolCategory.system
    let hasTrayTab = true

    let manual = [
        ToolManualSection(title: "Modes", points: [
            "Off uses normal macOS power settings. Indefinite remains active until disabled.",
            "Timed mode counts down for a duration. Until mode expires at a specific date and time.",
            "Keep Display On is independent and only applies while an active Kwake mode is selected."
        ]),
        ToolManualSection(title: "System Behavior", points: [
            "Kwake uses macOS power assertions and never edits your Energy settings.",
            "Manual sleep, closing a MacBook lid, low power, and thermal protection still take precedence."
        ])
    ]

    static let shared = AwakeTool()
}

// MARK: - Color Picker Tool

struct ColorPickerTool: Tool {
    let id = "color-picker"
    let name = "Color Picker"
    let summary = "Pick screen colors and copy them in your chosen format."
    let description = "Pick any onscreen color, copy it instantly, and keep a compact searchable history of useful values."
    let icon = ToolGlyph.colorPicker.symbol
    let logoAsset = "ColorPickerLogo"
    let category = ToolCategory.dev
    let hasTrayTab = true

    let manual = [
        ToolManualSection(title: "Pick and Copy", points: [
            "Press Pick Color to start the native macOS sampler immediately.",
            "The selected color is copied in your default format and saved to history.",
            "Open Color History to copy HEX, RGB, HSL, CSS, SwiftUI, or NSColor representations."
        ])
    ]

    static let shared = ColorPickerTool()
}

// MARK: - Text Extractor Tool

struct TextExtractorTool: Tool {
    let id = "text-extractor"
    let name = "Text Extractor"
    let summary = "Copy text from any screen region, processed on your Mac."
    let description = "Select text anywhere on screen and copy it using private, fully on-device Apple Vision recognition."
    let icon = ToolGlyph.textExtractor.symbol
    let logoAsset = "TextExtractorLogo"
    let category = ToolCategory.text
    let hasTrayTab = true

    let manual = [
        ToolManualSection(title: "Extract Text", points: [
            "Press Extract Text, drag around a screen region, and release to recognize and copy its text.",
            "Vision performs recognition locally. Captured pixels are discarded after processing.",
            "Screen Recording permission is required because macOS protects pixels belonging to other applications."
        ])
    ]

    static let shared = TextExtractorTool()
}

// MARK: - Input Devices Tool

struct InputDevicesTool: Tool {
    let id = "input-devices"
    let name = "Input Devices"
    let summary = "Set mouse and trackpad scroll direction and speed."
    let description = "Tune mouse and trackpad scrolling independently, including direction, speed, horizontal movement, and wheel smoothing."
    let icon = ToolGlyph.inputDevices.symbol
    let logoAsset = "InputDevicesLogoA"
    let category = ToolCategory.system
    let hasTrayTab = true

    let manual = [
        ToolManualSection(title: "Profiles", points: [
            "Mouse-like wheel events and precise trackpad events have separate controls.",
            "Reverse either axis, change speed, disable horizontal motion, or smooth coarse mouse-wheel steps.",
            "Auto selects the matching profile for wheel or precision scrolling."
        ]),
        ToolManualSection(title: "Permission", points: [
            "Enable Input Control and grant Accessibility permission when macOS asks.",
            "Input Devices changes only scroll events. It does not record keys, clicks, or pointer movement."
        ])
    ]

    static let shared = InputDevicesTool()
}

// MARK: - System Care Tool

struct SystemCareTool: Tool {
    let id = "system-care"
    let name = "System Cleaner"
    let summary = "Review storage, clean up files, and remove apps."
    let description = "Understand storage, preview safe cleanup, remove apps, and use advanced Mole maintenance."
    let icon = ToolGlyph.systemCare.symbol
    let logoAsset = "SystemCareLogo"
    let category = ToolCategory.system
    let hasTrayTab = true

    let manual = [
        ToolManualSection(title: "Storage and Cleanup", points: [
            "Choose a folder in Storage to see its largest contents and drill into any directory.",
            "Quick Cleanup scans supported rebuildable data. Guided Cleanup lets you choose categories. Analysis Only cannot clean.",
            "Review every selected item before moving it to macOS Trash."
        ]),
        ToolManualSection(title: "Mole CLI", points: [
            "Install or update Mole from the Mole CLI page with Homebrew.",
            "Preview each maintenance operation before opening it in Terminal.",
            "Mole uses Terminal when macOS needs administrator approval."
        ])
    ]

    static let shared = SystemCareTool()
}

struct DiskExplorerTool: Tool {
    let id = "disk-explorer"
    let name = "Partition Manager"
    let summary = "Mount, format, resize, and partition disks."
    let description = "See every disk as a partition map, then mount, format, resize, create, or delete partitions with the macOS disk tools."
    let icon = ToolGlyph.diskman.symbol
    let logoAsset = "DiskExplorerLogo"
    let category = ToolCategory.files

    let manual = [
        ToolManualSection(title: "Disks", points: [
            "The sidebar lists internal, external, and removable disks and attached disk images.",
            "Each disk shows a partition map. Block width follows partition size, and the darker fill shows used space.",
            "Click a block to select a partition or unallocated space. Click the disk header to select the whole disk."
        ]),
        ToolManualSection(title: "Actions", points: [
            "The inspector lists every action. An unavailable action shows why when you point to it.",
            "Resize and Create Partition preview the new layout on the map before you review them.",
            "Format, Delete, Resize, and Erase Disk open a confirmation that names the exact disk. Erase Disk asks you to type the disk name."
        ]),
        ToolManualSection(title: "Protection", points: [
            "Partition Manager never changes the startup disk, the disk with this app, internal disks, or the External1TB drive.",
            "It reads each disk again before every change and stops if the layout changed."
        ])
    ]

    static let shared = DiskExplorerTool()
}

// MARK: - Task Manager Tool

struct SystemMonitorTool: Tool {
    let id = "system-monitor"
    let name = "Task Manager"
    let summary = "Inspect processes and system activity, locally or by SSH."
    let description = "Inspect processes and live system activity locally or over SSH, with an optional lightweight menu-bar summary."
    let icon = ToolGlyph.taskManager.symbol
    let logoAsset = "SystemMonitorLogo"
    let category = ToolCategory.system
    let hasTrayTab = false

    let manual = [
        ToolManualSection(title: "Detailed Monitoring", points: [
            "Open Task Manager to inspect processes, CPU, GPU, memory, disk, network, battery, sensors, and system information.",
            "Choose a one, two, or five minute chart history without keeping a heavy sampler alive after the window closes.",
            "Closing the window stops detailed updates."
        ]),
        ToolManualSection(title: "Menu Bar", points: [
            "Enable a grouped Task Manager item or separate metric items; either opens the compact Task Manager panel.",
            "RAM is selected by default. Choose a refresh interval in settings, or turn the menu off to stop its timer."
        ]),
        ToolManualSection(title: "Remote Stats", points: [
            "Save an SSH host or alias for Linux, macOS, or Windows, then connect only while you need live readings.",
            "Choose manual refresh or an interval of five seconds or longer, and open that host in Terminal from Remote Stats."
        ])
    ]

    static let shared = SystemMonitorTool()
}

// MARK: - NetToys Tool

struct NetToysTool: Tool {
    let id = "nettoys"
    let name = "NetToys"
    let summary = "Scan networks, track outages, and keep SSH hosts linked."
    let description = "Scan IP networks, keep SSH hosts attached to changing local addresses, and review network outages."
    let icon = ToolGlyph.netToys.symbol
    let logoAsset = "NetToysLogo"
    let category = ToolCategory.system
    let hasTrayTab = true

    let manual = NetToysManual.sections.map { ToolManualSection(title: $0.title, points: $0.points) }

    static let shared = NetToysTool()
}

struct PortmanTool: Tool {
    let id = "portman"
    let name = "Portman"
    let summary = "Find local servers and forward private SSH ports."
    let description = "See local development servers and forward private SSH ports to this Mac."
    let icon = ToolGlyph.portman.symbol
    let logoAsset = "PortmanLogo"
    let category = ToolCategory.dev
    let hasTrayTab = false

    let manual = [
        ToolManualSection(title: "Local servers", points: [
            "Open Portman from the launcher or its counted menu-bar item. The panel shows listening development ports and their share of Mac memory.",
            "Select a server for process-tree, memory, CPU, and project details. Clean up previews the memory to free before stopping selected servers."
        ]),
        ToolManualSection(title: "SSH forwarding", points: [
            "Enter an SSH host or choose an alias from ~/.ssh/config, then scan its listening ports.",
            "Select ports and choose local port numbers. Portman binds each tunnel to 127.0.0.1.",
            "SSH uses your existing keys and known-host policy. A tunnel ends when you stop it or quit MacPowerToys."
        ])
    ]

    static let shared = PortmanTool()
}

struct MacTweaksTool: Tool {
    let id = "mac-tweaks"
    let name = "Mac Tweaks"
    let summary = "Tune input, Dock, Finder, windows, apps, and power."
    let description = "Find and control small Mac settings, starting with Mic Lock for Bluetooth headphone sound."
    let icon = ToolGlyph.macTweaks.symbol
    let logoAsset = "MacTweaksLogo"
    let category = ToolCategory.system
    let searchKeywords = ["mic lock", "microphone", "bluetooth", "airpods", "audio input"]

    let manual = [
        ToolManualSection(title: "Pages and search", points: [
            "Enable Mac Tweaks in the launcher, then choose Open Mac Tweaks.",
            "Choose Input, Dock, Finder, Windows, Screenshots, Apps, Power, or Menu bar in the sidebar.",
            "Press Cmd-K and type a setting name or behavior to search available controls across pages. Press Escape to clear search.",
            "Open About to see the app version, keyboard shortcuts, and Copy app details."
        ]),
        ToolManualSection(title: "Preferences and previews", points: [
            "Change a control to save its value. Default uses the system default. Custom means the current value does not match a listed choice.",
            "Preference edits are enabled on macOS 15.8, 26.7, and 27.0. Other releases keep controls read-only and allow reset. Finder column sizing and unused app termination are limited to macOS 15.8.",
            "Previews are static examples of the setting. They do not show the current state of your Mac.",
            "Managed preferences and values changed elsewhere are protected. If a save fails, read the error before trying again."
        ]),
        ToolManualSection(title: "Backups and reset", points: [
            "Mac Tweaks saves the exact original value before the first change. It also records when the original key was absent.",
            "Open Modified to compare Current and Original values. Changed settings remain listed while a saved original value can be restored, even at the system default.",
            "Use the reset arrow beside a control or Modified row to restore its saved original. A setting without a backup returns to the system default.",
            "Choose Reset all on Modified and confirm to restore every listed preference. If a backup cannot be read, new writes stop until it is recovered."
        ]),
        ToolManualSection(title: "Apply saved changes", points: [
            "Dock and Finder changes show a restart action. Save work, choose that action, then confirm Restart Dock or Restart Finder. Choose Later to keep the saved change and restart when ready.",
            "Follow the notice for other changes. It can require reopening an app, taking a new screenshot, or signing out and back in.",
            "A restart failure leaves the setting saved. Read the error and restart the affected app later."
        ]),
        ToolManualSection(title: "Mic Lock", points: [
            "Choose Input and turn on Mic Lock.",
            "Choose a primary microphone and up to three fallbacks. A disconnected choice stays saved.",
            "Mic Lock restores the first available choice when macOS changes input. If none is available, it selects a built-in or other non-wireless input.",
            "Use Test to check the input level. Grant microphone access when macOS asks.",
            "If Mac audio needs recovery, choose Revive Audio and confirm. macOS requests administrator approval; audio in other apps can stop briefly."
        ]),
        ToolManualSection(title: "Power", points: [
            "Turn on Keep this Mac awake and choose a duration. Keep display on controls display sleep separately.",
            "Read Status to check whether the Mac stays awake and how much time remains. These controls use the same Kwake state as the Kwake tool."
        ])
    ]

    static let shared = MacTweaksTool()
}

// MARK: - Marketplace Tool

struct MarketplaceTool: Tool {
    let receipt: MarketplaceReceipt
    let iconFileURL: URL?

    var id: String { receipt.toolID }
    var name: String { receipt.name }
    var description: String { receipt.summary }
    var icon: String { "shippingbox" }
    var logoAsset: String { "" }
    var category: ToolCategory { receipt.category.toolCategory }
    var manual: [ToolManualSection] {
        receipt.manual.map { ToolManualSection(title: $0.title, points: $0.points) }
    }
}

// MARK: - Available Tools

struct ToolRegistry {
    static let builtInTools: [any Tool] = [
        RcloneTool.shared,
        LogsTool.shared,
        RulerTool.shared,
        AwakeTool.shared,
        ColorPickerTool.shared,
        TextExtractorTool.shared,
        InputDevicesTool.shared,
        SystemCareTool.shared,
        DiskExplorerTool.shared,
        SystemMonitorTool.shared,
        NetToysTool.shared,
        PortmanTool.shared,
        MacTweaksTool.shared
    ]

    static var allTools: [any Tool] {
        builtInTools + MarketplaceManager.shared.installedTools
    }

    static func tools(for category: ToolCategory) -> [any Tool] {
        if category == .all {
            return allTools
        }
        return allTools.filter { $0.category == category }
    }

    static func tool(for id: String) -> (any Tool)? {
        allTools.first { $0.id == id }
    }
}
