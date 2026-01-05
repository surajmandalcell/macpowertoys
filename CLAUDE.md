# PowerToys - Claude Code Guidelines

## Code Style

- **No unnecessary comments** - Only add comments when absolutely necessary for complex logic or non-obvious behavior. Self-documenting code is preferred.
- Keep code clean and minimal
- Prefer descriptive variable/function names over comments

## Project Structure

- SwiftUI macOS app
- Tools/plugins are on-demand only - they should NOT open automatically on app start
- Main window shows tool settings, actual tool interfaces open in separate windows
