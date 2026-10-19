import Cocoa
import ApplicationServices
import Speech
import AVFoundation

func key(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
    let src = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] { let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down); e?.flags = flags; e?.post(tap: .cghidEventTap) }
}
func axAttr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
func axFind(_ e: AXUIElement, _ depth: Int, _ log: inout String, _ match: (AXUIElement, String) -> Bool) -> AXUIElement? {
    if depth > 40 { return nil }
    let role = axAttr(e, kAXRoleAttribute) as? String ?? ""
    let txt = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { axAttr(e, $0) as? String }.joined(separator: "|")
    log += String(repeating: " ", count: depth) + role + " " + txt.prefix(60) + "\n"
    if match(e, role + " " + txt) { return e }
    for c in (axAttr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { if let f = axFind(c, depth + 1, &log, match) { return f } }
    return nil
}
func axClick(_ e: AXUIElement) {
    var p = CGPoint.zero, sz = CGSize.zero
    if let pv = axAttr(e, kAXPositionAttribute) { AXValueGetValue(pv as! AXValue, .cgPoint, &p) }
    if let sv = axAttr(e, kAXSizeAttribute) { AXValueGetValue(sv as! AXValue, .cgSize, &sz) }
    let c = CGPoint(x: p.x + sz.width / 2, y: p.y + sz.height / 2)
    for t in [CGEventType.leftMouseDown, .leftMouseUp] { CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: c, mouseButton: .left)?.post(tap: .cghidEventTap) }
}
func sendToGrokBot(_ q: String) {
    let pb = NSPasteboard.general
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.anysphere.sand").first else { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Grok Bot.app")); return }
    app.activate(options: [.activateAllWindows])
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var log = ""; var tf: AXUIElement?
        for w in (axAttr(ax, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
            log += "=== window\n"
            var last: AXUIElement?
            _ = axFind(w, 0, &log, { e, t in if t.hasPrefix("AXTextArea") && !t.contains("検索") && !t.contains("Search") { last = e }; return false })
            if last != nil { tf = last; break }
        }
        try? log.write(toFile: NSHomeDirectory()+"/Developer/QuickLookupBar/grok.log", atomically: true, encoding: .utf8)
        guard let t = tf else { NSSound.beep(); return }
        axClick(t)
        let old = pb.string(forType: .string)
        pb.clearContents(); pb.setString(q, forType: .string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            key(9, .maskCommand)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                key(36)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { if let o = old { pb.clearContents(); pb.setString(o, forType: .string) } }
            }
        }
    }
}
func sendToDots(_ q: String) {
    let pb = NSPasteboard.general
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.chat").first ?? NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == "ChatGPT" }) else { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/ChatGPT.app")); return }
    app.activate(options: [.activateAllWindows])
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        for w in (axAttr(ax, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
            var l = ""
            if let close = axFind(w, 0, &l, { _, t in t.hasPrefix("AXButton ビューアーを閉じる") }) { AXUIElementPerformAction(close, kAXPressAction as CFString) }
        }
        var log = ""
        var win: AXUIElement = ax
        var found: AXUIElement?
        for w in (axAttr(ax, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
            log += "=== window\n"
            if let f = axFind(w, 0, &log, { _, t in t.hasPrefix("AXButton あなたのdot") }) { win = w; found = f; AXUIElementPerformAction(w, kAXRaiseAction as CFString); break }
        }
        if found == nil { try? log.write(toFile: NSHomeDirectory()+"/Developer/QuickLookupBar/ax.log", atomically: true, encoding: .utf8); NSSound.beep(); return }
        if let item = found {
            axClick(item)
        }
        try? log.write(toFile: NSHomeDirectory()+"/Developer/QuickLookupBar/ax.log", atomically: true, encoding: .utf8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            var l2 = ""
            if let tf = axFind(win, 0, &l2, { _, t in t.hasPrefix("AXTextArea") && !t.contains("検索") }) { axClick(tf); l2 += "FOCUSED\n" }
            try? l2.write(toFile: NSHomeDirectory()+"/Developer/QuickLookupBar/ax2.log", atomically: true, encoding: .utf8)
            let old = pb.string(forType: .string)
            pb.clearContents(); pb.setString(q, forType: .string)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
              key(9, .maskCommand)
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                key(36)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { if let o = old { pb.clearContents(); pb.setString(o, forType: .string) } }
              }
            }
        }
    }
}
