import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var contentController: SettingsContentViewController?
    var onClosed: (() -> Void)?

    init(model: MenuFoldModel) {
        let contentController = SettingsContentViewController(model: model)
        self.contentController = contentController

        let window = NSWindow(contentViewController: contentController)
        window.title = model.text("settings.title")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 390, height: 480))
        window.minSize = NSSize(width: 390, height: 480)
        window.maxSize = NSSize(width: 390, height: 480)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self

        contentController.onPreferredTitleChanged = { [weak window] title in
            window?.title = title
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func reload() {
        contentController?.reload()
    }

    func windowWillClose(_ notification: Notification) {
        // A field editor can keep AppKit text services and the settings view
        // hierarchy warm after the visible window is gone. End editing before
        // detaching the controller, then explicitly sever the window/view tree.
        let closingWindow = window
        closingWindow?.makeFirstResponder(nil)
        contentController?.tearDownForClose()
        contentController?.onPreferredTitleChanged = nil
        closingWindow?.contentViewController = nil
        closingWindow?.delegate = nil
        contentController = nil
        self.window = nil

        let callback = onClosed
        onClosed = nil
        callback?()
    }
}
