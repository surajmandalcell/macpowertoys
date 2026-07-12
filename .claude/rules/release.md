# Release & Install (MANDATORY after every big task)

After each big task (feature lands, major fix verified — anything worth a
minor/major version), ship it locally:

1. **Tests green first** — never install a build that hasn't passed the suite.
2. **Bump the version semantically** in `MARKETING_VERSION` (all targets):
   patch = fixes, minor = features, major = breaking/redesign. Increment
   `CURRENT_PROJECT_VERSION` on every install.
3. **Commit and push** the checkpoint (per global checkpoint-commit policy).
4. **Build Release and install** — builds MUST be throttled; the user accepts
   slower builds in exchange for a responsive machine. Never run an
   unthrottled full build:
   ```
   taskpolicy -c utility nice -n 10 xcodebuild -project powertoys.xcodeproj \
     -scheme powertoys -configuration Release -jobs 4 build
   osascript -e 'tell application "powertoys" to quit'   # transfers auto-pause and auto-resume
   rm -rf /Applications/PowerToys.app
   ditto <BUILT_PRODUCTS_DIR>/powertoys.app /Applications/PowerToys.app
   open /Applications/PowerToys.app
   ```
   Same throttle wrapper for Debug builds and `xcodebuild test`. Automatic
   signing (team GF57JXJF5A) — never pass CODE_SIGN_IDENTITY manually.
5. **Cleanup** — never leave versioned copies of the app anywhere (no
   PowerToys-1.x.app, no .zip exports). /Applications holds exactly one bundle.
   Keep DerivedData unless it exceeds several GB — purging forces an
   expensive full rebuild; incremental builds are the cheap path.

Interrupting transfers is safe by design: quitting marks active transfers
paused with auto-resume-on-launch; the new build continues them with byte
baselines intact (append-basis, no recalculation).
