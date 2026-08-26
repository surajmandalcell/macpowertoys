#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
mode=${1:-write}
status=0

if [ "$mode" = "--check" ]; then
  output_dir=$(mktemp -d "${TMPDIR:-/tmp}/macpowertoys-raycast-icons.XXXXXX")
  trap 'rm -rf "$output_dir"' EXIT
else
  output_dir="$repo_dir/raycast/assets"
fi

render() {
  source="$repo_dir/powertoys/Assets.xcassets/$1.imageset/icon.svg"
  target="$repo_dir/raycast/assets/$2.png"
  output="$output_dir/$2.png"
  sips -s format png "$source" --out "$output" >/dev/null
  if [ "$mode" = "--check" ] && ! cmp -s "$output" "$target"; then
    echo "Stale Raycast icon: $2.png"
    status=1
  fi
}

render ClaudeHistoryLogo ai-history
render CloudSyncLogo cloud-sync
render LogsLogo logs
render RulerLogo ruler
render AwakeLogo awake
render ColorPickerLogo color-picker
render TextExtractorLogo text-extractor
render InputDevicesLogoA input-devices
render SystemCareLogo system-care
render SystemMonitorLogo system-monitor
render NetToysLogo nettoys

exit "$status"
