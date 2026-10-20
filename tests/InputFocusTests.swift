import AppKit

@main enum InputFocusTests {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let domain = "QuickLookupBar.InputFocusTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = SettingsStore(defaults: defaults)
        let delegate = AppDelegate(store: store)
        let window = delegate.prepareFloatingWindow()
        let panel = delegate.panel
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ description: String) {
            precondition(condition(), description); checks += 1
        }
        check(window === delegate.prepareFloatingWindow(), "Must reuse the same window")
        check(window.canBecomeKey, "Input window must accept keyboard focus")
        check(window.styleMask.contains(.nonactivatingPanel), "Typing must not depend on application activation")
        check(!window.becomesKeyOnlyIfNeeded, "Keyboard focus must not require a mouse click")
        check(window.initialFirstResponder === panel.field, "Wrong initial input target")
        check(window.contentViewController === panel, "Input field not attached to the launcher")
        check(panel.field.isEditable && panel.field.acceptsFirstResponder, "Input must be editable")
        for index in 0..<20 {
            let other = NSTextField(frame: NSRect(x: 0, y: 0, width: 40, height: 20))
            panel.view.addSubview(other)
            check(window.makeFirstResponder(other), "Alternate editor cannot focus")
            panel.prepare()
            check(panel.field.stringValue.isEmpty && panel.selectedID == "monokakido", "Opening changed default/blank input")
            check(window.initialFirstResponder === panel.field, "Initial focus was lost")
            guard let editor = panel.field.currentEditor() as? NSTextView else { fatalError("Text insertion cursor missing") }
            check(window.firstResponder === editor, "Input field editor must own keyboard input")
            check(editor.selectedRange() == NSRange(location: 0, length: 0), "Empty field must have insertion point")
            let fixture = "focus fixture \(index)"
            editor.insertText(fixture, replacementRange: NSRange(location: NSNotFound, length: 0))
            check(editor.string == fixture && panel.field.stringValue == fixture, "Typed text did not reach the input field")
            check(window.makeFirstResponder(other), "Focus transfer failed")
            check(panel.focusInput(), "Cannot restore focus")
            check(panel.field.stringValue == fixture, "Restoring focus cleared existing input")
            window.initialFirstResponder = other
            check(panel.focusInput() && window.initialFirstResponder === panel.field, "Initial responder not repaired")
            panel.choose(panel.buttons[2])
            check(window.firstResponder === panel.field.currentEditor(), "Choosing a destination lost typing focus")
            check(panel.field.stringValue == fixture, "Choosing a destination altered input")
            other.removeFromSuperview()
        }
        let other = NSTextField(frame: NSRect(x: 0, y: 0, width: 40, height: 20))
        panel.view.addSubview(other); window.makeFirstResponder(other)
        let responder = window.firstResponder
        let foreign = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        delegate.wantsInputFocus = true
        delegate.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: foreign))
        check(delegate.wantsInputFocus && window.firstResponder === responder, "Foreign window event stole focus")
        delegate.focusInputIfReady()
        check(window.firstResponder === responder, "Hidden launcher stole focus")
        delegate.applicationDidResignActive(Notification(name: NSApplication.didResignActiveNotification, object: app))
        check(!delegate.wantsInputFocus, "Inactive app retained pending focus request")
        delegate.wantsInputFocus = true; delegate.dismiss()
        check(!delegate.wantsInputFocus && panel.field.stringValue.isEmpty, "Dismiss did not cancel focus/input")
        delegate.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification, object: app))
        check(!delegate.wantsInputFocus, "Closed launcher reclaimed focus")
        delegate.wantsInputFocus = true
        delegate.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        check(!delegate.wantsInputFocus, "Closing left a pending focus request")
        let detached = Panel(store: store, openURL: {_ in fatalError("No requests")}, transferToApp: {_,_ in fatalError("No transfers")})
        detached.prepare(); check(!detached.focusInput(), "Detached view reported focus")
        check(defaults.data(forKey: SettingsStore.storageKey) == nil, "Focus must not persist user settings")
        print("PASS: \(checks) input-focus checks; window policy, initial responder, 20 reopen/editor insert cycles, destination focus, close/deactivate guards. No global keys, external apps, general clipboard or searches used.")
    }
}
