import AppKit

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The Quick Launch list gets its own scroller only when it exceeds seven
/// rows. At either edge, keep sending the wheel gesture to the settings window
/// so the old nested-scroll "wheel trap" does not come back.
private final class EdgePassthroughScrollView: NSScrollView {
    weak var outerScrollView: NSScrollView?

    override func scrollWheel(with event: NSEvent) {
        guard let documentView else {
            outerScrollView?.scrollWheel(with: event)
            return
        }

        let maxY = max(0, documentView.fittingSize.height - contentView.bounds.height)
        let currentY = contentView.bounds.origin.y
        let deltaY = event.scrollingDeltaY
        let atTop = currentY <= 0.5
        let atBottom = currentY >= maxY - 0.5

        if maxY <= 0.5 || (atTop && deltaY > 0) || (atBottom && deltaY < 0) {
            outerScrollView?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}


/// Static, background-free representation of MenuFold's default two-line
/// network meter for the organizer guide. It intentionally does not mirror
/// live traffic or every display preference; the guide only needs to identify
/// the MenuFold status item. Dynamic labelColor keeps it legible in both light
/// and dark appearance without a second asset.
private final class MenuBarGuideNetworkPreviewView: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 31, height: 22) }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 8.6, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let top = "↓1.2M" as NSString
        let bottom = "↑320K" as NSString
        top.draw(at: NSPoint(x: 0, y: 11), withAttributes: attributes)
        bottom.draw(at: NSPoint(x: 0, y: 0), withAttributes: attributes)
    }
}

final class SettingsContentViewController: NSViewController, NSTextFieldDelegate {
    private let model: MenuFoldModel

    // Keep settings-only artwork on the settings controller, not in process-
    // lifetime static caches. Closing Settings can then release decoded images.
    private lazy var infoAppIcon: NSImage = {
        // Build 43: the information artwork is an Asset Catalog image.
        // Do not substitute an unrelated SF Symbol or applicationIconImage if
        // the asset is unavailable; a missing image is preferable to showing
        // the wrong MenuFold identity for even one frame.
        guard let source = NSImage(named: NSImage.Name("MenuFoldInfoIcon")),
              let image = source.copy() as? NSImage else {
            return NSImage()
        }
        image.isTemplate = false
        return image
    }()

    private lazy var statusIcon: NSImage = {
        if let image = BundledImageLoader.image(named: "MenuFoldStatusIcon", withExtension: "png") {
            return image
        }
        return NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted", accessibilityDescription: nil) ?? NSImage()
    }()

    private let width: CGFloat = 390
    private let windowContentHeight: CGFloat = 480
    private var contentStack: NSStackView?
    private weak var scrollView: NSScrollView?
    private var menuBarSettingsExpanded = false
    private var informationExpanded = false
    private var snackWindowController: SnackPurchaseWindowController?
    private var lastSnackPhotoName: String?
    private let snackPhotoNames = [
        "Maneem_2431",
        "Maneem_3276",
        "Maneem_3339",
        "Maneem_4892",
        "Maneem_4994",
        "Maneem_5104",
        "Maneem_5128",
        "Maneem_5142",
        "Maneem_5572"
    ]

    var onPreferredTitleChanged: ((String) -> Void)?

    init(model: MenuFoldModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Settings contains a few numeric text fields. They do not need spelling,
    /// replacements, link/data detection or predictive completion. Keeping
    /// those services disabled also avoids retaining the shared field editor
    /// and TextInput/AutoFill helpers after Settings is closed.
    private func prepareLeanEditableField(_ field: NSTextField) {
        field.delegate = self
        field.allowsEditingTextAttributes = false
        field.importsGraphics = false
        field.usesSingleLineMode = true
    }

    private func configureLeanFieldEditor(_ editor: NSTextView) {
        editor.isRichText = false
        editor.importsGraphics = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.enabledTextCheckingTypes = 0
        if #available(macOS 15.0, *) {
            editor.isAutomaticTextCompletionEnabled = false
        }
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
              let editor = field.window?.fieldEditor(false, for: field) as? NSTextView else { return }
        configureLeanFieldEditor(editor)
    }

    /// Called by SettingsWindowController before the window is detached. This
    /// deliberately destroys the transient AppKit hierarchy instead of merely
    /// hiding it, so released controls/backing stores can return to the system.
    func tearDownForClose() {
        guard isViewLoaded else {
            onPreferredTitleChanged = nil
            return
        }

        snackWindowController?.dismiss()
        snackWindowController = nil

        let hostWindow = view.window
        hostWindow?.makeFirstResponder(nil)
        if let editor = hostWindow?.fieldEditor(false, for: nil) as? NSTextView {
            configureLeanFieldEditor(editor)
        }

        func detachTargets(in root: NSView) {
            for child in root.subviews { detachTargets(in: child) }
            if let field = root as? NSTextField {
                field.delegate = nil
                field.target = nil
                field.action = nil
                field.formatter = nil
            } else if let control = root as? NSControl {
                control.target = nil
                control.action = nil
            }
        }
        detachTargets(in: view)

        if let stack = contentStack {
            stack.arrangedSubviews.forEach { child in
                stack.removeArrangedSubview(child)
                child.removeFromSuperview()
            }
        }
        scrollView?.documentView = nil
        contentStack = nil
        scrollView = nil
        onPreferredTitleChanged = nil

        // Replace the controller's strong root-view reference immediately.
        // The controller itself is dropped moments later by AppDelegate.
        view = NSView(frame: .zero)
    }

    override func loadView() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: windowContentHeight))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)

        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -16)
        ])

        contentStack = stack
        scrollView = scroll
        view = scroll

        rebuild(preserveScrollPosition: false)
    }

    func reload() {
        guard isViewLoaded else { return }
        rebuild(preserveScrollPosition: true)
    }

    private func rebuild(preserveScrollPosition: Bool) {
        guard let stack = contentStack else { return }
        let oldY = preserveScrollPosition ? (scrollView?.contentView.bounds.origin.y ?? 0) : 0

        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        onPreferredTitleChanged?(model.text("settings.title"))

        // General
        stack.addArrangedSubview(sectionTitle(model.text("settings.general")))
        stack.addArrangedSubview(formRow(
            label: model.text("settings.language"),
            control: makePopup(
                titles: AppLanguage.allCases.map { languageChoiceTitle($0) },
                selected: AppLanguage.allCases.firstIndex(of: model.settings.language) ?? 0,
                action: #selector(languageChanged(_:))
            )
        ))
        stack.addArrangedSubview(formRow(
            label: model.text("settings.appearance"),
            control: makePopup(
                titles: [
                    model.text("appearance.system"),
                    model.text("appearance.light"),
                    model.text("appearance.dark")
                ],
                selected: AppAppearance.allCases.firstIndex(of: model.settings.appearance) ?? 0,
                action: #selector(appearanceChanged(_:))
            )
        ))

        // Keep Awake
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionTitle(model.text("settings.awakeTimeTitle")))
        for (index, preset) in model.settings.awakePresets.enumerated() {
            stack.addArrangedSubview(makeAwakePresetEditor(index: index, preset: preset))
        }
        stack.addArrangedSubview(makeAwakePresetFooter())

        // Quick Launch grows naturally through seven rows. From the eighth item
        // onward only this list becomes scrollable; wheel gestures at either
        // edge are passed back to the outer settings scroller.
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionTitle(model.text("settings.quickLaunch")))
        stack.addArrangedSubview(formRow(
            label: model.text("settings.quickIconSize"),
            control: makePopup(
                titles: [model.text("quickIcon.small"), model.text("quickIcon.normal"), model.text("quickIcon.large")],
                selected: QuickLaunchIconSize.allCases.firstIndex(of: model.settings.quickLaunchIconSize) ?? 1,
                action: #selector(quickLaunchIconSizeChanged(_:))
            )
        ))
        stack.addArrangedSubview(makeQuickLaunchManager())

        // Menu-bar settings are intentionally last and collapsed by default.
        // Expanding this disclosure never changes the window size; the same
        // outer scroll view simply gains more content.
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(makeMenuBarDisclosure())
        if menuBarSettingsExpanded {
            addMenuBarSettings(to: stack)
        }
        // The organizer rule is intentionally always visible. The visual
        // manifold is the only boundary: every item to its left folds.
        stack.addArrangedSubview(makeMenuBarGuideBlock())

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(makeInformationDisclosure())
        if informationExpanded {
            stack.addArrangedSubview(makeInformationBlock())
        }

        stack.layoutSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()

        if preserveScrollPosition, let scroll = scrollView, let document = scroll.documentView {
            let maxY = max(0, document.fittingSize.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: min(oldY, maxY)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    // MARK: - Shared controls

    private func sectionTitle(_ string: String) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: width - 36).isActive = true
        return box
    }

    private func formRow(label: String, control: NSView) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: width - 36).isActive = true

        let title = NSTextField(labelWithString: label)
        title.font = .systemFont(ofSize: 12)
        title.textColor = .secondaryLabelColor
        title.alignment = .left
        title.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)

        row.addArrangedSubview(title)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(control)
        return row
    }

    private func makePopup(titles: [String], selected: Int, action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: titles)
        popup.selectItem(at: max(0, min(selected, titles.count - 1)))
        popup.target = self
        popup.action = action
        popup.controlSize = .small
        popup.sizeToFit()
        return popup
    }

    private func languageChoiceTitle(_ choice: AppLanguage) -> String {
        let current = model.settings.language.resolved
        if choice == .system {
            switch current {
            case .ko: return "시스템 설정 따름 (System)"
            case .en: return "Follow System"
            case .ja: return "システム設定に従う (System)"
            case .es: return "Seguir sistema (System)"
            case .system: return "Follow System"
            }
        }

        let selfName: String
        switch choice {
        case .ko: selfName = "한국어"
        case .en: selfName = "English"
        case .ja: selfName = "日本語"
        case .es: selfName = "Español"
        case .system: selfName = "System"
        }

        if choice == current { return selfName }

        let localized = model.text("language.\(choice.rawValue)")
        return "\(localized) (\(selfName))"
    }

    // MARK: - Keep Awake presets

    private func makeAwakePresetEditor(index: Int, preset: AwakePreset) -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.widthAnchor.constraint(equalToConstant: width - 36).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(stack)

        let modePopup = makePopup(
            titles: [model.text("settings.awakeMode.duration"), model.text("settings.awakeMode.until")],
            selected: AwakePresetMode.allCases.firstIndex(of: preset.mode) ?? 0,
            action: #selector(awakeModeChanged(_:))
        )
        modePopup.tag = index

        let modeControls = NSStackView()
        modeControls.orientation = .horizontal
        modeControls.alignment = .centerY
        modeControls.spacing = 4
        modeControls.addArrangedSubview(modePopup)

        if index >= 2 {
            let remove = NSButton(
                image: NSImage(systemSymbolName: "minus.circle", accessibilityDescription: model.text("settings.awakeRemove")) ?? NSImage(),
                target: self,
                action: #selector(removeAwakePreset(_:))
            )
            remove.tag = index
            remove.isBordered = false
            remove.toolTip = model.text("settings.awakeRemove")
            modeControls.addArrangedSubview(remove)
        }

        stack.addArrangedSubview(formRow(
            label: "\(model.text("settings.awakeButton")) #\(index + 1)",
            control: modeControls
        ))

        let detailRow = NSStackView()
        detailRow.orientation = .horizontal
        detailRow.alignment = .centerY
        detailRow.spacing = 6
        detailRow.translatesAutoresizingMaskIntoConstraints = false
        detailRow.widthAnchor.constraint(equalToConstant: width - 36).isActive = true
        detailRow.addArrangedSubview(NSView())

        switch preset.mode {
        case .duration:
            let value = NSTextField(string: String(max(1, preset.durationValue)))
            prepareLeanEditableField(value)
            let formatter = NumberFormatter()
            formatter.allowsFloats = false
            formatter.minimum = NSNumber(value: 1)
            formatter.maximum = NSNumber(value: 9999)
            value.formatter = formatter
            value.alignment = .right
            value.controlSize = .small
            value.tag = index
            value.target = self
            value.action = #selector(awakeDurationValueChanged(_:))
            value.translatesAutoresizingMaskIntoConstraints = false
            value.widthAnchor.constraint(equalToConstant: 48).isActive = true

            let unit = makePopup(
                titles: [model.text("awake.unit.hours"), model.text("awake.unit.minutes")],
                selected: AwakeDurationUnit.allCases.firstIndex(of: preset.durationUnit) ?? 0,
                action: #selector(awakeDurationUnitChanged(_:))
            )
            unit.tag = index

            let suffix = NSTextField(labelWithString: model.text("awake.durationSuffix"))
            suffix.font = .systemFont(ofSize: 11.5)
            suffix.textColor = .secondaryLabelColor

            detailRow.addArrangedSubview(value)
            detailRow.addArrangedSubview(unit)
            detailRow.addArrangedSubview(suffix)

        case .untilDate:
            let picker = NSDatePicker()
            picker.datePickerMode = .single
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = [.yearMonthDay, .hourMinute]
            picker.presentsCalendarOverlay = true
            picker.locale = Locale.current
            picker.calendar = Calendar.current
            picker.timeZone = TimeZone.current
            picker.minDate = Date()
            picker.dateValue = max(preset.endDate, Date())
            picker.controlSize = .small
            picker.tag = index
            picker.target = self
            picker.action = #selector(awakeEndDateChanged(_:))
            picker.sizeToFit()

            let suffix = NSTextField(labelWithString: model.text("awake.untilSuffix"))
            suffix.font = .systemFont(ofSize: 11.5)
            suffix.textColor = .secondaryLabelColor

            detailRow.addArrangedSubview(picker)
            detailRow.addArrangedSubview(suffix)
        }

        stack.addArrangedSubview(detailRow)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor),
            stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])
        return wrapper
    }

    private func makeAwakePresetFooter() -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.widthAnchor.constraint(equalToConstant: width - 36).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(stack)

        if model.settings.awakePresets.count < AppSettings.maxAwakePresets {
            let add = NSButton(
                title: "+ \(model.text("settings.awakeAdd"))",
                target: self,
                action: #selector(addAwakePreset)
            )
            add.bezelStyle = .rounded
            add.controlSize = .small
            stack.addArrangedSubview(add)
        }

        let help = NSTextField(labelWithString: model.text("settings.awakeMaximum"))
        help.font = .systemFont(ofSize: 10.5)
        help.textColor = .tertiaryLabelColor
        help.alignment = .right
        stack.addArrangedSubview(help)

        NSLayoutConstraint.activate([
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor),
            stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])
        return wrapper
    }

    // MARK: - Quick Launch

    private func makeQuickLaunchManager() -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.widthAnchor.constraint(equalToConstant: width - 36).isActive = true

        let managerStack = NSStackView()
        managerStack.orientation = .vertical
        managerStack.alignment = .leading
        managerStack.spacing = 5
        managerStack.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(managerStack)

        let iconSize = model.settings.quickLaunchIconSize.points
        let rowHeight = iconSize + 6
        let listSpacing: CGFloat = 5
        let listStack = NSStackView()
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = listSpacing
        listStack.translatesAutoresizingMaskIntoConstraints = false

        for (index, item) in model.quickLaunch.items.enumerated() {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 7

            let image = NSImageView(image: model.quickLaunch.icon(for: item, pointSize: iconSize))
            image.imageScaling = .scaleProportionallyDown
            if item.kind != .app {
                image.contentTintColor = model.quickLaunch.effectiveIconColor(for: item).tintColor
            }
            image.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                image.widthAnchor.constraint(equalToConstant: iconSize),
                image.heightAnchor.constraint(equalToConstant: iconSize)
            ])

            let name = NSTextField(labelWithString: item.name)
            name.font = .systemFont(ofSize: 12)
            name.lineBreakMode = .byTruncatingTail
            name.toolTip = quickLaunchTypeName(item.kind)
            name.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let up = NSButton(
                image: NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil) ?? NSImage(),
                target: self,
                action: #selector(moveQuickLaunchUpAt(_:))
            )
            up.tag = index
            up.isBordered = false
            up.isEnabled = index > 0
            up.toolTip = model.text("quick.moveUp")

            let down = NSButton(
                image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil) ?? NSImage(),
                target: self,
                action: #selector(moveQuickLaunchDownAt(_:))
            )
            down.tag = index
            down.isBordered = false
            down.isEnabled = index < model.quickLaunch.items.count - 1
            down.toolTip = model.text("quick.moveDown")

            let remove = NSButton(
                image: NSImage(systemSymbolName: "minus.circle", accessibilityDescription: nil) ?? NSImage(),
                target: self,
                action: #selector(removeQuickLaunchAt(_:))
            )
            remove.tag = index
            remove.isBordered = false
            remove.toolTip = model.text("quick.remove")

            row.addArrangedSubview(image)
            row.addArrangedSubview(name)

            if item.kind == .app {
                // Keep action columns aligned while app icons retain their
                // original full-color artwork and have no tint selector.
                let colorSpacer = NSView()
                colorSpacer.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    colorSpacer.widthAnchor.constraint(equalToConstant: 20),
                    colorSpacer.heightAnchor.constraint(equalToConstant: 20)
                ])
                row.addArrangedSubview(colorSpacer)
            } else {
                let preset = model.quickLaunch.effectiveIconColor(for: item)
                let colorButton = NSButton(
                    image: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: model.text("quick.iconColor")) ?? NSImage(),
                    target: self,
                    action: #selector(showQuickLaunchColorMenu(_:))
                )
                colorButton.tag = index
                colorButton.isBordered = false
                colorButton.contentTintColor = preset.tintColor ?? .secondaryLabelColor
                colorButton.toolTip = model.text("quick.iconColor")
                colorButton.imageScaling = .scaleProportionallyDown
                colorButton.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    colorButton.widthAnchor.constraint(equalToConstant: 20),
                    colorButton.heightAnchor.constraint(equalToConstant: 20)
                ])
                row.addArrangedSubview(colorButton)
            }

            row.addArrangedSubview(up)
            row.addArrangedSubview(down)
            row.addArrangedSubview(remove)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            listStack.addArrangedSubview(row)
        }

        if model.quickLaunch.items.count > 7 {
            let scroll = EdgePassthroughScrollView()
            scroll.translatesAutoresizingMaskIntoConstraints = false
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = false
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false
            scroll.borderType = .noBorder
            scroll.verticalScrollElasticity = .none
            scroll.outerScrollView = scrollView

            let document = FlippedView()
            document.translatesAutoresizingMaskIntoConstraints = false
            scroll.documentView = document
            document.addSubview(listStack)

            NSLayoutConstraint.activate([
                document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
                listStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
                listStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
                listStack.topAnchor.constraint(equalTo: document.topAnchor),
                listStack.bottomAnchor.constraint(equalTo: document.bottomAnchor)
            ])

            for row in listStack.arrangedSubviews {
                row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
            }

            let sevenRowsHeight = rowHeight * 7 + listSpacing * 6
            scroll.heightAnchor.constraint(equalToConstant: sevenRowsHeight).isActive = true
            scroll.widthAnchor.constraint(equalToConstant: width - 36).isActive = true
            managerStack.addArrangedSubview(scroll)
        } else if !model.quickLaunch.items.isEmpty {
            listStack.widthAnchor.constraint(equalToConstant: width - 36).isActive = true
            for row in listStack.arrangedSubviews {
                row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
            }
            managerStack.addArrangedSubview(listStack)
        }

        let add = NSButton(
            image: NSImage(systemSymbolName: "plus", accessibilityDescription: model.text("settings.quickLaunch")) ?? NSImage(),
            target: self,
            action: #selector(showAddMenu(_:))
        )
        add.isBordered = false
        add.toolTip = model.text("settings.quickLaunch")
        managerStack.addArrangedSubview(add)

        NSLayoutConstraint.activate([
            managerStack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            managerStack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            managerStack.topAnchor.constraint(equalTo: wrapper.topAnchor),
            managerStack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])
        return wrapper
    }

    private func quickLaunchTypeName(_ kind: QuickLaunchKind) -> String {
        switch kind {
        case .app: return model.text("quick.type.app")
        case .fileOrFolder: return model.text("quick.type.file")
        case .web: return model.text("quick.type.web")
        case .systemSetting: return model.text("quick.type.setting")
        }
    }

    // MARK: - Menu Bar settings disclosure

    private func makeMenuBarDisclosure() -> NSButton {
        let imageName = menuBarSettingsExpanded ? "chevron.down" : "chevron.right"
        let image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = true

        let button = NSButton(
            title: model.text("settings.menuBarDisplay"),
            image: image,
            target: self,
            action: #selector(toggleMenuBarSettings)
        )
        button.isBordered = false
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: width - 36).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    private func addMenuBarSettings(to stack: NSStackView) {
        stack.addArrangedSubview(formRow(
            label: model.text("settings.menuBarFoldMode"),
            control: makePopup(
                titles: [model.text("foldMode.keepExpanded"), model.text("foldMode.automatic")],
                selected: MenuBarFoldMode.allCases.firstIndex(of: model.settings.menuBarFoldMode) ?? 1,
                action: #selector(menuBarFoldModeChanged(_:))
            )
        ))

        if model.settings.menuBarFoldMode == .automatic {
            let delayField = NSTextField(string: String(Int(model.settings.autoFoldDelay.rounded())))
            prepareLeanEditableField(delayField)
            let formatter = NumberFormatter()
            formatter.allowsFloats = false
            formatter.minimum = 1
            formatter.maximum = 300
            delayField.formatter = formatter
            delayField.alignment = .right
            delayField.controlSize = .small
            delayField.target = self
            delayField.action = #selector(autoFoldDelayChanged(_:))
            delayField.translatesAutoresizingMaskIntoConstraints = false
            delayField.widthAnchor.constraint(equalToConstant: 44).isActive = true

            let suffix = NSTextField(labelWithString: model.text("settings.autoFoldSecondsSuffix"))
            suffix.font = .systemFont(ofSize: 11.5)
            suffix.textColor = .secondaryLabelColor
            let delayControl = NSStackView(views: [delayField, suffix])
            delayControl.orientation = .horizontal
            delayControl.alignment = .centerY
            delayControl.spacing = 5
            stack.addArrangedSubview(formRow(label: model.text("settings.autoFoldDelay"), control: delayControl))

            let wait = NSButton(checkboxWithTitle: model.text("settings.autoFoldWait"), target: self, action: #selector(waitWhilePointerChanged(_:)))
            wait.state = model.settings.waitWhilePointerInMenuBar ? .on : .off
            wait.controlSize = .small
            stack.addArrangedSubview(formRow(label: model.text("settings.autoFoldPointer"), control: wait))
        }

        stack.addArrangedSubview(formRow(
            label: model.text("settings.menuBarContent"),
            control: makePopup(
                titles: [
                    model.text("menuBarContent.network"),
                    model.text("menuBarContent.appIcon")
                ],
                selected: MenuBarContentMode.allCases.firstIndex(of: model.settings.menuBarContentMode) ?? 0,
                action: #selector(menuBarContentChanged(_:))
            )
        ))

        guard model.settings.menuBarContentMode == .network else {
            stack.addArrangedSubview(indentedHelpLabel(model.text("settings.networkPausedHelp")))
            return
        }

        stack.addArrangedSubview(formRow(
            label: model.text("settings.displayStyle"),
            control: makePopup(
                titles: [
                    model.text("style.twoLineCompact"),
                    model.text("style.oneLineCompact")
                ],
                selected: MenuBarDisplayStyle.allCases.firstIndex(of: model.settings.displayStyle) ?? 0,
                action: #selector(displayStyleChanged(_:))
            )
        ))

        let availableFontSizes: [MenuBarFontSize] = model.settings.displayStyle == .oneLineCompact
            ? [.small, .normal, .large, .extraLarge]
            : [.small, .normal, .large]
        let effectiveFontSize: MenuBarFontSize = (model.settings.displayStyle == .twoLineCompact && model.settings.fontSize == .extraLarge)
            ? .large
            : model.settings.fontSize
        let fontTitles = availableFontSizes.map { size -> String in
            switch size {
            case .small: return model.text("font.small")
            case .normal: return model.text("font.normal")
            case .large: return model.text("font.large")
            case .extraLarge: return model.text("font.extraLarge")
            }
        }
        stack.addArrangedSubview(formRow(
            label: model.text("settings.fontSize"),
            control: makePopup(
                titles: fontTitles,
                selected: availableFontSizes.firstIndex(of: effectiveFontSize) ?? 1,
                action: #selector(fontSizeChanged(_:))
            )
        ))

        stack.addArrangedSubview(formRow(
            label: model.text("settings.traffic"),
            control: makePopup(
                titles: [
                    model.text("traffic.both"),
                    model.text("traffic.download"),
                    model.text("traffic.upload")
                ],
                selected: TrafficDisplay.allCases.firstIndex(of: model.settings.trafficDisplay) ?? 0,
                action: #selector(trafficChanged(_:))
            )
        ))

        if model.settings.trafficDisplay == .both {
            stack.addArrangedSubview(formRow(
                label: model.text("settings.order"),
                control: makePopup(
                    titles: [
                        model.text("order.downloadFirst"),
                        model.text("order.uploadFirst")
                    ],
                    selected: NetworkOrder.allCases.firstIndex(of: model.settings.networkOrder) ?? 0,
                    action: #selector(orderChanged(_:))
                )
            ))
        }

        stack.addArrangedSubview(formRow(
            label: model.text("settings.arrows"),
            control: makePopup(
                titles: [model.text("arrows.hidden"), model.text("arrows.shown")],
                selected: ArrowDisplay.allCases.firstIndex(of: model.settings.arrowDisplay) ?? 0,
                action: #selector(arrowsChanged(_:))
            )
        ))

        stack.addArrangedSubview(formRow(
            label: model.text("settings.units"),
            control: makePopup(
                titles: [model.text("unit.simple"), model.text("unit.unit"), model.text("unit.bits")],
                selected: SpeedUnitMode.allCases.firstIndex(of: model.settings.unitMode) ?? 0,
                action: #selector(unitModeChanged(_:))
            )
        ))

        let refreshField = NSTextField(string: String(format: "%.1f", model.settings.refreshInterval))
        prepareLeanEditableField(refreshField)
        let refreshFormatter = NumberFormatter()
        refreshFormatter.numberStyle = .decimal
        refreshFormatter.allowsFloats = true
        refreshFormatter.minimum = NSNumber(value: 0.1)
        refreshFormatter.minimumFractionDigits = 1
        refreshFormatter.maximumFractionDigits = 1
        refreshFormatter.usesGroupingSeparator = false
        refreshField.formatter = refreshFormatter
        refreshField.alignment = .right
        refreshField.controlSize = .small
        refreshField.target = self
        refreshField.action = #selector(refreshChanged(_:))
        refreshField.translatesAutoresizingMaskIntoConstraints = false
        // Sized for common values such as 60.3 / 999.9. Larger values remain
        // valid and can scroll inside the field; there is intentionally no max.
        refreshField.widthAnchor.constraint(equalToConstant: 58).isActive = true

        let refreshSuffix = NSTextField(labelWithString: model.text("settings.secondsSuffix"))
        refreshSuffix.font = .systemFont(ofSize: 11.5)
        refreshSuffix.textColor = .secondaryLabelColor
        let refreshControl = NSStackView(views: [refreshField, refreshSuffix])
        refreshControl.orientation = .horizontal
        refreshControl.alignment = .centerY
        refreshControl.spacing = 5
        stack.addArrangedSubview(formRow(label: model.text("settings.refresh"), control: refreshControl))
    }

    private func indentedHelpLabel(_ text: String) -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.widthAnchor.constraint(equalToConstant: width - 36).isActive = true

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 115),
            label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            label.topAnchor.constraint(equalTo: wrapper.topAnchor),
            label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])
        return wrapper
    }

    private func makeMenuBarGuideBlock() -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.fillColor = .controlBackgroundColor
        box.borderColor = .separatorColor
        box.borderWidth = 1
        box.cornerRadius = 8
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: width - 36).isActive = true

        guard let content = box.contentView else { return box }

        let title = NSTextField(labelWithString: model.text("settings.menuBarGuideTitle"))
        title.font = .systemFont(ofSize: 12.5, weight: .semibold)

        let example = NSStackView()
        example.orientation = .horizontal
        example.alignment = .centerY
        example.spacing = 5
        example.translatesAutoresizingMaskIntoConstraints = false

        func token(_ text: String) -> NSTextField {
            let label = NSTextField(labelWithString: "[\(text)]")
            // The example is the primary teaching line, so keep it visibly
            // larger than the explanatory copy below it.
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.textColor = .labelColor
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return label
        }

        let foldIcon = NSImageView(image: FoldIconFactory.manifold(width: 14, height: 20))
        foldIcon.imageScaling = .scaleProportionallyDown
        foldIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            foldIcon.widthAnchor.constraint(equalToConstant: 14),
            foldIcon.heightAnchor.constraint(equalToConstant: 20)
        ])

        let modeIcons = makeMenuBarGuideModeIcons()

        example.addArrangedSubview(token(model.text("settings.menuBarGuideHidden")))
        example.addArrangedSubview(foldIcon)
        example.addArrangedSubview(token(model.text("settings.menuBarGuideVisible")))
        example.addArrangedSubview(modeIcons)
        example.addArrangedSubview(token(model.text("settings.menuBarGuideVisible")))

        let body = NSTextField(wrappingLabelWithString: model.text("settings.menuBarGuideBody"))
        body.font = .systemFont(ofSize: 11)
        body.textColor = .secondaryLabelColor
        body.maximumNumberOfLines = 0
        body.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [title, example, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            example.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
            body.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return box
    }

    private func makeMenuBarGuideModeIcons() -> NSView {
        switch model.settings.menuBarContentMode {
        case .network:
            let preview = MenuBarGuideNetworkPreviewView()
            preview.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                preview.widthAnchor.constraint(equalToConstant: 31),
                preview.heightAnchor.constraint(equalToConstant: 22)
            ])
            return preview

        case .appIcon:
            let imageView = NSImageView(image: statusIcon)
            imageView.imageScaling = .scaleProportionallyDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 17),
                imageView.heightAnchor.constraint(equalToConstant: 17)
            ])
            return imageView
        }
    }

    // MARK: - Information

    private func makeInformationDisclosure() -> NSButton {
        let imageName = informationExpanded ? "chevron.down" : "chevron.right"
        let image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = true
        let button = NSButton(
            title: model.text("settings.info"),
            image: image,
            target: self,
            action: #selector(toggleInformation)
        )
        button.isBordered = false
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: width - 36).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    private func makeInformationBlock() -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.widthAnchor.constraint(equalToConstant: width - 36).isActive = true

        let appIcon = NSImageView(image: infoAppIcon)
        appIcon.imageScaling = .scaleProportionallyDown
        appIcon.translatesAutoresizingMaskIntoConstraints = false

        let appName = NSTextField(labelWithString: "MenuFold")
        appName.font = .systemFont(ofSize: 16, weight: .semibold)
        appName.alignment = .center

        let description = NSTextField(wrappingLabelWithString: model.text("info.description"))
        description.font = .systemFont(ofSize: 11.5)
        description.alignment = .center
        description.maximumNumberOfLines = 0
        description.translatesAutoresizingMaskIntoConstraints = false

        let credit = NSTextField(wrappingLabelWithString: model.text("info.credit"))
        credit.font = .systemFont(ofSize: 11.5)
        credit.textColor = .secondaryLabelColor
        credit.alignment = .center
        credit.maximumNumberOfLines = 0
        credit.translatesAutoresizingMaskIntoConstraints = false

        let github = infoButton(
            title: model.text("info.github"),
            // Match the GitHub button symbol already used by NeManeem.
            image: NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: nil),
            action: #selector(openGitHub),
            enabled: true
        )
        let appStore = infoButton(
            title: model.text("info.appStore"),
            image: NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil),
            action: #selector(openAppStore),
            enabled: true
        )

        let snackIntro = NSTextField(wrappingLabelWithString: model.text("info.snackIntro"))
        snackIntro.font = .systemFont(ofSize: 11.5)
        snackIntro.textColor = .secondaryLabelColor
        snackIntro.alignment = .center
        snackIntro.maximumNumberOfLines = 0
        snackIntro.translatesAutoresizingMaskIntoConstraints = false

        let snack = infoButton(
            title: model.text("info.snack"),
            image: NSImage(systemSymbolName: "gift", accessibilityDescription: nil),
            action: #selector(openSnack),
            enabled: true
        )

        let stack = NSStackView(views: [appIcon, appName, description, credit, github, appStore, snack, snackIntro])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(stack)

        NSLayoutConstraint.activate([
            appIcon.widthAnchor.constraint(equalToConstant: 48),
            appIcon.heightAnchor.constraint(equalToConstant: 48),
            stack.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -2),
            description.widthAnchor.constraint(equalToConstant: width - 64),
            credit.widthAnchor.constraint(equalToConstant: width - 64),
            snackIntro.widthAnchor.constraint(equalToConstant: width - 64)
        ])
        return wrapper
    }

    private func infoButton(title: String, image: NSImage?, action: Selector?, enabled: Bool) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.alignment = .center
        button.isEnabled = enabled
        if let image {
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
        }
        button.sizeToFit()
        return button
    }


    // MARK: - Setting actions

    @objc private func toggleMenuBarSettings() {
        menuBarSettingsExpanded.toggle()
        rebuild(preserveScrollPosition: true)
    }

    @objc private func toggleInformation() {
        informationExpanded.toggle()
        rebuild(preserveScrollPosition: true)
    }

    @objc private func menuBarContentChanged(_ sender: NSPopUpButton) {
        let values = MenuBarContentMode.allCases
        guard values.indices.contains(sender.indexOfSelectedItem) else { return }
        model.settings.menuBarContentMode = values[sender.indexOfSelectedItem]
        rebuild(preserveScrollPosition: true)
    }

    @objc private func menuBarFoldModeChanged(_ sender: NSPopUpButton) {
        let values = MenuBarFoldMode.allCases
        guard values.indices.contains(sender.indexOfSelectedItem) else { return }
        model.settings.menuBarFoldMode = values[sender.indexOfSelectedItem]
        rebuild(preserveScrollPosition: true)
    }

    @objc private func autoFoldDelayChanged(_ sender: NSTextField) {
        let value = min(300, max(1, sender.doubleValue))
        model.settings.autoFoldDelay = value
        sender.stringValue = String(Int(model.settings.autoFoldDelay.rounded()))
    }

    @objc private func waitWhilePointerChanged(_ sender: NSButton) {
        model.settings.waitWhilePointerInMenuBar = sender.state == .on
    }

    @objc private func quickLaunchIconSizeChanged(_ sender: NSPopUpButton) {
        let values = QuickLaunchIconSize.allCases
        guard values.indices.contains(sender.indexOfSelectedItem) else { return }
        model.settings.quickLaunchIconSize = values[sender.indexOfSelectedItem]
        model.quickLaunch.purgeIconCache()
        // Keep the settings list as a live preview of the same 24/28/32pt
        // choice used by the popover, including matching row heights.
        rebuild(preserveScrollPosition: true)
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let values = AppLanguage.allCases
        guard values.indices.contains(sender.indexOfSelectedItem) else { return }
        model.settings.language = values[sender.indexOfSelectedItem]
        rebuild(preserveScrollPosition: true)
    }

    @objc private func appearanceChanged(_ sender: NSPopUpButton) {
        let values = AppAppearance.allCases
        guard values.indices.contains(sender.indexOfSelectedItem) else { return }
        model.settings.appearance = values[sender.indexOfSelectedItem]
    }

    @objc private func displayStyleChanged(_ sender: NSPopUpButton) {
        let values = MenuBarDisplayStyle.allCases
        guard values.indices.contains(sender.indexOfSelectedItem) else { return }
        model.settings.displayStyle = values[sender.indexOfSelectedItem]
        // Font choices are structural: Extra Large exists only for one-line.
        rebuild(preserveScrollPosition: true)
    }

    @objc private func trafficChanged(_ sender: NSPopUpButton) {
        let values = TrafficDisplay.allCases
        guard values.indices.contains(sender.indexOfSelectedItem) else { return }
        model.settings.trafficDisplay = values[sender.indexOfSelectedItem]
        rebuild(preserveScrollPosition: true)
    }

    @objc private func orderChanged(_ sender: NSPopUpButton) {
        let values = NetworkOrder.allCases
        guard values.indices.contains(sender.indexOfSelectedItem) else { return }
        model.settings.networkOrder = values[sender.indexOfSelectedItem]
    }

    @objc private func arrowsChanged(_ sender: NSPopUpButton) {
        let values = ArrowDisplay.allCases
        guard values.indices.contains(sender.indexOfSelectedItem) else { return }
        model.settings.arrowDisplay = values[sender.indexOfSelectedItem]
    }

    @objc private func unitModeChanged(_ sender: NSPopUpButton) {
        let values = SpeedUnitMode.allCases
        guard values.indices.contains(sender.indexOfSelectedItem) else { return }
        model.settings.unitMode = values[sender.indexOfSelectedItem]
    }

    @objc private func fontSizeChanged(_ sender: NSPopUpButton) {
        let values: [MenuBarFontSize] = model.settings.displayStyle == .oneLineCompact
            ? [.small, .normal, .large, .extraLarge]
            : [.small, .normal, .large]
        guard values.indices.contains(sender.indexOfSelectedItem) else { return }
        model.settings.fontSize = values[sender.indexOfSelectedItem]
    }

    @objc private func refreshChanged(_ sender: NSTextField) {
        let raw = sender.doubleValue
        let normalized = raw.isFinite ? max(0.1, (raw * 10).rounded() / 10) : 3.0
        model.settings.refreshInterval = normalized
        sender.stringValue = String(format: "%.1f", model.settings.refreshInterval)
    }

    @objc private func awakeModeChanged(_ sender: NSPopUpButton) {
        let values = AwakePresetMode.allCases
        guard values.indices.contains(sender.indexOfSelectedItem),
              model.settings.awakePresets.indices.contains(sender.tag) else { return }
        let selected = values[sender.indexOfSelectedItem]
        model.settings.updateAwakePreset(at: sender.tag) { preset in
            preset.mode = selected
            if selected == .untilDate, preset.endDate <= Date() {
                preset.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
            }
        }
        rebuild(preserveScrollPosition: true)
    }

    @objc private func awakeDurationValueChanged(_ sender: NSTextField) {
        guard model.settings.awakePresets.indices.contains(sender.tag) else { return }
        model.settings.updateAwakePreset(at: sender.tag) { preset in
            preset.durationValue = max(1, sender.integerValue)
        }
        sender.stringValue = String(model.settings.awakePresets[sender.tag].durationValue)
    }

    @objc private func awakeDurationUnitChanged(_ sender: NSPopUpButton) {
        let values = AwakeDurationUnit.allCases
        guard values.indices.contains(sender.indexOfSelectedItem),
              model.settings.awakePresets.indices.contains(sender.tag) else { return }
        model.settings.updateAwakePreset(at: sender.tag) { preset in
            preset.durationUnit = values[sender.indexOfSelectedItem]
        }
    }

    @objc private func awakeEndDateChanged(_ sender: NSDatePicker) {
        guard model.settings.awakePresets.indices.contains(sender.tag) else { return }
        model.settings.updateAwakePreset(at: sender.tag) { preset in
            preset.endDate = sender.dateValue
        }
    }

    @objc private func addAwakePreset() {
        model.settings.addAwakePreset()
        rebuild(preserveScrollPosition: true)
    }

    @objc private func removeAwakePreset(_ sender: NSButton) {
        model.settings.removeAwakePreset(at: sender.tag)
        rebuild(preserveScrollPosition: true)
    }

    @objc private func openGitHub() {
        guard let url = URL(string: "https://github.com/Bak2ya/MenuFold") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openAppStore() {
        guard let url = URL(string: "macappstore://itunes.apple.com/app/id6806565750") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openSnack() {
        guard snackWindowController == nil, let parentWindow = view.window else { return }
        let photoName = nextSnackPhotoName()
        let controller = SnackPurchaseWindowController(
            model: model,
            photoName: photoName,
            onDismiss: { [weak self] in
                self?.snackWindowController = nil
            }
        )
        snackWindowController = controller
        controller.present(asSheetOf: parentWindow)
    }

    private func nextSnackPhotoName() -> String {
        guard snackPhotoNames.count > 1 else { return snackPhotoNames.first ?? "Maneem_2431" }
        let candidates = snackPhotoNames.filter { $0 != lastSnackPhotoName }
        let selected = candidates.randomElement() ?? snackPhotoNames[0]
        lastSnackPhotoName = selected
        return selected
    }

    // MARK: - Quick Launch actions

    @objc private func showAddMenu(_ sender: NSButton) {
        let menu = NSMenu()

        let app = NSMenuItem(title: model.text("quick.addApp"), action: #selector(addApplication), keyEquivalent: "")
        app.target = self
        menu.addItem(app)

        let file = NSMenuItem(title: model.text("quick.addFile"), action: #selector(addFileOrFolder), keyEquivalent: "")
        file.target = self
        menu.addItem(file)

        let web = NSMenuItem(title: model.text("quick.addWeb"), action: #selector(addWeb), keyEquivalent: "")
        web.target = self
        menu.addItem(web)

        let settingRoot = NSMenuItem(title: model.text("quick.addSetting"), action: nil, keyEquivalent: "")
        let settingMenu = NSMenu()
        for (index, shortcut) in SystemSettingShortcut.presets.enumerated() {
            let item = NSMenuItem(
                title: model.text(shortcut.localizationKey),
                action: #selector(addSystemSetting(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            settingMenu.addItem(item)
        }
        settingRoot.submenu = settingMenu
        menu.addItem(settingRoot)

        let point = NSPoint(x: 0, y: sender.bounds.height + 2)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc private func addApplication() {
        model.quickLaunch.addApplication(title: model.text("quick.addApp"))
    }

    @objc private func addFileOrFolder() {
        model.quickLaunch.addFileOrFolder(title: model.text("quick.addFile"))
    }

    @objc private func addWeb() {
        let alert = NSAlert()
        alert.messageText = model.text("quick.webTitle")
        alert.addButton(withTitle: model.text("action.add"))
        alert.addButton(withTitle: model.text("action.cancel"))

        let grid = NSGridView(views: [])
        let name = NSTextField()
        let address = NSTextField()
        prepareLeanEditableField(name)
        prepareLeanEditableField(address)
        name.placeholderString = model.text("quick.webName")
        address.placeholderString = "https://"

        grid.addRow(with: [NSTextField(labelWithString: model.text("quick.webName")), name])
        grid.addRow(with: [NSTextField(labelWithString: model.text("quick.webAddress")), address])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.frame = NSRect(x: 0, y: 0, width: 300, height: 60)
        alert.accessoryView = grid

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.quickLaunch.addWeb(name: name.stringValue, urlString: address.stringValue)
    }

    @objc private func addSystemSetting(_ sender: NSMenuItem) {
        guard SystemSettingShortcut.presets.indices.contains(sender.tag) else { return }
        let shortcut = SystemSettingShortcut.presets[sender.tag]
        model.quickLaunch.addSystemSetting(
            shortcut,
            displayName: model.text(shortcut.localizationKey)
        )
    }

    @objc private func showQuickLaunchColorMenu(_ sender: NSButton) {
        guard model.quickLaunch.items.indices.contains(sender.tag) else { return }
        let item = model.quickLaunch.items[sender.tag]
        guard item.kind != .app else { return }

        let current = model.quickLaunch.effectiveIconColor(for: item)
        let menu = NSMenu()
        for preset in QuickLaunchIconColorPreset.allCases {
            let title = model.text(preset.localizationKey)
            let menuItem = NSMenuItem(
                title: title,
                action: #selector(selectQuickLaunchIconColor(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.state = preset == current ? .on : .off
            menuItem.representedObject = "\(item.id.uuidString)|\(preset.rawValue)"

            // A colored bullet gives a direct preview without introducing a
            // full custom color picker. Default intentionally follows labelColor.
            let bulletColor = preset.tintColor ?? NSColor.labelColor
            let attributed = NSMutableAttributedString(string: "●  \(title)")
            attributed.addAttribute(
                .foregroundColor,
                value: bulletColor,
                range: NSRange(location: 0, length: 1)
            )
            menuItem.attributedTitle = attributed
            menu.addItem(menuItem)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc private func selectQuickLaunchIconColor(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? String else { return }
        let parts = payload.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let id = UUID(uuidString: parts[0]),
              let preset = QuickLaunchIconColorPreset(rawValue: parts[1]) else { return }
        model.quickLaunch.setIconColor(preset, forID: id)
    }

    @objc private func removeQuickLaunchAt(_ sender: NSButton) {
        model.quickLaunch.remove(at: sender.tag)
    }

    @objc private func moveQuickLaunchUpAt(_ sender: NSButton) {
        model.quickLaunch.moveUp(at: sender.tag)
    }

    @objc private func moveQuickLaunchDownAt(_ sender: NSButton) {
        model.quickLaunch.moveDown(at: sender.tag)
    }
}
