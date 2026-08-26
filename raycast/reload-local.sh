#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
extension_dir="$HOME/.config/raycast/extensions/macpowertoys"

[ -d "$extension_dir" ] || exit 0

if ! pgrep -x Raycast >/dev/null; then
  cd "$repo_dir/raycast"
  exec ./node_modules/.bin/ray build -e dev -o "$extension_dir"
fi

log_file=$(mktemp "${TMPDIR:-/tmp}/macpowertoys-raycast-reload.XXXXXX")
pid=
cleanup() {
  [ -z "$pid" ] || kill -INT "$pid" 2>/dev/null || true
  [ -z "$pid" ] || wait "$pid" 2>/dev/null || true
  rm -f "$log_file"
}
trap cleanup EXIT HUP INT TERM

(cd "$repo_dir/raycast" && exec ./node_modules/.bin/ray develop --non-interactive) >"$log_file" 2>&1 &
pid=$!
attempt=0
until grep -q "built extension successfully" "$log_file"; do
  if ! kill -0 "$pid" 2>/dev/null || [ "$attempt" -ge 300 ]; then
    cat "$log_file"
    exit 1
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done

echo "Reloaded the local MacPowerToys Raycast extension."
