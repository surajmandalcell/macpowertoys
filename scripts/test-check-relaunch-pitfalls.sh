#!/bin/zsh
# Self-test for check-relaunch-pitfalls.sh: a direct permission ask outside PermissionCenter.swift fails, inside passes.
check="${0:A:h}/check-relaunch-pitfalls.sh"
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
mkdir -p "$dir/bad" "$dir/good"
print 'func ask() { _ = CGRequestScreenCaptureAccess(); open("x-apple.systempreferences:Privacy_ScreenCapture") }' > "$dir/bad/Feature.swift"
print 'func ask() { _ = CGRequestScreenCaptureAccess() }' > "$dir/good/PermissionCenter.swift"
zsh "$check" "$dir/bad/Feature.swift" >/dev/null && { echo "FAIL: direct ask outside PermissionCenter.swift passed"; exit 1 }
zsh "$check" "$dir/good/PermissionCenter.swift" >/dev/null || { echo "FAIL: ask inside PermissionCenter.swift failed"; exit 1 }
echo "check-relaunch-pitfalls self-test passed"
