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
  target="$repo_dir/raycast/assets/$2.png"
  output="$output_dir/$2.png"
  asset_dir="$repo_dir/powertoys/Assets.xcassets/$1.imageset"
  if [ -f "$asset_dir/icon.png" ]; then
    cp "$asset_dir/icon.png" "$output"
  else
    sips -s format png "$asset_dir/icon.svg" --out "$output" >/dev/null
  fi
  if [ "$mode" = "--check" ] && ! cmp -s "$output" "$target"; then
    echo "Stale Raycast icon: $2.png"
    status=1
  fi
}

render CloudSyncLogo cloud-sync
render LogsLogo logs
render RulerLogo ruler
render AwakeLogo awake
render ColorPickerLogo color-picker
render TextExtractorLogo text-extractor
render InputDevicesLogoA input-devices
render SystemCareLogo system-care
render DiskExplorerLogo disk-explorer
render SystemMonitorLogo system-monitor
render NetToysLogo nettoys

extension_source="$repo_dir/raycast/assets/extension-icon.svg"
extension_target="$repo_dir/raycast/assets/extension-icon.png"
extension_output="$output_dir/extension-icon.png"
sips -s format png "$extension_source" --out "$extension_output" >/dev/null
if [ "$mode" = "--check" ] && ! cmp -s "$extension_output" "$extension_target"; then
  echo "Stale Raycast icon: extension-icon.png"
  status=1
fi

exit "$status"
