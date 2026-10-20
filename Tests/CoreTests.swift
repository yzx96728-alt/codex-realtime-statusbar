import Foundation

@main struct CoreTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)), file = FileManager.default.temporaryDirectory.appendingPathComponent("cc-usage-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func event(_ type: String, _ extra: [String: Any] = [:], age: Double = 0) -> String {
            var payload = extra; payload["type"] = type
            return String(decoding: try! JSONSerialization.data(withJSONObject: ["type": "event_msg", "timestamp": iso.string(from: now.addingTimeInterval(-age)), "payload": payload], options: [.sortedKeys]), as: UTF8.self) + "\n"
        }
        func counts(_ n: Double) -> [String: Any] { ["total_tokens": n, "input_tokens": n - 100, "cached_input_tokens": n - 200, "output_tokens": 100, "reasoning_output_tokens": 40] }
        func token(_ occupancy: Double, age: Double = 0) -> String {
            event("token_count", ["info": ["total_token_usage": counts(occupancy * 1000), "last_token_usage": counts(occupancy * 100), "model_context_window": 10000], "rate_limits": ["primary": ["used_percent": 42.0]]], age: age)
        }
        func record(_ occupancy: Double, complete: Bool, age: Double = 0) throws -> UsageRecord {
            let text = event("task_started", ["turn_id": "root", "root_turn_id": "root"], age: age + 2) + token(occupancy, age: age)
                + (complete ? event("task_complete", ["turn_id": "root", "root_turn_id": "root"], age: age) : "")
            try text.write(to: file, atomically: true, encoding: .utf8)
            return try readUsage(file)
        }
        let low = try record(65, complete: true), high = try record(81, complete: false)
        assert(high.metrics?.contextPercent == 81 && high.taskRunning == true)
        assert(high.metrics?.cumulative.output == 100 && high.metrics?.cumulative.reasoning == 40)
        assert(high.metrics!.total == high.metrics!.input + high.metrics!.cumulative.output)
        assert(high.metrics?.cachePercent == ((81000 - 200) / (81000 - 100) * 100))
        var state = ReminderState(); state.observe(low, now: now, enabled: true)
        state.observe(high, now: now, enabled: true)
        assert(state.ready(high, now: now, enabled: true) == nil) // never interrupt real running turn
        let completed = try record(81, complete: true)
        state.observe(completed, now: now, enabled: true)
        assert(state.ready(completed, now: now, enabled: true) == 80)
        state.presented(80)
        state.observe(completed, now: now, enabled: true)
        assert(state.ready(completed, now: now, enabled: true) == nil)
        let ninety = try record(91, complete: true)
        state.observe(ninety, now: now, enabled: true); assert(state.ready(ninety, now: now, enabled: true) == 90); state.presented(90)
        var restarted = try JSONDecoder().decode(ReminderState.self, from: JSONEncoder().encode(state))
        restarted.observe(ninety, now: now, enabled: true); assert(restarted.ready(ninety, now: now, enabled: true) == nil)
        restarted.observe(low, now: now, enabled: true); restarted.observe(completed, now: now, enabled: true)
        assert(restarted.ready(completed, now: now, enabled: true) == 80)
        var stale = ReminderState(); stale.observe(low, now: now, enabled: true)
        let historic = try record(91, complete: true, age: 121)
        stale.observe(historic, now: now, enabled: true); assert(stale.ready(historic, now: now, enabled: true) == nil)
        var initial = ReminderState(); initial.observe(ninety, now: now, enabled: true); assert(initial.ready(ninety, now: now, enabled: true) == nil)
        var disabled = ReminderState(); disabled.observe(low, now: now, enabled: true); disabled.observe(ninety, now: now, enabled: false)
        assert(disabled.ready(ninety, now: now, enabled: false) == nil)
        var chats = ["a": state, "b": ReminderState()]; chats["b"]!.observe(completed, now: now, enabled: true)
        assert(chats["a"]!.presentedTier == 90 && chats["b"]!.presentedTier == 0)
        let unknown = UsageRecord(metrics: ninety.metrics, taskRunning: nil, completionID: nil)
        assert(restarted.ready(unknown, now: now, enabled: true) == nil)
        let overlap = event("task_started", ["turn_id": "new", "root_turn_id": "new"]) + token(91)
            + event("task_complete", ["turn_id": "old", "root_turn_id": "old"])
            + event("task_complete", ["turn_id": "child", "root_turn_id": "new"])
        try overlap.write(to: file, atomically: true, encoding: .utf8); assert((try? readUsage(file).taskRunning) == true)
        let incomplete = event("task_started", ["turn_id": "new"]) + token(91) + event("task_complete", ["turn_id": "new"]).trimmingCharacters(in: .newlines)
        try incomplete.write(to: file, atomically: true, encoding: .utf8); assert((try? readUsage(file).taskRunning) == true)
        let source = SessionReference(id: "11111111-1111-4111-8111-111111111111", title: "有空格的聊天", path: file.path, cwd: "/private/tmp")
        assert(PreparedAction.disabledReason(source) == nil)
        assert(PreparedAction.compact.command(for: source) == "/compact")
        let command = PreparedAction.handoff.command(for: source)
        for required in ["$handoff", "核对", "权限边界", "新建", "原工作目录", "先只读核验", "保留源聊天", "Plan", source.id, source.cwd] { assert(command.contains(required)) }
        assert(HandoffSource(source).url?.absoluteString == "codex://threads/\(source.id)")
        assert(PreparedAction.disabledReason(SessionReference(id: "", title: "", path: "")) != nil)
        assert(PreparedAction.disabledReason(SessionReference(id: source.id, title: "", path: "", cwd: "/missing/cc-test")) != nil)
        let bookmark = try JSONDecoder().decode(HandoffSource.self, from: JSONEncoder().encode(HandoffSource(source)))
        assert(bookmark.id == source.id && bookmark.cwd == source.cwd)
        print("Passed: usage splits and denominators; 80/90 thresholds; real completion gating; stale/unknown/partial/overlapping events; rearm below70; restart/dedup/per-chat/disabled state; pinned commands and validation; source bookmark.")
    }
}
