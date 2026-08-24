# PowerToys

SwiftUI macOS utility app with pluggable tools.

## Rules
@spec/troubleshoot/troubleshoot.md
@.codex/rules/vorssaint-utils-reference.md
@.codex/rules/window-experience.md
@spec/ruler-request-list.md
@spec/color-picker-request-list.md
@spec/system-tools-request-list.md
@DESIGN.md
@.claude/rules/code-style.md
@.claude/rules/architecture.md
@.claude/rules/design-tokens.md
@.claude/rules/release.md

The troubleshooting index is the highest-priority repo-local rule. Read it
before other repo guidance, then read every topic it routes for the task before
inspecting or changing implementation files.

`spec/troubleshoot/troubleshoot.md` is the only troubleshooting entry point.
Keep all troubleshooting knowledge under `spec/troubleshoot/`; do not add
compatibility shims or alternate troubleshooting rule files.

Keep `spec/color-picker-request-list.md` current when Color Picker
requirements or verification results change.

Keep `spec/ruler-request-list.md` current when Ruler requirements or
verification results change.

Keep `spec/system-tools-request-list.md` current when Input Devices, System
Care, or System Monitor requirements or verification results change.

Keep `goals.md` current when a request list adds or closes current work.
