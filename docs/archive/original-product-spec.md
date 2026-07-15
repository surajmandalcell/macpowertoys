# PowerToys macOS - Final Specification

## Overview

A macOS menu bar utility application with pluggable tools/applets. Each tool can:
- Display settings in the main window
- Open a dedicated tool window (double-click)
- Run background services (if needed)
- Register global hotkeys (if needed)

**Target**: macOS 14 (Sonoma)+
**First tool**: CC History (Claude Code conversation viewer)
**System tool**: Logs (app-wide logging with 2-day retention)

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
| macOS Target | 14 (Sonoma)+ |
| Menu bar icon | `wrench.adjustable.fill` |
| Window instances | Single main window |
| State preservation | Per-session (reset on relaunch) |
| Sidebar single-click | Navigate to settings page |
| Sidebar double-click | Open tool window (if hasWindow) |
| Window on close | Hide (stays in menu bar) |
| Theme persistence | Applied on app launch |
| Background services | Start with app (if enabled) |
| Tool window state | Persist exact size AND position |
| Database | SwiftData |
| Live updates | FSEvents file watching |

---

## App Flow

1. **App Launch**:
   - `AppInitializer` runs immediately
   - Applies saved theme
   - Starts background services for enabled tools
   - Registers global hotkeys
   - Clears old logs (>2 days) non-blocking

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

## Deep Linking

Support both URL scheme and CLI arguments:
- **URL scheme**: `powertoys://open/cchistory`
- **CLI**: `powertoys --open cchistory`
- Enables automation and integration with other tools

---

## Logs Tool (System)

**Position**: Below Settings in sidebar (always visible)

### Features
- Captures logs from main app AND all sub-apps (tools)
- 2-day retention policy
- Auto-clear old logs on startup (non-blocking)
- **4 log levels**: Error, Warning, Info, Debug
- Filter by log level and source
- Search functionality

### Storage
- **Hybrid approach**: Memory buffer for fast UI + periodic disk flush
- Survives crashes, can view logs across sessions
- **SwiftData** for persistence

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
│   ├── AccessibilityManager.swift    # Permissions (stub)
│   ├── LogManager.swift              # App-wide logging
│   ├── FileWatcher.swift             # FSEvents wrapper
│   └── Models/                       # SwiftData models
│
├── Tools/
│   ├── CCHistory/
│   │   ├── CCHistoryTool.swift
│   │   ├── Models/
│   │   ├── Services/
│   │   └── Views/
│   └── Logs/
│       ├── LogsTool.swift
│       └── Views/
│
├── Views/
│   ├── MainWindowView.swift
│   ├── ToolSidebarView.swift
│   ├── AllToolsGridView.swift
│   ├── SettingsView.swift
│   ├── ToolSettingsView.swift
│   └── Components/
│       ├── DoubleClickRow.swift
│       ├── SidebarStyle.swift        # Shared sidebar styling
│       └── SlideOverPanel.swift      # Resizable side panel
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
┌──────────────┬─────────────────────────────────┬────────────┐
│ [Progress]   │ [User|Claude|Tools] [Search]    │ [Thinking] │
├──────────────┼─────────────────────────────────┤  (panel)   │
│ [Search]     │                                 │            │
│ * Bookmarks  │  User: How do I...              │            │
│──────────────│  ────────────────────────────── │────────────│
│ dev/project1 │  Claude: Here's how...          │ [Tool      │
│  └ Session A │    [Bash] [Read] [Edit]         │  Details]  │
│  └ Session B │                                 │  (panel)   │
│ dev/project2 │  [Copy] [Select]                │            │
│  └ Session C │                                 │            │
└──────────────┴─────────────────────────────────┴────────────┘
```

### Sidebar Features
- **Progress bar**: Thin bar at very top, shows during parsing
- **Bookmarks**: 1-5 pinned conversations (horizontal chips)
  - Only show filled slots (no empty placeholders)
  - Add via right-click context menu
  - Dot indicator when conversation has new messages
  - Persistence: Store session ID + file path, graceful fallback
- **Global search**: Inline highlight in sidebar tree
- **Project tree**: Same visual style as main app sidebar
  - Project names: Last 2 path segments (e.g., `dev/myproject`)
  - Collapsed by default, persisted expand state (SwiftData)
  - Sessions sorted by date (recent first)
  - **Metadata visible**: Relative date + message count
  - **Hover tooltip**: Duration, file size, etc.
- **FSEvents monitoring**: Auto-detect new conversations
- **Virtualized**: Lazy-load for 100+ projects

### Error States
- Empty state with centered icon + helpful message
- E.g., "No conversations found" or "Cannot access ~/.claude"

### Caching System
- **SwiftData** for parsed conversation cache
- File modification time for invalidation
- Survives app restarts - no re-parsing if files unchanged
- Parse incrementally, show conversations as they're ready
- **Partial loading**: Show content as it parses (no blocking spinner)

### Conversation View Features
- **Filter toggles**: User | Claude | Tools | Outputs
  - Global default + per-session override (resets on window close)
  - Default: User + Claude only
- **Tool calls**: Icons only inline, click to expand in slide-over panel
- **Thinking**: Separate side panel toggle (not inline)
- **Markdown**: Code blocks only, with language-specific syntax highlighting
  - **Library**: Pure Swift highlighter (Splash or similar, NOT Highlightr)
- **Within-conversation search**
  - **Highlight**: System accent color
- **Virtual scrolling**
- **Live updates**: Append silently at bottom, auto-scroll if at bottom
- **Multi-select**: Click, shift+click, drag
  - Visual: Subtle background highlight
- **Keyboard navigation**:
  - Arrow keys move between messages
  - Enter to select/expand
  - Space to toggle tool expansion

### Slide-Over Panels
- **Tool Details Panel**: Shows on tool call click
  - Resizable width (drag handle)
  - Remember user's preferred width
  - Shows: tool name, input, output, duration
- **Thinking Panel**: Shows on toggle button
  - Contains all thinking blocks for current conversation
  - Also resizable

### Copy/Export
- **Cmd+C**: Uses default format from settings (instant)
- **Right-click/menu**: Choose Markdown, JSON, or Plain text
- Settings: Copy format preference

### Settings (Minimal)
- Auto-refresh toggle
- Copy format preference (Markdown/JSON/Plain)

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+1-5 | Jump to sidebar category |
| Arrow keys | Navigate sidebar / messages |
| Enter | Select/expand focused item |
| Space | Toggle tool call expansion |
| Cmd+F | Search within conversation |
| Cmd+Shift+F | Global search |
| Cmd+C | Copy selected (default format) |

---

## UI Styling (Tool Windows)

Tool windows share main app sidebar aesthetics:
- Same blur material (`.sidebar`)
- Same hover/selection states
- Same custom NSVisualEffectView background
- Tool-specific content (e.g., CC History shows projects/sessions)

---

## Implementation Phases

### Phase 1: Core Infrastructure
1. Create `Core/` folder
2. Set up SwiftData models
3. Implement `ToolCapabilities` (OptionSet)
4. Update `Tool` protocol with capabilities
5. Create `SettingsManager` with theme persistence
6. Create `AppInitializer` called from `AppDelegate`
7. **Fix theme bug**: Apply saved theme on app launch
8. Add `LogManager` with hybrid storage
9. Add `FileWatcher` for FSEvents

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
3. Implement SwiftData caching system
4. Add syntax highlighting (pure Swift library)
5. Create slide-over panel component
6. Implement virtualized sidebar

### Phase 5: Logs Tool
1. Create `Tools/Logs/` structure
2. Implement log viewer UI with filters/search
3. Wire into main sidebar below Settings

### Phase 6: Deep Linking
1. Register URL scheme (`powertoys://`)
2. Handle CLI arguments (`--open`)
3. Route to appropriate tool window

### Phase 7: Cleanup
1. Update `CLAUDE.md` references if needed

---

## Technical Stack

- **Framework**: SwiftUI (macOS 14+)
- **Menu bar**: `MenuBarExtra`
- **Layout**: Custom `HStack` (NOT NavigationSplitView)
- **Icons**: SF Symbols only
- **Persistence**: UserDefaults + SwiftData
- **Background**: Swift Actors
- **Concurrency**: async/await
- **File watching**: FSEvents
- **Syntax highlighting**: Pure Swift (Splash or similar)
- **State management**: @Observable macro (macOS 14+)
