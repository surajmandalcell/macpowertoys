#!/bin/sh
set -eu

# Build the local extension into Raycast's extension folder. Never use
# `ray develop` here: it registers a second, development copy of the same
# extension, and every command then appears twice in Raycast.
repo_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
extension_dir="$HOME/.config/raycast/extensions/macpowertoys"

mkdir -p "$extension_dir"
cd "$repo_dir/raycast"
./node_modules/.bin/ray build -e dev -o "$extension_dir"
for source_map in "$extension_dir"/*.js.map; do
  [ -e "$source_map" ] || break
  [ -f "${source_map%.map}" ] || rm -f "$source_map"
done
echo "Built the local MacPowerToys Raycast extension into $extension_dir."
