# PowerToys Specification - Q&A Session 2

## Q21: For global hotkeys (configurable per tool), should they require accessibility permissions?
**A:** Yes, with permission prompt. Full global hotkey support with guided accessibility permission flow.

## Q22: Should the CC History sidebar collapse project groups by default or expand them?
**A:** All collapsed by default. BUT:
- **Remember expanded state**: When user expands projects, remember across relaunches
- **Bookmarks feature**: Pin up to 5 conversations to top (compact display) for quick access

## Q23: How should bookmarked conversations be displayed at the top?
**A:** Horizontal chips - Small clickable pills in a row above the project tree. Most compact.

## Q24: Should conversations auto-refresh if the JSONL file changes while viewing?
**A:** Live auto-update with debounce. Automatically append new messages when files change, but debounce to prevent performance issues with rapid updates.

## Q25: Should there be a way to see raw JSON for debugging/inspection?
**A:** No raw view. Keep it simple - users who need raw can open files directly.

## Q26: Should thinking content (Claude's internal reasoning) be visible?
**A:** Filter toggle like tools. Add 'Thinking' as another filter option in the toolbar alongside User/Claude/Tools/Tool outputs.

