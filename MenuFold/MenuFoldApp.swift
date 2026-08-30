import AppKit
import os
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = MenuFoldModel()
    private let popover = NSPopover()
    private var popoverController: PopoverViewController?

    private var statusBarController: StatusBarController?
    private var settingsWindowController: SettingsWindowController?
    private var memoryTrimGeneration = 0

    private let logger = Logger(
        subsystem: "com.bak2ya.MenuFold",
        category: "lifecycle"
    )

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSLog("MenuFold LIFECYCLE: applicationWillFinishLaunching")
        logger.info("MenuFold applicationWillFinishLaunching")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("MenuFold LIFECYCLE: applicationDidFinishLaunching entered")
        NSApp.setActivationPolicy(.accessory)
        model.settings.applyAppearance()

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self

        let status = StatusBarController(model: model, popover: popover)
        status.onWillOpenPopover = { [weak self] in
            self?.preparePopoverController().refresh()
        }
        status.onHiddenZoneStateChanged = { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.popoverController?.refreshMenuBarExpansionState()
        }
        statusBarController = status

        model.onNetworkPresentationChanged = { [weak self] in
            self?.statusBarController?.networkPresentationDidChange()
        }

        model.onSettingsChanged = { [weak self] in
            guard let self else { return }
            self.statusBarController?.settingsDidChange()

            if self.popover.isShown {
                self.popoverController?.refresh()
            }
            // Settings controls already own the values they change. Avoid
            // rebuilding the entire settings window on every dropdown change;
            // the controller reloads itself only when structure/localization
            // actually changes.
        }

        model.onQuickLaunchChanged = { [weak self] in
            guard let self else { return }
            self.popoverController?.refreshCachedContent()
            if self.settingsWindowController?.window?.isVisible == true {
                DispatchQueue.main.async { [weak self] in
                    self?.settingsWindowController?.reload()
                }
            }
        }

        model.start()
        status.updatePresentation()

        NSLog("MenuFold LIFECYCLE: StatusBarController created and model started")
        logger.info("MenuFold AppKit lifecycle started")
        logger.info("MenuFold APPKIT_STATUS: NSStatusItem + NSPopover active")
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
        logger.info("MenuFold AppKit lifecycle terminated")
    }

    @discardableResult
    private func preparePopoverController() -> PopoverViewController {
        if let popoverController { return popoverController }

        let controller = PopoverViewController(model: model)
        controller.onContentSizeChanged = { [weak self] size in
            self?.popover.contentSize = size
        }
        controller.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        controller.onQuit = { [weak self] in
            self?.quit()
        }
        controller.isMenuBarExpanded = { [weak self] in
            self?.statusBarController?.isHiddenZoneExpanded ?? false
        }
        controller.onToggleMenuBarExpansion = { [weak self] in
            self?.statusBarController?.toggleHiddenZoneFromPopover() ?? false
        }

        popoverController = controller
        popover.contentViewController = controller
        popover.contentSize = controller.preferredContentSize
        return controller
    }

    func popoverDidClose(_ notification: Notification) {
        // The popover is transient. Tear down its view tree after every close
        // instead of paying a permanent idle-memory cost for UI that is hidden.
        popover.contentViewController = nil
        popoverController = nil
        releaseQuickLaunchIconCacheIfUIIdle()
        scheduleReleasedMemoryTrim()
    }

    private func releaseQuickLaunchIconCacheIfUIIdle() {
        guard !popover.isShown, settingsWindowController?.window?.isVisible != true else { return }
        model.quickLaunch.purgeIconCache()
    }

    /// AppKit creates a large number of short-lived objects while Settings and
    /// the popover are in use. After those controllers have genuinely been
    /// released, ask malloc once to return unused pages instead of keeping the
    /// high-water mark resident for the lifetime of this menu-bar utility.
    /// This is event-driven only; there is no memory polling or background loop.
    private func scheduleReleasedMemoryTrim() {
        memoryTrimGeneration += 1
        let generation = memoryTrimGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, generation == self.memoryTrimGeneration else { return }
            guard !self.popover.isShown, self.settingsWindowController?.window?.isVisible != true else { return }
            autoreleasepool {
                _ = malloc_zone_pressure_relief(nil, 0)
            }
        }
    }

    private func openSettings() {
        if settingsWindowController == nil {
            let controller = SettingsWindowController(model: model)
            controller.onClosed = { [weak self, weak controller] in
                guard let self, let controller else { return }
                if self.settingsWindowController === controller {
                    self.settingsWindowController = nil
                }
                self.releaseQuickLaunchIconCacheIfUIIdle()
                self.scheduleReleasedMemoryTrim()
            }
            settingsWindowController = controller
        }
        settingsWindowController?.show()
    }

    private func quit() {
        model.shutdown()
        NSApp.terminate(nil)
    }
}
