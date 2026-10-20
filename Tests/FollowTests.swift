import Foundation
import SQLite3

@main struct FollowTests {
    static func main() {
        let frame = CGRect(x: 100, y: 80, width: 1200, height: 800)
        assert(ChatFollower.isHeaderElement(CGRect(x: 500, y: 90, width: 160, height: 24), window: frame))
        assert(!ChatFollower.isHeaderElement(CGRect(x: 120, y: 500, width: 200, height: 24), window: frame))
        assert(!ChatFollower.isHeaderElement(CGRect(x: 600, y: 350, width: 160, height: 24), window: frame))
        assert(!ChatFollower.isHeaderElement(CGRect(x: 1400, y: 90, width: 160, height: 24), window: frame))
        assert(ChatFollower.windowIndex(main: [], focused: []) == nil)
        assert(ChatFollower.windowIndex(main: [false], focused: [false]) == 0)
        assert(ChatFollower.windowIndex(main: [true, false], focused: [false, false]) == 0)
        assert(ChatFollower.windowIndex(main: [true, false], focused: [false, true]) == 1)
        assert(ChatFollower.windowIndex(main: [false, false], focused: [false, false]) == nil)
        assert(ChatFollower.windowIndex(main: [true, true], focused: [false, false]) == nil)
        assert(ChatFollower.windowIndex(main: [false, false], focused: [true, true]) == nil)
        let catalog = SessionCatalog()
        let first = SessionReference(id: "11111111-1111-4111-8111-111111111111", title: "会话甲", path: "/tmp/a.jsonl")
        let second = SessionReference(id: "22222222-2222-4222-8222-222222222222", title: "会话乙", path: "/tmp/b.jsonl")
        catalog.byID = [first.id: first, second.id: second]
        catalog.byTitle = [first.title: [first], second.title: [second]]
        assert(catalog.resolve(route: "codex://threads/\(first.id)", titles: [second.title])?.0 == first)
        assert(catalog.resolve(route: "app://local/threads/\(second.id)?view=review", titles: [])?.0 == second)
        assert(catalog.resolve(route: nil, titles: [first.title])?.0 == first)
        assert(catalog.resolve(route: nil, titles: [second.title + " — ChatGPT"])?.0 == second)
        assert(catalog.resolve(route: nil, titles: [first.title, second.title]) == nil)
        assert(catalog.resolve(route: nil, titles: ["ChatGPT"]) == nil)
        assert(catalog.resolve(route: "codex://threads/33333333-3333-4333-8333-333333333333", titles: [first.title]) == nil)
        assert(SessionCatalog.routeThreadID("text mentions \(first.id)") == nil)
        catalog.byTitle[first.title] = [first, second]
        assert(catalog.resolve(route: nil, titles: [first.title]) == nil)
        if CommandLine.arguments.contains("--live-catalog") {
            let live = SessionCatalog()
            live.reload(force: true)
            assert(!live.byID.isEmpty)
        }
        let fixtureURL = FileManager.default.temporaryDirectory.appendingPathComponent("cc-catalog-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        var fixture: OpaquePointer?
        assert(sqlite3_open(fixtureURL.path, &fixture) == SQLITE_OK)
        let sql = """
            CREATE TABLE threads(id TEXT, title TEXT, name TEXT, rollout_path TEXT, source TEXT, thread_source TEXT, agent_path TEXT, cwd TEXT);
            INSERT INTO threads VALUES('11111111-1111-4111-8111-111111111111','第一条用户消息','界面显示名称','/tmp/a.jsonl','vscode',NULL,NULL,'/tmp');
            INSERT INTO threads VALUES('22222222-2222-4222-8222-222222222222','后台任务','界面显示名称','/tmp/b.jsonl','{"subagent":{"other":"guardian"}}','subagent',NULL,'/tmp');
            """
        assert(sqlite3_exec(fixture, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(fixture)
        let renamed = SessionCatalog(databaseURL: fixtureURL)
        renamed.reload(force: true)
        assert(renamed.resolve(route: nil, titles: ["界面显示名称"])?.0.id == first.id)
        assert(renamed.resolve(route: nil, titles: ["第一条用户消息"]) == nil)
        assert(renamed.byID[second.id] == nil)
        print("Passed: main-window fallback, ambiguous-window rejection, displayed-name regression, background-task exclusion, route matching, duplicate-title rejection and read-only catalog loading.")
    }
}
