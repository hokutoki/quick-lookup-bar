import AppKit

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
