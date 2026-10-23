import Foundation

@main struct UsageEventTests {
    static func main() throws {
        for occupancy in [64.9, 65, 69.9, 70, 55, 54.9] {
            let tier = ReminderPolicy.tier(for: occupancy)
            assert(ReminderPolicy.presentsHint(tier: tier) == (occupancy >= 70))
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("usage-events-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func line(_ type: String, _ payload: [String: Any], seconds: Double = 0) -> String {
            String(decoding: try! JSONSerialization.data(withJSONObject: ["type": type, "timestamp": iso.string(from: now.addingTimeInterval(seconds)), "payload": payload], options: [.sortedKeys]), as: UTF8.self) + "\n"
        }
        func lifecycle(_ type: String, _ task: String = "a") -> String { line("event_msg", ["type": type, "turn_id": task, "root_turn_id": task]) }
        func values(_ total: Double, input: Double? = nil, output: Double = 100) -> [String: Any] {
            ["total_tokens": total, "input_tokens": input ?? total - output, "output_tokens": output,
             "cached_input_tokens": max(0, (input ?? total - output) - 100), "reasoning_output_tokens": min(40, output)]
        }
        func token(_ total: Double, cumulative: Double, seconds: Double = 0, response: String = "", baseline: Bool = false) -> String {
            var p: [String: Any] = ["type": "token_count", "info": ["last_token_usage": values(total, input: baseline ? 0 : nil, output: baseline ? 0 : 100), "total_token_usage": values(cumulative), "model_context_window": 10000], "rate_limits": ["primary": ["used_percent": seconds]]]
            if !response.isEmpty { p["response_id"] = response }
            return line("event_msg", p, seconds: seconds)
        }
        let compact = line("compacted", [:])
        func read(_ text: String, limit: Int = 16 * 1024 * 1024) throws -> UsageRecord {
            try Data(text.utf8).write(to: file)
            return try readUsage(file, maximumLineBytes: limit)
        }
        let start = lifecycle("task_started"), lowText = start + token(5000, cumulative: 5000)
        let highText = lowText + token(7100, cumulative: 12100)
        let low = try read(lowText), high = try read(highText)
        var state = ReminderState(); state.observe(low, now: now, enabled: true); state.observe(high, now: now, enabled: true)
        assert(state.pendingTier == 70 && state.ready(high, now: now, enabled: true) == nil)
        let compressed = try read(highText + compact)
        state.observe(compressed, now: now, enabled: true)
        assert(compressed.compactionConfirmed && compressed.awaitingBaseline)
        assert(compressed.metrics?.contextPercent == nil && state.pendingTier == 0)
        assert(state.ready(compressed, now: now, enabled: true) == nil)
        let baselineText = highText + compact + token(1046, cumulative: 12100, seconds: 0.008, baseline: true)
        let baseline = try read(baselineText + lifecycle("task_complete"))
        assert(baseline.metrics?.kind == .compactionBaseline && baseline.metrics?.recent == 1046)
        assert(abs(baseline.metrics!.contextPercent! - 10.46) < 0.00001)
        assert(baseline.metrics?.last?.input == 0 && baseline.metrics?.last?.output == 0)
        assert(baseline.metrics?.last?.isRequest == false)
        state.observe(baseline, now: now.addingTimeInterval(1), enabled: true)
        assert(state.presentedTier == 0 && state.pendingTier == 0)
        assert(state.ready(baseline, now: now.addingTimeInterval(1), enabled: true) == nil)
        var skippedBaseline = ReminderState(); skippedBaseline.observe(low, now: now, enabled: true); skippedBaseline.presented(70)
        let after = try read(baselineText + token(6600, cumulative: 18700, seconds: 1) + lifecycle("task_complete"))
        skippedBaseline.observe(after, now: now.addingTimeInterval(1), enabled: true)
        assert(skippedBaseline.ready(after, now: now.addingTimeInterval(1), enabled: true) == 65)
        skippedBaseline.presented(65)
        skippedBaseline.observe(after, now: now.addingTimeInterval(1), enabled: true)
        assert(skippedBaseline.ready(after, now: now.addingTimeInterval(1), enabled: true) == nil)
        state.observe(after, now: now.addingTimeInterval(1), enabled: true)
        assert(state.ready(after, now: now.addingTimeInterval(1), enabled: true) == 65)
        assert(!ReminderPolicy.presentsHint(tier: state.ready(after, now: now.addingTimeInterval(1), enabled: true)!))
        var prominent = ReminderState(); prominent.observe(low, now: now, enabled: true)
        let completedHigh = try read(highText + lifecycle("task_complete"))
        prominent.observe(completedHigh, now: now, enabled: true)
        assert(ReminderPolicy.presentsHint(tier: prominent.ready(completedHigh, now: now, enabled: true)!))
        let hintEvent = completedHigh.metrics!.eventID
        assert(ReminderPolicy.keepsHint(completedHigh, eventID: hintEvent, now: now))
        assert(!ReminderPolicy.keepsHint(completedHigh, eventID: hintEvent, now: now.addingTimeInterval(121)))
        assert(!ReminderPolicy.keepsHint(high, eventID: hintEvent, now: now))
        assert(!ReminderPolicy.keepsHint(compressed, eventID: hintEvent, now: now))
        assert(!ReminderPolicy.keepsHint(baseline, eventID: hintEvent, now: now))
        assert(!ReminderPolicy.keepsHint(completedHigh, eventID: "other-event", now: now))
        let cancelledHint = try read(highText + lifecycle("task_complete") + lifecycle("turn_aborted"))
        assert(!ReminderPolicy.keepsHint(cancelledHint, eventID: hintEvent, now: now))
        let lateRequest = try read(highText + lifecycle("task_complete") + token(7200, cumulative: 19300, seconds: 1))
        assert(!ReminderPolicy.keepsHint(lateRequest, eventID: hintEvent, now: now.addingTimeInterval(1)))
        prominent.presented(70)
        assert(prominent.ready(completedHigh, now: now, enabled: true) == nil)
        // Same payload at a new broadcast timestamp does not refresh usage or grant alerts.
        let duplicate = try read(highText + token(7100, cumulative: 12100, seconds: 119) + lifecycle("task_complete"))
        assert(duplicate.metrics?.eventID == high.metrics?.eventID)
        assert(duplicate.metrics?.timestamp == high.metrics?.timestamp)
        assert(duplicate.metrics?.limitsTimestamp != duplicate.metrics?.timestamp)
        var stale = ReminderState(); stale.observe(low, now: now, enabled: true)
        stale.observe(duplicate, now: now.addingTimeInterval(121), enabled: true)
        assert(stale.ready(duplicate, now: now.addingTimeInterval(121), enabled: true) == nil)
        let sameLastNewTotal = try read(highText + token(7100, cumulative: 19200, seconds: 1))
        assert(sameLastNewTotal.metrics?.eventID != high.metrics?.eventID)
        let newResponse = try read(highText + token(7100, cumulative: 12100, seconds: 1, response: "request-b"))
        assert(newResponse.metrics?.eventID != high.metrics?.eventID)
        let newTask = try read(highText + lifecycle("task_started", "b") + token(7100, cumulative: 12100, seconds: 1))
        assert(newTask.metrics?.eventID != high.metrics?.eventID)
        // Completing a different task, changing cycle, or aborting never releases an old alert.
        var pending = ReminderState(); pending.observe(low, now: now, enabled: true); pending.observe(high, now: now, enabled: true)
        let otherComplete = try read(highText + lifecycle("task_started", "b") + lifecycle("task_complete", "b"))
        assert(pending.ready(otherComplete, now: now, enabled: true) == nil)
        pending.observe(otherComplete, now: now, enabled: true); assert(pending.pendingTier == 0)
        let aborted = try read(highText + lifecycle("turn_aborted") + lifecycle("task_complete"))
        assert(aborted.taskAborted && aborted.taskRunning == false && aborted.completionID == nil)
        pending.observe(aborted, now: now, enabled: true); assert(pending.ready(aborted, now: now, enabled: true) == nil)
        var wrongCycle = high; wrongCycle.cycleID = "different-cycle"
        assert(state.ready(wrongCycle, now: now, enabled: true) == nil)
        // A high post-compaction baseline does not bypass the below55 rearm rule.
        var presented = ReminderState(); presented.observe(low, now: now, enabled: true); presented.presented(70)
        let highBaseline = try read(highText + compact + token(6000, cumulative: 12100, baseline: true))
        presented.observe(highBaseline, now: now, enabled: true); assert(presented.presentedTier == 70)
        let lateUsage = try read(highText + lifecycle("task_complete") + token(7100, cumulative: 19200, seconds: 1))
        assert(lateUsage.completionID == nil)
        // A baseline-like token without a confirmed compaction has unknown semantics.
        let unknown = try read(start + token(1046, cumulative: 12100, baseline: true))
        assert(unknown.metrics?.kind == .unknown && unknown.metrics?.contextPercent == nil)
        let missing = line("event_msg", ["type": "token_count", "info": ["total_token_usage": ["total_tokens": 10], "last_token_usage": ["total_tokens": 10], "model_context_window": 100]])
        let partial = try read(start + missing)
        assert(partial.metrics?.last?.input == nil && partial.metrics?.kind == .unknown && partial.metrics?.contextPercent == nil)
        // An incomplete line cannot complete a task. Appending the newline makes it valid.
        let partialText = highText + lifecycle("task_complete").trimmingCharacters(in: .newlines)
        let incomplete = try read(partialText), appended = try read(partialText + "\n")
        assert(incomplete.taskRunning == true && appended.taskRunning == false)
        _ = try read(partialText)
        let appendHandle = try FileHandle(forWritingTo: file); try appendHandle.seekToEnd()
        try appendHandle.write(contentsOf: Data([10])); try appendHandle.close()
        let appendedOnDisk = try readUsage(file); assert(appendedOnDisk.taskRunning == false)
        // Real audit had a 4.1MB line. Support even >8MiB without discarding history.
        let giant = line("response_item", ["type": "test_blob", "padding": String(repeating: "x", count: 9 * 1024 * 1024)])
        let long = try read(lowText + giant + token(7100, cumulative: 12100) + lifecycle("task_complete"))
        assert(long.metrics?.recent == 7100 && long.taskRunning == false && !long.hasReadGap)
        let giantCompact = line("compacted", ["message": String(repeating: "x", count: 9 * 1024 * 1024)])
        let largeCompaction = try read(lowText + giantCompact + token(1046, cumulative: 12100, baseline: true))
        assert(largeCompaction.compactionConfirmed && largeCompaction.metrics?.kind == .compactionBaseline && !largeCompaction.hasReadGap)
        let oversize = try read(lowText + giant + token(7100, cumulative: 12100) + lifecycle("task_complete"), limit: 1024 * 1024)
        assert(oversize.hasReadGap)
        pending.observe(oversize, now: now, enabled: true); assert(pending.ready(oversize, now: now, enabled: true) == nil)
        let malformed = try read(lowText + "{\"type\":\"compacted\",BROKEN}\n" + token(7100, cumulative: 12100))
        assert(malformed.hasReadGap)
        // Restart discards pending but keeps presented dedup; migration is exercised in CoreTests.
        var restart = ReminderState(); restart.observe(low, now: now, enabled: true); restart.observe(high, now: now, enabled: true)
        restart = try JSONDecoder().decode(ReminderState.self, from: JSONEncoder().encode(restart))
        assert(restart.pendingTier == 0)
        let completed = try read(highText + lifecycle("task_complete"))
        assert(restart.ready(completed, now: now, enabled: true) == nil)
        let legacy17: [String: Any] = ["policyVersion": 2, "lastEvent": "legacy", "presentedTier": 65, "pendingTier": 70, "pendingEvent": "legacy-pending", "needsBaseline": false]
        var migrated17 = try JSONDecoder().decode(ReminderState.self, from: JSONSerialization.data(withJSONObject: legacy17))
        assert(migrated17.policyVersion == 3 && migrated17.presentedTier == 65 && migrated17.pendingTier == 0)
        migrated17.observe(completed, now: now, enabled: true)
        assert(migrated17.ready(completed, now: now, enabled: true) == nil)
        var gate = UsageReadGate()
        let a = gate.begin(sessionID: "a", path: "/a")
        gate.invalidate(); let b = gate.begin(sessionID: "b", path: "/b")
        assert(!gate.finish(a, sessionID: "b", path: "/b") && gate.current == b)
        gate.invalidate(); let aAgain = gate.begin(sessionID: "a", path: "/a")
        assert(!gate.finish(a, sessionID: "a", path: "/a"))
        assert(gate.finish(aAgain, sessionID: "a", path: "/a"))
        // Hold a real serial background read at delivery while the target changes.
        let background = DispatchQueue(label: "usage-reader-test")
        let computed = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), delivered = DispatchSemaphore(value: 0)
        let oldTicket = gate.begin(sessionID: "a", path: file.path)
        background.async {
            _ = try? readUsage(file)
            computed.signal(); release.wait(); delivered.signal()
        }
        assert(computed.wait(timeout: .now() + 5) == .success)
        gate.invalidate(); let newest = gate.begin(sessionID: "b", path: "/b")
        release.signal(); assert(delivered.wait(timeout: .now() + 5) == .success)
        assert(!gate.finish(oldTicket, sessionID: "b", path: "/b") && gate.current == newest)
        do { _ = try readUsage(file.appendingPathComponent("missing")); assertionFailure("Expected read failure") } catch {}
        print("Passed: audited compaction baseline, duplicate broadcasts, equal-sized real requests, cancellation, task/cycle binding, restart, partial append, >8MiB lines, bounded failure and stale-read gate.")
    }
}
