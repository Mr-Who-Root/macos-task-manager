import Foundation

/// Number formatting that mirrors the way Windows Task Manager prints values.
enum Fmt {
    private static let oneDecimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f
    }()

    private static let integer: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    /// CPU column: "0%", "0.3%", "12.5%", "100%". `value` is 0...100.
    static func percent(_ value: Double) -> String {
        if value < 0.05 { return "0%" }
        if value >= 99.95 { return "100%" }
        return String(format: "%.1f%%", value)
    }

    /// Whole-number percentage for fractions 0...1: "12%".
    static func wholePercent(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    /// Processes-tab memory: "1,234.5 MB".
    static func megabytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        return (oneDecimal.string(from: NSNumber(value: mb)) ?? String(format: "%.1f", mb)) + " MB"
    }

    /// Details-tab memory: "123,456 K".
    static func kilobytes(_ bytes: UInt64) -> String {
        (integer.string(from: NSNumber(value: bytes / 1024)) ?? "\(bytes / 1024)") + " K"
    }

    static func diskRate(_ bytesPerSecond: Double) -> String {
        let mb = bytesPerSecond / 1_048_576
        return mb < 0.05 ? "0 MB/s" : String(format: "%.1f MB/s", mb)
    }

    static func networkRate(_ bytesPerSecond: Double) -> String {
        let mbps = bytesPerSecond * 8 / 1_000_000
        return mbps < 0.05 ? "0 Mbps" : String(format: "%.1f Mbps", mbps)
    }

    /// "512 KB", "1.2 GB".
    static func bytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var v = max(value, 0)
        var i = 0
        while v >= 1024 && i < units.count - 1 {
            v /= 1024
            i += 1
        }
        if i == 0 { return "\(Int(v)) B" }
        return v >= 100 ? String(format: "%.0f %@", v, units[i]) : String(format: "%.1f %@", v, units[i])
    }

    static func bytes(_ value: UInt64) -> String { bytes(Double(value)) }

    static func byteRate(_ bytesPerSecond: Double) -> String {
        bytesPerSecond < 1 ? "0 KB/s" : bytes(bytesPerSecond) + "/s"
    }

    static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    /// Network throughput in bits per second: "0 Kbps", "8.0 Kbps", "1.2 Mbps".
    static func bitRate(_ bitsPerSecond: Double) -> String {
        let v = max(bitsPerSecond, 0)
        if v < 50 { return "0 Kbps" }
        if v < 1_000_000 { return String(format: "%.1f Kbps", v / 1_000) }
        if v < 1_000_000_000 { return String(format: "%.1f Mbps", v / 1_000_000) }
        return String(format: "%.1f Gbps", v / 1_000_000_000)
    }

    /// "S: 0 R: 8.0 Kbps" — the unit is written once when both share it.
    static func bitRatePair(send: Double, receive: Double) -> String {
        let s = bitRate(send).split(separator: " ")
        let r = bitRate(receive).split(separator: " ")
        if s.count == 2, r.count == 2, s[1] == r[1] { return "S: \(s[0]) R: \(r[0]) \(r[1])" }
        return "S: \(bitRate(send)) R: \(bitRate(receive))"
    }

    /// Short rate for the menu bar: "0K", "12K", "1.2M".
    static func compactRate(_ bytesPerSecond: Double) -> String {
        let v = max(bytesPerSecond, 0)
        if v < 1_000_000 { return "\(Int((v / 1_024).rounded()))K" }
        if v < 10_485_760 { return String(format: "%.1fM", v / 1_048_576) }
        return "\(Int((v / 1_048_576).rounded()))M"
    }

    static func linkSpeed(_ bitsPerSecond: UInt64) -> String {
        let v = Double(bitsPerSecond)
        if v <= 0 { return "Unknown" }
        if v >= 1_000_000_000 { return String(format: "%.1f Gbps", v / 1_000_000_000) }
        return String(format: "%.0f Mbps", v / 1_000_000)
    }

    /// Up time as d:hh:mm:ss, like the Performance tab.
    static func uptime(_ seconds: TimeInterval) -> String {
        let t = max(Int(seconds), 0)
        return String(format: "%d:%02d:%02d:%02d", t / 86_400, (t % 86_400) / 3_600, (t % 3_600) / 60, t % 60)
    }

    /// CPU time as h:mm:ss.
    static func cpuTime(_ seconds: Double) -> String {
        let t = max(Int(seconds), 0)
        return String(format: "%d:%02d:%02d", t / 3_600, (t % 3_600) / 60, t % 60)
    }

    static func temperature(_ celsius: Double, fahrenheit: Bool, decimals: Int = 0) -> String {
        let value = fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return String(format: "%.\(decimals)f °%@", value, fahrenheit ? "F" : "C")
    }

    /// Power: "0 W", "45 mW", "2.35 W", "18.2 W".
    static func watts(_ value: Double) -> String {
        let v = abs(value)
        if v < 0.0005 { return "0 W" }
        if v < 0.9995 { return "\(Int((v * 1000).rounded())) mW" }
        return v < 10 ? String(format: "%.2f W", v) : String(format: "%.1f W", v)
    }

    /// Energy from joules: "0 Wh", "<1 mWh", "12 mWh", "3.4 Wh".
    static func energy(_ joules: Double) -> String {
        let wh = max(joules, 0) / 3600
        if wh == 0 { return "0 Wh" }
        if wh < 0.0005 { return "<1 mWh" }
        if wh < 0.9995 { return "\(Int((wh * 1000).rounded())) mWh" }
        return wh < 100 ? String(format: "%.1f Wh", wh) : String(format: "%.0f Wh", wh)
    }

    /// Battery time: "45 min", "2 h 05 min".
    static func duration(minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : String(format: "%d h %02d min", minutes / 60, minutes % 60)
    }

    /// "6,475 mAh".
    static func milliampHours(_ value: Double) -> String {
        (integer.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value))") + " mAh"
    }

    static func rpm(_ value: Double) -> String {
        value < 1 ? "Off" : "\(Int(value.rounded())) RPM"
    }

    static func frequency(_ hertz: Double) -> String {
        String(format: "%.2f GHz", hertz / 1_000_000_000)
    }

    /// Label for the time window a 60-sample graph covers.
    static func span(_ seconds: Double) -> String {
        seconds < 120 ? "\(Int(seconds.rounded())) seconds" : "\(Int((seconds / 60).rounded())) minutes"
    }

    /// Rounds up to a 1-2-5 step so graph scales stay readable.
    static func niceCeiling(_ value: Double, minimum: Double) -> Double {
        let x = max(value, minimum)
        let magnitude = pow(10, floor(log10(x)))
        for step in [1.0, 2.0, 5.0, 10.0] where step * magnitude >= x {
            return step * magnitude
        }
        return 10 * magnitude
    }
}
