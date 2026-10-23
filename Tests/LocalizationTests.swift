import Foundation

@main struct LocalizationTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let dictionary = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: root.appendingPathComponent("Resources/Localization/en.json")))
        let translator = Translator(english: dictionary)
        let placeholder = try NSRegularExpression(pattern: "\\{[0-9]+\\}")
        func slots(_ value: String) -> [String] {
            let s = value as NSString
            return placeholder.matches(in: value, range: NSRange(location: 0, length: s.length)).map { s.substring(with: $0.range) }.sorted()
        }
        let chinese = try NSRegularExpression(pattern: "[\\p{Han}]")
        for (key, value) in dictionary {
            assert(slots(key) == slots(value), key)
            assert(!value.isEmpty)
            assert(chinese.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) == nil, key)
            assert(translator.text(key, language: .simplifiedChinese) == key)
        }
        // Every literal localization call must have an English entry.
        let literal = try NSRegularExpression(pattern: #"L\(("(?:[^"\\]|\\.)*")"#)
        for file in ["main.swift", "ChatPicker.swift", "Following.swift", "UsageCore.swift"] {
            let text = try String(contentsOf: root.appendingPathComponent("Sources/" + file), encoding: .utf8)
            let ns = text as NSString
            for match in literal.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let key = try JSONDecoder().decode(String.self, from: Data(ns.substring(with: match.range(at: 1)).utf8))
                assert(dictionary[key] != nil, "Missing translation: \(key)")
            }
        }
        let title = "原聊天 {1} 90% \"quoted\""
        assert(translator.text("固定监控：{0}", [title], language: .english) == "Pinned: " + title)
        assert(translator.text("缓存 {0}", ["99%"], language: .english) == "Cache 99%")
        let suite = "cc-language-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        assert(AppLanguage.load(from: defaults) == .simplifiedChinese)
        AppLanguage.english.save(to: defaults)
        assert(AppLanguage.load(from: UserDefaults(suiteName: suite)!) == .english)
        AppLanguage.simplifiedChinese.save(to: defaults)
        assert(AppLanguage.load(from: defaults) == .simplifiedChinese)
        defaults.set("unknown", forKey: AppLanguage.preferenceKey)
        assert(AppLanguage.load(from: defaults) == .simplifiedChinese)
        let ref = SessionReference(id: "11111111-1111-4111-8111-111111111111", title: title, path: "/tmp/test.jsonl", cwd: "/private/tmp")
        let english = PreparedAction.handoff.command(for: ref, language: .english)
        for required in ["$handoff", "permission boundaries", "original working directory", "Create and open", "read-only", "Preserve the source chat", "Plan", ref.id, ref.cwd, "原聊天"] { assert(english.contains(required), required) }
        print("Passed: full English coverage; interpolation safety; language persistence and fallback; English handoff boundaries; manual handoff fallback.")
    }
}
