#!/bin/zsh
# Fails when one Swift function resets Screen Recording with tccutil and then asks CoreGraphics again.
# CoreGraphics caches the Screen Recording answer per process, so that request never reaches macOS:
# no prompt, no new row in System Settings. Ask from a new process instead (PermissionCenter.fixScreenRecording).
# Usage: zsh scripts/check-screen-capture-reset.sh [swift files or folders, default powertoys]
(( $# )) || set -- "${0:A:h:h}/powertoys"
found=$(find "$@" -name '*.swift' -print0 | xargs -0 awk '
  /func / { depth = 0; infunc = 1; reset = 0; start = FNR }
  infunc {
    if ($0 ~ /tccutil/ && $0 ~ /ScreenCapture/) reset = 1
    if (reset && $0 ~ /CG(Request|Preflight)ScreenCaptureAccess/) { print FILENAME ":" start; reset = 0 }
    depth += gsub(/\{/, "{"); depth -= gsub(/\}/, "}")
    if (depth <= 0 && FNR > start) infunc = 0
  }')
if [[ -n "$found" ]]; then
  print -r -- "$found"
  echo "A Screen Recording request after tccutil reset in the same process does nothing. Relaunch the app and ask at launch."
  exit 1
fi
exit 0
