import AppKit

@main enum PanelTests {
    static func main() throws {
        _ = NSApplication.shared
        let domain = "QuickLookupBar.PanelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = SettingsStore(defaults: defaults)
        var opened: [URL] = []
        var transfers: [(String, String)] = []
        let panel = Panel(store: store, openURL: { opened.append($0); return true }, transferToApp: { transfers.append(($0, $1)) })
        panel.prepare()
        precondition(panel.selectedID == "monokakido")
        precondition(panel.field.stringValue.isEmpty && !panel.searchButton.isEnabled)
        precondition(panel.buttons.count == 7)
        func selectionKey(_ modifiers: NSEvent.ModifierFlags, code: UInt16 = 19) -> Bool {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil, characters: "2", charactersIgnoringModifiers: "2", isARepeat: false, keyCode: code)!
            return panel.handleSelectionKey(event)
        }
        for modifiers: NSEvent.ModifierFlags in [[], .command, .control, .option, [.shift, .command], [.shift, .control]] {
            precondition(!selectionKey(modifiers) && panel.selectedID == "monokakido")
        }
        precondition(selectionKey(.shift) && panel.selectedID == "chatgpt-web")
        precondition(opened.isEmpty && transfers.isEmpty)
        panel.select(id: "monokakido")
        precondition(selectionKey(.shift, code: 84) && panel.selectedID == "chatgpt-web")
        panel.prepare()
        precondition(panel.field.font?.fontName == "HiraMaruProN-W4")
        for (target, button) in zip(panel.targets, panel.buttons) {
            let width = (target.name as NSString).size(withAttributes: [.font: button.nameLabel.font!]).width + 4
            precondition(width <= button.nameLabel.frame.width, "Built-in label is clipped: \(target.name)")
        }
        var dismissed = 0
        panel.onDone = { dismissed += 1 }
        panel.field.stringValue = "fixture text"
        panel.updateSearchButton()
        precondition(panel.searchButton.isEnabled)
        panel.choose(panel.buttons[2])
        precondition(panel.selectedID == "claude")
        precondition(panel.field.stringValue == "fixture text" && dismissed == 0, "Selection must not submit")
        precondition(opened.isEmpty && transfers.isEmpty)
        panel.search()
        precondition(opened.count == 1 && opened[0].host == "claude.ai")
        precondition(panel.field.stringValue.isEmpty && dismissed == 1)
        panel.prepare()
        precondition(panel.field.stringValue.isEmpty && panel.selectedID == "monokakido")
        panel.field.stringValue = "fixture again"
        panel.closePanel()
        precondition(panel.field.stringValue.isEmpty && dismissed == 2)
        var reordered = store.settings
        reordered.targets.swapAt(0, 4)
        try store.save(reordered)
        panel.rebuild(); panel.prepare()
        precondition(panel.targets[0].id == "google" && panel.targets[0].shortcut == 5)
        precondition(panel.selectedID == "monokakido")
        precondition(panel.buttons[4].nameLabel.stringValue == "物書堂")
        panel.select(id: "chatgpt-dot"); panel.field.stringValue = "fixture app transfer"; panel.search()
        precondition(transfers.count == 1 && transfers[0].0 == "chatgpt-dot")
        var hidden = store.settings
        hidden.targets[hidden.targets.firstIndex { $0.id == "chatgpt-web" }!].enabled = false
        try store.save(hidden); panel.rebuild()
        precondition(!panel.mic.isEnabled, "Voice must honor disabled ChatGPT Web")
        var many = store.settings
        for number in 1...20 { many.targets.append(SettingsStore.newCustomTarget(name: "追加\(number)")) }
        try store.save(many); panel.rebuild()
        precondition(panel.view.frame.height <= 416)
        precondition(panel.view.subviews.compactMap { $0 as? NSScrollView }.first?.hasVerticalScroller == true)
        let editor = SettingsWindowController(store: store)
        editor.moveTargetDown()
        precondition(editor.draft.targets[1].id == "google")
        precondition(editor.draft.defaultTargetID == "monokakido")
        editor.cancelChanges()
        precondition(editor.draft == store.settings)
        precondition(opened.count == 1 && transfers.count == 1, "UI setup and settings must not send queries")
        print("PASS: native panel defaults, Shift+digits only (including keypad), clear-on-open/close, no-submit selection, fonts and label fit, reorder, disabled voice, scrolling, editor Cancel")
    }
}
