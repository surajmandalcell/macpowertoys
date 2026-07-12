//
//  DeepLinkHandler.swift
//  powertoys
//

import Foundation
import SwiftUI

@Observable
@MainActor
final class DeepLinkHandler {
    static let shared = DeepLinkHandler()

    private var pendingLinks: [URL] = []
    private var openWindowAction: OpenWindowAction?

    private init() {}

    func setOpenWindowAction(_ action: OpenWindowAction) {
        self.openWindowAction = action
        processPendingLinks()
    }

    func handle(url: URL) {
        LogManager.shared.info("Handling deep link: \(url.absoluteString)", source: "DeepLinkHandler")

        guard url.scheme == "powertoys" else {
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

    func handleCLIArguments(_ args: [String] = CommandLine.arguments) {
        LogManager.shared.debug("Processing CLI arguments: \(args)", source: "DeepLinkHandler")

        if let openIndex = args.firstIndex(of: "--open"),
           args.count > openIndex + 1 {
            let toolId = args[openIndex + 1]
            openTool(id: toolId)
        }
    }

    func processPendingLinks() {
        guard openWindowAction != nil else { return }

        for url in pendingLinks {
            processURL(url)
        }
        pendingLinks.removeAll()
    }

    private func processURL(_ url: URL) {
        switch url.host {
        case "open":
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            if let toolId = pathComponents.first {
                openTool(id: toolId)
            }

        default:
            LogManager.shared.warning("Unknown deep link host: \(url.host ?? "nil")", source: "DeepLinkHandler")
        }
    }

    private func openTool(id toolId: String) {
        LogManager.shared.info("Opening tool via deep link: \(toolId)", source: "DeepLinkHandler")

        guard let action = openWindowAction else {
            LogManager.shared.warning("OpenWindowAction not available", source: "DeepLinkHandler")
            return
        }

        let windowId: String?
        switch toolId {
        case "cc-history", "cchistory":
            windowId = "cc-history"
        case "rclone", "cloud-sync", "cloudsync", "rsync":
            windowId = "rclone"
        case "logs":
            windowId = "logs"
        case "main", "settings", "home":
            windowId = "main"
        default:
            windowId = ToolRegistry.tool(for: toolId) != nil ? toolId : nil
        }

        guard let windowId else {
            LogManager.shared.warning("Unknown tool ID: \(toolId)", source: "DeepLinkHandler")
            return
        }

        action(id: windowId)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
