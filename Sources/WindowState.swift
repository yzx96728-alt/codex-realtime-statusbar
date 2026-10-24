import Foundation
import CoreGraphics

/// Display the shell immediately; asynchronous identity lookup must not gate visibility.
enum WindowRecovery {
    static func frame(_ frame: CGRect, visibleScreens: [CGRect]) -> CGRect {
        guard let screen = visibleScreens.first else { return frame }
        if visibleScreens.contains(where: { $0.intersection(frame).width >= 80 && $0.intersection(frame).height >= 20 }) { return frame }
        return CGRect(x: max(screen.minX + 8, screen.maxX - frame.width - 16), y: screen.minY + 12, width: frame.width, height: frame.height)
    }
    static func acceptsTrust(pid: Int32?, livePIDs: [Int32], uptime: Double?, now: Double) -> Bool {
        guard let pid, livePIDs.contains(pid), let uptime else { return false }
        return (0...30).contains(now - uptime)
    }
}
