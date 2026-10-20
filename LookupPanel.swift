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
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 28))
        title = ""
        isBordered = false
        setButtonType(.momentaryPushIn)
        wantsLayer = true
        layer?.cornerRadius = 5
        nameLabel.stringValue = name
        nameLabel.font = lookupFont(12)
        nameLabel.frame = NSRect(x: 9, y: 5, width: width - 47, height: 19)
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)
        keyLabel.stringValue = shortcut.map { "⇧\($0)" } ?? ""
        keyLabel.font = lookupFont(10)
        keyLabel.alignment = .right
        keyLabel.frame = NSRect(x: width - 34, y: 6, width: 25, height: 17)
        addSubview(keyLabel)
        toolTip = name + (shortcut.map { " — Shift+\($0)で選択" } ?? " — クリックで選択")
        setAccessibilityLabel(toolTip)
        setSelected(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setSelected(_ selected: Bool) {
        layer?.backgroundColor = (selected ? NSColor.controlAccentColor.withAlphaComponent(0.14) : .clear).cgColor
        nameLabel.textColor = selected ? .controlAccentColor : .labelColor
        keyLabel.textColor = selected ? .controlAccentColor : .secondaryLabelColor
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
        view = LookupSurface(frame: NSRect(x: 0, y: 0, width: 680, height: 144), color: .white)
        view.appearance = NSAppearance(named: .aqua)
        view.layer?.cornerRadius = 10; view.layer?.masksToBounds = true
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
        let panelWidth: CGFloat = 680
        let inset: CGFloat = 14
        let contentWidth = panelWidth - inset * 2
        let columnGap: CGFloat = 6
        let columnWidth = (contentWidth - columnGap * 3) / 4
        let rowStride: CGFloat = 32
        let rows = max(1, Int(ceil(Double(targets.count + 1) / 4.0)))
        let gridHeight = CGFloat(min(rows, 3)) * rowStride - 4
        let gridBottom = 54 + gridHeight
        view.setFrameSize(NSSize(width: panelWidth, height: gridBottom + 32))
        preferredContentSize = view.frame.size

        field.frame = NSRect(x: inset, y: 14, width: contentWidth - 78, height: 28)
        field.font = lookupFont(15)
        field.isBordered = false; field.isBezeled = true; field.drawsBackground = true
        field.bezelStyle = .roundedBezel
        field.placeholderString = "調べたい言葉を入力"
        field.setAccessibilityLabel("調べたい言葉")
        view.addSubview(field)
        searchButton.target = self; searchButton.action = #selector(search)
        searchButton.font = lookupFont(12); searchButton.bezelStyle = .rounded
        searchButton.frame = NSRect(x: panelWidth - inset - 72, y: 12, width: 72, height: 32)
        view.addSubview(searchButton)

        let grid = LookupSurface(frame: NSRect(x: 0, y: 0, width: contentWidth, height: CGFloat(rows) * rowStride - 4), color: .clear)
        let scroll = NSScrollView(frame: NSRect(x: inset, y: 54, width: contentWidth, height: gridHeight))
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.hasVerticalScroller = rows > 3; scroll.scrollerStyle = .overlay
        scroll.documentView = grid; view.addSubview(scroll)
        for (index, target) in targets.enumerated() {
            let button = LookupTargetButton(name: target.name, symbolName: target.symbolName, shortcut: target.shortcut, width: columnWidth)
            button.tag = index; button.target = self; button.action = #selector(choose(_:))
            button.frame.origin = NSPoint(x: CGFloat(index % 4) * (columnWidth + columnGap), y: CGFloat(index / 4) * rowStride)
            buttons.append(button); grid.addSubview(button)
        }
        let micIndex = targets.count
        mic.setFrameSize(NSSize(width: columnWidth, height: 28))
        mic.nameLabel.frame.size.width = columnWidth - 47
        mic.keyLabel.frame.origin.x = columnWidth - 34
        mic.frame.origin = NSPoint(x: CGFloat(micIndex % 4) * (columnWidth + columnGap), y: CGFloat(micIndex / 4) * rowStride)
        mic.target = self; mic.action = #selector(toggleVoice)
        mic.toolTip = "音声入力 → ChatGPT Web（Shift+8）"
        mic.setAccessibilityLabel(mic.toolTip)
        mic.isEnabled = targets.contains(where: { $0.id == "chatgpt-web" })
        grid.addSubview(mic)

        statusLabel.font = lookupFont(10); statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: inset + 2, y: gridBottom + 7, width: contentWidth - 34, height: 17)
        statusLabel.stringValue = store.loadError == nil ? "⇧数字で選択   ↩ 検索   esc 閉じる   ⌘V 貼り付け" : "設定を読み込めませんでした。設定画面で確認してください。"
        view.addSubview(statusLabel)
        let gear = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "設定")!, target: self, action: #selector(settings))
        gear.frame = NSRect(x: panelWidth - inset - 26, y: gridBottom + 2, width: 26, height: 26)
        gear.isBordered = false; gear.contentTintColor = .secondaryLabelColor
        gear.toolTip = "検索先を追加・並べ替え"
        view.addSubview(gear)
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
        searchButton.title = "検索 ↩"
        searchButton.toolTip = "\(name)で検索（Enter）"
        searchButton.setAccessibilityLabel(searchButton.toolTip)
        searchButton.isEnabled = !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !listening
    }
    func prepare() {
        _ = view
        cancelInput()
        field.stringValue = ""
        select(id: store.settings.defaultTargetID)
        focusInput()
    }
    @discardableResult func focusInput() -> Bool {
        guard let window = view.window else { return false }
        window.initialFirstResponder = field
        guard window.makeFirstResponder(field) else { return false }
        return field.currentEditor() === window.firstResponder
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
