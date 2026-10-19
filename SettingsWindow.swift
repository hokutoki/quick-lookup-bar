import AppKit

private final class LookupSettingsFlippedView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        super.draw(dirtyRect)
    }
}

/// All controls edit a value copy. Only Save writes a validated snapshot to the store.
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    let store: SettingsStore
    var onSave: (() -> Void)?
    private(set) var draft: AppSettings
    let settingsContentView: NSView = LookupSettingsFlippedView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
    let targetTable = NSTableView()
    let nameField = NSTextField()
    let enabledButton = NSButton(checkboxWithTitle: "この検索先を表示する", target: nil, action: nil)
    let shortcutPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let templateField = NSTextField()
    let defaultPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let menuIconButton = NSButton(checkboxWithTitle: "メニューバーに単色アイコンを表示する", target: nil, action: nil)
    let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let routeDescription = NSTextField(wrappingLabelWithString: "")
    private let templateLabel = NSTextField(labelWithString: "検索URL")
    private let templateHelp = NSTextField(wrappingLabelWithString: "")
    private let upButton = NSButton(title: "↑ 上へ", target: nil, action: nil)
    private let downButton = NSButton(title: "↓ 下へ", target: nil, action: nil)
    private let deleteButton = NSButton(title: "削除…", target: nil, action: nil)
    private let restoreNameButton = NSButton(title: "標準の名前に戻す", target: nil, action: nil)
    private var selectedTargetID: String?
    private var isUpdatingControls = false
    private let shortcutValues: [Int?] = [nil, 1, 2, 3, 4, 5, 6, 7, 9]

    init(store: SettingsStore) {
        self.store = store
        self.draft = store.settings
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "調べものバーの設定"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 900, height: 600)
        super.init(window: window)
        window.contentView = settingsContentView
        buildControls()
        reloadFromStore()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        if window?.isVisible != true { reloadFromStore() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func font(_ size: CGFloat) -> NSFont {
        NSFont(name: "HiraMaruProN-W4", size: size) ?? NSFont.systemFont(ofSize: size)
    }

    private func label(_ text: String, _ frame: NSRect, size: CGFloat = 13, secondary: Bool = false) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.frame = frame
        label.font = font(size)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        settingsContentView.addSubview(label)
    }

    private func button(_ control: NSButton, frame: NSRect, action: Selector, accessibility: String? = nil) {
        control.frame = frame
        control.font = font(12)
        control.target = self
        control.action = action
        control.bezelStyle = .rounded
        if let accessibility = accessibility { control.setAccessibilityLabel(accessibility) }
        settingsContentView.addSubview(control)
    }

    private func buildControls() {
        label("検索先を、自分の使いやすい順番に。", NSRect(x: 26, y: 24, width: 840, height: 30), size: 20)
        label("表示順とショートカットキーは別々に設定できます。変更は「保存」で反映します。", NSRect(x: 26, y: 61, width: 840, height: 24), secondary: true)
        label("検索先", NSRect(x: 26, y: 98, width: 270, height: 22))
        let scroll = NSScrollView(frame: NSRect(x: 26, y: 128, width: 284, height: 282))
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("target"))
        column.width = 276
        targetTable.addTableColumn(column)
        targetTable.headerView = nil
        targetTable.rowHeight = 40
        targetTable.intercellSpacing = NSSize(width: 0, height: 2)
        targetTable.allowsEmptySelection = false
        targetTable.allowsMultipleSelection = false
        targetTable.delegate = self
        targetTable.dataSource = self
        targetTable.setAccessibilityLabel("検索先の表示順")
        scroll.documentView = targetTable
        settingsContentView.addSubview(scroll)
        button(upButton, frame: NSRect(x: 22, y: 418, width: 91, height: 32), action: #selector(moveTargetUp), accessibility: "選択した検索先を1つ上へ移動")
        button(downButton, frame: NSRect(x: 116, y: 418, width: 91, height: 32), action: #selector(moveTargetDown), accessibility: "選択した検索先を1つ下へ移動")
        button(deleteButton, frame: NSRect(x: 214, y: 418, width: 100, height: 32), action: #selector(deleteCustomTarget))
        let add = NSButton(title: "＋ Web検索先を追加", target: nil, action: nil)
        button(add, frame: NSRect(x: 22, y: 452, width: 292, height: 32), action: #selector(addCustomTarget))
        label("標準検索先は削除せず、表示をオフにできます。\n非表示でもキーの割当は予約されます。", NSRect(x: 28, y: 488, width: 280, height: 42), size: 11, secondary: true)

        label("選択した検索先", NSRect(x: 342, y: 98, width: 510, height: 22))
        label("名前", NSRect(x: 342, y: 135, width: 110, height: 24))
        nameField.frame = NSRect(x: 450, y: 130, width: 414, height: 30)
        nameField.font = font(14)
        nameField.delegate = self
        nameField.setAccessibilityLabel("検索先の名前（40文字以内）")
        settingsContentView.addSubview(nameField)
        enabledButton.frame = NSRect(x: 449, y: 175, width: 415, height: 24)
        enabledButton.font = font(13)
        enabledButton.target = self
        enabledButton.action = #selector(editorChanged)
        settingsContentView.addSubview(enabledButton)
        label("選択キー", NSRect(x: 342, y: 221, width: 105, height: 24))
        shortcutPopup.frame = NSRect(x: 448, y: 215, width: 165, height: 32)
        shortcutPopup.font = font(13)
        shortcutPopup.addItems(withTitles: shortcutValues.map { $0.map { "⇧\($0)" } ?? "未割当" })
        shortcutPopup.target = self
        shortcutPopup.action = #selector(editorChanged)
        shortcutPopup.setAccessibilityLabel("検索先の選択ショートカット")
        settingsContentView.addSubview(shortcutPopup)
        label("⇧8 は音声入力用です。", NSRect(x: 624, y: 222, width: 240, height: 24), size: 11, secondary: true)
        templateLabel.frame = NSRect(x: 342, y: 268, width: 510, height: 22)
        templateLabel.font = font(13)
        settingsContentView.addSubview(templateLabel)
        templateField.frame = NSRect(x: 342, y: 299, width: 522, height: 30)
        templateField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        templateField.delegate = self
        templateField.placeholderString = "https://検索先のドメイン/search?q={query}"
        templateField.setAccessibilityLabel("HTTPS検索URL。検索語の位置は {query}")
        settingsContentView.addSubview(templateField)
        templateHelp.frame = NSRect(x: 342, y: 339, width: 522, height: 47)
        templateHelp.font = font(11)
        templateHelp.textColor = .secondaryLabelColor
        settingsContentView.addSubview(templateHelp)
        routeDescription.frame = NSRect(x: 342, y: 299, width: 522, height: 66)
        routeDescription.font = font(12)
        routeDescription.textColor = .secondaryLabelColor
        settingsContentView.addSubview(routeDescription)
        button(restoreNameButton, frame: NSRect(x: 660, y: 361, width: 206, height: 30), action: #selector(restoreStandardName))

        let divider = NSBox(frame: NSRect(x: 340, y: 397, width: 526, height: 1))
        divider.boxType = .separator
        settingsContentView.addSubview(divider)
        label("初期検索先", NSRect(x: 342, y: 420, width: 110, height: 24))
        defaultPopup.frame = NSRect(x: 448, y: 412, width: 416, height: 32)
        defaultPopup.font = font(13)
        defaultPopup.target = self
        defaultPopup.action = #selector(defaultChanged)
        defaultPopup.setAccessibilityLabel("開いたときの初期検索先")
        settingsContentView.addSubview(defaultPopup)
        menuIconButton.frame = NSRect(x: 342, y: 456, width: 522, height: 24)
        menuIconButton.font = font(13)
        menuIconButton.target = self
        menuIconButton.action = #selector(menuIconChanged)
        settingsContentView.addSubview(menuIconButton)
        label("入力欄は毎回空で開きます。貼り付けは ⌘V。", NSRect(x: 342, y: 493, width: 520, height: 24), size: 11, secondary: true)
        errorLabel.frame = NSRect(x: 28, y: 537, width: 610, height: 51)
        errorLabel.font = font(11)
        errorLabel.textColor = .systemRed
        errorLabel.setAccessibilityLabel("設定の確認事項")
        settingsContentView.addSubview(errorLabel)
        let cancel = NSButton(title: "キャンセル", target: nil, action: nil)
        button(cancel, frame: NSRect(x: 646, y: 548, width: 116, height: 32), action: #selector(cancelChanges))
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "保存", target: nil, action: nil)
        button(save, frame: NSRect(x: 770, y: 548, width: 100, height: 32), action: #selector(saveChanges))
        save.keyEquivalent = "\r"
    }

    func reloadFromStore() {
        draft = store.settings
        selectedTargetID = draft.targets.first?.id
        errorLabel.stringValue = store.loadError ?? ""
        menuIconButton.state = draft.showMenuBarIcon ? .on : .off
        refreshListAndDefault()
        loadSelectedEditor()
    }

    private var selectedIndex: Int? { draft.targets.firstIndex { $0.id == selectedTargetID } }

    private func refreshListAndDefault() {
        isUpdatingControls = true
        targetTable.reloadData()
        if let index = selectedIndex { targetTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        defaultPopup.removeAllItems()
        for target in draft.targets {
            let item = NSMenuItem(title: target.name + (target.enabled ? "" : "（非表示）"), action: nil, keyEquivalent: "")
            item.representedObject = target.id
            item.isEnabled = target.enabled || target.id == draft.defaultTargetID
            defaultPopup.menu?.addItem(item)
        }
        if let index = draft.targets.firstIndex(where: { $0.id == draft.defaultTargetID }) { defaultPopup.selectItem(at: index) }
        else { defaultPopup.select(nil) }
        isUpdatingControls = false
        updateMovementButtons()
    }

    private func loadSelectedEditor() {
        guard let index = selectedIndex else { return }
        isUpdatingControls = true
        let target = draft.targets[index]
        nameField.stringValue = target.name
        enabledButton.state = target.enabled ? .on : .off
        shortcutPopup.selectItem(at: shortcutValues.firstIndex(where: { $0 == target.shortcut }) ?? 0)
        let custom = !target.isBuiltin
        templateLabel.stringValue = custom ? "検索URL" : "接続方式"
        templateField.isHidden = !custom
        templateHelp.isHidden = !custom
        routeDescription.isHidden = custom
        restoreNameButton.isHidden = custom
        if case .httpsTemplate(let template) = target.route { templateField.stringValue = template }
        else { templateField.stringValue = "" }
        templateHelp.stringValue = "HTTPS URLのクエリ値に {query} を1個入れてください。\n検索語は実行時に置き換えます。この画面から通信は行いません。"
        routeDescription.stringValue = "標準の接続方式を使います。名前・表示・キー・順番を変更できます。\n別のWebサービスを使う場合は「＋ Web検索先を追加」を選びます。"
        deleteButton.isEnabled = custom
        isUpdatingControls = false
        updateMovementButtons()
    }

    /// Called before selection changes and Save, including when a field editor is still active.
    private func commitEditor() {
        guard !isUpdatingControls, let index = selectedIndex else { return }
        draft.targets[index].name = nameField.currentEditor()?.string ?? nameField.stringValue
        draft.targets[index].enabled = enabledButton.state == .on
        draft.targets[index].shortcut = shortcutValues[max(0, shortcutPopup.indexOfSelectedItem)]
        if !draft.targets[index].isBuiltin { draft.targets[index].route = .httpsTemplate(templateField.currentEditor()?.string ?? templateField.stringValue) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { draft.targets.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard draft.targets.indices.contains(row) else { return nil }
        let target = draft.targets[row]
        let cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 276, height: 40))
        let title = NSTextField(labelWithString: (target.enabled ? "" : "○ ") + target.name)
        title.frame = NSRect(x: 10, y: 12, width: 208, height: 19)
        title.font = font(12)
        title.lineBreakMode = .byTruncatingTail
        title.textColor = target.enabled ? .labelColor : .secondaryLabelColor
        title.toolTip = target.name
        cell.addSubview(title)
        cell.textField = title
        let key = NSTextField(labelWithString: target.shortcut.map { "⇧\($0)" } ?? "—")
        key.frame = NSRect(x: 226, y: 12, width: 42, height: 19)
        key.font = font(12)
        key.alignment = .right
        key.textColor = .secondaryLabelColor
        cell.addSubview(key)
        cell.setAccessibilityLabel(target.name + (target.enabled ? "、表示" : "、非表示") + "、" + (target.shortcut.map { "Shift \($0)" } ?? "キー未割当"))
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingControls else { return }
        commitEditor()
        let row = targetTable.selectedRow
        guard draft.targets.indices.contains(row) else { return }
        selectedTargetID = draft.targets[row].id
        loadSelectedEditor()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard !isUpdatingControls else { return }
        commitEditor()
        // Reload only the row: reselecting it would interrupt the active field editor.
        if let index = selectedIndex { targetTable.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(integer: 0)) }
        refreshDefaultTitles()
    }

    private func refreshDefaultTitles() {
        for (index, target) in draft.targets.enumerated() where index < defaultPopup.numberOfItems {
            defaultPopup.item(at: index)?.title = target.name + (target.enabled ? "" : "（非表示）")
            defaultPopup.item(at: index)?.isEnabled = target.enabled || target.id == draft.defaultTargetID
        }
    }

    @objc func editorChanged() {
        commitEditor()
        refreshListAndDefault()
        errorLabel.stringValue = draft.defaultTarget == nil ? "初期検索先が非表示です。有効な検索先を初期検索先に選び直してください。" : ""
    }

    @objc func defaultChanged() {
        if let id = defaultPopup.selectedItem?.representedObject as? String { draft.defaultTargetID = id }
        errorLabel.stringValue = draft.defaultTarget == nil ? "有効な検索先を初期検索先に指定してください。" : ""
    }

    @objc func menuIconChanged() { draft.showMenuBarIcon = menuIconButton.state == .on }

    private func updateMovementButtons() {
        upButton.isEnabled = selectedIndex.map { $0 > 0 } ?? false
        downButton.isEnabled = selectedIndex.map { $0 + 1 < draft.targets.count } ?? false
    }

    private func moveSelection(by delta: Int) {
        commitEditor()
        guard let index = selectedIndex, draft.targets.indices.contains(index + delta) else { return }
        draft.targets.swapAt(index, index + delta)
        refreshListAndDefault()
        targetTable.scrollRowToVisible(index + delta)
    }

    @objc func moveTargetUp() { moveSelection(by: -1) }
    @objc func moveTargetDown() { moveSelection(by: 1) }

    @objc func restoreStandardName() {
        commitEditor()
        guard let index = selectedIndex, let standard = AppSettings.defaults.targets.first(where: { $0.id == draft.targets[index].id }) else { return }
        draft.targets[index].name = standard.name
        refreshListAndDefault(); loadSelectedEditor()
        errorLabel.stringValue = "選択した検索先の名前を標準に戻しました。「保存」で反映します。"
    }

    @objc func addCustomTarget() {
        commitEditor()
        guard draft.targets.count < 100 else { errorLabel.stringValue = "検索先は100件までです。"; return }
        let target = SettingsStore.newCustomTarget(template: "")
        draft.targets.append(target)
        selectedTargetID = target.id
        refreshListAndDefault()
        loadSelectedEditor()
        targetTable.scrollRowToVisible(draft.targets.count - 1)
        errorLabel.stringValue = "追加した検索先の名前とHTTPS検索URLを入力してください。"
        window?.makeFirstResponder(nameField)
        nameField.selectText(nil)
    }

    @objc func deleteCustomTarget() {
        commitEditor()
        guard let index = selectedIndex, !draft.targets[index].isBuiltin else { return }
        let target = draft.targets[index]
        let alert = NSAlert()
        alert.messageText = "「\(target.name)」を削除しますか？"
        alert.informativeText = "この検索先の名前・検索URL・キー割当を設定案から削除します。「保存」で確定し、「キャンセル」で元に戻せます。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "キャンセル")
        alert.addButton(withTitle: "削除")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        draft.targets.remove(at: index)
        selectedTargetID = draft.targets[min(index, draft.targets.count - 1)].id
        // Keep the default ID invalid until the user explicitly chooses its replacement.
        refreshListAndDefault()
        loadSelectedEditor()
        errorLabel.stringValue = draft.defaultTarget == nil ? "削除した検索先が初期検索先でした。初期検索先を選び直してください。" : ""
    }

    @objc func saveChanges() {
        // Clicking Save must not persist an unfinished Japanese input-method composition.
        if [nameField, templateField].contains(where: { ($0.currentEditor() as? NSTextView)?.hasMarkedText() == true }) {
            errorLabel.stringValue = "変換中の文字を確定してから「保存」を選んでください。"
            return
        }
        if let window = window, !window.makeFirstResponder(nil) {
            errorLabel.stringValue = "入力を確定してから「保存」を選んでください。"
            return
        }
        commitEditor()
        draft.showMenuBarIcon = menuIconButton.state == .on
        do {
            try store.save(draft)
            errorLabel.stringValue = ""
            onSave?()
            close()
        } catch {
            errorLabel.stringValue = error.localizedDescription
        }
    }

    @objc func cancelChanges() {
        reloadFromStore()
        close()
    }
}
