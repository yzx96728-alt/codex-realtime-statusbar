import Foundation
import CoreGraphics

@main struct WindowTemperatureTests {
    static func main() {
        let screen = CGRect(x: 0, y: 25, width: 1512, height: 920)
        let old = CGRect(x: 753, y: 361, width: 348, height: 30)
        assert(WindowRecovery.frame(old, visibleScreens: [screen]) == old)
        let lost = CGRect(x: 5000, y: 3000, width: 348, height: 30)
        let recovered = WindowRecovery.frame(lost, visibleScreens: [screen])
        assert(screen.contains(recovered))
        let second = CGRect(x: -1600, y: 0, width: 1600, height: 1000)
        let external = CGRect(x: -1200, y: 300, width: 348, height: 30)
        assert(WindowRecovery.frame(external, visibleScreens: [screen, second]) == external)
        assert(WindowRecovery.frame(external, visibleScreens: [screen]) != external)
        assert(WindowRecovery.frame(lost, visibleScreens: []) == lost)
        assert(WindowRecovery.acceptsTrust(pid: 42, livePIDs: [42], uptime: 100, now: 120))
        assert(!WindowRecovery.acceptsTrust(pid: 41, livePIDs: [42], uptime: 100, now: 120))
        assert(!WindowRecovery.acceptsTrust(pid: 42, livePIDs: [42], uptime: 100, now: 131))
        assert(!WindowRecovery.acceptsTrust(pid: 42, livePIDs: [42], uptime: 100, now: 10))
        assert(!WindowRecovery.acceptsTrust(pid: nil, livePIDs: [], uptime: nil, now: 120))
        assert(TemperatureValues.keys(for: "Apple M1 Max").count == 10)
        assert(TemperatureValues.keys(for: "Apple M2 Max").isEmpty)
        assert(TemperatureValues.keys(for: "Unknown").isEmpty)
        assert(TemperatureValues.decode(type: 0x73703738, bytes: [0x38, 0x80]) == 56.5)
        let bits = Float(57.25).bitPattern
        var bytes = [UInt8](repeating: 0, count: 4)
        TemperatureValues.store(bits, in: &bytes, at: 0)
        assert(TemperatureValues.decode(type: 0x666c7420, bytes: bytes) == 57.25)
        assert(TemperatureValues.decode(type: 0x666c7420, bytes: [0, 0, 0, 0]) == nil)
        assert(TemperatureValues.decode(type: 0x73703738, bytes: [0xff, 0x00]) == nil)
        assert(TemperatureValues.decode(type: 0x666c7420, bytes: [0, 0, 0x80, 0x7f]) == nil)
        assert(TemperatureValues.decode(type: 0, bytes: bytes) == nil)
        assert(TemperatureValues.decode(type: 0x666c7420, bytes: [1]) == nil)
        let date = Date(timeIntervalSince1970: 100)
        let sample = TemperatureValues.sample([0, .nan, 52, 56, 999], date: date)!
        assert(sample.celsius == 56 && sample.sensorCount == 2)
        assert(sample.isFresh(at: date.addingTimeInterval(30)))
        assert(!sample.isFresh(at: date.addingTimeInterval(31)))
        assert(!sample.isFresh(at: date.addingTimeInterval(-1)))
        assert(TemperatureValues.sample([], date: date) == nil)
        print("Passed: on/off-screen recovery, monitor removal, live GUI trust PID/freshness, CPU family isolation, SMC decoding, hottest-sensor aggregation, unavailable and stale samples.")
    }
}
