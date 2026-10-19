import AppKit
import Speech
import AVFoundation

func lookupFont(_ size: CGFloat) -> NSFont {
    NSFont(name: "HiraMaruProN-W4", size: size) ?? NSFont.systemFont(ofSize: size)
}
let lookupTeal = NSColor(calibratedRed: 0.02, green: 0.47, blue: 0.53, alpha: 1)

final class LookupSurface: NSView {
    override var isFlipped: Bool { true }
    init(frame: NSRect, color: NSColor) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class LookupTargetButton: NSButton {
    let nameLabel = NSTextField(labelWithString: "")
    let keyLabel = NSTextField(labelWithString: "")
    let symbol = NSImageView()
    override var isFlipped: Bool { true }

    init(name: String, symbolName: String, shortcut: Int?, width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 52))
        title = ""
        isBordered = false
        setButtonType(.momentaryPushIn)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        symbol.frame = NSRect(x: 12, y: 16, width: 20, height: 20)
        symbol.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        symbol.imageScaling = .scaleProportionallyDown
        addSubview(symbol)
        nameLabel.stringValue = name
        nameLabel.font = lookupFont(14)
        nameLabel.frame = NSRect(x: 40, y: 16, width: width - 88, height: 22)
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)
        keyLabel.stringValue = shortcut.map { "⇧\($0)" } ?? ""
        keyLabel.font = lookupFont(12)
        keyLabel.alignment = .center
        keyLabel.frame = NSRect(x: width - 41, y: 15, width: 32, height: 24)
        keyLabel.wantsLayer = true
        keyLabel.layer?.cornerRadius = 6
        keyLabel.layer?.backgroundColor = NSColor.white.cgColor
        addSubview(keyLabel)
        toolTip = name + (shortcut.map { " — Shift+\($0)で選択" } ?? " — クリックで選択")
        setAccessibilityLabel(toolTip)
        setSelected(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setSelected(_ selected: Bool) {
        layer?.backgroundColor = (selected ? NSColor(calibratedRed: 0.88, green: 0.96, blue: 0.96, alpha: 1) : .white).cgColor
        layer?.borderColor = (selected ? lookupTeal : NSColor(calibratedWhite: 0.84, alpha: 1)).cgColor
        nameLabel.textColor = selected ? lookupTeal : .labelColor
        symbol.contentTintColor = selected ? lookupTeal : .secondaryLabelColor
        keyLabel.textColor = selected ? lookupTeal : .secondaryLabelColor
        setAccessibilityValue(selected ? "選択中" : "未選択")
    }
}

final class Panel: NSViewController, NSTextFieldDelegate {
    let store: SettingsStore
    private let openURL: (URL) -> Bool
    private let transferToApp: (String, String) -> Void
    let field = NSTextField()
    let mic = LookupTargetButton(name: "音声入力", symbolName: "mic", shortcut: 8, width: 200.5)
    let searchButton = NSButton(title: "物書堂で検索", target: nil, action: nil)
    let statusLabel = NSTextField(labelWithString: "")
    var buttons: [LookupTargetButton] = []
    var selectedID = "monokakido"
    var onDone: (() -> Void)?
    var onSettings: (() -> Void)?
    var onResize: ((NSSize) -> Void)?
    var keyMonitor: Any?
    var targets: [LookupTarget] { store.settings.enabledTargets }
    let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    let engine = AVAudioEngine()
    var request: SFSpeechAudioBufferRecognitionRequest?
    var task: SFSpeechRecognitionTask?
    var silence: Timer?
    var listening = false
    var voiceStart = Date()
    var testMode = false

    init(store: SettingsStore, openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }, transferToApp: @escaping (String, String) -> Void = { id, query in
        if id == "chatgpt-dot" { sendToDots(query) }
        if id == "grok-bot" { sendToGrokBot(query) }
    }) {
        self.store = store; self.openURL = openURL; self.transferToApp = transferToApp
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) } }

    override func loadView() {
        view = LookupSurface(frame: NSRect(x: 0, y: 0, width: 880, height: 350), color: NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.96, alpha: 1))
        view.appearance = NSAppearance(named: .aqua)
        view.layer?.cornerRadius = 22; view.layer?.masksToBounds = true
        field.delegate = self
        rebuild()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.view.window?.isKeyWindow == true else { return event }
            return self.handleSelectionKey(event) ? nil : event
        }
    }

    @discardableResult func handleSelectionKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.shift, .control, .command, .option])
        let digits: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9]
        guard modifiers == .shift, let number = digits[event.keyCode] else { return false }
        if event.isARepeat { return true }
        if number == 8 { toggleVoice(); return true }
        if let target = targets.first(where: { $0.shortcut == number }) { select(id: target.id); return true }
        return false
    }

    func rebuild() {
        view.subviews.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        let columnWidth: CGFloat = 200.5
        let rows = max(1, Int(ceil(Double(targets.count + 1) / 4.0)))
        let gridHeight = CGFloat(min(rows, 3) * 62 - 10)
        let gridBottom = 140 + gridHeight
        let height = gridBottom + 100
        view.setFrameSize(NSSize(width: 880, height: height))
        preferredContentSize = view.frame.size
        let icon = NSImageView(frame: NSRect(x: 24, y: 20, width: 34, height: 34))
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") { icon.image = NSImage(contentsOf: url) }
        icon.imageScaling = .scaleProportionallyDown
        view.addSubview(icon)
        let title = NSTextField(labelWithString: "調べものバー")
        title.font = lookupFont(21); title.frame = NSRect(x: 70, y: 22, width: 400, height: 30)
        view.addSubview(title)
        let gear = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "設定")!, target: self, action: #selector(settings))
        gear.frame = NSRect(x: 818, y: 19, width: 38, height: 36)
        gear.bezelStyle = .texturedRounded; gear.toolTip = "検索先を追加・並べ替え"
        view.addSubview(gear)
        let input = LookupSurface(frame: NSRect(x: 24, y: 72, width: 832, height: 50), color: .white)
        input.layer?.cornerRadius = 12; input.layer?.borderWidth = 1.5; input.layer?.borderColor = lookupTeal.withAlphaComponent(0.55).cgColor
        let glass = NSImageView(frame: NSRect(x: 14, y: 14, width: 22, height: 22))
        glass.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        glass.contentTintColor = .secondaryLabelColor; input.addSubview(glass)
        field.frame = NSRect(x: 48, y: 11, width: 768, height: 30)
        field.font = lookupFont(20); field.isBordered = false; field.drawsBackground = false
        field.placeholderString = "調べたい言葉を入力"
        field.setAccessibilityLabel("調べたい言葉")
        input.addSubview(field); view.addSubview(input)
        let grid = LookupSurface(frame: NSRect(x: 0, y: 0, width: 832, height: CGFloat(rows * 62 - 10)), color: .clear)
        let scroll = NSScrollView(frame: NSRect(x: 24, y: 140, width: 832, height: gridHeight))
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.hasVerticalScroller = rows > 3; scroll.scrollerStyle = .overlay
        scroll.documentView = grid; view.addSubview(scroll)
        for (index, target) in targets.enumerated() {
            let button = LookupTargetButton(name: target.name, symbolName: target.symbolName, shortcut: target.shortcut, width: columnWidth)
            button.tag = index; button.target = self; button.action = #selector(choose(_:))
            button.frame.origin = NSPoint(x: CGFloat(index % 4) * 210.5, y: CGFloat(index / 4) * 62)
            buttons.append(button); grid.addSubview(button)
        }
        let micIndex = targets.count
        mic.frame.origin = NSPoint(x: CGFloat(micIndex % 4) * 210.5, y: CGFloat(micIndex / 4) * 62)
        mic.target = self; mic.action = #selector(toggleVoice)
        mic.toolTip = "音声入力 → ChatGPT Web（Shift+8）"
        mic.setAccessibilityLabel(mic.toolTip)
        mic.isEnabled = targets.contains(where: { $0.id == "chatgpt-web" })
        grid.addSubview(mic)
        let divider = LookupSurface(frame: NSRect(x: 24, y: gridBottom + 16, width: 832, height: 1), color: NSColor(calibratedWhite: 0.86, alpha: 1))
        view.addSubview(divider)
        let paste = NSButton(title: "⌘V  貼り付け", target: self, action: #selector(pasteText))
        paste.font = lookupFont(13); paste.isBordered = false; paste.frame = NSRect(x: 18, y: gridBottom + 28, width: 130, height: 30)
        view.addSubview(paste)
        let close = NSButton(title: "Esc  閉じる", target: self, action: #selector(closePanel))
        close.font = lookupFont(13); close.isBordered = false; close.frame = NSRect(x: 152, y: gridBottom + 28, width: 120, height: 30)
        view.addSubview(close)
        searchButton.target = self; searchButton.action = #selector(search)
        searchButton.font = lookupFont(16); searchButton.bezelStyle = .rounded
        searchButton.bezelColor = lookupTeal; searchButton.contentTintColor = .white
        searchButton.frame = NSRect(x: 610, y: gridBottom + 26, width: 246, height: 38)
        view.addSubview(searchButton)
        statusLabel.font = lookupFont(11); statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 24, y: gridBottom + 72, width: 832, height: 20)
        statusLabel.stringValue = store.loadError == nil ? "音声入力の送信先：ChatGPT Web" : "設定を読み込めなかったため標準設定で起動しました。設定画面で確認してください。"
        view.addSubview(statusLabel)
        select(id: targets.contains(where: { $0.id == selectedID }) ? selectedID : store.settings.defaultTargetID)
        onResize?(view.frame.size)
    }

    func select(id: String) {
        guard targets.contains(where: { $0.id == id }) else { return }
        selectedID = id
        for (index, button) in buttons.enumerated() { button.setSelected(targets[index].id == id) }
        updateSearchButton()
    }
    func updateSearchButton() {
        let name = targets.first(where: { $0.id == selectedID })?.name ?? "検索"
        searchButton.title = "\(name)で検索  ↩"
        searchButton.toolTip = "\(name)で検索（Enter）"
        searchButton.setAccessibilityLabel(searchButton.toolTip)
        searchButton.isEnabled = !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !listening
    }
    func prepare() {
        _ = view
        cancelInput()
        field.stringValue = ""
        select(id: store.settings.defaultTargetID)
        view.window?.makeFirstResponder(field)
    }
    func cancelInput() {
        if listening { stopVoice(send: false) }
        field.stringValue = ""
        updateSearchButton()
    }
    @objc func choose(_ button: NSButton) { select(id: targets[button.tag].id); view.window?.makeFirstResponder(field) }
    @objc func settings() { onSettings?() }
    @objc func closePanel() { cancelInput(); onDone?() }
    @objc func pasteText() {
        view.window?.makeFirstResponder(field)
        (field.currentEditor() as? NSTextView)?.paste(nil)
        updateSearchButton()
    }
    @objc func search() { openTarget(id: selectedID) }
    func controlTextDidChange(_ notification: Notification) { updateSearchButton() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            guard !textView.hasMarkedText() else { return false }
            search(); return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) { closePanel(); return true }
        return false
    }
    func openTarget(id: String) {
        guard !listening, let target = targets.first(where: { $0.id == id }) else { return }
        let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        do {
            switch target.route {
            case .builtin(.chatGPTDot), .builtin(.grokBot): onDone?(); transferToApp(target.id, query)
            default:
                guard let url = try target.makeURL(query: query), openURL(url) else {
                    statusLabel.stringValue = "検索先を開けませんでした。設定をご確認ください。"; return
                }
                onDone?()
            }
            field.stringValue = ""; updateSearchButton()
        } catch { statusLabel.stringValue = error.localizedDescription }
    }

    @objc func toggleVoice() {
        guard targets.contains(where: { $0.id == "chatgpt-web" }) else { return }
        listening ? stopVoice(send: true) : startVoice()
    }
    func startVoice() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self, self.view.window?.isVisible == true else { return }
                guard status == .authorized else { self.statusLabel.stringValue = "音声認識の許可をご確認ください。"; return }
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    DispatchQueue.main.async {
                        guard self.view.window?.isVisible == true else { return }
                        if allowed { self.beginListening() } else { self.statusLabel.stringValue = "マイクの許可をご確認ください。" }
                    }
                }
            }
        }
    }
    func beginListening() {
        guard !listening, recognizer?.isAvailable == true else { statusLabel.stringValue = "音声認識を現在利用できません。"; return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { statusLabel.stringValue = "マイクの入力を確認してください。"; self.request = nil; return }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in self?.request?.append(buffer) }
        do { engine.prepare(); try engine.start() } catch {
            input.removeTap(onBus: 0); self.request = nil; statusLabel.stringValue = "マイクを開始できませんでした。"; return
        }
        listening = true; voiceStart = Date(); field.stringValue = ""
        field.placeholderString = "聞いています…（送信先：ChatGPT Web）"
        mic.nameLabel.stringValue = "停止"; mic.setSelected(true)
        updateSearchButton(); restartTask(first: request); armSilence()
    }
    func restartTask(first: SFSpeechAudioBufferRecognitionRequest? = nil) {
        task?.cancel()
        let current = first ?? SFSpeechAudioBufferRecognitionRequest()
        current.shouldReportPartialResults = true; request = current
        task = recognizer?.recognitionTask(with: current) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.listening, self.request === current else { return }
                if let result { self.field.stringValue = result.bestTranscription.formattedString; self.armSilence() }
                if (result?.isFinal ?? false) || (error != nil && !self.field.stringValue.isEmpty) { self.stopVoice(send: true) }
                else if error != nil {
                    if Date().timeIntervalSince(self.voiceStart) < 15 { self.restartTask() }
                    else { self.stopVoice(send: false); self.statusLabel.stringValue = "音声を聞き取れませんでした。Shift+8でもう一度お試しください。" }
                }
            }
        }
    }
    func armSilence() {
        silence?.invalidate()
        silence = Timer.scheduledTimer(withTimeInterval: field.stringValue.isEmpty ? 15 : 2.5, repeats: false) { [weak self] _ in
            if self?.listening == true { self?.stopVoice(send: true) }
        }
    }
    func stopVoice(send: Bool) {
        silence?.invalidate(); silence = nil
        guard listening else { return }
        listening = false; engine.stop(); engine.inputNode.removeTap(onBus: 0)
        request?.endAudio(); task?.cancel(); task = nil; request = nil
        mic.nameLabel.stringValue = "音声入力"; mic.setSelected(false)
        field.placeholderString = "調べたい言葉を入力"; updateSearchButton()
        if testMode { testMode = false; closePanel(); return }
        if send { openTarget(id: "chatgpt-web") }
    }
}
