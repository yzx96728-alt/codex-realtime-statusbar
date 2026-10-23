import AppKit
import ApplicationServices
import Foundation
import SQLite3

struct SessionReference: Equatable {
    let id: String
    let title: String
    let path: String
    var cwd: String = ""
}

enum VisibleSession {
    case matched(SessionReference, String)
    case permissionRequired
    case unavailable(String)
}

final class SessionCatalog {
    var byID: [String: SessionReference] = [:]
    var byTitle: [String: [SessionReference]] = [:]
    private var refreshed = Date.distantPast
    let databaseURL: URL

    init(databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/state_5.sqlite")) {
        self.databaseURL = databaseURL
    }

    func reload(force: Bool = false) {
        guard force || Date().timeIntervalSince(refreshed) > 4 else { return }
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if database != nil { sqlite3_close(database) }; return
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 100)
        var statement: OpaquePointer?
        let query = """
            SELECT id, COALESCE(NULLIF(TRIM(name), ''), title), rollout_path, cwd
            FROM threads
            WHERE source NOT LIKE '%"subagent"%'
              AND COALESCE(thread_source, '') != 'subagent'
              AND COALESCE(agent_path, '') IN ('', '/root')
            """
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        var references: [String: SessionReference] = [:]
        var titles: [String: [SessionReference]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = sqlite3_column_text(statement, 0),
                  let title = sqlite3_column_text(statement, 1),
                  let path = sqlite3_column_text(statement, 2) else { continue }
            let reference = SessionReference(id: String(cString: id), title: String(cString: title), path: String(cString: path), cwd: sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? "")
            references[reference.id] = reference
            titles[reference.title.trimmingCharacters(in: .whitespacesAndNewlines), default: []].append(reference)
        }
        byID = references; byTitle = titles; refreshed = Date()
    }

    func resolve(route: String?, titles: [String]) -> (SessionReference, String)? {
        if let route = route, let id = Self.routeThreadID(route) {
            guard let reference = byID[id] else { return nil }
            return (reference, L("窗口会话标识"))
        }
        // Only exact, unique titles are accepted. Background activity is never used as a signal.
        var matches: [String: SessionReference] = [:]
        for rawTitle in titles {
            var variants = [rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)]
            for suffix in [" — ChatGPT", " - ChatGPT", " — Codex", " - Codex"] where rawTitle.hasSuffix(suffix) {
                variants.append(String(rawTitle.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            for title in variants {
                guard let candidates = byTitle[title] else { continue }
                guard candidates.count == 1 else { return nil }
                matches[candidates[0].id] = candidates[0]
            }
        }
        guard matches.count == 1, let reference = matches.values.first else { return nil }
        return (reference, L("唯一窗口标题"))
    }

    static func routeThreadID(_ route: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: "(?:^|[/:#])(?:threads|thread)/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})(?=[/?#]|$)"),
              let match = expression.firstMatch(in: route, range: NSRange(route.startIndex..., in: route)),
              let range = Range(match.range(at: 1), in: route) else { return nil }
        return String(route[range]).lowercased()
    }
}

final class ChatFollower {
    let catalog = SessionCatalog()

    static func windowIndex(main: [Bool], focused: [Bool]) -> Int? {
        guard main.count == focused.count, !main.isEmpty else { return nil }
        let focusedIndices = focused.indices.filter { focused[$0] }
        if focusedIndices.count == 1 { return focusedIndices[0] }
        if focusedIndices.count > 1 { return nil }
        let mainIndices = main.indices.filter { main[$0] }
        if mainIndices.count == 1 { return mainIndices[0] }
        return main.count == 1 ? 0 : nil
    }

    private func chatWindow(_ root: AXUIElement) -> (AXUIElement?, String) {
        // Chromium apps may omit AXFocusedWindow while still exposing AXMainWindow or AXWindows.
        for name in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(root, name as CFString, &value) == .success,
               let value = value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                return ((value as! AXUIElement), "")
            }
        }
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &value)
        guard error == .success else { return (nil, L("窗口读取失败（AX {0}）", String(describing: error.rawValue))) }
        guard let windows = value as? [AXUIElement], !windows.isEmpty else { return (nil, L("应用未提供可读窗口")) }
        let main = windows.map { (attribute($0, kAXMainAttribute) as? NSNumber)?.boolValue ?? false }
        let focused = windows.map { (attribute($0, kAXFocusedAttribute) as? NSNumber)?.boolValue ?? false }
        guard let index = Self.windowIndex(main: main, focused: focused) else { return (nil, L("多个窗口无法确定当前项")) }
        return (windows[index], "")
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func string(_ element: AXUIElement, _ name: String) -> String? {
        guard let value = attribute(element, name) else { return nil }
        if let text = value as? String { return text }
        if CFGetTypeID(value) == CFURLGetTypeID() { return (value as! URL).absoluteString }
        return nil
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    static func isHeaderElement(_ element: CGRect, window: CGRect) -> Bool {
        let strip = CGRect(x: window.minX, y: window.minY, width: window.width, height: min(52, window.height))
        return strip.contains(CGPoint(x: element.midX, y: element.midY))
    }

    private func headerMetadata(_ window: AXUIElement) -> (titles: [String], routes: [String]) {
        guard let windowFrame = frame(window) else { return ([], []) }
        let strip = CGRect(x: windowFrame.minX, y: windowFrame.minY, width: windowFrame.width, height: min(52, windowFrame.height))
        var titles: [String] = []
        var routes: [String] = []
        var pending: [(AXUIElement, Int)] = [(window, 0)]
        var visited = 0
        let deadline = Date().addingTimeInterval(0.45)
        while !pending.isEmpty, visited < 180, Date() < deadline {
            let (element, depth) = pending.removeFirst()
            visited += 1
            let bounds = frame(element)
            if let bounds = bounds, !bounds.intersects(strip) { continue }
            let role = string(element, kAXRoleAttribute) ?? ""
            if role == "AXWebArea" {
                for name in ["AXURL", kAXDocumentAttribute] {
                    if let route = string(element, name) { routes.append(route) }
                }
            }
            // Only read labels located in the top toolbar, including its button/static-text title.
            // Sidebar rows and message text below the toolbar are pruned by screen geometry.
            if let bounds = bounds, Self.isHeaderElement(bounds, window: windowFrame),
               ["AXStaticText", "AXButton", "AXPopUpButton", "AXMenuButton", "AXHeading"].contains(role) {
                var text = string(element, kAXTitleAttribute)
                if (text ?? "").isEmpty, role == "AXStaticText" || role == "AXHeading" {
                    text = string(element, kAXValueAttribute)
                }
                if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { titles.append(text) }
            }
            if depth < 12, !["AXTextArea", "AXTextField", "AXStaticText", "AXHeading"].contains(role),
               let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                pending.append(contentsOf: children.prefix(80).map { ($0, depth + 1) })
            }
        }
        return (titles, routes)
    }

    func current() -> VisibleSession {
        guard AXIsProcessTrusted() else { return .permissionRequired }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first else {
            return .unavailable(L("Codex 未运行"))
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        let (candidate, failure) = chatWindow(root)
        guard let window = candidate else { return .unavailable(failure) }
        catalog.reload()
        var windowTitles: [String] = []
        if let title = string(window, kAXTitleAttribute), !title.isEmpty { windowTitles.append(title) }
        let header = headerMetadata(window)
        var routes = header.routes
        if let route = string(window, kAXDocumentAttribute) { routes.append(route) }
        let routeIDs = Set(routes.compactMap { SessionCatalog.routeThreadID($0) })
        // Conflicting window locations or an explicit unknown/remote thread must not fall back to a different title.
        if routeIDs.count > 1 { return .unavailable(L("当前窗口含多个会话")) }
        if let id = routeIDs.first {
            guard let reference = catalog.byID[id] else { return .unavailable(L("此聊天暂无本地记录")) }
            return .matched(reference, L("窗口会话标识"))
        }
        if let (reference, _) = catalog.resolve(route: nil, titles: header.titles) { return .matched(reference, L("顶部聊天名称")) }
        if header.titles.contains(where: { (catalog.byTitle[$0]?.count ?? 0) > 1 }) { return .unavailable(L("顶部名称对应多个聊天")) }
        if let (reference, method) = catalog.resolve(route: nil, titles: windowTitles) { return .matched(reference, method) }
        return .unavailable(header.titles.isEmpty ? L("未读到顶部聊天名称") : L("顶部名称未匹配聊天"))
    }
}
