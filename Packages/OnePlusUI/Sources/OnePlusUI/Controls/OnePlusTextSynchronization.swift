import AppKit

@MainActor
final class OnePlusTextSynchronization {
    private var pending: (String, String?)?
    private var resourceID: String?
    private var selections: [String: NSRange] = [:]
    private(set) var replacing = false

    func update(_ value: String, in editor: NSTextView, resourceID nextID: String? = nil) {
        guard !replacing else { return }
        if editor.hasMarkedText() {
            if value != editor.string || nextID != resourceID { pending = (value, nextID) }
            return
        }
        pending = nil
        replace(value, in: editor, resourceID: nextID)
    }

    func applyPending(in editor: NSTextView) {
        guard !replacing, !editor.hasMarkedText(), let (value, id) = pending else { return }
        pending = nil
        replace(value, in: editor, resourceID: id)
    }

    private func replace(_ value: String, in editor: NSTextView, resourceID nextID: String?) {
        let changedResource = nextID != resourceID
        guard value != editor.string || changedResource else { return }
        replacing = true
        defer { replacing = false }
        var selection = editor.selectedRange()
        if changedResource {
            if let resourceID { selections[resourceID] = selection }
            selection = nextID.flatMap { selections[$0] } ?? NSRange(location: 0, length: 0)
            resourceID = nextID
            editor.undoManager?.removeAllActions()
            editor.string = value
        } else {
            editor.undoManager?.beginUndoGrouping()
            editor.insertText(value, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
            editor.undoManager?.endUndoGrouping()
        }
        let length = (editor.string as NSString).length
        let location = min(selection.location, length)
        editor.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
    }
}

extension NSTextView {
    func useOnePlusTextSelection() {
        selectedTextAttributes = [.backgroundColor: NSColor(OnePlusColor.accent).withAlphaComponent(0.28),
                                  .foregroundColor: NSColor(OnePlusColor.ink)]
    }
}
