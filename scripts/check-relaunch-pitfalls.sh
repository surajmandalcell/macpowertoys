#!/bin/zsh
# Two pitfalls that broke Text Extractor's Fix button. Fails on either.
# 1. One Swift function resets Screen Recording with tccutil and then asks CoreGraphics again.
#    CoreGraphics caches the answer per process, so that request never reaches macOS: no prompt, no row.
#    Ask from a new process instead (PermissionCenter.fixScreenRecording).
# 2. NSApp.terminate called from a Task (here: outside AppDelegate.swift and Views/). Its wait loop blocks the
#    main actor, so the quit steps never run and the app hangs.
#    Use NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0).
# 3. An app folder (Info.plist beside Swift files) whose NSPrincipalClass is not our NSApplication subclass
#    that ends sheets in terminate. AppKit silently refuses every quit while a sheet is open, before the
#    delegate runs, so the permission reopen hangs. Use MacPowerToysApplication.swift.
# Usage: zsh scripts/check-relaunch-pitfalls.sh [swift files or folders, default powertoys]
(( $# )) || set -- "${0:A:h:h}/powertoys"
for dir in "$@"; do
  [[ -d $dir && -f $dir/Info.plist ]] || continue
  principal=$(/usr/libexec/PlistBuddy -c 'Print :NSPrincipalClass' "$dir/Info.plist" 2>/dev/null)
  file=$(grep -rl --include='*.swift' "final class ${principal:-none}: NSApplication" "$dir" | head -1)
  if [[ -z $file ]] || ! grep -q 'endSheet' "$file"; then
    print -r -- "$dir/Info.plist: NSPrincipalClass must name an NSApplication subclass that ends sheets in terminate"
    failed=1
  fi
done
found=$(find "$@" -name '*.swift' -print0 | xargs -0 awk '
  /func / { depth = 0; infunc = 1; reset = 0; start = FNR }
  infunc {
    if ($0 ~ /tccutil/ && $0 ~ /ScreenCapture/) reset = 1
    if (reset && $0 ~ /CG(Request|Preflight)ScreenCaptureAccess/) { print FILENAME ":" FNR ": Screen Recording request after tccutil reset"; reset = 0 }
    depth += gsub(/\{/, "{"); depth -= gsub(/\}/, "}")
    if (depth <= 0 && FNR > start) infunc = 0
  }
  # Menu, button, and AppDelegate handlers run from an event; any other caller may be inside a Task.
  /NSApp(lication\.shared)?\.terminate\(/ && FILENAME !~ /(AppDelegate\.swift|\/Views\/)/ {
    print FILENAME ":" FNR ": direct NSApp.terminate outside an event handler"
  }
')
if [[ -n "$found" || -n "$failed" ]]; then
  [[ -n "$found" ]] && print -r -- "$found"
  echo "See the comments at the top of scripts/check-relaunch-pitfalls.sh for the fix."
  exit 1
fi
exit 0
