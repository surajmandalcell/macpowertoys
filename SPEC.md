# PowerToys macOS - Specification

## Overview

A macOS utility application that lives in the menu bar, providing quick access to various productivity tools through a sidebar-based interface. First tool: **CC History** (Claude Code conversation viewer).

---

## Core Decisions (Confirmed)

| Decision | Choice |
|----------|--------|
| Menu bar icon | `wrench.adjustable.fill` SF Symbol |
| Window instances | Single instance only |
| State preservation | Per-session (reset on relaunch) |
| Keyboard navigation | Arrow keys + Cmd+1-5 shortcuts |
| Window on close | Hide (stays in menu bar) |
| Dock presence | Show in dock |
| Delete conversations | Read-only, no delete |

---

## App Flow

1. **Menu bar icon** -> Left-click opens window, right-click shows Open/Quit menu
2. **Main window** shows "All Tools" by default (or last selected tab in session)
3. **Left sidebar**: "All Tools" at top, then tools grouped by type
4. **Clicking a tool** shows settings panel on right:
   - Enable/Disable toggle at top
   - Tool configuration settings
   - "Open tool externally" option
5. **Opening a tool externally** -> Standard macOS window with tool interface

---

## First Tool: CC History (Claude Code History Viewer)

### Data Source
```
~/.claude/
├── projects/                     # Project-specific conversations
│   └── -Path-To-Project/        # Folder per project (path encoded with dashes)
│       └── {session-id}.jsonl   # JSONL conversation files
├── history.jsonl                # Global history reference
└── ...
```

### JSONL Message Types
- `type: "user"` - User messages
- `type: "assistant"` - Claude responses (contains tool_use in content)
- `type: "system"` - System messages
- Key fields: `sessionId`, `uuid`, `timestamp`, `cwd`, `message.content`

### CC History Layout
```
┌────────────────────────────────────────────────────────────┐
│ [Search...                    ]                            │
├──────────────┬─────────────────────────────────────────────┤
│              │ [Filter: User | Claude | Tools] [Search]    │
│ PROJECT 1    ├─────────────────────────────────────────────┤
│  └ Session A │                                             │
│  └ Session B │  User: How do I...                          │
│              │  ─────────────────────────────────────────  │
│ PROJECT 2    │  Claude: Here's how to...                   │
│  └ Session C │                                             │
│              │  [Copy] [Select]                            │
│              │                                             │
└──────────────┴─────────────────────────────────────────────┘
     │                              │
  Sidebar                    Conversation View
  (by project,               (virtual scrolling)
   sorted by date)
```

### Features

**Sidebar:**
- **Bookmarks**: Up to 5 pinned conversations as horizontal chips at top
- **Global search**: Search bar at top (across all conversations)
- **Project tree**: Projects grouped by path, all collapsed by default
- **Persist expand state**: Remember which projects user expanded across relaunches
- Sessions within each project, sorted by date (recent first)
- Session shows: timestamp + first user message preview

**Conversation View:**
- **Toolbar toggles** (top right): User | Claude | Tools | Tool outputs | Thinking
- **Default view**: User + Claude responses only
- **Within-conversation search**: Expandable search icon in toolbar
- **Virtual scrolling**: For performance (preserve click+drag multi-select)
- **Multi-select**: Click, Shift+click, click+drag to select messages
- **Copy buttons**: Per-message and for selection
- **Code blocks**: Subtle syntax highlighting when detected
- **Live auto-update**: Watch files, auto-append new messages (debounced)

**Export:**
- Export selected/all to: Markdown, JSON, Plain text

**Settings:**
- Copy format: Plain text (default) or Markdown
- Global hotkeys: Configurable per tool (requires accessibility permission)

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

## Technical Stack

- **Framework**: SwiftUI (macOS 13+)
- **Menu bar**: `MenuBarExtra`
- **Layout**: `NavigationSplitView`
- **Icons**: SF Symbols only
- **Data**: Read JSONL files from `~/.claude/`

---

## Q&A Reference

See `spec/spec1.md` for detailed interview responses.
