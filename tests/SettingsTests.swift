import Foundation

@main struct SettingsTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fatalError("FAIL: \(message)") }
    }
    static func rejects(_ message: String, _ operation: () throws -> Void) {
        do { try operation(); fatalError("FAIL: \(message)") } catch { checks += 1 }
    }
    static func mutate(_ change: (inout AppSettings) -> Void) throws {
        var settings = AppSettings.defaults
        change(&settings)
        try settings.validated()
    }
    static func main() throws {
        let baseline = AppSettings.defaults
        try baseline.validated()
        expect(baseline.defaultTarget?.id == "monokakido", "物書堂が初期検索先")
        expect(baseline.targets.map(\.shortcut) == [1,2,3,4,5,6,7], "標準キー")
        expect(!baseline.showMenuBarIcon, "メニューアイコンの既存状態")
        var reordered = baseline
        reordered.targets.reverse()
        try reordered.validated()
        expect(reordered.defaultTargetID == baseline.defaultTargetID, "並べ替えても初期検索先維持")
        expect(reordered.targets.first?.shortcut == 7, "並べ替えてもキー維持")
        rejects("重複ID") { try mutate { $0.targets.append($0.targets[0]) } }
        rejects("空ID") { try mutate { $0.targets[0].id = "" } }
        rejects("空名前") { try mutate { $0.targets[0].name = " \n " } }
        rejects("長い名前") { try mutate { $0.targets[0].name = String(repeating: "辞", count: 41) } }
        rejects("名前の制御文字") { try mutate { $0.targets[0].name = "a\tb" } }
        rejects("重複キーは無効検索先でも拒否") { try mutate { $0.targets[1].enabled = false; $0.targets[1].shortcut = 1 } }
        for invalid in [-1,0,8,10] {
            rejects("不正/予約キー") { try mutate { $0.targets[0].shortcut = invalid } }
        }
        rejects("全無効") { try mutate { for i in $0.targets.indices { $0.targets[i].enabled = false } } }
        rejects("初期検索先無効") { try mutate { $0.targets[0].enabled = false } }
        rejects("初期検索先不存在") { try mutate { $0.defaultTargetID = "missing" } }
        rejects("標準削除") { try mutate { $0.targets.removeLast() } }
        rejects("標準接続の変更") { try mutate { $0.targets[0].route = .httpsTemplate("https://example.com/?q={query}") } }
        rejects("標準のID偽装") { try mutate { $0.targets[0].route = .builtin(.google) } }
        rejects("将来バージョン") { try mutate { $0.version = 2 } }
        var custom = baseline
        let target = SettingsStore.newCustomTarget(name: "追加サイト", template: "https://example.com/search?fixed=a%2Bb&term=before{query}after#help", shortcut: 9)
        custom.targets.append(target)
        custom.defaultTargetID = target.id
        custom.showMenuBarIcon = true
        try custom.validated()
        expect(target.id != SettingsStore.newCustomTarget().id, "カスタムID一意")
        var noKey = custom
        noKey.targets[0].shortcut = nil
        try noKey.validated()
        let query = "日本語 & = + ? # % / 😀"
        let url = try target.makeURL(query: query)!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        expect(components.queryItems?.first(where: {$0.name == "term"})?.value == "before" + query + "after", "クエリの往復で文字維持")
        expect(components.queryItems?.first(where: {$0.name == "fixed"})?.value == "a+b", "固定パラメータ維持")
        expect(components.fragment == "help", "固定fragment維持")
        expect(!url.absoluteString.contains("+"), "リテラル+を符号化")
        expect(components.queryItems?.count == 2, "検索文字列からパラメータ混入なし")
        for kind in BuiltinLookupRoute.allCases {
            let builtURL = try LookupRoute.builtin(kind).makeURL(query: query)
            if kind == .chatGPTDot || kind == .grokBot { expect(builtURL == nil, "アプリ経由はURLなし"); continue }
            let parts = URLComponents(url: builtURL!, resolvingAgainstBaseURL: false)!
            expect(parts.queryItems?.first(where: {$0.name == (kind == .monokakido ? "text" : "q")})?.value == query, "標準URLの符号化")
        }
        for template in [
            "http://example.com/?q={query}", "javascript:alert({query})",
            "https://user:pass@example.com/?q={query}", "https://example.com/{query}?q=x",
            "https://{query}.example.com/?q=x", "https://example.com/?{query}=x",
            "https://example.com/?q=x#{query}", "https://example.com/?q={query}&x={query}",
            "https://example.com/?q=x", "https://example.com/?q={query}\n",
            "https://example.com/%7Bquery%7D?q={query}", "https://example.com/?q={query}&x=%7Bquery%7D"
        ] {
            rejects("不正テンプレート拒否: \(template)") { _ = try HTTPSQueryTemplate(template) }
        }
        var deleted = custom
        deleted.targets.removeAll { $0.id == target.id }
        rejects("初期検索先の削除") { try deleted.validated() }
        deleted.defaultTargetID = "monokakido"
        try deleted.validated()
        let suite = "QuickLookupBar.Tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        expect(store.settings == baseline && store.loadError == nil, "初回は標準設定")
        expect(defaults.object(forKey: SettingsStore.storageKey) == nil, "読込のみでは保存しない")
        try store.save(custom)
        let loaded = SettingsStore(defaults: defaults)
        expect(loaded.settings == custom && loaded.loadError == nil, "設定を再読込")
        let saved = defaults.data(forKey: SettingsStore.storageKey)!
        var invalid = custom; invalid.defaultTargetID = "missing"
        rejects("無効設定保存拒否") { try store.save(invalid) }
        expect(defaults.data(forKey: SettingsStore.storageKey) == saved && store.settings == custom, "保存失敗時に元の状態保持")
        expect(!String(data: saved, encoding: .utf8)!.contains(query), "検索本文を保存しない")
        for bad in [Data("not json".utf8), try JSONEncoder().encode(AppSettings(version: 2, targets: baseline.targets, defaultTargetID: "monokakido"))] {
            defaults.set(bad, forKey: SettingsStore.storageKey)
            let recovered = SettingsStore(defaults: defaults)
            expect(recovered.settings == baseline && recovered.loadError != nil, "破損/将来設定から標準に回復")
            expect(defaults.data(forKey: SettingsStore.storageKey) == bad, "読込失敗でも元のデータ保持")
        }
        defaults.set("wrong type", forKey: SettingsStore.storageKey)
        let wrongType = SettingsStore(defaults: defaults)
        expect(wrongType.settings == baseline && wrongType.loadError != nil, "型違い設定から回復")
        expect(defaults.string(forKey: SettingsStore.storageKey) == "wrong type", "型違い元データ保持")
        print("PASS: \(checks) settings checks")
    }
}
