import AppKit
@main enum BoundaryCheck {
 static func main() throws {
  let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
  let domain = "QuickLookupBar.SettingsBoundary." + UUID().uuidString
  let defaults = UserDefaults(suiteName:domain)!
  defer {defaults.removePersistentDomain(forName:domain)}
  let store=SettingsStore(defaults:defaults); let editor=SettingsWindowController(store:store)
  let original=store.settings
  editor.window!.makeFirstResponder(editor.nameField)
  guard let text=editor.nameField.currentEditor() as? NSTextView else {fatalError("field editor unavailable")}
  text.string="入力中の名前"
  editor.targetTable.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
  precondition(editor.draft.targets[0].name == "入力中の名前", "Active field editor lost on selection")
  editor.cancelChanges(); precondition(store.settings == original)
  editor.window!.makeFirstResponder(editor.nameField)
  let marked=editor.nameField.currentEditor() as! NSTextView
  marked.setMarkedText("未確定文字", selectedRange:NSRange(location:5,length:0), replacementRange:NSRange(location:NSNotFound,length:0))
  precondition(marked.hasMarkedText())
  editor.saveChanges(); precondition(store.settings == original); precondition(editor.errorLabel.stringValue.contains("変換中"))
  marked.unmarkText(); editor.cancelChanges()
  editor.defaultPopup.selectItem(at:4); editor.defaultChanged(); editor.saveChanges()
  precondition(store.settings.defaultTargetID == "google")
  editor.reloadFromStore(); editor.defaultPopup.selectItem(at:1); editor.defaultChanged(); editor.cancelChanges()
  precondition(editor.draft.defaultTargetID == "google")
  editor.defaultPopup.selectItem(at:2); editor.defaultChanged(); editor.close(); editor.reloadFromStore()
  precondition(editor.draft.defaultTargetID == "google")
  editor.addCustomTarget(); editor.nameField.stringValue="長いURLの確認"
  editor.templateField.stringValue="https://example.com/search?x="+String(repeating:"long-value-",count:60)+"&q={query}"
  editor.editorChanged(); editor.saveChanges()
  precondition(store.settings.targets.last!.name == "長いURLの確認")
  editor.reloadFromStore(); editor.targetTable.selectRowIndexes(IndexSet(integer:7),byExtendingSelection:false)
  editor.templateField.stringValue="http://invalid.example/?q={query}"; editor.editorChanged(); editor.saveChanges()
  editor.settingsContentView.appearance=NSAppearance(named:.aqua)
  let view=editor.settingsContentView
  if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) {view.cacheDisplay(in:view.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))}
  precondition(!editor.errorLabel.stringValue.isEmpty)
  print("Boundary checks passed: active field editor selection commit, marked text save guard, default save/cancel/close reload, long HTTPS URL, inline invalid-URL display.")
 }
}
