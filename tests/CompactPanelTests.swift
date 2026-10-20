import AppKit

@main enum CompactPanelTests {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let domain = "QuickLookupBar.CompactRegression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = SettingsStore(defaults: defaults)
        var urls: [URL] = []
        var transfers: [(String, String)] = []
        var dismissals = 0
        let panel = Panel(store: store, openURL: { urls.append($0); return true }, transferToApp: { transfers.append(($0, $1)) })
        panel.onDone = { dismissals += 1 }
        panel.prepare()
        let window = NSWindow(contentRect: panel.view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = panel.view
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        func snapshot(_ view: NSView, _ name: String) throws {
            guard CommandLine.arguments.count > 1 else { return }
            let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
        }
        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags, repeatKey: Bool = false) -> Bool {
            panel.handleSelectionKey(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "!", charactersIgnoringModifiers: "1", isARepeat: repeatKey, keyCode: code)!)
        }
        // All modifier combinations, both digit rows, and keys outside the mapping.
        let modifiers: [NSEvent.ModifierFlags] = [.shift, .command, .control, .option]
        let codes: [(UInt16, String)] = [(18,"monokakido"),(19,"chatgpt-web"),(20,"claude"),(21,"grok"),(23,"google"),(22,"chatgpt-dot"),(26,"grok-bot"),(83,"monokakido"),(84,"chatgpt-web"),(85,"claude"),(86,"grok"),(87,"google"),(88,"chatgpt-dot"),(89,"grok-bot")]
        for mask in 0..<16 {
            var flags: NSEvent.ModifierFlags = []
            for index in 0..<4 where mask & (1 << index) != 0 { flags.insert(modifiers[index]) }
            for (code, id) in codes {
                panel.select(id: "claude")
                let handled = key(code, flags)
                check(handled == (flags == .shift), "Incorrect modifiers accepted")
                check(panel.selectedID == (flags == .shift ? id : "claude"), "Selection changed for wrong modifiers")
            }
        }
        panel.select(id: "monokakido")
        check(key(19, [.shift, .numericPad]) && panel.selectedID == "chatgpt-web", "Numeric pad flag")
        check(key(18, .shift, repeatKey: true) && panel.selectedID == "chatgpt-web", "Repeat must not alter selection")
        for code: UInt16 in [0, 29, 25, 82, 92, 36, 53] { check(!key(code, .shift), "Unassigned key consumed") }
        check(urls.isEmpty && transfers.isEmpty, "Key selection sent a query")

        // Real field editor and marked text: Enter confirms IME without sending.
        panel.prepare(); window.makeFirstResponder(panel.field)
        let editor = panel.field.currentEditor() as! NSTextView
        editor.setMarkedText("変換中", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let newline = #selector(NSResponder.insertNewline(_:))
        check(!panel.control(panel.field, textView: editor, doCommandBy: newline), "IME Enter consumed")
        check(urls.isEmpty && transfers.isEmpty, "IME confirmation sent data")
        panel.prepare()
        check(panel.field.stringValue.isEmpty && editor.string.isEmpty && !editor.hasMarkedText(), "Reopen retained field editor/IME text")
        panel.field.stringValue = "日本語 & + ? # % 😀"
        panel.select(id: "monokakido")
        check(panel.control(panel.field, textView: editor, doCommandBy: newline), "Enter not handled")
        check(urls.count == 1 && urls[0].scheme == "mkdictionaries", "Enter route incorrect")
        check(URLComponents(url: urls[0], resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "日本語 & + ? # % 😀", "Query encoding lost text")
        check(panel.field.stringValue.isEmpty && !panel.searchButton.isEnabled, "Input not cleared after send")
        window.makeFirstResponder(nil)

        // Compact geometry, row boundaries, scrolling, longest built-in labels.
        for count in [1, 2, 3, 4, 7, 8, 9, 11, 12, 13, 20, 97] {
            var settings = AppSettings.defaults
            for index in settings.targets.indices { settings.targets[index].enabled = index < min(count, 7) }
            if count > 7 {
                for index in 7..<count { settings.targets.append(SettingsStore.newCustomTarget(name: "追加先\(index)")) }
            }
            try store.save(settings); panel.rebuild(); panel.prepare()
            check(panel.targets.count == count, "Target count incorrect")
            check(panel.view.frame.width == 680 && panel.view.frame.height <= 178, "Panel grew excessively")
            check(panel.field.frame.maxY < 54, "Input overlaps target rows")
            let scroll = panel.view.subviews.compactMap { $0 as? NSScrollView }.first!
            let document = scroll.documentView!
            let controls = panel.buttons + [panel.mic]
            check(scroll.hasVerticalScroller == (count + 1 > 12), "Wrong scroll threshold")
            check(scroll.frame.maxY < panel.statusLabel.frame.minY, "Footer overlap")
            for (index, button) in controls.enumerated() {
                check(document.bounds.contains(button.frame), "Button outside document")
                check(button.frame.height >= 28, "Target too small")
                for other in controls.dropFirst(index + 1) { check(!button.frame.intersects(other.frame), "Buttons overlap") }
                if index < count && panel.targets[index].isBuiltin {
                    let labelWidth = (button.nameLabel.stringValue as NSString).size(withAttributes: [.font: button.nameLabel.font!]).width
                    check(labelWidth <= button.nameLabel.frame.width, "Built-in label clipped")
                }
            }
            if scroll.hasVerticalScroller {
                document.scrollToVisible(panel.mic.frame)
                check(scroll.contentView.bounds.intersects(panel.mic.frame), "Last row not reachable")
            }
            if [1, 7, 13, 97].contains(count) { try snapshot(panel.view, "targets-\(count)") }
        }
        var custom = AppSettings.defaults
        let longName = String(repeating: "長い検索先の名前", count: 5)
        var added = SettingsStore.newCustomTarget(name: longName); added.shortcut = 9
        custom.targets.append(added); try store.save(custom)
        panel.rebuild(); panel.prepare()
        check(panel.buttons.last!.toolTip?.contains(longName) == true, "Truncated name lost accessible full name")
        check(key(25, .shift) && panel.selectedID == added.id, "Custom Shift+9")
        try snapshot(panel.view, "long-name-selected")
        custom.targets[1].enabled = false; try store.save(custom); panel.rebuild()
        check(!panel.mic.isEnabled && key(28, .shift) && !panel.listening, "Disabled voice activated")
        check(key(91, .shift) && !panel.listening, "Disabled keypad voice activated")

        // Every original destination, through injected local sinks only.
        try store.save(.defaults); panel.rebuild()
        let query = " fixture 日本語 & + 😀 "
        for target in panel.targets {
            let prior = urls.count + transfers.count
            panel.field.stringValue = query; panel.choose(panel.buttons[panel.targets.firstIndex(where: {$0.id == target.id})!])
            check(urls.count + transfers.count == prior, "Selection sent query")
            panel.search()
            check(urls.count + transfers.count == prior + 1, "Search did not route exactly once")
            check(panel.field.stringValue.isEmpty, "Completed search retained query")
        }
        check(transfers.map(\.0) == ["chatgpt-dot", "grok-bot"], "App destinations changed")
        let countBeforeEmpty = urls.count + transfers.count
        for empty in ["", " ", "\n\t"] { panel.field.stringValue = empty; panel.search() }
        check(urls.count + transfers.count == countBeforeEmpty, "Empty input sent")
        let failing = Panel(store: store, openURL: { _ in false }, transferToApp: { _, _ in fatalError("Unexpected app send") })
        failing.prepare(); failing.field.stringValue = "fixture"; failing.updateSearchButton(); failing.search()
        try snapshot(failing.view, "url-error")
        check(!failing.statusLabel.stringValue.isEmpty && failing.field.stringValue == "fixture", "Open failure lost query or error")
        let data = Data("invalid settings".utf8)
        defaults.set(data, forKey: SettingsStore.storageKey)
        let recovery = SettingsStore(defaults: defaults)
        let recoveredPanel = Panel(store: recovery, openURL: {_ in fatalError("Recovery sent")}, transferToApp: {_,_ in fatalError("Recovery sent")})
        recoveredPanel.prepare()
        try snapshot(recoveredPanel.view, "settings-error")
        check(recovery.loadError != nil && recoveredPanel.statusLabel.stringValue.contains("設定"), "Load error not visible")
        check(defaults.data(forKey: SettingsStore.storageKey) == data, "Recovery overwrote corrupt settings")
        // Construct under both system appearances: fixed Aqua text needs a light surface.
        for appearanceName: NSAppearance.Name in [.aqua, .darkAqua] {
            app.appearance = NSAppearance(named: appearanceName)
            var contrastPanel: Panel!
            NSAppearance(named: appearanceName)!.performAsCurrentDrawingAppearance {
                contrastPanel = Panel(store: store, openURL: {_ in false}, transferToApp: {_,_ in fatalError("Appearance sent")})
                contrastPanel.prepare()
            }
            let color = NSColor(cgColor: contrastPanel.view.layer!.backgroundColor!)!.usingColorSpace(.deviceRGB)!
            check(min(color.redComponent, color.greenComponent, color.blueComponent) > 0.9, "Dark appearance made Aqua text unreadable")
            try snapshot(contrastPanel.view, "appearance-\(appearanceName.rawValue)")
        }
        app.appearance = nil
        check(dismissals == 8, "Unexpected dismissal count")
        print("PASS: \(checks) compact panel regression checks; modifiers, IME, exact routes, 1–97 targets, geometry, scrolling, errors. Zero external requests.")
    }
}
