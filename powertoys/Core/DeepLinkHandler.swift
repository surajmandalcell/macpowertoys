//
//  DeepLinkHandler.swift
//  powertoys
//

import Foundation
import SwiftUI
import Darwin

nonisolated struct NetToysScanPrefill: Equatable, Sendable {
    let targets: String
    let ports: String?

    static func parse(_ url: URL) -> Self? {
        guard DeepLinkHandler.isSupportedScheme(url.scheme),
              url.host == "open",
              url.pathComponents.first(where: { $0 != "/" }) == "nettoys",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let targetValue = items.first(where: { $0.name == "targets" })?.value
        else { return nil }
        let targets = targetValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targets.isEmpty,
              targets.utf8.count <= 8_192,
              (try? NetToysTargetInput.parse(targets)) != nil
        else { return nil }
        let ports = items.first(where: { $0.name == "ports" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard ports?.utf8.count ?? 0 <= 4_096,
              ports.map({ (try? PortList.parse($0)) != nil }) ?? true
        else { return nil }
        return Self(targets: targets, ports: ports)
    }
}

extension Notification.Name {
    static let netToysPrefill = Notification.Name("netToysPrefill")
}

@Observable
@MainActor
final class DeepLinkHandler {
    static let shared = DeepLinkHandler()

    private var pendingLinks: [URL] = []
    private var openWindowAction: OpenWindowAction?
    private var pendingNetToysPrefill: NetToysScanPrefill?

    private init() {}

    func setOpenWindowAction(_ action: OpenWindowAction) {
        guard openWindowAction == nil else { return }
        self.openWindowAction = action
        ToolActionRouter.shared.configure(openWindow: action)
        processPendingLinks()
    }

    func handle(url: URL) {
        LogManager.shared.info("Handling deep link: \(url.absoluteString)", source: "DeepLinkHandler")

        guard Self.isSupportedScheme(url.scheme) else {
            LogManager.shared.warning("Invalid scheme: \(url.scheme ?? "nil")", source: "DeepLinkHandler")
            return
        }

        guard openWindowAction != nil else {
            pendingLinks.append(url)
            LogManager.shared.debug("Queued pending link: \(url)", source: "DeepLinkHandler")
            return
        }

        processURL(url)
    }

    nonisolated static func isSupportedScheme(_ scheme: String?) -> Bool {
        scheme == "macpowertoys" || scheme == "powertoys"
    }

    func handleCLIArguments(_ args: [String] = CommandLine.arguments) {
        LogManager.shared.debug("Processing CLI arguments: \(args)", source: "DeepLinkHandler")

        if let openIndex = args.firstIndex(of: "--open"),
           args.count > openIndex + 1 {
            let toolId = args[openIndex + 1]
            openTool(id: toolId)
        }

        if let actionIndex = args.firstIndex(of: "--action"), args.count > actionIndex + 1,
           let action = ToolActionID(rawValue: args[actionIndex + 1]) {
            ToolActionRouter.shared.execute(ToolActionRequest(action: action))
        }

        if SettingsManager.shared.isToolEnabled("awake")
            && (args.contains("--awake") || args.contains("--time-limit") || args.contains("--expire-at")) {
            let displayOn = value(after: "--display-on", in: args).flatMap(Bool.init) ?? false
            AwakeService.shared.setKeepDisplayOn(displayOn)
            if let seconds = value(after: "--time-limit", in: args).flatMap(TimeInterval.init) {
                AwakeService.shared.setMode(.timed, duration: seconds)
            } else if let value = value(after: "--expire-at", in: args), let date = Self.parseDate(value) {
                AwakeService.shared.setMode(.until, until: date)
            } else {
                AwakeService.shared.setMode(.indefinite)
            }
            if let process = value(after: "--pid", in: args).flatMap(Int32.init) {
                AwakeService.shared.attach(to: process)
            } else if args.contains("--use-parent-pid") {
                AwakeService.shared.attach(to: getppid())
            }
        }
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        if let exact = arguments.firstIndex(of: flag), arguments.indices.contains(exact + 1) {
            return arguments[exact + 1]
        }
        return arguments.first { $0.hasPrefix("\(flag)=") }.map { String($0.dropFirst(flag.count + 1)) }
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.date(from: value)
    }

    func processPendingLinks() {
        guard openWindowAction != nil else { return }

        for url in pendingLinks {
            processURL(url)
        }
        pendingLinks.removeAll()
    }

    func takeNetToysPrefill() -> NetToysScanPrefill? {
        defer { pendingNetToysPrefill = nil }
        return pendingNetToysPrefill
    }

    private func processURL(_ url: URL) {
        if ToolActionRouter.shared.execute(url: url) { return }

        switch url.host {
        case "open":
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            if let toolId = pathComponents.first {
                if toolId == "nettoys", let prefill = NetToysScanPrefill.parse(url) {
                    pendingNetToysPrefill = prefill
                    openTool(id: toolId)
                    NotificationCenter.default.post(name: .netToysPrefill, object: prefill)
                    return
                }
                openTool(id: toolId)
            }

        default:
            LogManager.shared.warning("Unknown deep link host: \(url.host ?? "nil")", source: "DeepLinkHandler")
        }
    }

    private func openTool(id toolId: String) {
        LogManager.shared.info("Opening tool via deep link: \(toolId)", source: "DeepLinkHandler")
        ToolActionRouter.shared.open(toolID: toolId)
    }
}
