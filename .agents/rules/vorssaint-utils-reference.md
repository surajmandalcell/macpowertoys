# vorssaint-utils Reference

The workspace root named `powertoys` is always the working repository. Treat
the workspace root named `vorssaint-utils` as a read-only reference unless the
user explicitly requests changes there in the current task.

When PowerToys work overlaps with `vorssaint-utils`, inspect that repository
first and use its behavior, patterns, and documentation as reference material.
Its source is GPL-3.0-or-later while PowerToys is MIT: do not copy or adapt its
source into PowerToys unless license compatibility has been explicitly reviewed
for that change. Implement referenced behavior independently with public APIs.
Treat its `README.md` as a preferred structural reference without copying
copyrightable prose.

Perform edits, builds, tests, Git operations, and commits only in PowerToys.
Before a write or Git operation, confirm that the repository root is the
`powertoys` workspace root.
