import Cocoa
import ApplicationServices
import Speech
import AVFoundation
weak var sharedDelegate: AppDelegate?

struct Target { let name: String; let key: String; let make: (String) -> URL? }
func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#"))) ?? s }
let targets: [Target] = [
    Target(name: "物書堂 辞書", key: "1") { URL(string: "mkdictionaries:///?text=\(enc($0))&type=starts-with") },
    Target(name: "ChatGPT", key: "2") { URL(string: "https://chatgpt.com/?q=\(enc($0))") },
    Target(name: "Claude", key: "3") { URL(string: "https://claude.ai/new?q=\(enc($0))") },
    Target(name: "Grok", key: "4") { URL(string: "https://grok.com/?q=\(enc($0))") },
    Target(name: "Google", key: "5") { URL(string: "https://www.google.com/search?q=\(enc($0))") },
    Target(name: "ChatGPT小窓", key: "6") { _ in nil },
    Target(name: "Grok Bot", key: "7") { _ in nil },
]

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

class Panel: NSViewController, NSTextFieldDelegate {
    let field = NSTextField()
    let mic = NSButton()
    let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    let engine = AVAudioEngine()
    var request: SFSpeechAudioBufferRecognitionRequest?
    var task: SFSpeechRecognitionTask?
    var silence: Timer?
    var listening = false
    var voiceStart = Date()
    var testMode = false
    var peak: Float = 0
    var buffers = 0
    var fmtDesc = ""
    var buttons: [NSButton] = []
    var selected = 0
    var keyMonitor: Any?
    func select(_ i: Int) {
        selected = i
        for (j, b) in buttons.enumerated() {
            b.bezelColor = (j == i) ? .controlAccentColor : nil
            b.contentTintColor = (j == i) ? .white : nil
            b.state = (j == i) ? .on : .off
        }
    }
    @objc func toggleVoice() { listening ? stopVoice(send: true) : startVoice() }
    func startVoice() {
        SFSpeechRecognizer.requestAuthorization { st in
            DispatchQueue.main.async {
                guard st == .authorized else { self.field.stringValue = "音声認識が許可されていません"; return }
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    DispatchQueue.main.async { ok ? self.beginListening() : (self.field.stringValue = "マイクが許可されていません") }
                }
            }
        }
    }
    func beginListening() {
        let req = SFSpeechAudioBufferRecognitionRequest(); req.shouldReportPartialResults = true; request = req
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] b, _ in self?.buffers += 1; self?.request?.append(b); if let d = b.floatChannelData?[0] { var m: Float = 0; for i in 0..<Int(b.frameLength) { m = max(m, abs(d[i])) }; if m > (self?.peak ?? 0) { self?.peak = m } } }
        do { engine.prepare(); try engine.start() } catch { field.stringValue = "マイクを開始できませんでした"; return }
        voiceStart = Date(); peak = 0; buffers = 0; fmtDesc = "\(input.outputFormat(forBus: 0))"; listening = true; mic.title = "⏹ 停止"; mic.bezelColor = .systemRed; field.stringValue = ""; field.placeholderString = "聞いています…"
        restartTask(first: req)
        armSilence()
    }
    func restartTask(first: SFSpeechAudioBufferRecognitionRequest? = nil) {
        task?.cancel()
        let r0 = first ?? { let n = SFSpeechAudioBufferRecognitionRequest(); n.shouldReportPartialResults = true; return n }()
        request = r0
        task = recognizer?.recognitionTask(with: r0) { r, err in
            DispatchQueue.main.async {
                if let r = r { self.field.stringValue = r.bestTranscription.formattedString; self.armSilence() }
                if let err = err { try? "voice error: \(err)\n".write(toFile: NSHomeDirectory()+"/Developer/QuickLookupBar/voice.log", atomically: true, encoding: .utf8) }
                if (r?.isFinal ?? false) || (err != nil && !self.field.stringValue.isEmpty) { if self.listening { self.stopVoice(send: true) } }
                else if err != nil && self.listening {
                    try? "mic=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue) speech=\(SFSpeechRecognizer.authorizationStatus().rawValue) peak=\(self.peak) elapsed=\(Date().timeIntervalSince(self.voiceStart))\n".write(toFile: NSHomeDirectory()+"/Developer/QuickLookupBar/voice2.log", atomically: true, encoding: .utf8)
                    if Date().timeIntervalSince(self.voiceStart) < 15 { self.restartTask() }
                    else { self.stopVoice(send: false); self.field.placeholderString = "音声を聞き取れませんでした。もう一度Shift+6を押してください" }
                }
            }
        }
    }
    func armSilence() {
        silence?.invalidate()
        let wait: TimeInterval = field.stringValue.isEmpty ? 15.0 : 2.5
        silence = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { _ in if self.listening { self.stopVoice(send: true) } }
    }
    func stopVoice(send: Bool) {
        silence?.invalidate(); listening = false
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        request?.endAudio(); task?.cancel(); task = nil; request = nil
        mic.title = "🎤 話す"; mic.bezelColor = nil; field.placeholderString = "調べたい言葉（Shift+1〜7で選んでEnter、Shift+8で音声）"
        let heard = field.stringValue
        try? "stopped buffers=\(buffers) fmt=\(fmtDesc) send=\(send) text=\(heard) peak=\(peak) elapsed=\(Date().timeIntervalSince(voiceStart))\n".write(toFile: NSHomeDirectory()+"/Developer/QuickLookupBar/voice3.log", atomically: true, encoding: .utf8)
        if testMode { testMode = false; field.stringValue = ""; onDone?(); return }
        if send && !heard.trimmingCharacters(in: .whitespaces).isEmpty { open(1) }
    }
    var onDone: (() -> Void)?
    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 92))
        field.frame = NSRect(x: 12, y: 54, width: 616, height: 26)
        field.placeholderString = "調べたい言葉（Shift+1〜7で選んでEnter、Shift+8で音声）"
        field.delegate = self
        v.addSubview(field)
        var x: CGFloat = 12
        for (i, t) in targets.enumerated() {
            let b = NSButton(title: t.name, target: self, action: #selector(go(_:)))
            b.tag = i; b.bezelStyle = .rounded; b.sizeToFit()
            b.frame.origin = NSPoint(x: x, y: 12)
            b.setButtonType(.pushOnPushOff)
            buttons.append(b); v.addSubview(b); x += b.frame.width + 4
        }
        mic.title = "🎤 話す"; mic.bezelStyle = .rounded; mic.target = self; mic.action = #selector(toggleVoice)
        mic.sizeToFit()
        mic.frame.origin = NSPoint(x: x, y: 12); v.addSubview(mic)
        view = v
        select(0)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self = self, self.view.window?.isKeyWindow == true else { return e }
            let m = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let digits: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8]
            guard m.contains(.shift) || m.contains(.control) || m.contains(.command), let n = digits[e.keyCode] else { return e }
            if e.isARepeat { return nil }
            if n >= 1 && n <= self.buttons.count { self.select(n - 1); return nil }
            if n == self.buttons.count + 1 { self.toggleVoice(); return nil }
            return e
        }
    }
    func prepare() {
        select(0)
        let pb = NSPasteboard.general.string(forType: .string) ?? ""
        if field.stringValue.isEmpty && pb.count < 200 { field.stringValue = pb }
        view.window?.makeFirstResponder(field); field.selectText(nil)
    }
    func control(_ c: NSControl, textView: NSTextView, doCommandBy s: Selector) -> Bool {
        if s == #selector(NSResponder.insertNewline(_:)) { open(selected); return true }
        if s == #selector(NSResponder.cancelOperation(_:)) { if listening { stopVoice(send: false) }; onDone?(); return true }
        return false
    }
    @objc func go(_ b: NSButton) { select(b.tag); open(b.tag) }
    func open(_ i: Int) {
        let q = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if targets[i].name == "Grok Bot" { guard !q.isEmpty else { NSSound.beep(); return }; field.stringValue = ""; onDone?(); sendToGrokBot(q); return }
        if targets[i].name == "ChatGPT小窓" { guard !q.isEmpty else { NSSound.beep(); return }; field.stringValue = ""; onDone?(); sendToDots(q); return }
        guard !q.isEmpty, let u = targets[i].make(q) else { NSSound.beep(); return }
        NSWorkspace.shared.open(u); field.stringValue = ""; onDone?()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let pop = NSPopover(); let panel = Panel()
    func applicationDidFinishLaunching(_ n: Notification) {
        item.button?.image = NSImage(systemSymbolName: "text.magnifyingglass", accessibilityDescription: "調べもの")
        item.button?.action = #selector(toggle); item.button?.target = self
        pop.contentViewController = panel; pop.behavior = .transient
        panel.onDone = { [weak self] in self?.pop.performClose(nil); self?.floating?.orderOut(nil) }
        sharedDelegate = self
        item.isVisible = false
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("local.taka.qlb.voicetest"), object: nil, queue: .main) { [weak self] _ in
            self?.showFloating(); self?.panel.testMode = true; self?.panel.startVoice()
        }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        try? "trusted=\(trusted) mic=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue) speech=\(SFSpeechRecognizer.authorizationStatus().rawValue)\n".write(toFile: NSHomeDirectory()+"/Developer/QuickLookupBar/status.log", atomically: true, encoding: .utf8)
        var last: TimeInterval = 0
        var cmdDown = false
        var otherPressed = false
        let logPath = NSHomeDirectory()+"/Developer/QuickLookupBar/shift.log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        let fh = FileHandle(forWritingAtPath: logPath)
        let handler: (NSEvent) -> Void = { e in
            if e.type == .flagsChanged && (e.keyCode == 56 || e.keyCode == 60) { fh?.seekToEndOfFile(); fh?.write("shift code=\(e.keyCode) down=\(e.modifierFlags.contains(.shift))\n".data(using: .utf8)!) }
            if e.type == .keyDown { otherPressed = true; return }
            guard e.keyCode == 56 || e.keyCode == 60 else { otherPressed = true; return }
            let down = e.modifierFlags.contains(.shift)
            if down && !cmdDown { cmdDown = true; otherPressed = false; return }
            if !down && cmdDown {
                cmdDown = false
                if otherPressed { last = 0; return }
                let now = ProcessInfo.processInfo.systemUptime
                if now - last < 0.5 { last = 0; fh?.write("toggle requested\n".data(using: .utf8)!); DispatchQueue.main.async { sharedDelegate?.showFloating() } } else { last = now }
            }
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: handler)
        NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { e in handler(e); return e }
    }
    var floating: NSPanel?
    @objc func toggle() {
        if pop.isShown { pop.performClose(nil); return }
        if let f = floating, f.isVisible { f.orderOut(nil) }
        if pop.contentViewController !== panel { floating?.contentViewController = nil; pop.contentViewController = panel }
        NSApp.activate(ignoringOtherApps: true)
        pop.show(relativeTo: item.button!.bounds, of: item.button!, preferredEdge: .minY)
        panel.prepare()
    }
    func showFloating() {
        if pop.isShown { pop.performClose(nil) }
        if let f = floating, f.isVisible { f.orderOut(nil); return }
        if floating == nil {
            let f = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 92), styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
            f.title = "調べものバー"; f.level = .floating; f.isReleasedWhenClosed = false
            f.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            floating = f
        }
        guard let f = floating else { return }
        if pop.contentViewController === panel { pop.contentViewController = nil }
        f.contentViewController = panel
        f.center()
        NSApp.activate(ignoringOtherApps: true)
        f.makeKeyAndOrderFront(nil)
        panel.prepare()
    }
}
let app = NSApplication.shared; let d = AppDelegate(); app.delegate = d
app.setActivationPolicy(.regular); app.run()
