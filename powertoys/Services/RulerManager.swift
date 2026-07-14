import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class RulerManager {
    static let shared = RulerManager()
    private static let layoutVersion = 3

    private(set) var rulers: [RulerState] = []
    private(set) var measurements: [RulerMeasurement] = []
    var style: RulerStyle { didSet { persist(); refreshPanels() } }
    var aspectRatio: Double?

    private var panels: [UUID: RulerOverlayPanel] = [:]
    private var keyMonitor: Any?
    private let defaults = UserDefaults.standard
    private let statesKey = "ruler.states.v1"
    private let styleKey = "ruler.style.v1"
    private let measurementsKey = "ruler.measurements.v1"
    private let layoutVersionKey = "ruler.layoutVersion"

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
        if !AppRuntime.isRunningTests, defaults.integer(forKey: layoutVersionKey) < Self.layoutVersion {
            normalizeStandardThicknesses()
            normalizeGroupedPairs(minimumDefaultLengths: true)
            defaults.set(Self.layoutVersion, forKey: layoutVersionKey)
            persist()
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock) == .command,
                  let identifier = NSApp.keyWindow?.identifier?.rawValue,
                  Self.isRulerWindowIdentifier(identifier)
            else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "q": self?.closeTool()
            case "w": self?.closeWindow(identifier: identifier)
            default: return event
            }
            return nil
        }
    }

    func restore() {
        normalizeGroupedPairs()
        for state in rulers where state.isVisible { show(state.id) }
    }

    func openSettings() {
        ToolActionRouter.shared.execute(ToolActionRequest(action: .rulerSettings))
    }

    func openTool() {
        guard !rulers.isEmpty else {
            createPair()
            return
        }
        normalizeGroupedPairs()
        let visibleIDs = rulers.filter(\.isVisible).map(\.id)
        let ids = visibleIDs.isEmpty ? rulers.map(\.id) : visibleIDs
        ids.forEach(show)
        if let id = ids.first { focus(id) }
    }

    func create(_ orientation: RulerOrientation) {
        let screen = targetScreen
        let visible = screen?.visibleFrame ?? CGRect(x: 100, y: 100, width: 1200, height: 800)
        let size = defaultSize(for: orientation, in: visible)
        let origin = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        var state = RulerState(orientation: orientation, frame: CGRect(origin: origin, size: size), screenID: screen?.displayID)
        state.frame = clamped(state.frame, to: screen)
        rulers.append(state)
        persist()
        show(state.id)
        focus(state.id)
    }

    func createPair() {
        let screen = targetScreen
        let visible = screen?.visibleFrame ?? CGRect(x: 100, y: 100, width: 1200, height: 800)
        let horizontalSize = defaultSize(for: .horizontal, in: visible)
        let verticalSize = defaultSize(for: .vertical, in: visible)
        let horizontalOrigin = CGPoint(
            x: visible.midX - (horizontalSize.width - verticalSize.width) / 2,
            y: visible.midY - horizontalSize.height + verticalSize.height / 2
        )
        let verticalOrigin = CGPoint(
            x: horizontalOrigin.x - verticalSize.width,
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
        focus(horizontal.id)
    }

    func show(_ id: UUID) {
        guard let index = rulers.firstIndex(where: { $0.id == id }) else { return }
        rulers[index].isVisible = true
        let requestedScreen = rulers[index].screenID.flatMap { savedID in
            NSScreen.screens.first { $0.displayID == savedID }
        }
        rulers[index].frame = clamped(rulers[index].frame, to: requestedScreen)
        rulers[index].screenID = (requestedScreen ?? NSScreen.screens.first(where: { $0.frame.intersects(rulers[index].frame) }) ?? NSScreen.main)?.displayID
        if AppRuntime.isRunningTests && !AppRuntime.isUITesting { return }
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

    func closeTool() {
        panels.values.forEach { $0.orderOut(nil) }
        NSApp.windows.first { $0.identifier?.rawValue == "ruler" }?.close()
    }

    func closeWindow(identifier: String) {
        if identifier == "ruler" {
            NSApp.windows.first { $0.identifier?.rawValue == identifier }?.close()
            return
        }
        guard let id = UUID(uuidString: String(identifier.dropFirst("ruler.".count))),
              let state = rulers.first(where: { $0.id == id })
        else { return }
        let ids = state.groupID.map { groupID in
            rulers.filter { $0.groupID == groupID }.map(\.id)
        } ?? [id]
        for index in rulers.indices where ids.contains(rulers[index].id) {
            rulers[index].isVisible = false
            panels[rulers[index].id]?.orderOut(nil)
        }
        persist()
    }

    nonisolated static func isRulerWindowIdentifier(_ identifier: String?) -> Bool {
        identifier == "ruler" || identifier?.hasPrefix("ruler.") == true
    }

    func updateFrame(id: UUID, frame: CGRect, persistChanges: Bool = true) {
        guard let index = rulers.firstIndex(where: { $0.id == id }) else { return }
        var next = frame
        if let ratio = aspectRatio, ratio > 0 { next.size.height = next.size.width / ratio }
        rulers[index].frame = clamped(next, to: panels[id]?.screen)
        panels[id]?.setFrame(rulers[index].frame, display: false)
        if persistChanges { persist() }
    }

    func setSize(_ id: UUID, width: Double? = nil, height: Double? = nil) {
        guard let state = rulers.first(where: { $0.id == id }) else { return }
        var frame = state.frame
        if let width, width.isFinite { frame.size.width = max(RulerGeometry.thickness, width) }
        if let height, height.isFinite { frame.size.height = max(RulerGeometry.thickness, height) }
        updateFrame(id: id, frame: frame, persistChanges: false)
        normalizeGroupedPairs()
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
        guard let state = rulers.first(where: { $0.id == id }) else { return }
        let groupID = state.groupID
        for index in rulers.indices where rulers[index].id == id || groupID != nil && rulers[index].groupID == groupID {
            let rulerScreen = panels[rulers[index].id]?.screen
                ?? (rulers[index].id == id ? screen : nil)
                ?? NSScreen.screens.first { $0.frame.intersects(rulers[index].frame) }
            rulers[index].screenID = rulerScreen?.displayID
        }
        normalizeGroupedPairs()
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
        let size = defaultSize(for: orientation, in: visible)
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
        normalizeGroupedPairs()
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

    func moveGroup(containing id: UUID, delta: CGPoint, persistChanges: Bool = true) {
        guard let groupID = rulers.first(where: { $0.id == id })?.groupID else { return }
        for index in rulers.indices where rulers[index].groupID == groupID && rulers[index].id != id {
            rulers[index].x += delta.x
            rulers[index].y += delta.y
            panels[rulers[index].id]?.setFrameOrigin(rulers[index].frame.origin)
        }
        if persistChanges { persist() }
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
        case .rulerOpen: openTool()
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
        guard !AppRuntime.isRunningTests else { return }
        defaults.set(try? JSONEncoder().encode(rulers), forKey: statesKey)
        defaults.set(try? JSONEncoder().encode(style), forKey: styleKey)
        defaults.set(try? JSONEncoder().encode(measurements), forKey: measurementsKey)
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func defaultSize(for orientation: RulerOrientation, in visibleFrame: CGRect) -> CGSize {
        let fraction = min(max(style.defaultSizeFraction, 0.1), 1)
        return switch orientation {
        case .horizontal: CGSize(width: max(RulerGeometry.thickness, visibleFrame.width * fraction), height: RulerGeometry.thickness)
        case .vertical: CGSize(width: RulerGeometry.thickness, height: max(RulerGeometry.thickness, visibleFrame.height * fraction))
        case .joined: CGSize(
            width: max(RulerGeometry.thickness, visibleFrame.width * fraction),
            height: max(RulerGeometry.thickness, visibleFrame.height * fraction)
        )
        }
    }

    private func normalizeStandardThicknesses() {
        for index in rulers.indices {
            switch rulers[index].orientation {
            case .horizontal: rulers[index].height = RulerGeometry.thickness
            case .vertical: rulers[index].width = RulerGeometry.thickness
            case .joined: break
            }
        }
    }

    func normalizeGroupedPairs(minimumDefaultLengths: Bool = false) {
        for groupID in Set(rulers.compactMap(\.groupID)) {
            let indices = rulers.indices.filter { rulers[$0].groupID == groupID }
            guard indices.count == 2,
                  let horizontalIndex = indices.first(where: { rulers[$0].orientation == .horizontal }),
                  let verticalIndex = indices.first(where: { rulers[$0].orientation == .vertical })
            else { continue }

            let savedScreenID = rulers[horizontalIndex].screenID ?? rulers[verticalIndex].screenID
            let screen = savedScreenID.flatMap { id in NSScreen.screens.first { $0.displayID == id } }
                ?? NSScreen.screens.first { $0.frame.intersects(rulers[horizontalIndex].frame) }
                ?? targetScreen
            let visible = screen?.visibleFrame ?? CGRect(x: 100, y: 100, width: 1200, height: 800)
            var horizontal = rulers[horizontalIndex].frame
            var vertical = rulers[verticalIndex].frame
            horizontal.size.height = RulerGeometry.thickness
            vertical.size.width = RulerGeometry.thickness
            if minimumDefaultLengths {
                horizontal.size.width = max(horizontal.width, defaultSize(for: .horizontal, in: visible).width)
                vertical.size.height = max(vertical.height, defaultSize(for: .vertical, in: visible).height)
            }
            vertical.origin = CGPoint(
                x: horizontal.minX - RulerGeometry.thickness,
                y: horizontal.maxY - vertical.height
            )

            let union = horizontal.union(vertical)
            let dx = union.width <= visible.width
                ? min(max(visible.minX - union.minX, 0), visible.maxX - union.maxX)
                : visible.minX - union.minX
            let dy = union.height <= visible.height
                ? min(max(visible.minY - union.minY, 0), visible.maxY - union.maxY)
                : visible.minY - union.minY
            horizontal = horizontal.offsetBy(dx: dx, dy: dy)
            vertical = vertical.offsetBy(dx: dx, dy: dy)

            rulers[horizontalIndex].frame = horizontal
            rulers[verticalIndex].frame = vertical
            rulers[horizontalIndex].screenID = screen?.displayID
            rulers[verticalIndex].screenID = screen?.displayID
            panels[rulers[horizontalIndex].id]?.setFrame(horizontal, display: false)
            panels[rulers[verticalIndex].id]?.setFrame(vertical, display: false)
        }
    }

    private func focus(_ id: UUID) {
        guard (!AppRuntime.isRunningTests || AppRuntime.isUITesting), let panel = panels[id] else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func clamped(_ frame: CGRect, to requestedScreen: NSScreen?) -> CGRect {
        let screen = requestedScreen ?? NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }
        var result = frame
        result.size.width = min(max(result.width, RulerGeometry.thickness), visible.width)
        result.size.height = min(max(result.height, RulerGeometry.thickness), visible.height)
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
