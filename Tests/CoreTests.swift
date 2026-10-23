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
        let low = try record(54, complete: true), high = try record(66, complete: false)
        assert(high.metrics?.contextPercent == 66 && high.taskRunning == true)
        assert(high.metrics?.cumulative.output == 100 && high.metrics?.cumulative.reasoning == 40)
        assert(high.metrics!.total == high.metrics!.input! + high.metrics!.cumulative.output!)
        assert(high.metrics?.cachePercent == ((66000 - 200) / (66000 - 100) * 100))
        var state = ReminderState(); state.observe(low, now: now, enabled: true)
        state.observe(high, now: now, enabled: true)
        assert(state.ready(high, now: now, enabled: true) == nil) // never interrupt real running turn
        let completed = try record(66, complete: true)
        state.observe(completed, now: now, enabled: true)
        assert(state.ready(completed, now: now, enabled: true) == 65)
        state.presented(65)
        state.observe(completed, now: now, enabled: true)
        assert(state.ready(completed, now: now, enabled: true) == nil)
        let ninety = try record(71, complete: true)
        state.observe(ninety, now: now, enabled: true); assert(state.ready(ninety, now: now, enabled: true) == 70); state.presented(70)
        var restarted = try JSONDecoder().decode(ReminderState.self, from: JSONEncoder().encode(state))
        restarted.observe(ninety, now: now, enabled: true); assert(restarted.ready(ninety, now: now, enabled: true) == nil)
        restarted.observe(low, now: now, enabled: true); restarted.observe(completed, now: now, enabled: true)
        assert(restarted.ready(completed, now: now, enabled: true) == 65)
        var stale = ReminderState(); stale.observe(low, now: now, enabled: true)
        let historic = try record(71, complete: true, age: 121)
        stale.observe(historic, now: now, enabled: true); assert(stale.ready(historic, now: now, enabled: true) == nil)
        var initial = ReminderState(); initial.observe(ninety, now: now, enabled: true); assert(initial.ready(ninety, now: now, enabled: true) == nil)
        var disabled = ReminderState(); disabled.observe(low, now: now, enabled: true); disabled.observe(ninety, now: now, enabled: false)
        assert(disabled.ready(ninety, now: now, enabled: false) == nil)
        var chats = ["a": state, "b": ReminderState()]; chats["b"]!.observe(completed, now: now, enabled: true)
        assert(chats["a"]!.presentedTier == 70 && chats["b"]!.presentedTier == 0)
        let unknown = UsageRecord(metrics: ninety.metrics, taskRunning: nil, completionID: nil)
        assert(restarted.ready(unknown, now: now, enabled: true) == nil)
        let overlap = event("task_started", ["turn_id": "new", "root_turn_id": "new"]) + token(71)
            + event("task_complete", ["turn_id": "old", "root_turn_id": "old"])
            + event("task_complete", ["turn_id": "child", "root_turn_id": "new"])
        try overlap.write(to: file, atomically: true, encoding: .utf8); assert((try? readUsage(file).taskRunning) == true)
        let incomplete = event("task_started", ["turn_id": "new"]) + token(71) + event("task_complete", ["turn_id": "new"]).trimmingCharacters(in: .newlines)
        try incomplete.write(to: file, atomically: true, encoding: .utf8); assert((try? readUsage(file).taskRunning) == true)
        // Threshold boundaries and visual policy share a single definition.
        for (occupancy, expected) in [(64.9, 0), (65.0, 65), (69.9, 65), (70.0, 70)] {
            var boundary = ReminderState(); boundary.observe(low, now: now, enabled: true)
            let sample = try record(occupancy, complete: true)
            boundary.observe(sample, now: now, enabled: true)
            assert(ReminderPolicy.tier(for: occupancy) == expected)
            assert(boundary.ready(sample, now: now, enabled: true) == (expected == 0 ? nil : expected))
        }
        var cycle = ReminderState(); cycle.observe(low, now: now, enabled: true)
        let sixtyFive = try record(65, complete: true), seventy = try record(70, complete: true)
        cycle.observe(sixtyFive, now: now, enabled: true); assert(cycle.ready(sixtyFive, now: now, enabled: true) == 65); cycle.presented(65)
        let between = try record(69.9, complete: true)
        cycle.observe(between, now: now, enabled: true); assert(cycle.ready(between, now: now, enabled: true) == nil)
        cycle.observe(seventy, now: now, enabled: true); assert(cycle.ready(seventy, now: now, enabled: true) == 70); cycle.presented(70)
        let fiftyFive = try record(55, complete: true)
        cycle.observe(fiftyFive, now: now, enabled: true); cycle.observe(seventy, now: now, enabled: true)
        assert(cycle.ready(seventy, now: now, enabled: true) == nil) // exactly55 does not rearm
        let below = try record(54.9, complete: true)
        cycle.observe(below, now: now, enabled: true); cycle.observe(sixtyFive, now: now, enabled: true)
        assert(cycle.ready(sixtyFive, now: now, enabled: true) == 65)
        cycle.presented(65)
        cycle = try JSONDecoder().decode(ReminderState.self, from: JSONEncoder().encode(cycle))
        cycle.observe(seventy, now: now, enabled: true); assert(cycle.ready(seventy, now: now, enabled: true) == 70)
        // Legacy states migrate once, clear pending work and baseline even the same event.
        for (oldTier, newTier) in [(0, 0), (80, 65), (90, 70)] {
            let legacy: [String: Any] = ["lastEvent": seventy.metrics!.eventID, "presentedTier": oldTier, "pendingTier": 90, "pendingEvent": "old"]
            var migrated = try JSONDecoder().decode(ReminderState.self, from: JSONSerialization.data(withJSONObject: legacy))
            assert(migrated.presentedTier == newTier && migrated.pendingTier == 0 && migrated.pendingEvent.isEmpty)
            assert(migrated.ready(seventy, now: now, enabled: true) == nil)
            migrated.observe(seventy, now: now, enabled: true)
            assert(migrated.ready(seventy, now: now, enabled: true) == nil)
            migrated = try JSONDecoder().decode(ReminderState.self, from: JSONEncoder().encode(migrated))
            assert(migrated.presentedTier == newTier && migrated.policyVersion == 3)
            let next = try record(71, complete: true)
            migrated.observe(next, now: now, enabled: true)
            assert(migrated.ready(next, now: now, enabled: true) == (newTier < 70 ? 70 : nil))
        }
        var independent = ["a": cycle, "b": ReminderState()]
        independent["b"]!.observe(low, now: now, enabled: true); independent["b"]!.observe(sixtyFive, now: now, enabled: true)
        assert(independent["b"]!.ready(sixtyFive, now: now, enabled: true) == 65)
        assert(independent["a"]!.presentedTier == 65)
        let source = SessionReference(id: "11111111-1111-4111-8111-111111111111", title: "有空格的聊天", path: file.path, cwd: "/private/tmp")
        assert(PreparedAction.disabledReason(source) == nil)
        let command = PreparedAction.handoff.command(for: source)
        for required in ["$handoff", "核对", "权限边界", "新建", "原工作目录", "先只读核验", "保留源聊天", "Plan", source.id, source.cwd] { assert(command.contains(required)) }
        assert(HandoffSource(source).url?.absoluteString == "codex://threads/\(source.id)")
        assert(PreparedAction.disabledReason(SessionReference(id: "", title: "", path: "")) != nil)
        assert(PreparedAction.disabledReason(SessionReference(id: source.id, title: "", path: "", cwd: "/missing/cc-test")) != nil)
        let bookmark = try JSONDecoder().decode(HandoffSource.self, from: JSONEncoder().encode(HandoffSource(source)))
        assert(bookmark.id == source.id && bookmark.cwd == source.cwd)
        print("Passed: usage splits and denominators; 65/70 thresholds; real completion gating; stale/unknown/partial/overlapping events; rearm below55; restart/dedup/per-chat/disabled state; pinned commands and validation; source bookmark.")
    }
}
