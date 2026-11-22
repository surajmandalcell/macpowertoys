#!/bin/zsh
# Proves the demo build cannot change the Mac. Run by `make demo`; pass the built demo app to also check it.
#  1. Builds and runs scripts/demo-safety/main.swift against the app's own DemoSafety.swift (the runtime wall).
#  2. Audits every writer call site in powertoys/: each one must go through a wall stub or sit in a file whose
#     demo guard is named below. A new writer in an unlisted file fails the audit.
#  3. Checks the demo app's name, bundle id, and URL schemes, so it never shares state with the real app.
set -u
repo=${0:A:h:h}
src="$repo/powertoys"
fail=0
note() { print -r -- "$1"; }
bad() { print -r -- "FAIL  $1"; fail=1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/mpt-demo-safety.XXXXXX")
trap 'rm -rf "$work"' EXIT
if xcrun swiftc -swift-version 5 -D MPT_DEMO -o "$work/demo-safety" \
    "$src/Core/DemoMode.swift" "$src/Demo/DemoSafety.swift" "$repo/scripts/demo-safety/main.swift" 2>"$work/build.log"; then
  "$work/demo-safety" || fail=1
else
  cat "$work/build.log"; bad "safety test did not compile"
fi

sites() { grep -rnE --include='*.swift' "$1" "$src" | grep -v "^$src/Demo/" | sed "s#^$src/##"; }

# Qualified calls skip the module-level shadows. Allowed only where the target is a Process this app
# started itself, which never exists in the demo because Process.run is stubbed.
for line in ${(f)"$(sites 'Darwin\.kill\(')"}; do
  case ${line%%:*} in
    Core/SSHProcessRunner.swift|Core/FanControlService.swift|Portman/PortmanService.swift) ;;
    *) bad "unshadowed kill: $line" ;;
  esac
done
for line in ${(f)"$(sites '(CoreFoundation\.CFPreferencesSet|IOKit\.IOPM|Darwin\.(setxattr|removexattr)|CoreAudio\.AudioObjectSet|ServiceManagement\.SMJobBless)')"}; do
  [[ -n $line ]] && bad "qualified call skips the shadow: $line"
done
for line in ${(f)"$(sites '(posix_spawn|popen\(|execv[a-z]*\(|[^a-zA-Z_.]fork\(\)|NSAppleScript|NSPasteboard\(name: *\.general\)|[=({ ;]system\("|CGWarpMouseCursorPosition|IOHIDSetParameter|IORegistryEntrySetCFPropert)')"}; do
  [[ -n $line ]] && bad "writer with no demo stub: $line"
done
for line in ${(f)"$(sites 'NSWorkspace\.shared\.[a-zA-Z]+')"}; do
  method=$(print -r -- "$line" | grep -oE 'NSWorkspace\.shared\.[a-zA-Z]+' | head -1)
  case ${method##*.} in
    open|openApplication|selectFile|activateFileViewerSelecting|notificationCenter|runningApplications|frontmostApplication|urlForApplication|icon) ;;
    *) bad "NSWorkspace method with no demo stub: $line" ;;
  esac
done

# Writers the runtime wall cannot see. Each file names the guard that keeps the writer from running in the
# demo, or why its path is inside the demo sandbox (AppDataLocation is MacPowerToys-Demo there).
typeset -A guards=(
  Core/GlobalShortcutManager.swift      'DemoMode.blocks("'
  Core/InputDevicesManager.swift        'DemoMode.blocks("'
  Core/DeepLinkHandler.swift            'DemoMode.blocks("deep-link")'
  Core/MarketplaceInstaller.swift       'sandbox: reached only from MarketplaceManager.installTool, which DemoMode blocks'
  Core/MarketplaceManager.swift         'DemoMode.blocks("marketplace.install")'
  Core/OrderedAtomicFileWriter.swift    'sandbox: callers write transfers and local changes under AppDataLocation'
  Core/ResourceDiagnostics.swift        'sandbox: AppDataLocation/diagnostics'
  Core/ActivationDiagnostics.swift      'sandbox: AppDataLocation/diagnostics'
  Core/AppDataLocation.swift            'sandbox: the data folder itself'
  Core/SSHProcessRunner.swift           'sandbox: askpass script in the temporary folder'
  Portman/PortmanServerMonitor.swift    'sandbox: its own SSH control sockets; ssh never starts'
  Portman/PortmanRestart.swift          'DemoMode.blocks("'
  Services/RcloneDaemon.swift           'DemoMode.blocks("'
  Services/RcloneJobManager.swift       'sandbox: preview cache in the temporary folder'
  Services/ColorPickerService.swift     'DemoMode.blocks("'
  Views/Logs/LogsWindowView.swift       'DemoMode.blocks("'
  Views/Rclone/RemoteBrowserView.swift  'DemoMode.blocks("'
)
for line in ${(f)"$(sites '(\.write\(to:|\.write\(toFile:|FileManager\.default\.(removeItem|moveItem|trashItem|copyItem|createFile|setAttributes|createSymbolicLink)|CGEvent\.tapCreate)')"}; do
  [[ -z $line ]] && continue
  file=${line%%:*}
  if [[ $file == Services/DevSync/* ]]; then
    grep -q 'DemoMode' "$src/Services/DevSync/DevSyncService.swift" || bad "DevSync writer while DevSyncService has no demo guard: $line"
    continue
  fi
  rule=${guards[$file]-}
  if [[ -z $rule ]]; then bad "unclassified writer: $line"; continue; fi
  if [[ $rule != sandbox:* ]] && ! grep -qF -- "$rule" "$src/$file"; then bad "missing demo guard $rule in $file"; fi
done

# Entry points that change hardware or system input: each must open with a DemoMode guard.
# The owner forbids any fan mode change from the demo.
typeset -a entries=(
  'Core/FanControlService.swift:func select('
  'Core/FanControlService.swift:func selectFromLink('
  'Core/FanControlService.swift:func restoreSavedPreset('
  'Core/FanControlService.swift:func restoreAutomaticOnExit('
  'Core/FanHelperService.swift:func install('
)
for entry in $entries; do
  file=${entry%%:*}; name=${entry#*:}
  num=$(grep -nF -- "$name" "$src/$file" | head -1 | cut -d: -f1)
  if [[ -z $num ]]; then bad "entry point not found: $entry"; continue; fi
  sed -n "${num},$(( num + 4 ))p" "$src/$file" | grep -q 'DemoMode' || bad "no DemoMode guard at the top of $entry"
done
for line in ${(f)"$(sites 'CGEvent\.tapCreate')"}; do
  [[ -z $line ]] && continue
  file=${line%%:*}; rest=${line#*:}; num=${rest%%:*}
  sed -n "$(( num > 25 ? num - 25 : 1 )),${num}p" "$src/$file" | grep -q 'DemoMode' || bad "event tap with no demo guard above it: $line"
done

if (( $# > 0 )); then
  app=$1
  plist="$app/Contents/Info.plist"
  [[ $(plutil -extract CFBundleIdentifier raw "$plist") == com.surajmandal.macpowertoys.demo ]] || bad "demo bundle id"
  [[ $(plutil -extract CFBundleDisplayName raw "$plist") == "MacPowerToys Demo" ]] || bad "demo display name"
  schemes=$(plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes json -o - "$plist")
  [[ $schemes == '["macpowertoys.demo","powertoys.demo"]' ]] || bad "demo URL schemes: $schemes"
  strings "$app/Contents/MacOS/MacPowerToys Demo" | grep -q 'MacPowerToys-Demo' || bad "demo binary has no demo data folder"
  codesign --verify --deep --strict "$app" || bad "demo signature"
fi

(( fail == 0 )) && note "demo safety audit: passed" || note "demo safety audit: FAILED"
exit $fail
