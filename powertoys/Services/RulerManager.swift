import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class RulerManager {
    static let shared = RulerManager()

    private(set) var rulers: [RulerState] = []
    private(set) var measurements: [RulerMeasurement] = []
    var style: RulerStyle { didSet { persist(); refreshPanels() } }
    var aspectRatio: Double?

    private var panels: [UUID: RulerOverlayPanel] = [:]
    private let defaults = UserDefaults.standard
    private let statesKey = "ruler.states.v1"
    private let styleKey = "ruler.style.v1"
    private let measurementsKey = "ruler.measurements.v1"

    private init() {
        if AppRuntime.isUITesting {
            style = RulerStyle()
            rulers = []
            measurements = []
        } else {
            style = Self.decode(RulerStyle.self, key: styleKey) ?? RulerStyle()
            rulers = Self.decode([RulerState].self, key: statesKey) ?? []
            measurements = Self.decode([RulerMeasurement].self, key: measurementsKey) ?? []
        }
        NotificationCenter.default.addObserver(forName: .toolActionRequested, object: nil, queue: .main) { [weak self] note in
            guard let self, let action = note.object as? ToolActionID else { return }
            Task { @MainActor [self, action] in self.handle(action) }
        }
        NotificationCenter.default.addObserver(forName: .commandOpenSettings, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self != nil, NSApp.keyWindow == nil else { return }
                ToolActionRouter.shared.execute(ToolActionRequest(action: .rulerSettings))
            }
        }
    }

    func restore() {
        for state in rulers where state.isVisible { show(state.id) }
    }

    func openSettings() {
        ToolActionRouter.shared.execute(ToolActionRequest(action: .rulerSettings))
    }

    func create(_ orientation: RulerOrientation) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? CGRect(x: 100, y: 100, width: 1200, height: 800)
        let size: CGSize = switch orientation {
        case .horizontal: CGSize(width: min(560, visible.width * 0.6), height: 54)
        case .vertical: CGSize(width: 54, height: min(560, visible.height * 0.65))
        case .joined: CGSize(width: min(560, visible.width * 0.6), height: min(340, visible.height * 0.5))
        }
        let origin = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        var state = RulerState(orientation: orientation, frame: CGRect(origin: origin, size: size), screenID: screen?.displayID)
        state.frame = clamped(state.frame, to: screen)
        rulers.append(state)
        persist()
        show(state.id)
    }

    func createPair() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? CGRect(x: 100, y: 100, width: 1200, height: 800)
        let horizontalSize = CGSize(width: min(560, visible.width * 0.6), height: 54)
        let verticalSize = CGSize(width: 54, height: min(560, visible.height * 0.65))
        let horizontalOrigin = CGPoint(
            x: visible.midX - horizontalSize.width / 2,
            y: visible.midY
        )
        let verticalOrigin = CGPoint(
            x: horizontalOrigin.x,
            y: horizontalOrigin.y - verticalSize.height + horizontalSize.height
        )
        let groupID = UUID()
        var horizontal = RulerState(
            orientation: .horizontal,
            frame: CGRect(origin: horizontalOrigin, size: horizontalSize),
            screenID: screen?.displayID
        )
        var vertical = RulerState(
            orientation: .vertical,
            frame: CGRect(origin: verticalOrigin, size: verticalSize),
            screenID: screen?.displayID
        )
        horizontal.groupID = groupID
        vertical.groupID = groupID
        horizontal.frame = clamped(horizontal.frame, to: screen)
        vertical.frame = clamped(vertical.frame, to: screen)
        rulers.append(contentsOf: [horizontal, vertical])
        persist()
        show(horizontal.id)
        show(vertical.id)
    }

    func show(_ id: UUID) {
        guard let index = rulers.firstIndex(where: { $0.id == id }) else { return }
        rulers[index].isVisible = true
        let requestedScreen = rulers[index].screenID.flatMap { savedID in
            NSScreen.screens.first { $0.displayID == savedID }
        }
        rulers[index].frame = clamped(rulers[index].frame, to: requestedScreen)
        rulers[index].screenID = (requestedScreen ?? NSScreen.screens.first(where: { $0.frame.intersects(rulers[index].frame) }) ?? NSScreen.main)?.displayID
        let state = rulers[index]
        let panel = panels[id] ?? RulerOverlayPanel(state: state, manager: self)
        panels[id] = panel
        panel.apply(state: state, style: style)
        panel.orderFrontRegardless()
        persist()
    }

    func hide(_ id: UUID) {
        guard let index = rulers.firstIndex(where: { $0.id == id }) else { return }
        rulers[index].isVisible = false
        panels[id]?.orderOut(nil)
        persist()
    }

    func remove(_ id: UUID) {
        panels.removeValue(forKey: id)?.close()
        rulers.removeAll { $0.id == id }
        persist()
    }

    func removeAll() {
        panels.values.forEach { $0.close() }
        panels.removeAll()
        rulers.removeAll()
        persist()
    }

    func updateFrame(id: UUID, frame: CGRect) {
        guard let index = rulers.firstIndex(where: { $0.id == id }) else { return }
        var next = frame
        if let ratio = aspectRatio, ratio > 0 { next.size.height = next.size.width / ratio }
        rulers[index].frame = clamped(next, to: panels[id]?.screen)
        panels[id]?.setFrame(rulers[index].frame, display: true)
        persist()
    }

    func setCalibration(_ value: Double, for screen: NSScreen?) {
        guard let id = screen?.displayID else {
            style.calibration = value
            return
        }
        style.displayCalibrations[String(id)] = value
    }

    func updateScreen(id: UUID, screen: NSScreen?) {
        guard let index = rulers.firstIndex(where: { $0.id == id }) else { return }
        rulers[index].screenID = screen?.displayID
        persist()
    }

    func setOriginAtPointer(_ id: UUID) {
        guard let index = rulers.firstIndex(where: { $0.id == id }) else { return }
        let pointer = NSEvent.mouseLocation
        var frame = rulers[index].frame
        switch rulers[index].orientation {
        case .horizontal: frame.origin.x = pointer.x
        case .vertical: frame.origin.y = pointer.y - frame.height
        case .joined: frame.origin = CGPoint(x: pointer.x, y: pointer.y - frame.height)
        }
        updateFrame(id: id, frame: frame)
    }

    func reset(_ id: UUID) {
        guard let index = rulers.firstIndex(where: { $0.id == id }) else { return }
        let orientation = rulers[index].orientation
        let screen = panels[id]?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 100, y: 100, width: 1200, height: 800)
        let size: CGSize = switch orientation {
        case .horizontal: CGSize(width: min(560, visible.width * 0.6), height: 54)
        case .vertical: CGSize(width: 54, height: min(560, visible.height * 0.65))
        case .joined: CGSize(width: min(560, visible.width * 0.6), height: min(340, visible.height * 0.5))
        }
        rulers[index].frame = CGRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        rulers[index].showsHorizontalArm = true
        rulers[index].showsVerticalArm = true
        panels[id]?.apply(state: rulers[index], style: style)
        persist()
    }

    func toggleArm(_ id: UUID, horizontal: Bool) {
        guard let index = rulers.firstIndex(where: { $0.id == id }), rulers[index].orientation == .joined else { return }
        if horizontal { rulers[index].showsHorizontalArm.toggle() }
        else { rulers[index].showsVerticalArm.toggle() }
        if !rulers[index].showsHorizontalArm && !rulers[index].showsVerticalArm {
            rulers[index].showsHorizontalArm = true
        }
        panels[id]?.apply(state: rulers[index], style: style)
        persist()
    }

    func groupVisible() {
        let id = UUID()
        for index in rulers.indices where rulers[index].isVisible { rulers[index].groupID = id }
        persist()
    }

    func isGrouped(_ id: UUID) -> Bool {
        rulers.first(where: { $0.id == id })?.groupID != nil
    }

    func ungroup(containing id: UUID) {
        guard let groupID = rulers.first(where: { $0.id == id })?.groupID else { return }
        for index in rulers.indices where rulers[index].groupID == groupID {
            rulers[index].groupID = nil
        }
        persist()
    }

    func ungroupAll() {
        for index in rulers.indices { rulers[index].groupID = nil }
        persist()
    }

    func moveGroup(containing id: UUID, delta: CGPoint) {
        guard let groupID = rulers.first(where: { $0.id == id })?.groupID else { return }
        for index in rulers.indices where rulers[index].groupID == groupID && rulers[index].id != id {
            rulers[index].x += delta.x
            rulers[index].y += delta.y
            panels[rulers[index].id]?.setFrameOrigin(rulers[index].frame.origin)
        }
        persist()
    }

    func copy(_ state: RulerState, as format: RulerCopyFormat) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(format.render(frame: state.frame), forType: .string)
    }

    func recordMeasurement(_ frame: CGRect) {
        measurements.insert(RulerMeasurement(frame: frame), at: 0)
        let pinned = measurements.filter(\.isPinned)
        measurements = pinned + Array(measurements.filter { !$0.isPinned }.prefix(max(0, 50 - pinned.count)))
        persist()
    }

    func toggleMeasurementPin(_ id: UUID) {
        guard let index = measurements.firstIndex(where: { $0.id == id }) else { return }
        measurements[index].isPinned.toggle()
        persist()
    }

    func removeMeasurement(_ id: UUID) {
        measurements.removeAll { $0.id == id }
        persist()
    }

    func clearMeasurements() {
        measurements.removeAll { !$0.isPinned }
        persist()
    }

    private func handle(_ action: ToolActionID) {
        switch action {
        case .rulerOpen: createPair()
        case .rulerNewHorizontal: create(.horizontal)
        case .rulerNewVertical: create(.vertical)
        case .rulerNewJoined: create(.joined)
        case .rulerMeasure: MeasurementOverlayController.shared.begin()
        default: break
        }
    }

    private func refreshPanels() {
        for state in rulers { panels[state.id]?.apply(state: state, style: style) }
    }

    private func persist() {
        guard !AppRuntime.isUITesting else { return }
        defaults.set(try? JSONEncoder().encode(rulers), forKey: statesKey)
        defaults.set(try? JSONEncoder().encode(style), forKey: styleKey)
        defaults.set(try? JSONEncoder().encode(measurements), forKey: measurementsKey)
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private func clamped(_ frame: CGRect, to requestedScreen: NSScreen?) -> CGRect {
        let screen = requestedScreen ?? NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }
        var result = frame
        result.size.width = min(max(result.width, 54), visible.width)
        result.size.height = min(max(result.height, 54), visible.height)
        result.origin.x = min(max(result.origin.x, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.origin.y, visible.minY), visible.maxY - result.height)
        return result
    }
}

extension NSScreen {
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
