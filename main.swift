import AppKit
import ApplicationServices

final class LookupFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = SettingsStore()
    lazy var panel = Panel(store: store)
    lazy var settingsController = SettingsWindowController(store: store)
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var floating: LookupFloatingPanel?
    var globalMonitor: Any?
    var localMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let image = NSImage(systemSymbolName: "text.magnifyingglass", accessibilityDescription: "調べものバー")
        image?.isTemplate = true; item.button?.image = image
        item.button?.toolTip = "調べものバー — Shiftを2回で開く"
        item.button?.target = self; item.button?.action = #selector(toggle)
        item.isVisible = store.settings.showMenuBarIcon
        panel.onDone = { [weak self] in self?.dismiss() }
        panel.onSettings = { [weak self] in self?.showSettings() }
        panel.onResize = { [weak self] size in self?.floating?.setContentSize(size) }
        settingsController.onSave = { [weak self] in
            guard let self else { return }
            self.panel.rebuild(); self.item.isVisible = self.store.settings.showMenuBarIcon
        }
        buildMenu()
        installShortcut()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        // Only a permission flag is logged. Never record input, speech, or key history.
        try? "trusted=\(trusted)\n".write(toFile: NSHomeDirectory() + "/Developer/QuickLookupBar/status.log", atomically: true, encoding: .utf8)
        if CommandLine.arguments.contains("--show") { showFloating() }
        if CommandLine.arguments.contains("--settings") { showSettings() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showFloating() }
        return true
    }
    func buildMenu() {
        let menu = NSMenu()
        let root = NSMenuItem(); menu.addItem(root)
        let appMenu = NSMenu(); root.submenu = appMenu
        let open = NSMenuItem(title: "調べものバーを開く", action: #selector(showFloating), keyEquivalent: "")
        open.target = self; appMenu.addItem(open)
        let settings = NSMenuItem(title: "設定…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self; appMenu.addItem(settings); appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let editRoot = NSMenuItem(title: "編集", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "編集"); editRoot.submenu = edit; menu.addItem(editRoot)
        for (name, selector, key) in [("取り消す", "undo:", "z"), ("切り取り", "cut:", "x"), ("コピー", "copy:", "c"), ("貼り付け", "paste:", "v"), ("すべて選択", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: name, action: Selector(selector), keyEquivalent: key))
        }
        NSApp.mainMenu = menu
    }
    func installShortcut() {
        var last: TimeInterval = 0
        var down = false
        var interrupted = false
        let handler: (NSEvent) -> Void = { [weak self] event in
            if event.type == .keyDown { interrupted = true; last = 0; return }
            let other = event.modifierFlags.intersection([.command, .control, .option])
            guard other.isEmpty else { interrupted = true; last = 0; down = false; return }
            guard event.keyCode == 56 || event.keyCode == 60 else { interrupted = true; last = 0; return }
            let pressed = event.modifierFlags.contains(.shift)
            if pressed && !down { down = true; interrupted = false; return }
            if !pressed && down {
                down = false
                guard !interrupted else { last = 0; return }
                let now = ProcessInfo.processInfo.systemUptime
                if now - last < 0.5 { last = 0; self?.showFloating() } else { last = now }
            }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in handler(event); return event }
    }
    func dismiss() { panel.cancelInput(); floating?.orderOut(nil) }
    @objc func toggle() { showFloating() }
    @objc func showFloating() {
        if floating?.isVisible == true { dismiss(); return }
        if floating == nil {
            _ = panel.view
            let window = LookupFloatingPanel(contentRect: NSRect(origin: .zero, size: panel.preferredContentSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = "調べものバー"; window.level = .floating; window.isReleasedWhenClosed = false
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentViewController = panel; window.delegate = self
            panel.view.layer?.cornerRadius = 22; panel.view.layer?.masksToBounds = true
            floating = window
        }
        guard let window = floating else { return }
        window.setContentSize(panel.preferredContentSize); window.center()
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); panel.prepare()
    }
    @objc func showSettings() { dismiss(); settingsController.show() }
    func windowWillClose(_ notification: Notification) { panel.cancelInput() }
}

func renderView(_ view: NSView, to path: URL) throws {
    let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw SettingsError.invalid("プレビューを作成できません。") }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw SettingsError.invalid("PNGへ変換できません。") }
    try png.write(to: path)
    window.contentView = nil
}

let app = NSApplication.shared
if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
    // Isolated defaults and offscreen views. No global monitor, clipboard read, permissions, or requests.
    app.setActivationPolicy(.prohibited)
    let defaults = UserDefaults(suiteName: "QuickLookupBar.preview.\(UUID().uuidString)")!
    let store = SettingsStore(defaults: defaults)
    let panel = Panel(store: store)
    let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        panel.prepare()
        try renderView(panel.view, to: directory.appendingPathComponent("lookup-panel.png"))
        let settings = SettingsWindowController(store: store)
        settings.settingsContentView.appearance = NSAppearance(named: .aqua)
        try renderView(settings.settingsContentView, to: directory.appendingPathComponent("lookup-settings.png"))
        print("Rendered native panel and settings using isolated defaults; no queries sent.")
    } catch { fputs("Preview failed: \(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let delegate = AppDelegate(); app.delegate = delegate
    app.setActivationPolicy(.regular); app.run()
}
