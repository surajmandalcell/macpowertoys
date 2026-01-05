//
//  WindowAccessor.swift
//  powertoys
//

import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowAccessorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class WindowAccessorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = window else { return }
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
    }
}
