#!/bin/zsh
# Builds the demo window capture tool. Output never goes into the repo.
set -euo pipefail
out="${1:-${AGENT_DATA_DIR:-/Volumes/External1TB/data/_custom/claude}/powertoys/demo-capture/demo-capture}"
mkdir -p "${out:h}"
xcrun swiftc -O -o "$out" "${0:A:h}/main.swift"
echo "$out"
