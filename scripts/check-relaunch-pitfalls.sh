#!/bin/zsh
# Two pitfalls that broke Text Extractor's Fix button. Fails on either.
# 1. One Swift function resets Screen Recording with tccutil and then asks CoreGraphics again.
#    CoreGraphics caches the answer per process, so that request never reaches macOS: no prompt, no row.
#    Ask from a new process instead (PermissionCenter.fixScreenRecording).
# 2. NSApp.terminate called from a Task (here: outside AppDelegate.swift and Views/). Its wait loop blocks the
#    main actor, so the quit steps never run and the app hangs.
#    Use NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0).
# Usage: zsh scripts/check-relaunch-pitfalls.sh [swift files or folders, default powertoys]
(( $# )) || set -- "${0:A:h:h}/powertoys"
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
if [[ -n "$found" ]]; then
  print -r -- "$found"
  echo "See the comments at the top of scripts/check-relaunch-pitfalls.sh for the fix."
  exit 1
fi
exit 0
