import Foundation
import IOKit.pwr_mgt

final class SleepController {
    private(set) var isActive = false
    private(set) var activePresetIndex: Int?
    private(set) var isForever = false
    private(set) var endDate: Date?

    private var assertionID: IOPMAssertionID = 0
    private var timer: Timer?

    deinit {
        stop()
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }

        isActive = false
        activePresetIndex = nil
        isForever = false
        endDate = nil
    }

    func startForever() {
        start(until: nil, presetIndex: nil, forever: true)
    }

    func start(preset: AwakePreset, index: Int) {
        let targetDate: Date
        switch preset.mode {
        case .duration:
            let value = max(1, preset.durationValue)
            targetDate = Date().addingTimeInterval(TimeInterval(value) * preset.durationUnit.secondsPerUnit)
        case .untilDate:
            targetDate = preset.endDate
        }

        guard targetDate > Date() else {
            stop()
            return
        }
        start(until: targetDate, presetIndex: index, forever: false)
    }

    private func start(until date: Date?, presetIndex: Int?, forever: Bool) {
        stop()

        var newAssertion: IOPMAssertionID = 0
        let reason = "MenuFold Keep Awake" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &newAssertion
        )

        guard result == kIOReturnSuccess else { return }

        assertionID = newAssertion
        isActive = true
        activePresetIndex = presetIndex
        isForever = forever
        endDate = date

        if let date {
            timer = Timer.scheduledTimer(
                withTimeInterval: max(date.timeIntervalSinceNow, 1),
                repeats: false
            ) { [weak self] _ in
                self?.stop()
            }
        }
    }
}
