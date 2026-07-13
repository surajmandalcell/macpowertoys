import AppKit
import Foundation
import SwiftUI

enum ToolActionID: String, CaseIterable, Codable, Sendable {
    case rulerOpen = "ruler.open"
    case rulerNewHorizontal = "ruler.new-horizontal"
    case rulerNewVertical = "ruler.new-vertical"
    case rulerNewJoined = "ruler.new-joined"
    case rulerMeasure = "ruler.measure"
    case awakeOpen = "awake.open"
    case awakeToggle = "awake.toggle"
    case awakeIndefinite = "awake.indefinite"
    case awakeTimed = "awake.timed"
    case awakeUntil = "awake.until"
    case colorPickerPick = "color-picker.pick"
    case colorPickerHistory = "color-picker.history"
    case colorPickerCopyLast = "color-picker.copy-last"
    case textExtractorCapture = "text-extractor.capture"
    case textExtractorOpen = "text-extractor.open"

    var toolID: String {
        rawValue.split(separator: ".").first.map(String.init) ?? rawValue
    }

    var opensWindow: Bool {
        switch self {
        case .rulerOpen, .awakeOpen, .colorPickerHistory, .textExtractorOpen:
            true
        default:
            false
        }
    }
}

struct ToolActionRequest: Equatable, Sendable {
    let action: ToolActionID
    var parameters: [String: String] = [:]
}

extension Notification.Name {
    static let toolActionRequested = Notification.Name("toolActionRequested")
}

@Observable
@MainActor
final class ToolActionRouter {
    static let shared = ToolActionRouter()

    private var openWindowAction: OpenWindowAction?
    private var pending: [ToolActionRequest] = []

    private init() {}

    func configure(openWindow: OpenWindowAction) {
        openWindowAction = openWindow
        let requests = pending
        pending.removeAll()
        requests.forEach(execute)
    }

    func execute(_ request: ToolActionRequest) {
        guard openWindowAction != nil else {
            if pending.last != request { pending.append(request) }
            return
        }

        if request.action.opensWindow {
            openWindowAction?(id: request.action.toolID)
            NSApp.activate(ignoringOtherApps: true)
        }

        NotificationCenter.default.post(
            name: .toolActionRequested,
            object: request.action,
            userInfo: request.parameters
        )
    }

    func execute(url: URL) -> Bool {
        guard DeepLinkHandler.isSupportedScheme(url.scheme), url.host == "run" else { return false }
        let components = url.pathComponents.filter { $0 != "/" }
        guard let value = components.first,
              let action = ToolActionID(rawValue: value.replacingOccurrences(of: "/", with: "."))
        else { return false }

        let parameters = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .reduce(into: [String: String]()) { result, item in
                if let value = item.value { result[item.name] = value }
            } ?? [:]
        execute(ToolActionRequest(action: action, parameters: parameters))
        return true
    }
}
