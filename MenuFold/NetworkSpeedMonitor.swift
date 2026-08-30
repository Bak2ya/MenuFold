import Foundation
import Darwin

final class NetworkSpeedMonitor {
    var onUpdate: ((Double, Double) -> Void)?

    private var timer: DispatchSourceTimer?
    var isRunning: Bool { timer != nil }
    private var previous: (rx: UInt64, tx: UInt64)?
    private var previousDate: Date?
    private(set) var interval: Double = 1.0

    func start(interval: Double) {
        stop()
        self.interval = max(0.1, interval)
        previous = sample()
        previousDate = Date()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(
            deadline: .now() + self.interval,
            repeating: self.interval,
            leeway: .milliseconds(Int(min(250, self.interval * 120)))
        )
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }

    func updateInterval(_ newInterval: Double) {
        let value = max(0.1, newInterval)
        guard abs(value - interval) > 0.001 else { return }
        start(interval: value)
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        let now = Date()
        let current = sample()
        guard let previous, let previousDate else {
            self.previous = current
            self.previousDate = now
            return
        }

        let elapsed = max(now.timeIntervalSince(previousDate), 0.01)
        let rxDelta = current.rx >= previous.rx ? current.rx - previous.rx : 0
        let txDelta = current.tx >= previous.tx ? current.tx - previous.tx : 0

        self.previous = current
        self.previousDate = now

        let download = Double(rxDelta) / elapsed
        let upload = Double(txDelta) / elapsed
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(download, upload)
        }
    }

    private func sample() -> (rx: UInt64, tx: UInt64) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return (0, 0) }
        defer { freeifaddrs(head) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let item = cursor {
            let interface = item.pointee
            let flags = Int32(interface.ifa_flags)

            if (flags & IFF_UP) != 0,
               (flags & IFF_LOOPBACK) == 0,
               let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) {
                rx += UInt64(data.pointee.ifi_ibytes)
                tx += UInt64(data.pointee.ifi_obytes)
            }

            cursor = interface.ifa_next
        }

        return (rx, tx)
    }
}

enum SpeedFormatter {
    static func format(_ bytesPerSecond: Double, mode: SpeedUnitMode) -> String {
        switch mode {
        case .simple:
            return formatBytes(bytesPerSecond, includeUnit: false)
        case .unit:
            return formatBytes(bytesPerSecond, includeUnit: true)
        case .bits:
            return formatBits(bytesPerSecond * 8)
        }
    }

    private static func formatBytes(_ value: Double, includeUnit: Bool) -> String {
        let safe = max(0, value)
        if safe >= 1_000_000_000 {
            return formatted(safe / 1_000_000_000, suffix: includeUnit ? " GB/s" : "G")
        }
        if safe >= 1_000_000 {
            return formatted(safe / 1_000_000, suffix: includeUnit ? " MB/s" : "M")
        }
        return formatted(safe / 1_000, suffix: includeUnit ? " KB/s" : "K")
    }

    private static func formatBits(_ bitsPerSecond: Double) -> String {
        let safe = max(0, bitsPerSecond)
        if safe >= 1_000_000_000 {
            return formatted(safe / 1_000_000_000, suffix: " Gbps")
        }
        if safe >= 1_000_000 {
            return formatted(safe / 1_000_000, suffix: " Mbps")
        }
        return formatted(safe / 1_000, suffix: " Kbps")
    }

    private static func formatted(_ value: Double, suffix: String) -> String {
        if value >= 100 {
            return "\(Int(value.rounded()))\(suffix)"
        }
        if value >= 10 {
            return String(format: "%.0f%@", value, suffix)
        }
        return String(format: "%.1f%@", value, suffix)
    }
}
