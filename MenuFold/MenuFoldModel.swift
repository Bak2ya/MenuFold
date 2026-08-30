import AppKit
import Foundation

struct StatusPresentation {
    let lines: [String]
    let fontSize: CGFloat
    let width: CGFloat
}

final class MenuFoldModel {
    let settings = AppSettings()
    let network = NetworkSpeedMonitor()
    let sleep = SleepController()
    let quickLaunch = QuickLaunchStore()
    let snackStore = SnackStore()

    private(set) var downloadBytesPerSecond: Double = 0
    private(set) var uploadBytesPerSecond: Double = 0

    var onNetworkPresentationChanged: (() -> Void)?
    var onSettingsChanged: (() -> Void)?
    var onQuickLaunchChanged: (() -> Void)?

    private var settingsObserver: NSObjectProtocol?

    init() {
        network.onUpdate = { [weak self] download, upload in
            guard let self else { return }
            self.downloadBytesPerSecond = download
            self.uploadBytesPerSecond = upload
            self.onNetworkPresentationChanged?()
        }

        quickLaunch.onChange = { [weak self] in
            self?.onQuickLaunchChanged?()
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .menuFoldSettingsDidChange,
            object: settings,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.applyNetworkMonitoringPolicy()
            self.settings.applyAppearance()
            self.onSettingsChanged?()
        }
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        network.stop()
        sleep.stop()
    }

    func start() {
        settings.applyAppearance()
        applyNetworkMonitoringPolicy()
    }

    func shutdown() {
        network.stop()
        sleep.stop()
    }

    private func applyNetworkMonitoringPolicy() {
        switch settings.menuBarContentMode {
        case .network:
            if network.isRunning {
                network.updateInterval(settings.refreshInterval)
            } else {
                network.start(interval: settings.refreshInterval)
            }
        case .appIcon:
            network.stop()
            downloadBytesPerSecond = 0
            uploadBytesPerSecond = 0
        }
    }

    func text(_ key: String) -> String {
        settings.localized(key)
    }

    private func orderedStatusValues(
        download: Double? = nil,
        upload: Double? = nil
    ) -> [String] {
        let downValue = download ?? downloadBytesPerSecond
        let upValue = upload ?? uploadBytesPerSecond

        var down = SpeedFormatter.format(downValue, mode: settings.unitMode)
        var up = SpeedFormatter.format(upValue, mode: settings.unitMode)

        if settings.arrowDisplay == .shown {
            down = "↓" + down
            up = "↑" + up
        }

        switch settings.trafficDisplay {
        case .downloadOnly:
            return [down]
        case .uploadOnly:
            return [up]
        case .both:
            return settings.networkOrder == .downloadUpload ? [down, up] : [up, down]
        }
    }

    /// Final visible strings only. Network timer ticks use this lightweight path
    /// so they never recalculate stable width/font metrics.
    func statusLines(
        download: Double? = nil,
        upload: Double? = nil
    ) -> [String] {
        let ordered = orderedStatusValues(download: download, upload: upload)
        switch settings.displayStyle {
        case .twoLineCompact:
            return ordered
        case .oneLineCompact:
            return [ordered.joined(separator: "  ")]
        }
    }

    func statusPresentation(
        download: Double? = nil,
        upload: Double? = nil
    ) -> StatusPresentation {
        let lines = statusLines(download: download, upload: upload)
        let valueCount = settings.trafficDisplay == .both ? 2 : 1
        switch settings.displayStyle {
        case .twoLineCompact:
            let baseFont: CGFloat = valueCount == 1 ? 10.8 : 10.0
            // Extra Large is a one-line-only choice. Keep the preference
            // remembered, but render two-line at Large until one-line returns.
            let effectiveSize: MenuBarFontSize = settings.fontSize == .extraLarge ? .large : settings.fontSize
            let fontSize = baseFont * effectiveSize.scale
            return StatusPresentation(
                lines: lines,
                fontSize: fontSize,
                width: compactStableWidth(lineCount: valueCount, fontSize: fontSize)
            )

        case .oneLineCompact:
            let fontSize = 10.8 * settings.fontSize.scale
            return StatusPresentation(
                lines: lines,
                fontSize: fontSize,
                width: compactStableWidth(lineCount: valueCount, fontSize: fontSize, oneLine: true)
            )
        }
    }

    /// Use the actual menu-bar font metrics instead of the old hand-tuned wide
    /// constants. The sample represents the widest normal formatted value, so
    /// the status item stays stable while eliminating the large empty area on
    /// its left side.
    private func compactStableWidth(lineCount: Int, fontSize: CGFloat, oneLine: Bool = false) -> CGFloat {
        let core: String
        switch settings.unitMode {
        case .simple: core = "999M"
        case .unit: core = "999 MB/s"
        case .bits: core = "999 Mbps"
        }

        let sample: String
        if settings.arrowDisplay == .shown {
            let down = "↓" + core
            let up = "↑" + core
            sample = measuredWidth(of: down, fontSize: fontSize) >= measuredWidth(of: up, fontSize: fontSize) ? down : up
        } else {
            sample = core
        }

        let text = oneLine && lineCount > 1 ? "\(sample)  \(sample)" : sample
        // StatusDisplayView contributes 1.5pt on each side. Keep only a tiny
        // extra breathing margin; the previous values left 10–30pt unused.
        return ceil(measuredWidth(of: text, fontSize: fontSize) + 4.0)
    }

    private func measuredWidth(of text: String, fontSize: CGFloat) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}
