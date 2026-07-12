# Release & Install (MANDATORY after every big task)

After each big task (feature lands, major fix verified — anything worth a
minor/major version), ship it locally:

1. **Tests green first** — never install a build that hasn't passed the suite.
2. **Bump the version semantically** in `MARKETING_VERSION` (all targets):
   patch = fixes, minor = features, major = breaking/redesign. Increment
   `CURRENT_PROJECT_VERSION` on every install.
3. **Commit and push** the checkpoint (per global checkpoint-commit policy).
4. **Build Release and install**:
   ```
   xcodebuild -project powertoys.xcodeproj -scheme powertoys -configuration Release build
   osascript -e 'tell application "powertoys" to quit'   # transfers auto-pause and auto-resume
   rm -rf /Applications/PowerToys.app
   ditto <BUILT_PRODUCTS_DIR>/powertoys.app /Applications/PowerToys.app
   open /Applications/PowerToys.app
   ```
   Automatic signing (team GF57JXJF5A) — never pass CODE_SIGN_IDENTITY manually.
5. **Cleanup** — never leave versioned copies of the app anywhere (no
   PowerToys-1.x.app, no .zip exports). /Applications holds exactly one bundle.
   Purge this project's DerivedData when it exceeds a few GB:
   `rm -rf ~/Library/Developer/Xcode/DerivedData/powertoys-*` (forces a clean
   rebuild — do it between tasks, not mid-iteration).

Interrupting transfers is safe by design: quitting marks active transfers
paused with auto-resume-on-launch; the new build continues them with byte
baselines intact (append-basis, no recalculation).
