import AppKit
import Foundation
import SQLite3

struct ChatChoice {
    let reference: SessionReference
    let updated: Date
    let folder: String

    var detail: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return "\(formatter.string(from: updated)) · \(folder)"
    }
}

func availableChats() -> [ChatChoice] {
    let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/state_5.sqlite").path
    var database: OpaquePointer?
    guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
        if database != nil { sqlite3_close(database) }; return []
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 100)
    let query = """
        SELECT id, COALESCE(NULLIF(TRIM(name), ''), title), rollout_path,
               MAX(updated_at, recency_at), cwd
        FROM threads
        WHERE archived = 0 AND source NOT LIKE '%"subagent"%'
          AND COALESCE(thread_source, '') != 'subagent'
          AND COALESCE(agent_path, '') IN ('', '/root')
        ORDER BY MAX(updated_at, recency_at) DESC, id
        LIMIT 500
        """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { return [] }
    defer { sqlite3_finalize(statement) }
    var choices: [ChatChoice] = []
    func text(_ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }
    while sqlite3_step(statement) == SQLITE_ROW {
        let file = text(2)
        guard FileManager.default.fileExists(atPath: file) else { continue }
        let title = text(1).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let reference = SessionReference(id: text(0), title: title.isEmpty ? "未命名聊天" : title, path: file, cwd: text(4))
        choices.append(ChatChoice(reference: reference,
            updated: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
            folder: URL(fileURLWithPath: text(4)).lastPathComponent))
    }
    return choices
}

final class ChatPicker: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let choices: [ChatChoice]
    var results: [ChatChoice]
    let onChoose: (ChatChoice) -> Void
    let table = NSTableView()
    let search = NSSearchField()
    let hint = NSTextField(labelWithString: "")

    init(choices: [ChatChoice], onChoose: @escaping (ChatChoice) -> Void) {
        self.choices = choices
        self.results = choices
        self.onChoose = onChoose
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 490, height: 400),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "选择要监控的聊天"
        window.isReleasedWhenClosed = false
        window.level = .floating
        super.init(window: window)
        guard let content = window.contentView else { return }
        search.placeholderString = "搜索聊天名称"
        search.sendsSearchStringImmediately = true
        search.delegate = self
        search.target = self; search.action = #selector(enterSearch)
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("chat")))
        table.headerView = nil
        table.rowHeight = 46
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.dataSource = self; table.delegate = self
        table.target = self; table.action = #selector(pickRow)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.autoresizingMask = [.width]
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = table
        scroll.borderType = .bezelBorder
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.stringValue = "\(choices.count) 个本地聊天 · 点击名称即可切换监控"
        for view in [search, scroll, hint] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            search.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -10),
            hint.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            hint.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func numberOfRows(in tableView: NSTableView) -> Int { results.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let choice = results[row]
        let container = NSView()
        let title = NSTextField(labelWithString: choice.reference.title)
        title.font = .systemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingTail
        let detail = NSTextField(labelWithString: choice.detail)
        detail.font = .systemFont(ofSize: 10.5)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        container.toolTip = "\(choice.reference.title)\n\(choice.detail)"
        for field in [title, detail] { field.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(field) }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3)
        ])
        return container
    }
    func controlTextDidChange(_ notification: Notification) {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        results = query.isEmpty ? choices : choices.filter {
            $0.reference.title.localizedStandardContains(query) || $0.folder.localizedStandardContains(query)
        }
        table.deselectAll(nil)
        table.reloadData()
        hint.stringValue = results.isEmpty ? "没有找到匹配的本地聊天" : "\(results.count) 个聊天 · 点击名称即可切换监控"
    }
    @objc func enterSearch() {
        guard NSApp.currentEvent?.type == .keyDown, NSApp.currentEvent?.keyCode == 36 else { return }
        let index = table.selectedRow >= 0 ? table.selectedRow : 0
        select(index)
    }
    @objc func pickRow() { select(table.clickedRow) }
    private func select(_ row: Int) {
        guard results.indices.contains(row) else { return }
        onChoose(results[row])
        close()
    }
    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(search)
    }
}
