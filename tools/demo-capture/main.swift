// demo-capture: records one MacPowerToys Demo window to ProRes 4444 with alpha, 2x, 60 fps.
//
// Usage:
//   demo-capture --out clip.mov (--window-id N | --scene-file scene.json | --bundle-id ID --title TEXT)
//                [--duration 8] [--timeout 20] [--allow-any-app]
// The filter holds exactly one window (desktop independent), so no desktop, menu bar, wallpaper,
// or other window can be in a frame. The window shadow is kept and the background is transparent.
// Only windows of com.surajmandal.macpowertoys.demo are accepted unless --allow-any-app is passed.
// With --scene-file it waits for the file DemoDirector writes and stops when it says done:true
// (or at --duration, whichever comes first). Needs Screen Recording permission; it never prompts,
// never activates an app, never moves the pointer. Build: tools/demo-capture/build.sh [output path].

import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit

let demoBundleID = "com.surajmandal.macpowertoys.demo"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("demo-capture: \(message)\n".utf8))
    exit(1)
}

var options: [String: String] = [:]
var flags = Set<String>()
var argIterator = CommandLine.arguments.dropFirst().makeIterator()
while let arg = argIterator.next() {
    guard arg.hasPrefix("--") else { fail("unexpected argument \(arg)") }
    if arg == "--allow-any-app" { flags.insert(arg); continue }
    guard let value = argIterator.next() else { fail("\(arg) needs a value") }
    options[arg] = value
}

guard let outPath = options["--out"] else { fail("--out <file.mov> is required") }
let outURL = URL(fileURLWithPath: outPath)
let timeout = Double(options["--timeout"] ?? "20") ?? 20
let duration = options["--duration"].flatMap(Double.init)
let sceneFile = options["--scene-file"].map { URL(fileURLWithPath: $0) }
guard duration != nil || sceneFile != nil else { fail("give --duration, or --scene-file to stop when the scene is done") }
let maxDuration = duration ?? 60

func readScene() -> [String: Any]? {
    guard let sceneFile, let data = try? Data(contentsOf: sceneFile) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

func waitUntil(_ seconds: Double, what: String, _ check: () async -> Bool) async {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if await check() { return }
        try? await Task.sleep(for: .milliseconds(200))
    }
    fail("\(what) not found within \(Int(seconds)) s")
}

guard CGPreflightScreenCaptureAccess() else {
    fail("no Screen Recording permission for this terminal. Grant it in System Settings > Privacy & Security.")
}

var windowID = options["--window-id"].flatMap(CGWindowID.init)
if windowID == nil, sceneFile != nil {
    await waitUntil(timeout, what: "scene file \(sceneFile!.path)") {
        guard let windows = readScene()?["windows"] as? [[String: Any]],
              let number = windows.first?["number"] as? Int else { return false }
        windowID = CGWindowID(number)
        return true
    }
}
let titleNeedle = options["--title"]
let bundleNeedle = options["--bundle-id"]
guard windowID != nil || (titleNeedle != nil && bundleNeedle != nil) else {
    fail("choose the window with --window-id, --scene-file, or --bundle-id plus --title")
}

var target: SCWindow?
await waitUntil(timeout, what: "the window") {
    let content: SCShareableContent
    do {
        content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    } catch {
        fail("cannot list windows (\(error.localizedDescription)). Screen Recording permission is likely missing.")
    }
    target = content.windows.first { window in
        if let windowID { return window.windowID == windowID }
        return window.owningApplication?.bundleIdentifier == bundleNeedle
            && (window.title ?? "").localizedCaseInsensitiveContains(titleNeedle!)
    }
    return target != nil
}
let window = target!
let owner = window.owningApplication?.bundleIdentifier ?? "unknown"
guard owner == demoBundleID || flags.contains("--allow-any-app") else {
    fail("window \(window.windowID) belongs to \(owner), not \(demoBundleID). Pass --allow-any-app to override.")
}

let filter = SCContentFilter(desktopIndependentWindow: window)
let pixelScale = 2.0  // Forced 2x so clips match on any display.
let width = Int((filter.contentRect.width * pixelScale).rounded())
let height = Int((filter.contentRect.height * pixelScale).rounded())
guard width > 0, height > 0 else { fail("window \(window.windowID) has no size") }

let config = SCStreamConfiguration()
config.width = width
config.height = height
config.pixelFormat = kCVPixelFormatType_32BGRA
config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
config.showsCursor = false
config.backgroundColor = .clear
config.shouldBeOpaque = false
config.ignoreShadowsSingleWindow = false
config.capturesAudio = false
config.queueDepth = 8

try? FileManager.default.removeItem(at: outURL)
let writer: AVAssetWriter
do { writer = try AVAssetWriter(outputURL: outURL, fileType: .mov) } catch { fail("cannot create \(outPath): \(error.localizedDescription)") }
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.proRes4444,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
])
input.expectsMediaDataInRealTime = true
guard writer.canAdd(input) else { fail("the writer refused the ProRes 4444 input") }
writer.add(input)
guard writer.startWriting() else { fail("writer failed to start: \(writer.error?.localizedDescription ?? "unknown")") }

final class FrameSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    var started = false
    var frames = 0
    var dropped = 0
    var streamError: Error?

    init(writer: AVAssetWriter, input: AVAssetWriterInput) {
        self.writer = writer
        self.input = input
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        if !started {
            writer.startSession(atSourceTime: buffer.presentationTimeStamp)
            started = true
        }
        if input.isReadyForMoreMediaData, input.append(buffer) { frames += 1 } else { dropped += 1 }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { streamError = error }
}

let queue = DispatchQueue(label: "demo-capture.frames")
let sink = FrameSink(writer: writer, input: input)
let stream = SCStream(filter: filter, configuration: config, delegate: sink)
do {
    try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: queue)
    try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
        stream.startCapture { error in error.map { done.resume(throwing: $0) } ?? done.resume() }
    }
} catch {
    fail("capture did not start: \(error.localizedDescription)")
}
print("demo-capture: recording window \(window.windowID) (\(owner)) at \(width)x\(height), 60 fps")

let stopAt = Date().addingTimeInterval(maxDuration)
while Date() < stopAt {
    if let error = queue.sync(execute: { sink.streamError }) { fail("stream stopped: \(error.localizedDescription)") }
    if duration == nil, readScene()?["done"] as? Bool == true { break }
    try? await Task.sleep(for: .milliseconds(100))
}

await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
    stream.stopCapture { _ in done.resume() }
}
let (frames, dropped, started) = queue.sync { (sink.frames, sink.dropped, sink.started) }
guard started else { fail("no complete frame arrived; the window may be hidden or minimized") }
input.markAsFinished()
await writer.finishWriting()
guard writer.status == .completed else { fail("writer failed: \(writer.error?.localizedDescription ?? "unknown")") }
print("demo-capture: wrote \(frames) frames (\(dropped) dropped) to \(outPath)")
