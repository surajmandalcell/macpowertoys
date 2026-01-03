# PowerToys Specification - Q&A Session 1

## Q1: Should the main window support multiple instances (open several windows simultaneously), or enforce a single window that comes to front when re-opened?
**A:** Single instance only - Re-opening always brings the same window to front. Cleaner UX, simpler state.

## Q2: When the user switches categories, should tool state be preserved (e.g., text entered in a text tool)?
**A:** Per-session only - Preserve within session but reset on app relaunch. Middle ground approach.

## Q3: How should keyboard navigation work in the sidebar?
**A:** Both approaches - Support arrow navigation AND number shortcuts (Cmd+1-5) for maximum flexibility.

## Q4: For the 'All Tools' view, how should tools be displayed when showing all categories together?
**A:** Grouped list by category - Collapsible sections per category. Better for organization and finding specific tools.

## Q5: Should PowerToys support global hotkeys to trigger specific tools without opening the main window?
**A:** Yes, configurable - Users can assign hotkeys per tool. More powerful but requires additional UI for configuration.

## Q6: How should the main app flow work?
**A:** Clarified flow:
1. Menu bar icon -> click to open, or right-click for context menu
2. Main window shows "All Tools" by default (or last selected tab if user previously navigated)
3. Left sidebar has "All Tools" at top, then tools grouped by type
4. Clicking a tool in sidebar shows settings on the right side:
   - Top option: Enable/Disable toggle
   - Settings panel with tool configuration
   - First setting option: "Open tool externally" (organized aesthetically)
5. If user opens the tool (e.g., "CC History"), they see the actual tool interface without preferences (tightly integrated to main app)

## Q7: When a tool is 'opened externally', should it open as a separate floating window or a full standalone app window?
**A:** Standard window - Regular macOS window that behaves like any other app window.

## Q8: What is "CC History"?
**A:** CC History = Claude Code History. It's a tool to view Claude Code conversation history stored in `~/.claude/projects/*/` as JSONL files. Features needed:
- Sidebar with conversation navigation
- Compact, minimal viewing interface
- Copy buttons for single items or multiple items
- Option to select multiple items
- Read-only (no retention/modification)

## Q9: For the CC History sidebar, should conversations be organized by project folder, by date, or both?
**A:** Sort by date (recent first). Sidebar organization follows Claude's structure but sorted chronologically. Sidebar can have some complexity as needed.

## Q10: What content from each JSONL message should be displayed in the conversation view?
**A:** Full messages with flexible filtering via top-right toolbar:
- **Default view**: User messages + Claude responses only
- **Toolbar toggles**: Enable/disable: tool calls, tool outputs, Claude responses
- Combinations: outputs only, tool calls only, outputs + tool outputs, etc.
- Search icon in toolbar (expandable) for within-conversation search

## Q11: Should the CC History tool support search/filter across conversations?
**A:** Both:
- **Global search**: On top of sidebar to search across all conversations
- **Within-conversation search**: Search icon button in conversation toolbar (expandable)

## Q12: For copying messages, what format should the copied content be in?
**A:** Configurable in settings. Default: plain text.

## Q13: Should CC History support exporting entire conversations?
**A:** Yes, multiple formats:
- Markdown (.md)
- JSON
- Plain text

## Q14: Beyond CC History, what other tools are planned for PowerToys?
**A:** Focus on CC History for now. Other tools TBD later.

## Q15: Claude Code ~/.claude/ structure analysis
**A:** Structure understood from analysis:
```
~/.claude/
├── projects/                     # Project-specific conversations
│   └── -Path-To-Project/        # Folder per project (path encoded with dashes)
│       └── {session-id}.jsonl   # Each conversation is a JSONL file
├── history.jsonl                # Global history (all projects)
├── settings.json                # User settings
├── plans/                       # Plan files
├── todos/                       # Todo files
├── file-history/                # File snapshots
├── debug/                       # Debug logs
├── session-env/                 # Session environment data
└── ...
```

**JSONL Message Types:**
- `type: "user"` - User messages
- `type: "assistant"` - Claude responses (may contain tool_use)
- `type: "system"` - System messages (commands, etc.)
- `type: "file-history-snapshot"` - File snapshots

**Key fields:** sessionId, uuid, timestamp, cwd (project path), message.content

## Q16: Sidebar organization for CC History
**A:** Follow Claude's hierarchy:
- Projects grouped by path (decoded from folder names)
- Within each project: sessions sorted by date (recent first)
- Each session shows: timestamp + first user message preview

## Q17: Long conversations handling
**A:** Virtual scrolling - but must preserve click+hold+scroll selection behavior for multi-select

## Q18: Delete conversations?
**A:** No delete - read-only viewer only

## Q19: How should code blocks be rendered?
**A:** Most content is text/ASCII diagrams. Add subtle syntax highlighting for actual code blocks when detected. Keep it light and appropriate.

## Q20: Should the app track recently opened conversations?
**A:** No recent tracking. Start fresh each time.

