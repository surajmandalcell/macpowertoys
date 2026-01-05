# Spec Q&A - Part 1

## Q1: Error Handling for Malformed JSONL
**A:** Create a dedicated **Logs Tool** below Settings in the sidebar. This logs tool will:
- Capture logs from main app AND sub-apps (tools)
- 2-day retention policy
- Auto-clear old logs on startup (non-blocking)
- Include filter and search functionality

For malformed JSONL specifically: Log the error but continue parsing valid lines.

## Q2: Virtual Scrolling & Performance Strategy
**A:** Implement a **caching system** for conversations:
- First load: Show loading/parsing with progress bar
- Detect changes via hash comparison
- Load incrementally as parsed (show conversations as they're ready for better UX)
- Progress bar: thin, minimal, in sidebar

**Critical UI Change**: Copy the main app sidebar design to sub-apps (tools). This means:
- Tool windows get the same sidebar styling as main window
- Update architecture rules for this revised design decision
- Create good-looking nested conversation viewing UI that matches new sidebar

## Q3: Bookmark Persistence Strategy
**A:** Store both session ID AND file path with graceful fallback:
1. Try session ID first
2. Fall back to file path
3. Show 'missing' state if both fail

## Q4: Logs Storage Strategy
**A:** Hybrid approach:
- Memory buffer for fast UI rendering
- Periodic flush to disk for persistence
- Can view logs across sessions, survives crashes
- Still performant for real-time log viewing

## Q5: Tool Window Sidebar Design
**A:** Tool-specific sidebar with same visual style:
- Each tool window has its OWN sidebar with tool-relevant navigation
- CC History sidebar shows projects/sessions (not the main app's tool list)
- Same visual styling (blur, colors, hover states) as main app sidebar
- Different content per tool

## Q6: Progress Bar Location
**A:** Top of sidebar:
- Thin horizontal bar across full sidebar width
- Positioned at the very top
- Shows during conversation parsing/loading operations

## Q7: Cache Storage & Invalidation
**A:** Disk cache with file modification time:
- Persist parsed conversation cache to disk (SQLite or file-based)
- Use fast file modification timestamp for invalidation checks
- Survives app restarts - no re-parsing on launch if files unchanged
- Best balance of speed and persistence

## Q8: Filter Toggle Persistence
**A:** Global default with per-session override:
- Set a global default filter preference (saved in settings)
- Each session can have temporary overrides
- Overrides reset when window closes (not persisted per-session)
- Good balance between consistency and flexibility

## Q9: Selection Visual Feedback
**A:** Background highlight:
- Subtle background color change on selected messages
- Clean, minimal approach
- Works well with existing message styling

## Q10: Nested Sidebar Structure (Clarification)
**A:** "Nested" refers to the **project/session hierarchy**, not message nesting:
- Projects as parent folders with sessions as children
- Currently shows as folder with sub-items in existing UI
- Update to match new sidebar aesthetics (same blur/styling as main app)
- Keep the hierarchical folder structure, just restyle it

## Q11: Copy/Export Flow
**A:** Cmd+C uses default format, menu for others:
- User sets preferred copy format in settings (Markdown/JSON/Plain text)
- Cmd+C instantly copies in that default format
- Right-click menu or export menu for choosing other formats
- No picker popup on every copy - fast workflow

## Q12: Window State Persistence
**A:** Persist exact size AND position:
- Remember window size and position from last session
- Restore exactly on next launch
- Per-tool window memory (CCHistory window state saved separately)

## Q13: Global Search Results Display
**A:** Inline highlight in sidebar tree:
- Matching sessions are highlighted directly in the sidebar tree
- Click to navigate to that conversation
- No separate results pane - keeps UI clean
- Filter/highlight happens in-place

## Q14: Tool Call Display in Conversation
**A:** Icons only, click to expand:
- Show tool icon/name inline in message flow (minimal footprint)
- Click to expand into modal or side panel with full details
- Keeps conversation view clean and readable
- Details available on demand

## Q15: Keyboard Navigation in Conversation View
**A:** Full keyboard navigation:
- Arrow keys (up/down) move focus between messages
- Enter to select/expand current message
- Space to toggle tool call expansion
- Works alongside mouse interaction

## Q16: Tool Call Expansion UI
**A:** Slide-over panel:
- Right-side panel slides in over the conversation view
- Shows full tool details (input, output, duration, etc.)
- Dismiss by clicking X or clicking away
- Keeps context visible while viewing tool details

## Q17: Cache Storage Format
**A:** SQLite database:
- Single .db file in Application Support
- Efficient queries for metadata and search
- Good for future features (search indexing, statistics)
- Easy to inspect with standard SQLite tools

## Q18: Live Update Detection
**A:** Auto-detect with FSEvents:
- Watch ~/.claude/projects directory for file changes
- Automatically update sidebar when new sessions appear
- Real-time feel without manual refresh
- Native macOS API for efficient monitoring

