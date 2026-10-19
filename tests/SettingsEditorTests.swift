import AppKit

@main
enum SettingsWindowSmoke {
    static func main() throws {
        _ = NSApplication.shared
        let domain = "QuickLookupBar.SettingsWindowSmoke." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = SettingsStore(defaults: defaults)
        let editor = SettingsWindowController(store: store)
        editor.settingsContentView.appearance = NSAppearance(named: .aqua)
        editor.window?.displayIfNeeded()
        let view = editor.settingsContentView
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        let original = store.settings
        editor.moveTargetDown()
        precondition(editor.draft.targets[1].id == "monokakido")
        precondition(editor.draft.defaultTargetID == "monokakido")
        precondition(editor.draft.targets[1].shortcut == 1)
        editor.enabledButton.state = .off
        editor.editorChanged()
        editor.saveChanges()
        precondition(store.settings == original, "Invalid default must not persist")
        precondition(!editor.errorLabel.stringValue.isEmpty)
        editor.cancelChanges()
        precondition(editor.draft == original)
        editor.addCustomTarget()
        precondition(editor.draft.targets.count == 8)
        editor.nameField.stringValue = "辞書テスト"
        editor.templateField.stringValue = "http://invalid.example/?q={query}"
        editor.shortcutPopup.selectItem(at: 8)
        editor.editorChanged()
        editor.saveChanges()
        precondition(store.settings == original, "Invalid URL must not persist")
        precondition(!editor.errorLabel.stringValue.isEmpty)
        editor.templateField.stringValue = "https://example.com/search?q={query}"
        editor.editorChanged()
        editor.saveChanges()
        precondition(store.settings.targets.count == 8)
        precondition(store.settings.targets.last?.name == "辞書テスト")
        precondition(store.settings.targets.last?.shortcut == 9)
        precondition(store.settings.defaultTargetID == "monokakido")
        let reloaded = SettingsStore(defaults: defaults)
        precondition(reloaded.settings == store.settings)
        print("Settings editor smoke checks passed: stable reorder/default/key, invalid default/URL atomic rejection, Cancel, valid custom Save/reload.")
    }
}
