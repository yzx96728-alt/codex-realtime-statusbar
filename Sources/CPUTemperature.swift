import Foundation
import IOKit

/// Read-only AppleSMC transport. No write command, helper, sudo or fan control.
/// Undocumented SMC ABI: 80-byte message, selector 2; commands 9 (metadata), 5 (read).
/// Key provenance and compatibility limits are documented in docs/v1.7.3-validation.md.
struct CPUTemperatureSample {
    let celsius: Double
    let sensorCount: Int
    let date: Date
    func isFresh(at now: Date) -> Bool { (0...30).contains(now.timeIntervalSince(date)) }
}
enum TemperatureValues {
    static func keys(for brand: String) -> [String] {
        // Do not apply another generation's similarly named keys to an unknown CPU.
        if brand.hasPrefix("Apple M1") { return ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"] }
        if brand.contains("Intel") { return ["TC0D"] }
        return []
    }
    static func uint32(_ b: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(b[offset + $1]) << ($1 * 8) }
    }
    static func store(_ value: UInt32, in bytes: inout [UInt8], at offset: Int) {
        for i in 0..<4 { bytes[offset + i] = UInt8(truncatingIfNeeded: value >> (i * 8)) }
    }
    static func decode(type: UInt32, bytes: [UInt8]) -> Double? {
        let result: Double
        switch (type, bytes.count) {
        case (0x666c7420, 4): result = Double(Float(bitPattern: uint32(bytes, at: 0))) // flt, native little endian
        case (0x73703738, 2): result = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256 // sp78
        default: return nil
        }
        return result.isFinite && (10...125).contains(result) ? result : nil
    }
    static func sample(_ values: [Double], date: Date) -> CPUTemperatureSample? {
        let valid = values.filter { $0.isFinite && (10...125).contains($0) }
        guard let hottest = valid.max() else { return nil }
        return CPUTemperatureSample(celsius: hottest, sensorCount: valid.count, date: date)
    }
}
final class CPUTemperatureReader {
    private var connection: io_connect_t = 0
    private let keys: [String]
    init(brand: String = CPUTemperatureReader.cpuBrand()) { keys = TemperatureValues.keys(for: brand) }
    deinit { if connection != 0 { IOServiceClose(connection) } }
    static func cpuBrand() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0, size < 1024 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(cString: bytes)
    }
    private func open() -> Bool {
        if connection != 0 { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        return IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS
    }
    private func call(_ bytes: [UInt8]) -> [UInt8]? {
        var output = [UInt8](repeating: 0, count: 80), size = 80
        let status = bytes.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { result in
                IOConnectCallStructMethod(connection, 2, input.baseAddress, 80, result.baseAddress, &size)
            }
        }
        guard status == KERN_SUCCESS, size == 80, output[40] == 0 else { return nil }
        return output
    }
    func read() -> CPUTemperatureSample? {
        guard !keys.isEmpty, open() else { return nil }
        var values: [Double] = []
        for key in keys {
            var input = [UInt8](repeating: 0, count: 80)
            TemperatureValues.store(key.utf8.reduce(0) { $0 << 8 | UInt32($1) }, in: &input, at: 0)
            input[42] = 9
            guard let info = call(input) else { continue }
            let count = TemperatureValues.uint32(info, at: 28), type = TemperatureValues.uint32(info, at: 32)
            guard (1...32).contains(count) else { continue }
            TemperatureValues.store(count, in: &input, at: 28); input[42] = 5
            guard let raw = call(input), let value = TemperatureValues.decode(type: type, bytes: Array(raw[48..<(48 + Int(count))])) else { continue }
            values.append(value)
        }
        if values.isEmpty { IOServiceClose(connection); connection = 0 }
        return TemperatureValues.sample(values, date: Date())
    }
}
