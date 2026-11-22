//
//  DemoSafety.swift
//  powertoys
//
//  The demo build's side-effect wall. Nothing here exists outside `make demo`.
//  Cocoa writers are replaced at runtime (install()), C writers are shadowed at module level below,
//  so every call in the app resolves to a stub. scripts/demo-safety.sh tests both and audits call sites.
//

#if MPT_DEMO
import AppKit
import CoreAudio
import IOKit.pwr_mgt
import ObjectiveC
import ServiceManagement
import UserNotifications

nonisolated enum DemoSafety {
    static let pasteboardName = NSPasteboard.Name("com.surajmandal.macpowertoys.demo.pasteboard")
    static let blockedError = NSError(domain: "MacPowerToysDemo", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "The demo build does not change your Mac."])
    private static let lock = NSLock()
    nonisolated(unsafe) private static var counts: [String: Int] = [:]

    static func record(_ effect: String) {
        lock.withLock { counts[effect, default: 0] += 1 }
    }

    static func count(_ effect: String) -> Int {
        lock.withLock { counts[effect] ?? 0 }
    }

    /// Call once, first thing at launch.
    static func install() { _ = installed }

    private static let installed: Void = {
        typealias OpenHandler = @convention(block) (NSRunningApplication?, NSError?) -> Void

        // Processes: rclone, rsync, git, ssh, defaults, killall, lsof never start.
        let launch: @convention(block) (NSObject, AutoreleasingUnsafeMutablePointer<NSError?>?) -> ObjCBool = { _, error in
            record("process.launch")
            error?.pointee = blockedError
            return false
        }
        let launchLegacy: @convention(block) (NSObject) -> Void = { _ in record("process.launch") }
        for name in ["NSTask", "NSConcreteTask"] {
            replace(NSClassFromString(name), NSSelectorFromString("launchAndReturnError:"), with: launch)
            replace(NSClassFromString(name), NSSelectorFromString("launch"), with: launchLegacy)
        }

        // Clipboard: every NSPasteboard.general use lands on a private pasteboard.
        let demoBoard = NSPasteboard(name: pasteboardName)
        let general: @convention(block) (AnyObject) -> NSPasteboard = { _ in
            record("pasteboard.general")
            return demoBoard
        }
        replace(NSPasteboard.self, NSSelectorFromString("generalPasteboard"), classMethod: true, with: general)

        // Other apps, links, Finder, and System Settings never open; other apps never quit.
        let openURL: @convention(block) (NSObject, NSURL) -> ObjCBool = { _, _ in record("workspace.open"); return false }
        let openWithConfiguration: @convention(block) (NSObject, NSURL, NSObject, OpenHandler?) -> Void = { _, _, _, done in
            record("workspace.open")
            done?(nil, blockedError)
        }
        let openURLsWithApp: @convention(block) (NSObject, NSArray, NSURL, NSObject, OpenHandler?) -> Void = { _, _, _, _, done in
            record("workspace.open")
            done?(nil, blockedError)
        }
        let selectFile: @convention(block) (NSObject, NSString?, NSString) -> ObjCBool = { _, _, _ in
            record("workspace.reveal")
            return false
        }
        let reveal: @convention(block) (NSObject, NSArray) -> Void = { _, _ in record("workspace.reveal") }
        replace(NSWorkspace.self, NSSelectorFromString("openURL:"), with: openURL)
        replace(NSWorkspace.self, NSSelectorFromString("openURL:configuration:completionHandler:"), with: openWithConfiguration)
        replace(NSWorkspace.self, NSSelectorFromString("openApplicationAtURL:configuration:completionHandler:"),
                with: openWithConfiguration)
        replace(NSWorkspace.self, NSSelectorFromString("openURLs:withApplicationAtURL:configuration:completionHandler:"),
                with: openURLsWithApp)
        replace(NSWorkspace.self, NSSelectorFromString("selectFile:inFileViewerRootedAtPath:"), with: selectFile)
        replace(NSWorkspace.self, NSSelectorFromString("activateFileViewerSelectingURLs:"), with: reveal)

        let refuse: @convention(block) (NSObject) -> ObjCBool = { _ in record("app.terminate"); return false }
        replace(NSRunningApplication.self, NSSelectorFromString("terminate"), with: refuse)
        replace(NSRunningApplication.self, NSSelectorFromString("forceTerminate"), with: refuse)
        let refuseActivate: @convention(block) (NSObject, UInt) -> ObjCBool = { _, _ in record("app.activate"); return false }
        replace(NSRunningApplication.self, NSSelectorFromString("activateWithOptions:"), with: refuseActivate)

        // The demo app never takes focus from the owner's front app.
        let noActivate: @convention(block) (NSObject) -> Void = { _ in record("app.activate") }
        let noActivateIgnoring: @convention(block) (NSObject, ObjCBool) -> Void = { _, _ in record("app.activate") }
        replace(NSApplication.self, NSSelectorFromString("activate"), with: noActivate)
        replace(NSApplication.self, NSSelectorFromString("activateIgnoringOtherApps:"), with: noActivateIgnoring)

        // Login items, notifications.
        let serviceChange: @convention(block) (NSObject, AutoreleasingUnsafeMutablePointer<NSError?>?) -> ObjCBool = { _, error in
            record("login-item.change")
            error?.pointee = blockedError
            return false
        }
        let serviceUnregister: @convention(block) (NSObject, (@convention(block) (NSError?) -> Void)?) -> Void = { _, done in
            record("login-item.change")
            done?(blockedError)
        }
        replace(SMAppService.self, NSSelectorFromString("registerAndReturnError:"), with: serviceChange)
        replace(SMAppService.self, NSSelectorFromString("unregisterAndReturnError:"), with: serviceChange)
        replace(SMAppService.self, NSSelectorFromString("unregisterWithCompletionHandler:"), with: serviceUnregister)

        let notify: @convention(block) (NSObject, NSObject, (@convention(block) (NSError?) -> Void)?) -> Void = { _, _, done in
            record("notification.post")
            done?(blockedError)
        }
        let authorize: @convention(block) (NSObject, UInt, (@convention(block) (ObjCBool, NSError?) -> Void)?) -> Void = { _, _, done in
            record("notification.authorize")
            done?(false, blockedError)
        }
        replace(UNUserNotificationCenter.self, NSSelectorFromString("addNotificationRequest:withCompletionHandler:"), with: notify)
        replace(UNUserNotificationCenter.self, NSSelectorFromString("requestAuthorizationWithOptions:completionHandler:"), with: authorize)

        // The privileged fan helper: any mach service of ours resolves to a name nobody serves, so every call fails.
        let initMach = NSSelectorFromString("initWithMachServiceName:options:")
        if let method = class_getInstanceMethod(NSXPCConnection.self, initMach) {
            typealias Original = @convention(c) (AnyObject, Selector, NSString, UInt) -> AnyObject
            let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
            let redirect: @convention(block) (AnyObject, NSString, UInt) -> AnyObject = { connection, name, options in
                guard name.hasPrefix("com.surajmandal.") else { return original(connection, initMach, name, options) }
                record("xpc.helper")
                return original(connection, initMach, "com.surajmandal.macpowertoys.demo.no-service", options)
            }
            method_setImplementation(method, imp_implementationWithBlock(redirect))
        }
    }()

    private static func replace(_ cls: AnyClass?, _ selector: Selector, classMethod: Bool = false, with block: Any) {
        guard let cls, let target: AnyClass = classMethod ? object_getClass(cls) : cls,
              let method = class_getInstanceMethod(target, selector) else { return }
        let stub = imp_implementationWithBlock(block)
        // Overrides an inherited method on this class only; replaces one this class defines itself.
        if !class_addMethod(target, selector, stub, method_getTypeEncoding(method)) {
            method_setImplementation(method, stub)
        }
    }
}

// C writers. A module-level function shadows the imported one, so every unqualified call in the app lands here.

nonisolated func kill(_ pid: pid_t, _ signal: Int32) -> Int32 {
    // Signal 0 only asks whether a process exists.
    if signal == 0 { return Darwin.kill(pid, 0) }
    DemoSafety.record("process.signal")
    errno = EPERM
    return -1
}

nonisolated func CFPreferencesSetValue(_ key: CFString, _ value: CFPropertyList?, _ applicationID: CFString,
                                       _ userName: CFString, _ hostName: CFString) {
    DemoSafety.record("preferences.write")
}

nonisolated func CFPreferencesSetAppValue(_ key: CFString, _ value: CFPropertyList?, _ applicationID: CFString) {
    DemoSafety.record("preferences.write")
}

nonisolated func IOPMAssertionCreateWithName(_ type: CFString!, _ level: IOPMAssertionLevel, _ name: CFString!,
                                             _ assertionID: UnsafeMutablePointer<IOPMAssertionID>!) -> IOReturn {
    DemoSafety.record("power.assertion")
    return kIOReturnNotPermitted
}

nonisolated func IOPMSleepSystem(_ connection: io_connect_t) -> IOReturn {
    DemoSafety.record("power.sleep")
    return kIOReturnNotPermitted
}

nonisolated func SMJobBless(_ domain: CFString!, _ label: CFString, _ authorization: AuthorizationRef?,
                            _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool {
    DemoSafety.record("helper.install")
    return false
}

nonisolated func AudioObjectSetPropertyData(_ objectID: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
                                            _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?,
                                            _ dataSize: UInt32, _ data: UnsafeRawPointer) -> OSStatus {
    DemoSafety.record("audio.write")
    return OSStatus(kAudioHardwareIllegalOperationError)
}

nonisolated func setxattr(_ path: UnsafePointer<CChar>!, _ name: UnsafePointer<CChar>!, _ value: UnsafeRawPointer!,
                          _ size: Int, _ position: UInt32, _ options: Int32) -> Int32 {
    DemoSafety.record("file.xattr")
    errno = EPERM
    return -1
}

nonisolated func removexattr(_ path: UnsafePointer<CChar>!, _ name: UnsafePointer<CChar>!, _ options: Int32) -> Int32 {
    DemoSafety.record("file.xattr")
    errno = EPERM
    return -1
}
#endif
