// Proves the demo build's side-effect wall. Built by scripts/demo-safety.sh from the app's own
// DemoSafety.swift and DemoMode.swift with MPT_DEMO set, so the same shadows and stubs run here.
// Writers that are safe to call are called and checked for no effect; writers that would show UI or
// change login items are checked by proving their method implementation was replaced.

import AppKit
import CoreAudio
import IOKit.pwr_mgt
import ObjectiveC
import ServiceManagement
import UserNotifications

var failures = 0
func check(_ ok: Bool, _ name: String) {
    print(ok ? "ok    \(name)" : "FAIL  \(name)")
    if !ok { failures += 1 }
}

let replaced: [(AnyClass, String, Bool)] = [
    (NSClassFromString("NSConcreteTask")!, "launchAndReturnError:", false),
    (NSPasteboard.self, "generalPasteboard", true),
    (NSWorkspace.self, "openURL:", false),
    (NSWorkspace.self, "openURL:configuration:completionHandler:", false),
    (NSWorkspace.self, "openApplicationAtURL:configuration:completionHandler:", false),
    (NSWorkspace.self, "openURLs:withApplicationAtURL:configuration:completionHandler:", false),
    (NSWorkspace.self, "selectFile:inFileViewerRootedAtPath:", false),
    (NSWorkspace.self, "activateFileViewerSelectingURLs:", false),
    (NSRunningApplication.self, "terminate", false),
    (NSRunningApplication.self, "forceTerminate", false),
    (NSRunningApplication.self, "activateWithOptions:", false),
    (NSApplication.self, "activate", false),
    (NSApplication.self, "activateIgnoringOtherApps:", false),
    (SMAppService.self, "registerAndReturnError:", false),
    (SMAppService.self, "unregisterAndReturnError:", false),
    (SMAppService.self, "unregisterWithCompletionHandler:", false),
    (UNUserNotificationCenter.self, "addNotificationRequest:withCompletionHandler:", false),
    (UNUserNotificationCenter.self, "requestAuthorizationWithOptions:completionHandler:", false),
    (NSXPCConnection.self, "initWithMachServiceName:options:", false),
]
func implementation(_ cls: AnyClass, _ selector: String, _ classMethod: Bool) -> IMP? {
    let target: AnyClass = classMethod ? object_getClass(cls)! : cls
    return class_getMethodImplementation(target, NSSelectorFromString(selector))
}
let before = replaced.map { implementation($0.0, $0.1, $0.2) }
DemoSafety.install()
for (index, entry) in replaced.enumerated() {
    check(implementation(entry.0, entry.1, entry.2) != before[index], "stubbed \(entry.1)")
}

let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("mpt-demo-safety-\(getpid())")
try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }

// Process: rclone, git, defaults, killall all start through NSTask.
let marker = scratch.appendingPathComponent("touched")
let touch = Process()
touch.executableURL = URL(fileURLWithPath: "/usr/bin/touch")
touch.arguments = [marker.path]
check((try? touch.run()) == nil && !FileManager.default.fileExists(atPath: marker.path), "Process.run never starts a process")

// Clipboard.
let realBoard = NSPasteboard(name: .general)
let realCount = realBoard.changeCount
NSPasteboard.general.clearContents()
NSPasteboard.general.setString("demo", forType: .string)
check(realBoard.changeCount == realCount && NSPasteboard.general.name == DemoSafety.pasteboardName,
      "NSPasteboard.general writes a private pasteboard, the real clipboard is untouched")

// Signals: a real child process survives the shadowed kill().
var child: pid_t = 0
let argv: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/sleep"), strdup("30"), nil]
posix_spawn(&child, "/bin/sleep", nil, nil, argv, nil)
check(kill(child, SIGTERM) == -1 && Darwin.kill(child, 0) == 0, "kill() never signals another process")
check(kill(child, 0) == 0, "kill(pid, 0) still answers whether a process exists")
Darwin.kill(child, SIGKILL)
var status: Int32 = 0
waitpid(child, &status, 0)

// Preferences of other apps (Dock, Finder, global domain).
let domain = "com.surajmandal.macpowertoys.demo-safety-probe" as CFString
CFPreferencesSetAppValue("probe" as CFString, "x" as CFString, domain)
CFPreferencesSetValue("probe2" as CFString, "x" as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
check(CFPreferencesCopyAppValue("probe" as CFString, domain) == nil
      && CFPreferencesCopyValue("probe2" as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) == nil,
      "CFPreferencesSet* never writes")

// Awake and sleep.
var assertion = IOPMAssertionID(0)
let created = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                          IOPMAssertionLevel(kIOPMAssertionLevelOn), "demo-safety" as CFString, &assertion)
check(created != kIOReturnSuccess && assertion == 0, "IOPMAssertionCreateWithName never holds the Mac awake")
check(IOPMSleepSystem(0) != kIOReturnSuccess && DemoSafety.count("power.sleep") == 1, "IOPMSleepSystem never sleeps the Mac")

// Fan helper install and calls.
check(!SMJobBless(kSMDomainSystemLaunchd, "com.surajmandal.macpowertoys.helper" as CFString, nil, nil)
      && DemoSafety.count("helper.install") == 1, "SMJobBless never installs the helper")
let helper = NSXPCConnection(machServiceName: "com.surajmandal.macpowertoys.helper", options: .privileged)
check(DemoSafety.count("xpc.helper") == 1 && helper.serviceName != "com.surajmandal.macpowertoys.helper",
      "the helper connection goes to a name nobody serves")
helper.invalidate()

// Audio input device (Mic Lock).
var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                         mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var device = AudioObjectID(0)
let audio = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                       UInt32(MemoryLayout<AudioObjectID>.size), &device)
check(audio != noErr && DemoSafety.count("audio.write") == 1, "AudioObjectSetPropertyData never changes the input device")

// Extended attributes (DevSync link markers).
FileManager.default.createFile(atPath: marker.path, contents: Data())
let value = "x"
check(setxattr(marker.path, "com.surajmandal.demo-probe", value, 1, 0, 0) == -1
      && getxattr(marker.path, "com.surajmandal.demo-probe", nil, 0, 0, 0) == -1, "setxattr never writes")
check(removexattr(marker.path, "com.apple.quarantine", 0) == -1 && DemoSafety.count("file.xattr") == 2, "removexattr never writes")

// Opening links and apps: no app may open, so only safe targets are tried.
check(!NSWorkspace.shared.open(URL(fileURLWithPath: "/nonexistent-mpt-demo-safety"))
      && DemoSafety.count("workspace.open") == 1, "NSWorkspace.open never opens anything")
check(!NSRunningApplication.current.terminate() && DemoSafety.count("app.terminate") == 1, "NSRunningApplication.terminate never quits an app")

check(DemoMode.blocks("probe") && DemoSafety.count("probe") == 1, "DemoMode.blocks records and blocks")

print(failures == 0 ? "demo safety: all checks passed" : "demo safety: \(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
