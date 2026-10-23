import AppKit
import ApplicationServices
import Foundation

let arguments = CommandLine.arguments
if arguments.contains("--list-chats") {
    let rows = availableChats().map { ["id": $0.reference.id, "title": $0.reference.title, "path": $0.reference.path, "cwd": $0.reference.cwd, "detail": $0.detail] }
    if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]) { print(String(decoding: data, as: UTF8.self)); exit(0) }
    exit(1)
}
if arguments.contains("--check") {
    do {
        guard let path = arguments.last else { exit(2) }
        let r = try readUsage(URL(fileURLWithPath: path))
        guard let m = r.metrics else { print("No usage event available"); exit(2) }
        let result: [String: Any] = ["total_tokens": m.total, "input_tokens": m.input, "cached_input_tokens": m.cached,
            "output_tokens": m.cumulative.output, "reasoning_output_tokens": m.cumulative.reasoning,
            "context_percent_estimate": m.contextPercent as Any? ?? NSNull(), "timestamp": m.timestamp,
            "task_running": r.taskRunning as Any? ?? NSNull()]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self)); exit(0)
    } catch { print("Read failed: \(error.localizedDescription)"); exit(1) }
}
final class FloatingPanel: NSPanel { override var canBecomeKey: Bool { true } }
final class HoverSurface: NSView {
    var onHover: ((Bool) -> Void)?
    private var area: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(next); area = next
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
final class ActionButton: NSButton {
    var invoke: (() -> Void)?
    init(_ title: String, invoke: @escaping () -> Void) {
        self.invoke = invoke; super.init(frame: .zero)
        self.title = title; bezelStyle = .rounded; target = self; action = #selector(runAction)
        font = .systemFont(ofSize: 11)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func runAction() { invoke?() }
}
func textLabel(_ text: String, bold: Bool = false) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.preferredMaxLayoutWidth = 338
    field.font = .systemFont(ofSize: bold ? 12 : 11, weight: bold ? .semibold : .regular)
    field.textColor = bold ? .labelColor : .secondaryLabelColor
    field.setContentCompressionResistancePriority(.required, for: .vertical)
    return field
}
func cardView(_ views: [NSView], width: CGFloat = 370) -> NSView {
    let stack = NSStackView(views: views); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 9
    stack.translatesAutoresizingMaskIntoConstraints = false
    let view = NSView(); view.addSubview(stack)
    NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant: width),
        stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14), stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14)])
    for child in views { child.widthAnchor.constraint(lessThanOrEqualToConstant: width - 32).isActive = true }
    view.layoutSubtreeIfNeeded(); view.setFrameSize(view.fittingSize)
    let maximum = max(260, (NSScreen.main?.visibleFrame.height ?? 800) - 100)
    if view.fittingSize.height > maximum {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: maximum))
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalToConstant: width), scroll.heightAnchor.constraint(equalToConstant: maximum)])
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false; scroll.documentView = view
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, view.frame.height - maximum)))
        return scroll
    }
    return view
}

final class Monitor: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var panel: NSPanel!
    var timer: Timer?, observer: NSObjectProtocol?
    var selected: URL?, reference: SessionReference?, snapshot: UsageSnapshot?
    var metricModification: Date?
    let follower = ChatFollower()
    let detectionQueue = DispatchQueue(label: "local.cc.usage-following", qos: .utility)
    var detecting = false, generation = 0
    var suppressReminders = false
    var followEnabled = UserDefaults.standard.object(forKey: "followCurrentChat") as? Bool ?? false
    var followStatus = L("等待识别当前聊天")
    var chosenTitle = L("手动选定聊天")
    var chatPicker: ChatPicker?
    let tokens = NSButton(title: "— tok", target: nil, action: nil)
    let cache = NSButton(title: L("缓存 —"), target: nil, action: nil)
    let context = NSButton(title: L("上下文 —"), target: nil, action: nil)
    let mode = NSButton(title: "↪", target: nil, action: nil)
    let session = NSButton(title: "⋯", target: nil, action: nil)
    var idleOpacity: CGFloat = {
        let value = UserDefaults.standard.object(forKey: "idleOpacity") as? Double ?? 0.42
        return CGFloat(min(0.94, max(0.15, value)))
    }()
    var alertsEnabled = UserDefaults.standard.object(forKey: "contextAlertsEnabled") as? Bool ?? true
    var reminderStates: [String: ReminderState] = {
        guard let data = UserDefaults.standard.data(forKey: "contextReminderStates"), let states = try? JSONDecoder().decode([String: ReminderState].self, from: data) else { return [:] }
        return states
    }()
    var detail: NSPopover?, hint: NSPanel?
    var detailTag: Int?
    var hintReminderID: String?, restorePicker = false
    var lastSource: HandoffSource? = {
        guard let data = UserDefaults.standard.data(forKey: "lastHandoffSource") else { return nil }
        return try? JSONDecoder().decode(HandoffSource.self, from: data)
    }()
    let preferenceKey = "selectedSession"
    var frontID: String { NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "" }
    var isCodex: Bool { frontID == "com.openai.codex" }
    var ownsForeground: Bool { frontID == Bundle.main.bundleIdentifier }
    var allowedVisible: Bool { isCodex || ownsForeground }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let saved = UserDefaults.standard.string(forKey: preferenceKey) { selected = URL(fileURLWithPath: saved) }
        else if let initial = Bundle.main.object(forInfoDictionaryKey: "CCInitialSessionPath") as? String { selected = URL(fileURLWithPath: initial.trimmingCharacters(in: .whitespacesAndNewlines)) }
        reference = availableChats().first(where: { $0.reference.path == selected?.path })?.reference
        chosenTitle = reference?.title ?? chosenTitle
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 348, height: 30), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = L("Codex实时状态栏"); panel.isFloatingPanel = true; panel.level = .floating
        panel.hidesOnDeactivate = false; panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.isReleasedWhenClosed = false
        panel.delegate = self; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.alphaValue = idleOpacity
        panel.setFrameAutosaveName("CCUsageCompactPanel")
        let surface = HoverSurface(); surface.wantsLayer = true; surface.layer?.cornerRadius = 9
        surface.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.8).cgColor
        surface.onHover = { [weak self] hovering in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { animation in animation.duration = 0.18; self.panel.animator().alphaValue = hovering ? 0.94 : self.idleOpacity }
        }
        panel.contentView = surface
        for (index, button) in [tokens, cache, context].enumerated() {
            button.isBordered = false; button.bezelStyle = .inline
            button.font = .monospacedDigitSystemFont(ofSize: index == 1 ? 10.5 : 11, weight: .regular)
            button.contentTintColor = .secondaryLabelColor; button.target = self; button.action = #selector(showDetail(_:)); button.tag = index
        }
        for button in [mode, session] { button.isBordered = false; button.bezelStyle = .inline; button.contentTintColor = .secondaryLabelColor; button.target = self }
        mode.font = .systemFont(ofSize: 10); mode.action = #selector(showDetail(_:)); mode.tag = 2
        session.font = .systemFont(ofSize: 15); session.action = #selector(showMenu)
        let separators = (0..<2).map { _ in let l = NSTextField(labelWithString: "·"); l.textColor = .tertiaryLabelColor; return l }
        let row = NSStackView(views: [mode, tokens, separators[0], cache, separators[1], context, session])
        row.orientation = .horizontal; row.distribution = .equalSpacing; row.alignment = .centerY; row.spacing = 3
        row.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 8), row.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -7), row.centerYAnchor.constraint(equalTo: surface.centerYAnchor), session.widthAnchor.constraint(equalToConstant: 16), mode.widthAnchor.constraint(equalToConstant: 12)])
        if !panel.setFrameUsingName("CCUsageCompactPanel"), let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 364, y: screen.visibleFrame.minY + 12)) }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.foregroundChanged() }
        refresh(); timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func foregroundChanged() {
        generation += 1
        if !allowedVisible {
            restorePicker = chatPicker?.window?.isVisible == true
            detail?.close(); dismissHint(); chatPicker?.window?.orderOut(nil); panel.orderOut(nil)
            UserDefaults.standard.set("hidden", forKey: "visibilityDiagnostic")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastHiddenAt")
        } else if isCodex {
            // A fresh identity check completes before restoring the bar.
            panel.orderOut(nil); UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastCodexReturnAt"); refresh()
        } else { reveal() }
    }
    func reveal() {
        guard allowedVisible else { return }
        panel.orderFrontRegardless()
        if restorePicker { chatPicker?.window?.orderFrontRegardless(); restorePicker = false }
        UserDefaults.standard.set("visible", forKey: "visibilityDiagnostic")
    }
    func refresh() {
        guard allowedVisible else { return }
        mode.title = followEnabled ? "↪" : "⌖"
        mode.toolTip = followEnabled ? L("自动跟随当前聊天") : L("固定监控：{0}", String(describing: chosenTitle))
        guard followEnabled else { refreshMetrics(); reveal(); return }
        // Own menus and cards retain their pinned target without doing AX work.
        guard isCodex else { reveal(); return }
        guard !detecting else { return }
        detecting = true; let revision = generation
        detectionQueue.async { [weak self] in
            guard let self else { return }; let result = self.follower.current()
            DispatchQueue.main.async {
                self.detecting = false
                guard self.followEnabled, revision == self.generation, self.isCodex else { return }
                switch result {
                case .matched(let ref, let method):
                    self.recordFollowDiagnostic("matched")
                    if self.reference?.id != ref.id || self.selected?.path != ref.path { self.resetSnapshot(); self.selected = URL(fileURLWithPath: ref.path) }
                    self.reference = ref; self.chosenTitle = ref.title
                    self.followStatus = L("自动跟随：{0}（{1}）", String(describing: ref.title), String(describing: method))
                    self.refreshMetrics()
                case .permissionRequired:
                    self.recordFollowDiagnostic("permission-required"); self.resetSnapshot(); self.reference = nil
                    self.followStatus = L("辅助功能权限失效 · 点 ⋯ 检查"); self.clearDisplay(L("需授权自动跟随"))
                case .unavailable(let reason):
                    self.recordFollowDiagnostic(reason); self.resetSnapshot(); self.reference = nil; self.followStatus = reason; self.clearDisplay(reason)
                }
                self.reveal()
            }
        }
    }
    func recordFollowDiagnostic(_ value: String) {
        if UserDefaults.standard.string(forKey: "followDiagnostic") != value { UserDefaults.standard.set(value, forKey: "followDiagnostic") }
    }
    func resetSnapshot() { snapshot = nil; metricModification = nil; detail?.close(); dismissHint() }
    func clearDisplay(_ message: String) {
        tokens.title = message; tokens.toolTip = followStatus; cache.title = "—"; context.title = L("上下文 —")
        context.contentTintColor = .secondaryLabelColor
        for button in [cache, context, session] { button.toolTip = followStatus }
    }
    func refreshMetrics() {
        guard let selected else { clearDisplay(L("未选择聊天")); return }
        do {
            let modification = try selected.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if snapshot == nil || modification != metricModification {
                let record = try readUsage(selected)
                let ref = reference ?? SessionReference(id: "", title: chosenTitle, path: selected.path)
                snapshot = UsageSnapshot(reference: ref, record: record); metricModification = modification
                var state = reminderStates[ref.id] ?? ReminderState()
                let old = state
                state.observe(record, now: Date(), enabled: alertsEnabled)
                reminderStates[ref.id] = state
                if state != old { saveReminders() }
            }
            guard let snapshot, let m = snapshot.metrics else { clearDisplay(L("等待用量数据")); return }
            tokens.title = "\(short(m.total)) tok"; cache.title = L("缓存 {0}", String(describing: percent(m.cachePercent))); context.title = L("上下文≈{0}", String(describing: percent(m.contextPercent)))
            let tier = ReminderPolicy.tier(for: m.contextPercent ?? 0)
            context.contentTintColor = tier >= ReminderPolicy.secondTier ? .systemRed : tier >= ReminderPolicy.firstTier ? .systemOrange : .secondaryLabelColor
            let status = followEnabled ? followStatus : L("固定监控：{0}", String(describing: snapshot.reference.title))
            let time = L("记录 {0}{1}", String(describing: timestampLabel(m.timestamp)), String(describing: (m.date.map { Date().timeIntervalSince($0) > 120 } ?? true) ? L("（历史快照）") : ""))
            for button in [tokens, cache, context, session] { button.toolTip = L("{0}\n{1}\n点击查看详情 · 监控不调用模型", String(describing: status), String(describing: time)) }
            UserDefaults.standard.set(snapshot.reference.id, forKey: "monitoredChatDiagnostic")
            UserDefaults.standard.set(m.timestamp, forKey: "usageTimestampDiagnostic")
            maybeRemind(snapshot)
        } catch { resetSnapshot(); clearDisplay(L("记录读取失败")); session.toolTip = error.localizedDescription }
    }
    func saveReminders() { if let data = try? JSONEncoder().encode(reminderStates) { UserDefaults.standard.set(data, forKey: "contextReminderStates") } }
    func maybeRemind(_ snapshot: UsageSnapshot) {
        guard !suppressReminders, allowedVisible, hint == nil, detail?.isShown != true, chatPicker?.window?.isVisible != true,
              let tier = reminderStates[snapshot.reference.id]?.ready(snapshot.record, now: Date(), enabled: alertsEnabled) else { return }
        reminderStates[snapshot.reference.id]?.presented(tier); saveReminders()
        let views: [NSView] = [textLabel(L("上下文估算达到 {0}%", String(describing: tier)), bold: true), textLabel(L("{0}\n本轮任务已结束。可在合适阶段准备交接，为整理材料预留空间；估算值不代表必须换聊天。", String(describing: snapshot.reference.title))), commandButtons(snapshot), ActionButton(L("稍后")) { [weak self] in self?.dismissHint() }]
        showHint(views); hintReminderID = snapshot.reference.id
    }
    func showHint(_ views: [NSView]) {
        dismissHint()
        guard allowedVisible else { return }
        let view = cardView(views)
        let window = NSPanel(contentRect: NSRect(origin: .zero, size: view.fittingSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = L("Codex 状态提示"); window.level = .floating; window.isReleasedWhenClosed = false; window.hidesOnDeactivate = false
        window.backgroundColor = .windowBackgroundColor; window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; window.contentView = view
        let screen = panel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let x = min(max(panel.frame.minX, screen.minX + 8), screen.maxX - window.frame.width - 8)
        let below = panel.frame.minY - window.frame.height - 8
        let y = below >= screen.minY ? below : min(screen.maxY - window.frame.height, panel.frame.maxY + 8)
        window.setFrameOrigin(NSPoint(x: x, y: y)); hint = window; window.orderFrontRegardless()
    }
    func dismissHint() { hint?.orderOut(nil); hint = nil; hintReminderID = nil }
    func notice(_ message: String) {
        showHint([textLabel(message), ActionButton(L("知道了")) { [weak self] in self?.dismissHint() }])
    }
    @objc func showDetail(_ sender: NSButton) {
        if detail?.isShown == true {
            detail?.close()
            if detailTag == sender.tag { detailTag = nil; return }
        }
        detailTag = sender.tag
        dismissHint()
        guard let snapshot, let m = snapshot.metrics else { notice(L("{0}\n当前没有可核验的用量快照。", String(describing: followStatus))); return }
        let title = sender.tag == 0 ? L("Token 用量") : sender.tag == 1 ? L("缓存命中") : L("上下文占用（估算）")
        var views: [NSView] = [textLabel(title, bold: true), textLabel("\(followEnabled ? L("↪ 自动跟随") : L("⌖ 固定监控")) · \(snapshot.reference.title)"), textLabel(L("记录时间：{0}", String(describing: timestampLabel(m.timestamp))))]
        if sender.tag == 0 {
            let a = m.cumulative
            views.append(textLabel(L("累计处理：{0} tok\n输入：{1}（其中缓存 {2}）\n输出：{3}（其中思考 {4}）", String(describing: number(a.total)), String(describing: number(a.input)), String(describing: number(a.cached)), String(describing: number(a.output)), String(describing: number(a.reasoning)))))
            if let b = m.last { views.append(textLabel(L("最近请求：{0} tok\n输入：{1}（其中缓存 {2}）\n输出：{3}（其中思考 {4}）", String(describing: number(b.total)), String(describing: number(b.input)), String(describing: number(b.cached)), String(describing: number(b.output)), String(describing: number(b.reasoning))))) }
            views.append(textLabel(L("总量为输入 + 输出。缓存计入输入；思考计入输出，不重复相加。累计包含重复发送的上下文，不等于费用或上下文长度。")))
        } else if sender.tag == 1 {
            views.append(textLabel(L("累计缓存命中率：{0}\n缓存输入 {1} ÷ 全部输入 {2} × 100%", String(describing: percent(m.cachePercent)), String(describing: number(m.cached)), String(describing: number(m.input)))))
            if let b = m.last { views.append(textLabel(L("最近请求：缓存 {0} / 输入 {1}\n命中率 {2}", String(describing: number(b.cached)), String(describing: number(b.input)), String(describing: percent(b.input > 0 ? b.cached / b.input * 100 : nil))))) }
            views.append(textLabel(L("只统计输入缓存命中，不含输出，也不是价格折扣比例。输入为零时不计算。")))
        } else {
            views.append(textLabel(L("估算占用：{0}\n最近请求总 token {1} ÷ 记录的窗口容量 {2}", String(describing: percent(m.contextPercent)), String(describing: number(m.recent)), String(describing: number(m.capacity)))))
            views.append(textLabel(L("最近请求包含输入和输出。这是本地记录的估算，压缩或请求完成后可能变化；不作为必须换聊天的判断。")))
            views.append(commandButtons(snapshot))
        }
        views.append(textLabel(L("账号额度 · 会话历史快照"), bold: true))
        views.append(textLabel(L("5 小时剩余：{0}\n每周剩余：{1}\n来源：此聊天的 token_count / rate_limits\n采集时间：{2}\n非实时余额；账号共享额度可能已变化。", String(describing: remaining(m, "primary")), String(describing: remaining(m, "secondary")), String(describing: timestampLabel(m.timestamp)))))
        let controller = NSViewController(); controller.view = cardView(views)
        let popover = NSPopover(); popover.behavior = .transient; popover.animates = false
        popover.contentViewController = controller; popover.contentSize = controller.view.fittingSize; detail = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }
    func commandButtons(_ source: UsageSnapshot) -> NSView {
        let name = source.reference.title.count > 16 ? String(source.reference.title.prefix(16)) + "…" : source.reference.title
        let handoff = ActionButton(L("准备交接 · {0}", String(describing: name))) { [weak self] in self?.prepare(.handoff, source: source) }
        let reason = PreparedAction.disabledReason(source.reference)
        for button in [handoff] { button.isEnabled = reason == nil; button.toolTip = reason ?? L("目标：{0}\n目录：{1}\n复制指令并返回此聊天；由你粘贴后发送。", String(describing: source.reference.title), String(describing: source.reference.cwd)) }
        let row = NSStackView(views: [handoff]); row.orientation = .vertical; row.alignment = .leading; row.spacing = 6
        let stack = NSStackView(views: [row, textLabel(reason ?? L("目标：{0}\n目录：{1}", String(describing: source.reference.title), String(describing: source.reference.cwd)))]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        return stack
    }
    func prepare(_ action: PreparedAction, source: UsageSnapshot) {
        let target = source.reference
        guard let reason = PreparedAction.disabledReason(target) else {
            guard let url = HandoffSource(target).url else { return }
            let board = NSPasteboard.general; board.clearContents()
            let command = action.command(for: target)
            guard board.setString(command, forType: .string), board.string(forType: .string) == command else { notice(L("剪贴板写入失败，请重试。")); return }
            lastSource = HandoffSource(target); if let data = try? JSONEncoder().encode(lastSource) { UserDefaults.standard.set(data, forKey: "lastHandoffSource") }
            detail?.close(); dismissHint()
            let opened = NSWorkspace.shared.open(url)
            UserDefaults.standard.set(["id": target.id, "action": "handoff", "clipboardVerified": true, "linkOpened": opened] as [String: Any], forKey: "preparedActionDiagnostic")
            notice(L("{0}\n指令已复制，按 ⌘V 后发送。{1}\n{2}", String(describing: target.title), String(describing: opened ? "" : L("\n未能打开聊天链接，请手动返回此聊天。")), String(describing: L("尚未交接；由 Codex 按 handoff 流程执行。"))))
            return
        }
        notice(reason)
    }
    @objc func returnToSource() { if let url = lastSource?.url { _ = NSWorkspace.shared.open(url) } }
    @objc func showMenu() {
        panel.alphaValue = 0.94; detail?.close(); dismissHint()
        let menu = NSMenu()
        func add(_ title: String, _ selector: Selector?, enabled: Bool = true) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; item.isEnabled = enabled; menu.addItem(item); return item
        }
        _ = add(L("搜索聊天名称…"), #selector(searchChats))
        menu.addItem(.separator()); _ = add(followEnabled ? followStatus : L("固定监控：{0}", String(describing: chosenTitle)), nil, enabled: false)
        if let m = snapshot?.metrics { _ = add(L("记录：{0} · 非实时余额", String(describing: timestampLabel(m.timestamp))), nil, enabled: false) }
        let follow = add(L("自动跟随当前聊天"), #selector(toggleFollowing)); follow.state = followEnabled ? .on : .off
        let alerts = add(L("交接轻提醒（65% / 70%）"), #selector(toggleAlerts)); alerts.state = alertsEnabled ? .on : .off
        if let source = lastSource { _ = add(L("返回上次交接来源 · {0}", String(describing: source.title)), #selector(returnToSource), enabled: source.url != nil) }
        if !UserDefaults.standard.bool(forKey: "followAccessConfirmed") || !AXIsProcessTrusted() { _ = add(L("检查自动跟随权限…"), #selector(requestFollowingAccess)) }
        _ = add(L("手动选择记录文件…"), #selector(choose)); _ = add(L("查看指标说明"), #selector(explain))
        let opacity = add(L("透明度"), nil); let choices = NSMenu()
        for (title, value) in [(L("更淡（30%）"), 30), (L("轻淡（42%）"), 42), (L("清晰（65%）"), 65)] {
            let item = NSMenuItem(title: title, action: #selector(setOpacity(_:)), keyEquivalent: ""); item.target = self; item.tag = value
            item.state = Int((idleOpacity * 100).rounded()) == value ? .on : .off; choices.addItem(item)
        }
        opacity.submenu = choices
        let language = add("语言 / Language", nil)
        let languages = NSMenu()
        for (name, code) in [("简体中文", "zh-Hans"), ("English", "en")] {
            let item = NSMenuItem(title: name, action: #selector(setLanguage(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = code
            item.state = AppLanguage.current.rawValue == code ? .on : .off
            languages.addItem(item)
        }
        language.submenu = languages
        menu.addItem(.separator()); _ = add(L("关闭小窗"), #selector(closeApp))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: session.bounds.minY), in: session); panel.alphaValue = idleOpacity
    }
    @objc func setLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String, let next = AppLanguage(rawValue: code), next != AppLanguage.current else { return }
        let reopenPicker = chatPicker?.window?.isVisible == true
        generation += 1; detail?.close(); dismissHint(); chatPicker?.close()
        suppressReminders = true
        next.save()
        panel.title = L("Codex实时状态栏")
        followStatus = followEnabled && reference != nil ? L("自动跟随：{0}", reference!.title) : L("等待识别当前聊天")
        clearDisplay(followEnabled ? L("正在识别聊天") : L("等待用量数据"))
        // Language does not reset the selected chat, usage snapshot or reminder history.
        if snapshot != nil { refreshMetrics() }
        refresh()
        if reopenPicker { searchChats() }
        notice(L("界面语言已切换为中文"))
        suppressReminders = false
    }
    @objc func searchChats() {
        chatPicker = ChatPicker(choices: availableChats()) { [weak self] choice in self?.useChat(choice) }; chatPicker?.present()
    }
    func useChat(_ choice: ChatChoice) {
        generation += 1; resetSnapshot(); selected = URL(fileURLWithPath: choice.reference.path); reference = choice.reference; chosenTitle = choice.reference.title
        followEnabled = false; UserDefaults.standard.set(false, forKey: "followCurrentChat"); UserDefaults.standard.set(choice.reference.path, forKey: preferenceKey)
        followStatus = L("固定监控：{0}", String(describing: chosenTitle)); refresh(); notice(L("已切为固定监控\n{0}\n如需随聊天切换，可在 ⋯ 菜单开启自动跟随。", String(describing: chosenTitle)))
    }
    @objc func setOpacity(_ sender: NSMenuItem) { idleOpacity = CGFloat(sender.tag) / 100; UserDefaults.standard.set(Double(idleOpacity), forKey: "idleOpacity"); panel.alphaValue = idleOpacity }
    @objc func toggleFollowing() {
        generation += 1; followEnabled.toggle(); UserDefaults.standard.set(followEnabled, forKey: "followCurrentChat"); resetSnapshot()
        if followEnabled { reference = nil; clearDisplay(L("正在识别聊天")) }; refresh()
    }
    @objc func toggleAlerts() {
        alertsEnabled.toggle(); UserDefaults.standard.set(alertsEnabled, forKey: "contextAlertsEnabled"); dismissHint()
        for id in reminderStates.keys { reminderStates[id]?.pendingTier = 0 }; saveReminders()
    }
    @objc func requestFollowingAccess() {
        let alert = NSAlert(); alert.messageText = L("允许小窗识别当前聊天")
        alert.informativeText = L("辅助功能权限允许应用读取界面并具备控制能力。小窗仅读取 Codex 当前窗口标题与顶部会话信息，匹配本地记录；不会点击、输入或上传内容。\n请在系统设置中为当前这份“Codex实时状态栏”启用权限。")
        alert.addButton(withTitle: L("打开系统设置")); alert.addButton(withTitle: L("取消"))
        alert.beginSheetModal(for: panel) { response in
            guard response == .alertFirstButtonReturn else { return }; UserDefaults.standard.set(true, forKey: "followAccessConfirmed")
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
        }
    }
    @objc func choose() {
        let picker = NSOpenPanel(); picker.title = L("选择 Codex 会话记录"); picker.message = L("选择后固定监控此会话。无法匹配聊天标识或目录时，交接入口会禁用。")
        picker.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions"); picker.canChooseDirectories = false; picker.allowsMultipleSelection = false
        picker.beginSheetModal(for: panel) { [weak self] response in
            guard response == .OK, let url = picker.url, let self else { return }
            let choice = availableChats().first(where: { $0.reference.path == url.path }) ?? ChatChoice(reference: SessionReference(id: "", title: url.deletingPathExtension().lastPathComponent, path: url.path), updated: Date(), folder: L("未知目录"))
            self.useChat(choice)
        }
    }
    @objc func explain() {
        notice(L("单击 token、缓存或上下文可查看详情。↪ 为自动跟随，⌖ 为固定监控。\n\n上下文是最近请求总 token / 记录容量的估算；账号额度仅为带时间的会话快照。提醒只在新记录达到阈值、真实任务结束后出现。\n\n交接只复制指令并返回指定聊天，由你粘贴发送。监控仅本地读取，不调用模型；离开 Codex 后隐藏并暂停界面识别。"))
    }
    @objc func closeApp() { NSApp.terminate(nil) }
    func windowWillClose(_ notification: Notification) { if (notification.object as? NSWindow) === panel { closeApp() } }
}
let application = NSApplication.shared
let monitor = Monitor(); application.delegate = monitor; application.run()
