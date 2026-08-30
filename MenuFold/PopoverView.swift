import AppKit

/// One tiny reusable hover card for the popover. It appears after 0.16s rather
/// than the much longer system tooltip delay, and disappears immediately when
/// the pointer leaves. The panel exists only for MenuFold's own UI; no global
/// monitoring or accessibility permission is involved.
private final class HoverTipPresenter {
    private var pending: DispatchWorkItem?
    private var panel: NSPanel?
    private let delay: TimeInterval = 0.16

    func schedule(text: String, from sourceView: NSView) {
        pending?.cancel()
        hidePanelOnly()
        guard !text.isEmpty else { return }

        let work = DispatchWorkItem { [weak self, weak sourceView] in
            guard let self, let sourceView else { return }
            self.show(text: text, from: sourceView)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func hide() {
        pending?.cancel()
        pending = nil
        hidePanelOnly()
    }

    private func show(text: String, from sourceView: NSView) {
        guard let window = sourceView.window else { return }

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11.5, weight: .medium)
        label.textColor = .labelColor
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.sizeToFit()

        let paddingX: CGFloat = 10
        let paddingY: CGFloat = 6
        let contentSize = NSSize(width: ceil(label.fittingSize.width + paddingX * 2), height: ceil(label.fittingSize.height + paddingY * 2))

        let tipPanel: NSPanel
        if let panel {
            tipPanel = panel
            panel.contentView?.subviews.forEach { $0.removeFromSuperview() }
        } else {
            tipPanel = NSPanel(
                contentRect: NSRect(origin: .zero, size: contentSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            tipPanel.isOpaque = false
            tipPanel.backgroundColor = .clear
            tipPanel.hasShadow = true
            tipPanel.level = .popUpMenu
            tipPanel.ignoresMouseEvents = true
            tipPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = tipPanel
        }

        let card = NSView(frame: NSRect(origin: .zero, size: contentSize))
        card.wantsLayer = true
        card.layer?.cornerRadius = 6
        card.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.65).cgColor
        card.layer?.borderWidth = 0.5

        label.frame.origin = NSPoint(x: paddingX, y: paddingY)
        card.addSubview(label)
        tipPanel.contentView = card

        let rectInWindow = sourceView.convert(sourceView.bounds, to: nil)
        let screenRect = window.convertToScreen(rectInWindow)
        var origin = NSPoint(x: screenRect.midX - contentSize.width / 2, y: screenRect.minY - contentSize.height - 5)

        if let screen = window.screen ?? NSScreen.main {
            origin.x = min(max(origin.x, screen.visibleFrame.minX + 4), screen.visibleFrame.maxX - contentSize.width - 4)
            if origin.y < screen.visibleFrame.minY + 4 {
                origin.y = screenRect.maxY + 5
            }
        }

        tipPanel.setFrame(NSRect(origin: origin, size: contentSize), display: true)
        tipPanel.orderFrontRegardless()
    }

    private func hidePanelOnly() {
        panel?.orderOut(nil)
    }
}

private final class PayloadButton: NSButton {
    var payload: Any?
    var hoverText: String?
    weak var hoverPresenter: HoverTipPresenter?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if let hoverText { hoverPresenter?.schedule(text: hoverText, from: self) }
    }

    override func mouseExited(with event: NSEvent) {
        hoverPresenter?.hide()
        super.mouseExited(with: event)
    }
}

private final class HoverSegmentedControl: NSSegmentedControl {
    var hoverTextForSegment: ((Int) -> String?)?
    weak var hoverPresenter: HoverTipPresenter?
    private var tracking: NSTrackingArea?
    private var hoveredSegment = -1

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateHover(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHover(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        hoveredSegment = -1
        hoverPresenter?.hide()
        super.mouseExited(with: event)
    }

    private func updateHover(with event: NSEvent) {
        guard segmentCount > 0, bounds.width > 0 else { return }
        let point = convert(event.locationInWindow, from: nil)
        let segmentWidth = bounds.width / CGFloat(segmentCount)
        let index = min(segmentCount - 1, max(0, Int(point.x / max(1, segmentWidth))))
        guard index != hoveredSegment else { return }
        hoveredSegment = index
        hoverPresenter?.hide()
        if let text = hoverTextForSegment?(index) {
            hoverPresenter?.schedule(text: text, from: self)
        }
    }
}

/// Stable popover layout: the frame is built once. Runtime changes update only
/// the content inside each section, never tear down and recreate the popover.
final class PopoverViewController: NSViewController {
    private let model: MenuFoldModel

    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?
    var onContentSizeChanged: ((NSSize) -> Void)?
    var onToggleMenuBarExpansion: (() -> Bool)?
    var isMenuBarExpanded: (() -> Bool)?

    private let contentWidth: CGFloat = 308
    private let horizontalPadding: CGFloat = 16
    private let toolbarHeight: CGFloat = 38
    private let awakeHeight: CGFloat = 86

    private let hoverPresenter = HoverTipPresenter()
    private let rootStack = NSStackView()
    private let toolbar = NSView()
    private let settingsButton = NSButton()
    private let menuBarToggleButton = NSButton()
    private let quitButton = NSButton()

    private let toolbarDivider = NSBox()
    private let quickSection = NSView()
    private let quickRows = NSStackView()
    private let quickDivider = NSBox()
    private var quickHeightConstraint: NSLayoutConstraint?

    private let awakeSection = NSView()
    private let awakeTitle = NSTextField(labelWithString: "")
    private let awakeSegments = HoverSegmentedControl()

    init(model: MenuFoldModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: toolbarHeight + 1 + awakeHeight))
        buildStableHierarchy()
        refresh()
    }

    func refresh() {
        guard isViewLoaded else { return }
        hoverPresenter.hide()
        refreshLocalizedContent()
        refreshQuickLaunch()
        refreshAwakeState()
        updatePreferredSize()
    }

    func reloadLocalizedContent() { refresh() }

    func refreshCachedContent() {
        guard isViewLoaded else { return }
        hoverPresenter.hide()
        refreshQuickLaunch()
        updatePreferredSize()
    }

    func refreshMenuBarExpansionState() {
        guard isViewLoaded else { return }
        refreshMenuBarToggleButton()
    }

    // MARK: - Stable hierarchy

    private func buildStableHierarchy() {
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 0
        rootStack.frame = view.bounds
        rootStack.autoresizingMask = [.width, .height]
        view.addSubview(rootStack)

        buildToolbar()
        buildQuickSection()
        buildAwakeSection()

        rootStack.addArrangedSubview(toolbar)
        rootStack.addArrangedSubview(toolbarDivider)
        rootStack.addArrangedSubview(quickSection)
        rootStack.addArrangedSubview(quickDivider)
        rootStack.addArrangedSubview(awakeSection)

        configureHorizontalSeparator(toolbarDivider)
        configureHorizontalSeparator(quickDivider)

        toolbar.translatesAutoresizingMaskIntoConstraints = false
        quickSection.translatesAutoresizingMaskIntoConstraints = false
        awakeSection.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            toolbar.widthAnchor.constraint(equalToConstant: contentWidth),
            toolbar.heightAnchor.constraint(equalToConstant: toolbarHeight),
            awakeSection.widthAnchor.constraint(equalToConstant: contentWidth),
            awakeSection.heightAnchor.constraint(equalToConstant: awakeHeight)
        ])

        let quickHeight = quickSection.heightAnchor.constraint(equalToConstant: 0)
        quickHeight.isActive = true
        quickHeightConstraint = quickHeight
    }

    // MARK: - Toolbar

    private func buildToolbar() {
        settingsButton.isBordered = false
        settingsButton.imagePosition = .imageOnly
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false

        menuBarToggleButton.bezelStyle = .rounded
        menuBarToggleButton.controlSize = .small
        menuBarToggleButton.font = .systemFont(ofSize: 11.5, weight: .medium)
        menuBarToggleButton.target = self
        menuBarToggleButton.action = #selector(toggleMenuBarExpansion)
        menuBarToggleButton.translatesAutoresizingMaskIntoConstraints = false

        quitButton.isBordered = false
        quitButton.imagePosition = .imageOnly
        quitButton.target = self
        quitButton.action = #selector(quitApp)
        quitButton.translatesAutoresizingMaskIntoConstraints = false

        toolbar.addSubview(settingsButton)
        toolbar.addSubview(menuBarToggleButton)
        toolbar.addSubview(quitButton)

        NSLayoutConstraint.activate([
            settingsButton.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: horizontalPadding),
            settingsButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 24),
            settingsButton.heightAnchor.constraint(equalToConstant: 24),

            menuBarToggleButton.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor),
            menuBarToggleButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            menuBarToggleButton.heightAnchor.constraint(equalToConstant: 24),
            menuBarToggleButton.leadingAnchor.constraint(greaterThanOrEqualTo: settingsButton.trailingAnchor, constant: 8),
            menuBarToggleButton.trailingAnchor.constraint(lessThanOrEqualTo: quitButton.leadingAnchor, constant: -8),

            quitButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -horizontalPadding),
            quitButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            quitButton.widthAnchor.constraint(equalToConstant: 24),
            quitButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func refreshLocalizedContent() {
        let gear = NSImage(systemSymbolName: "gearshape", accessibilityDescription: model.text("action.settings"))
        gear?.isTemplate = true
        settingsButton.image = gear
        settingsButton.toolTip = model.text("action.settings")

        let power = NSImage(systemSymbolName: "power", accessibilityDescription: model.text("action.quit"))
        power?.isTemplate = true
        quitButton.image = power
        quitButton.toolTip = model.text("action.quit")

        refreshMenuBarToggleButton()

        awakeTitle.stringValue = model.text("awake.title")
        let labels = awakeLabels()
        if awakeSegments.segmentCount != labels.count { awakeSegments.segmentCount = labels.count }
        for (index, label) in labels.enumerated() {
            awakeSegments.setLabel(label, forSegment: index)
            // Do not set the system tooltip; the custom hover card is faster.
            awakeSegments.setToolTip(nil, forSegment: index)
        }
        awakeSegments.hoverTextForSegment = { [weak self] index in
            self?.awakeToolTip(forSegment: index)
        }
    }

    private func refreshMenuBarToggleButton() {
        let expanded = isMenuBarExpanded?() ?? false
        menuBarToggleButton.title = model.text(expanded ? "menu.foldNow" : "menu.keepExpanded")
        menuBarToggleButton.toolTip = model.text(expanded ? "menu.foldNowHelp" : "menu.keepExpandedHelp")
        menuBarToggleButton.setAccessibilityLabel(menuBarToggleButton.title)
    }

    // MARK: - Quick Launch

    private func buildQuickSection() {
        quickRows.orientation = .vertical
        quickRows.alignment = .leading
        quickRows.spacing = 6
        quickRows.translatesAutoresizingMaskIntoConstraints = false
        quickSection.addSubview(quickRows)

        NSLayoutConstraint.activate([
            quickRows.leadingAnchor.constraint(equalTo: quickSection.leadingAnchor, constant: horizontalPadding),
            quickRows.trailingAnchor.constraint(lessThanOrEqualTo: quickSection.trailingAnchor, constant: -horizontalPadding),
            quickRows.topAnchor.constraint(equalTo: quickSection.topAnchor, constant: 10)
        ])
    }

    private func refreshQuickLaunch() {
        for arranged in quickRows.arrangedSubviews {
            quickRows.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }

        let items = model.quickLaunch.items
        guard !items.isEmpty else {
            quickSection.isHidden = true
            quickDivider.isHidden = true
            quickHeightConstraint?.constant = 0
            return
        }

        let iconSize = model.settings.quickLaunchIconSize.points
        let spacing: CGFloat = iconSize <= 24 ? 7 : (iconSize >= 32 ? 6 : 8)
        let usableWidth = contentWidth - horizontalPadding * 2
        let columnCount = max(1, Int(floor((usableWidth + spacing) / (iconSize + spacing))))

        var index = 0
        var rowCount = 0
        while index < items.count {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = spacing
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: iconSize).isActive = true

            for offset in 0..<columnCount {
                let itemIndex = index + offset
                guard itemIndex < items.count else { break }
                let item = items[itemIndex]
                let button = PayloadButton(
                    image: model.quickLaunch.icon(for: item, pointSize: iconSize),
                    target: self,
                    action: #selector(quickLaunchPressed(_:))
                )
                button.payload = item
                button.hoverText = item.name
                button.hoverPresenter = hoverPresenter
                button.isBordered = false
                if item.kind != .app {
                    button.contentTintColor = model.quickLaunch.effectiveIconColor(for: item).tintColor
                }
                button.imageScaling = .scaleProportionallyDown
                button.toolTip = nil
                button.setAccessibilityLabel(item.name)
                button.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    button.widthAnchor.constraint(equalToConstant: iconSize),
                    button.heightAnchor.constraint(equalToConstant: iconSize)
                ])
                row.addArrangedSubview(button)
            }

            quickRows.addArrangedSubview(row)
            rowCount += 1
            index += columnCount
        }

        let height = CGFloat(rowCount) * iconSize + CGFloat(max(0, rowCount - 1)) * 6 + 20
        quickHeightConstraint?.constant = height
        quickSection.isHidden = false
        quickDivider.isHidden = false
    }

    // MARK: - Keep Awake

    private func buildAwakeSection() {
        awakeTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        awakeTitle.translatesAutoresizingMaskIntoConstraints = false

        awakeSegments.segmentCount = 4
        awakeSegments.trackingMode = .selectOne
        awakeSegments.segmentStyle = .rounded
        awakeSegments.segmentDistribution = .fillEqually
        awakeSegments.controlSize = .small
        awakeSegments.target = self
        awakeSegments.action = #selector(awakeChanged(_:))
        awakeSegments.hoverPresenter = hoverPresenter
        awakeSegments.translatesAutoresizingMaskIntoConstraints = false

        awakeSection.addSubview(awakeTitle)
        awakeSection.addSubview(awakeSegments)

        NSLayoutConstraint.activate([
            awakeTitle.leadingAnchor.constraint(equalTo: awakeSection.leadingAnchor, constant: horizontalPadding),
            awakeTitle.trailingAnchor.constraint(lessThanOrEqualTo: awakeSection.trailingAnchor, constant: -horizontalPadding),
            awakeTitle.topAnchor.constraint(equalTo: awakeSection.topAnchor, constant: 12),

            awakeSegments.leadingAnchor.constraint(equalTo: awakeSection.leadingAnchor, constant: horizontalPadding),
            awakeSegments.trailingAnchor.constraint(equalTo: awakeSection.trailingAnchor, constant: -horizontalPadding),
            awakeSegments.topAnchor.constraint(equalTo: awakeTitle.bottomAnchor, constant: 8),
            awakeSegments.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    private func awakeLabels() -> [String] {
        var labels = [model.text("awake.forever"), model.text("awake.off")]
        labels.append(contentsOf: model.settings.awakePresets.indices.map { "#\($0 + 1)" })
        return labels
    }

    private func awakeToolTip(forSegment index: Int) -> String? {
        switch index {
        case 0: return model.text("awake.forever")
        case 1: return model.text("awake.off")
        default:
            let presetIndex = index - 2
            guard model.settings.awakePresets.indices.contains(presetIndex) else { return nil }
            return "#\(presetIndex + 1) · \(model.settings.awakePresets[presetIndex].tooltip(language: model.settings.language))"
        }
    }

    private func refreshAwakeState() {
        if !model.sleep.isActive {
            awakeSegments.selectedSegment = 1
        } else if model.sleep.isForever {
            awakeSegments.selectedSegment = 0
        } else if let presetIndex = model.sleep.activePresetIndex,
                  model.settings.awakePresets.indices.contains(presetIndex) {
            awakeSegments.selectedSegment = presetIndex + 2
        } else {
            awakeSegments.selectedSegment = -1
        }
    }

    // MARK: - Size and separators

    private func updatePreferredSize() {
        let quickHeight = quickSection.isHidden ? 0 : (quickHeightConstraint?.constant ?? 0) + 1
        let height = toolbarHeight + 1 + quickHeight + awakeHeight
        let size = NSSize(width: contentWidth, height: height)
        preferredContentSize = size
        onContentSizeChanged?(size)
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
    }

    private func configureHorizontalSeparator(_ separator: NSBox) {
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    // MARK: - Actions

    @objc private func toggleMenuBarExpansion() {
        _ = onToggleMenuBarExpansion?()
        refreshMenuBarToggleButton()
    }

    @objc private func quickLaunchPressed(_ sender: PayloadButton) {
        hoverPresenter.hide()
        guard let item = sender.payload as? QuickLaunchItem else { return }
        model.quickLaunch.open(item)
    }

    @objc private func awakeChanged(_ sender: NSSegmentedControl) {
        hoverPresenter.hide()
        switch sender.selectedSegment {
        case 0:
            model.sleep.startForever()
        case 1:
            model.sleep.stop()
        default:
            let presetIndex = sender.selectedSegment - 2
            guard model.settings.awakePresets.indices.contains(presetIndex) else { break }
            model.sleep.start(preset: model.settings.awakePresets[presetIndex], index: presetIndex)
        }
        refreshAwakeState()
    }

    @objc private func openSettings() {
        hoverPresenter.hide()
        onOpenSettings?()
    }

    @objc private func quitApp() {
        hoverPresenter.hide()
        onQuit?()
    }
}
