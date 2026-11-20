#!/bin/zsh
# Exits 1 when RSync UI has a transfer that rclone is really running.
# A "running" entry blocks when it has moved bytes, or when an rclone daemon is busy.
# A queued, paused, failed, or 0-byte running entry with an idle rclone does not block:
# the app resumes it after relaunch, and no data is in flight.
store="$HOME/Library/Application Support/MacPowerToys/transfers.json"
[[ -f "$store" ]] || exit 0

running=$(jq '[.[] | select(.state == "running")] | length' "$store")
moved=$(jq '[.[] | select(.state == "running" and (.bytes // 0) > 0)] | length' "$store")
(( running == 0 )) && exit 0
if (( moved > 0 )); then
  echo "Refusing: $moved RSync UI transfer(s) are moving data. Wait for them to finish."
  exit 1
fi

cpu_seconds() {
  ps -o time= -p "$1" 2>/dev/null | awk -F: '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; print s }'
}

for pid in $(pgrep -f "rclone rcd"); do
  before=$(cpu_seconds "$pid")
  sleep 3
  after=$(cpu_seconds "$pid")
  [[ -z "$before" || -z "$after" ]] && continue
  if (( after - before > 0.05 )); then
    echo "Refusing: rclone daemon $pid is busy while $running transfer(s) show running."
    exit 1
  fi
done

echo "Ignoring $running running entr(ies) with 0 bytes: no rclone daemon is busy."
exit 0
