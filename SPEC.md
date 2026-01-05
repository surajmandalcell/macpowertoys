# PowerToys macOS - Specification v2

## Overview

A macOS menu bar utility application with pluggable tools/applets. Each tool can:
- Display settings in the main window
- Open a dedicated tool window (double-click)
- Run background services (if needed)
- Register global hotkeys (if needed)

**First tool**: CC History (Claude Code conversation viewer)

---

## Architecture Principles

### Tool Capabilities System

Tools declare what they need via capabilities:

| Capability | Description |
|------------|-------------|
| `hasWindow` | Can open a separate window with tool UI |
| `needsBackgroundService` | Runs continuously in background when enabled |
| `needsGlobalHotkeys` | Registers system-wide hotkeys |
| `needsAccessibility` | Requires accessibility permissions |

### Tool Protocol

```swift
protocol Tool {
    var id: String { get }
    var name: String { get }
    var icon: String { get }
    var category: ToolCategory { get }
    var capabilities: ToolCapabilities { get }
    var isEnabled: Bool { get set }

    func settingsView() -> AnyView
    func createBackgroundService() -> BackgroundService?
}
```

### Background Services

- Swift actors for thread-safe, lightweight concurrency
- Start automatically on app launch if tool is enabled
- Managed by `BackgroundServiceManager`
- Clean start/stop lifecycle

### Settings Persistence

All settings use UserDefaults with namespacing:
- App-level: `app.theme`, `app.enabledTools`
- Tool-level: `tool.{toolId}.{key}`

**Critical**: Settings applied on app launch via `AppInitializer`:
1. Load `SettingsManager`
2. Apply theme immediately
3. Start background services for enabled tools
4. Register global hotkeys

---

## Core Decisions

| Decision | Choice |
|----------|--------|
| Menu bar icon | `wrench.adjustable.fill` |
| Window instances | Single main window |
| State preservation | Per-session (reset on relaunch) |
| Sidebar single-click | Navigate to settings page |
| Sidebar double-click | Open tool window (if hasWindow) |
| Window on close | Hide (stays in menu bar) |
| Theme persistence | Applied on app launch |
| Background services | Start with app (if enabled) |

---

## App Flow

1. **App Launch**:
   - `AppInitializer` runs immediately
   - Applies saved theme
   - Starts background services for enabled tools
   - Registers global hotkeys

2. **Menu bar icon**:
   - Left-click: Open main window
   - Right-click: Context menu (Open/Quit)

3. **Main Window**:
   - Left sidebar: Categories + tools
   - Right content: Settings or tool grid
   - "All Tools" shown by default

4. **Sidebar Interaction**:
   - Single-click tool: Show settings page
   - Double-click tool: Open tool window (if hasWindow)
   - Click category: Filter tools

5. **Settings Page** (per tool):
   - Enable/Disable toggle
   - Tool-specific configuration
   - "Open" button to launch tool window

---

## Folder Structure

```
powertoys/
├── Core/
│   ├── Tool.swift                    # Tool protocol + ToolCapabilities
│   ├── ToolCategory.swift
│   ├── ToolRegistry.swift
│   ├── BackgroundService.swift       # Protocol
│   ├── BackgroundServiceManager.swift
│   ├── SettingsManager.swift         # App-level settings
│   ├── AppInitializer.swift          # Startup sequence
│   ├── HotkeyManager.swift           # Global hotkeys (stub)
│   └── AccessibilityManager.swift    # Permissions (stub)
│
├── Tools/
│   └── CCHistory/
│       ├── CCHistoryTool.swift
│       ├── Models/
│       ├── Services/
│       └── Views/
│
├── Views/
│   ├── MainWindowView.swift
│   ├── ToolSidebarView.swift
│   ├── AllToolsGridView.swift
│   ├── SettingsView.swift
│   ├── ToolSettingsView.swift
│   └── Components/
│       └── DoubleClickRow.swift
│
├── AppDelegate.swift
└── powertoysApp.swift
```

---

## First Tool: CC History

### Capabilities
- `hasWindow` - Yes
- `needsBackgroundService` - No
- `needsGlobalHotkeys` - No
- `needsAccessibility` - No

### Data Source
```
~/.claude/projects/
└── -Path-To-Project/
    └── {session-id}.jsonl
```

### Layout
```
┌──────────────┬─────────────────────────────────┐
│ [Search]     │ [User|Claude|Tools|Think] [Search]│
├──────────────┼─────────────────────────────────┤
│ * Bookmarks  │                                 │
│──────────────│  User: How do I...              │
│ PROJECT 1    │  ────────────────────────────── │
│  └ Session A │  Claude: Here's how...          │
│  └ Session B │                                 │
│ PROJECT 2    │  [Copy] [Select]                │
│  └ Session C │                                 │
└──────────────┴─────────────────────────────────┘
```

### Features

**Sidebar**:
- Bookmarks: 5 pinned conversations (horizontal chips)
- Global search: Search all conversations
- Project tree: Collapsed by default, persisted expand state
- Sessions sorted by date (recent first)

**Conversation View**:
- Filter toggles: User | Claude | Tools | Outputs | Thinking
- Default: User + Claude only
- Within-conversation search
- Virtual scrolling
- Multi-select (click, shift+click, drag)
- Copy/export (Markdown, JSON, Plain text)

**Settings**:
- Auto-refresh toggle
- Copy format preference

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+1-5 | Jump to sidebar category |
| Arrow keys | Navigate sidebar |
| Cmd+F | Search within conversation |
| Cmd+Shift+F | Global search |
| Cmd+C | Copy selected messages |

---

## Implementation Phases

### Phase 1: Core Infrastructure
1. Create `Core/` folder
2. Implement `ToolCapabilities` (OptionSet)
3. Update `Tool` protocol with capabilities
4. Create `SettingsManager` with theme persistence
5. Create `AppInitializer` called from `AppDelegate`
6. **Fix theme bug**: Apply saved theme on app launch

### Phase 2: Background Services
1. Create `BackgroundService` protocol (actor-based)
2. Create `BackgroundServiceManager`
3. Wire into `AppInitializer`
4. Add stubs for `HotkeyManager`, `AccessibilityManager`

### Phase 3: Double-Click UI
1. Create `DoubleClickRow` component
2. Update `ToolSidebarView` to detect double-click
3. Open tool window on double-click (if hasWindow)

### Phase 4: Tool Migration
1. Move CCHistory to `Tools/CCHistory/`
2. Update to new `Tool` protocol with capabilities
3. Test settings persistence across restarts

### Phase 5: Cleanup
1. Update `CLAUDE.md` references if needed

---

## Technical Stack

- **Framework**: SwiftUI (macOS 13+)
- **Menu bar**: `MenuBarExtra`
- **Layout**: Custom `HStack` (NOT NavigationSplitView)
- **Icons**: SF Symbols only
- **Persistence**: UserDefaults
- **Background**: Swift Actors
- **Concurrency**: async/await
