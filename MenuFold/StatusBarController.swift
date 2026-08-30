import AppKit
import os

/// Lightweight menu-bar renderer designed specifically for NSStatusItem.
///
/// macOS 26 repeatedly asks status items for replicant snapshots even while the
/// app is otherwise idle. A previous NSStackView + two NSTextField hierarchy
/// caused each snapshot to re-enter Auto Layout, CoreText, and AppKit styling.
/// This view keeps no controls or constraints. It rasterizes the tiny meter only
/// when the visible strings/style/appearance actually change; normal AppKit
/// snapshots then copy one already-rendered bitmap.
final class StatusDisplayView: NSView {
    private var presentation = StatusPresentation(lines: ["0.0K", "0.0K"], fontSize: 10.0, width: 44)
    private var cachedImage: NSImage?
    private var cachedSize: NSSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // Keep the native NSStatusBarButton as the pointer target.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        ensureCachedImage()
        cachedImage?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(frame.size.width - newSize.width) > 0.5 || abs(frame.size.height - newSize.height) > 0.5
        super.setFrameSize(newSize)
        if changed {
            invalidateCachedRendering()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        invalidateCachedRendering()
    }

    /// Full style/layout application is reserved for settings changes. Normal
    /// network ticks only change the strings and regenerate this tiny bitmap.
    func applyPresentation(_ newPresentation: StatusPresentation, updateStyle: Bool) {
        let styleChanged = updateStyle
            || abs(presentation.fontSize - newPresentation.fontSize) > 0.001
            || presentation.lines.count != newPresentation.lines.count
        let linesChanged = presentation.lines != newPresentation.lines
        presentation = newPresentation
        if styleChanged || linesChanged {
            invalidateCachedRendering()
        }
    }

    /// Returns true only when visible strings actually changed.
    @discardableResult
    func updateLines(_ lines: [String]) -> Bool {
        guard lines != presentation.lines else { return false }
        presentation = StatusPresentation(lines: lines, fontSize: presentation.fontSize, width: presentation.width)
        invalidateCachedRendering()
        return true
    }

    private func invalidateCachedRendering() {
        cachedImage = nil
        cachedSize = .zero
        needsDisplay = true
    }

    private func ensureCachedImage() {
        let targetSize = NSSize(width: max(1, bounds.width), height: max(1, bounds.height))
        if cachedImage != nil,
           abs(cachedSize.width - targetSize.width) <= 0.5,
           abs(cachedSize.height - targetSize.height) <= 0.5 {
            return
        }

        let image = NSImage(size: targetSize)
        let appearance = effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            image.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .none

            let font = NSFont.monospacedDigitSystemFont(ofSize: presentation.fontSize, weight: .semibold)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            paragraph.lineBreakMode = .byClipping
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]

            let lines = Array(presentation.lines.prefix(2))
            let lineHeight = max(1, ceil(font.ascender - font.descender + font.leading))
            let spacing: CGFloat = lines.count >= 2 ? -2.4 : 0
            let totalHeight = lineHeight * CGFloat(max(1, lines.count)) + spacing * CGFloat(max(0, lines.count - 1))
            let bottomY = floor((targetSize.height - totalHeight) / 2.0)
            let horizontalInset: CGFloat = 1.5
            let textWidth = max(1, targetSize.width - horizontalInset * 2)

            if let first = lines.first {
                let y = lines.count >= 2 ? bottomY + lineHeight + spacing : bottomY
                (first as NSString).draw(
                    in: NSRect(x: horizontalInset, y: y, width: textWidth, height: lineHeight),
                    withAttributes: attributes
                )
            }
            if lines.count >= 2 {
                (lines[1] as NSString).draw(
                    in: NSRect(x: horizontalInset, y: bottomY, width: textWidth, height: lineHeight),
                    withAttributes: attributes
                )
            }

            image.unlockFocus()
        }
        image.isTemplate = false
        cachedImage = image
        cachedSize = targetSize
    }
}

private final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A non-activating overlay that visually represents the fold control without
/// exposing the underlying NSStatusItem to Command-drag. macOS owns status-item
/// rearrangement and offers no public "lock this item in place" API, so the
/// actual spacer remains invisible while this panel provides the visible,
/// clickable manifold.
private final class FoldOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FoldOverlayView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    private var mouseDownPoint: NSPoint?
    private var dragged = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image else { return }
        let imageSize = image.size
        let rect = NSRect(
            x: bounds.midX - imageSize.width / 2,
            y: bounds.midY - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        )
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        if hypot(current.x - start.x, current.y - start.y) > 2 { dragged = true }
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil; dragged = false }
        // Command-drag is intentionally swallowed. The manifold is a fixed
        // MenuFold control, not a user-reorderable status item.
        guard !dragged, !event.modifierFlags.contains(.command) else { return }
        onLeftClick?()
    }

    override func rightMouseUp(with event: NSEvent) {
        onRightClick?()
    }
}

/// Small, transparent menu-bar artwork for the fold marker.
///
/// The three inputs curve into one output so the shape reads both as a compact
/// manifold and as a closing brace. A bold variant is used only while the
/// current expansion is pinned open.
enum FoldIconFactory {
    private static let outline = NSColor(calibratedWhite: 0.08, alpha: 0.90)
    private static let pinnedOutline = NSColor(calibratedWhite: 0.98, alpha: 0.98)
    private static let manifoldColor = NSColor(calibratedRed: 0.32, green: 0.57, blue: 0.98, alpha: 1.0)

    static func manifold(width: CGFloat = 9, height: CGFloat = 18, bold: Bool = false) -> NSImage {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()

        let leftX = width * 0.20
        let joinX = width * 0.63
        let outX = width * 0.84
        let topY = height * 0.77
        let midY = height * 0.50
        let bottomY = height * 0.23
        let baseOuterWidth = max(1.35, min(width, height) * 0.10)
        let outerWidth = bold ? max(2.15, baseOuterWidth * 1.65) : baseOuterWidth
        let innerWidth = bold ? max(0.95, baseOuterWidth * 0.70) : max(0.75, outerWidth * 0.56)
        let outerColor = bold ? pinnedOutline : outline
        let radius = max(0.90, min(width, height) * 0.095)

        let upper = NSBezierPath()
        upper.move(to: NSPoint(x: leftX, y: topY))
        upper.curve(
            to: NSPoint(x: joinX, y: midY),
            controlPoint1: NSPoint(x: width * 0.49, y: topY),
            controlPoint2: NSPoint(x: width * 0.47, y: height * 0.59)
        )
        stroke(upper, outerWidth: outerWidth, innerWidth: innerWidth, color: manifoldColor, outlineColor: outerColor)

        let middle = NSBezierPath()
        middle.move(to: NSPoint(x: leftX, y: midY))
        middle.curve(
            to: NSPoint(x: joinX, y: midY),
            controlPoint1: NSPoint(x: width * 0.39, y: midY),
            controlPoint2: NSPoint(x: width * 0.50, y: midY)
        )
        stroke(middle, outerWidth: outerWidth, innerWidth: innerWidth, color: manifoldColor, outlineColor: outerColor)

        let lower = NSBezierPath()
        lower.move(to: NSPoint(x: leftX, y: bottomY))
        lower.curve(
            to: NSPoint(x: joinX, y: midY),
            controlPoint1: NSPoint(x: width * 0.49, y: bottomY),
            controlPoint2: NSPoint(x: width * 0.47, y: height * 0.41)
        )
        stroke(lower, outerWidth: outerWidth, innerWidth: innerWidth, color: manifoldColor, outlineColor: outerColor)

        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: joinX, y: midY))
        stem.line(to: NSPoint(x: outX, y: midY))
        stroke(stem, outerWidth: outerWidth, innerWidth: innerWidth, color: manifoldColor, outlineColor: outerColor)

        ring(center: NSPoint(x: leftX, y: topY), radius: radius, outerWidth: outerWidth, innerWidth: innerWidth, outlineColor: outerColor)
        ring(center: NSPoint(x: leftX, y: midY), radius: radius, outerWidth: outerWidth, innerWidth: innerWidth, outlineColor: outerColor)
        ring(center: NSPoint(x: leftX, y: bottomY), radius: radius, outerWidth: outerWidth, innerWidth: innerWidth, outlineColor: outerColor)
        ring(center: NSPoint(x: outX, y: midY), radius: radius, outerWidth: outerWidth, innerWidth: innerWidth, outlineColor: outerColor)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    static func preview() -> NSImage {
        manifold(width: 30, height: 42)
    }

    private static func stroke(
        _ path: NSBezierPath,
        outerWidth: CGFloat,
        innerWidth: CGFloat,
        color: NSColor,
        outlineColor: NSColor
    ) {
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        outlineColor.setStroke()
        path.lineWidth = outerWidth
        path.stroke()
        color.setStroke()
        path.lineWidth = innerWidth
        path.stroke()
    }

    private static func ring(
        center: NSPoint,
        radius: CGFloat,
        outerWidth: CGFloat,
        innerWidth: CGFloat,
        outlineColor: NSColor
    ) {
        let rect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let circle = NSBezierPath(ovalIn: rect)
        stroke(circle, outerWidth: outerWidth, innerWidth: innerWidth, color: manifoldColor, outlineColor: outlineColor)
    }
}

/// App-Store-safe fold engine.
///
/// Expanded:
///     [items to hide ...] [3→1 manifold] [MenuFold] [always-visible items ...]
///
/// Collapsed:
///     [MenuFold] [always-visible items ...]
///
/// The visible MenuFold status item always keeps its compact native width.
/// The manifold helper doubles as the fold spacer: expanded it is a 9pt visible
/// control; collapsed the *same* helper becomes a wide transparent spacer that
/// pushes only items to its left off-screen. MenuFold itself never grows, so its
/// network meter / app icon remains present and keeps a stable anchor.
final class StatusBarController: NSObject {
    private let model: MenuFoldModel
    private let popover: NSPopover

    private let statusItem: NSStatusItem
    private let displayView = StatusDisplayView()
    private let mainIconView = PassthroughImageView()
    private let statusHostPlaceholderImage: NSImage = {
        // A non-nil 1x1 transparent image keeps the native NSStatusBarButton
        // host alive without making AppKit style and typeset a whitespace title
        // for every status-item replicant snapshot.
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }()
    private var cachedCompactMenuFoldIcon: NSImage?
    private var mainVisibleWidth: CGFloat = 44

    private var foldControlItem: NSStatusItem?
    private var foldOverlayPanel: FoldOverlayPanel?
    private var foldOverlayView: FoldOverlayView?
    private var foldPlacementMouseMonitor: Any?
    private var foldOverlayGeneration = 0
    private lazy var normalFoldIcon = FoldIconFactory.manifold(width: foldControlWidth, height: 18, bold: false)
    private lazy var pinnedFoldIcon = FoldIconFactory.manifold(width: foldControlWidth, height: 18, bold: true)

    private var screenObserver: NSObjectProtocol?
    private var popoverCloseObserver: NSObjectProtocol?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    private let foldControlWidth: CGFloat = 9
    private(set) var isHiddenZoneExpanded = true
    private var temporaryExpansionPinned = false
    private var startupCollapseWorkItem: DispatchWorkItem?
    private var autoFoldWorkItem: DispatchWorkItem?

    private let logger = Logger(subsystem: "com.bak2ya.MenuFold", category: "statusbar")

    var onWillOpenPopover: (() -> Void)?
    var onHiddenZoneStateChanged: ((Bool) -> Void)?

    init(model: MenuFoldModel, popover: NSPopover) {
        self.model = model
        self.popover = popover
        self.statusItem = NSStatusBar.system.statusItem(withLength: 44)
        super.init()

        configureMainItem()
        updatePresentation()
        restoreMainItemVisibility()
        ensureOrganizerItems()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.applyMainLengthForCurrentState()
            self.layoutMainVisualsSoon()
            self.positionFoldOverlaySoon()
            if self.isHiddenZoneExpanded {
                self.scheduleAutoFoldIfNeeded()
            }
        }

        popoverCloseObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification,
            object: popover,
            queue: .main
        ) { [weak self] _ in
            self?.stopOutsideClickMonitoring()
            self?.clearButtonHighlight()
        }

        if model.settings.hasConfiguredMenuBar {
            DispatchQueue.main.async { [weak self] in
                self?.prepareConfiguredLayoutAfterLaunch()
            }
        } else {
            // A fresh organizer schema opens without hiding anything. The user
            // can place items to the left of the manifold, then fold once to
            // save the new arrangement.
            expandHiddenZone(userInitiated: false, scheduleAutomatic: false)
        }

        DispatchQueue.main.async { [weak self] in
            self?.updatePresentation()
            self?.restoreOrganizerVisibility()
            self?.logGeometry(reason: "next-runloop")
        }
    }

    deinit {
        startupCollapseWorkItem?.cancel()
        autoFoldWorkItem?.cancel()
        stopOutsideClickMonitoring()
        stopFoldPlacementMonitoring()
        foldOverlayPanel?.orderOut(nil)
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let popoverCloseObserver { NotificationCenter.default.removeObserver(popoverCloseObserver) }
        if let foldControlItem { NSStatusBar.system.removeStatusItem(foldControlItem) }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Main MenuFold item

    func updatePresentation() {
        guard let button = statusItem.button else { return }

        button.title = ""
        button.image = statusHostPlaceholderImage
        button.imagePosition = .imageOnly

        switch model.settings.menuBarContentMode {
        case .network:
            let presentation = model.statusPresentation()
            mainVisibleWidth = presentation.width
            displayView.isHidden = false
            mainIconView.isHidden = true
            displayView.applyPresentation(presentation, updateStyle: true)
            button.setAccessibilityValue(presentation.lines.joined(separator: " / "))

        case .appIcon:
            mainVisibleWidth = 22
            displayView.isHidden = true
            mainIconView.isHidden = false
            mainIconView.image = compactMenuFoldIcon()
            button.setAccessibilityValue(model.text("menuBarContent.appIcon"))
        }

        applyMainLengthForCurrentState()
        layoutMainVisualsSoon()
        button.toolTip = "MenuFold"
        button.setAccessibilityLabel("MenuFold")
    }

    /// Fast path used by NetworkSpeedMonitor ticks. Width, font and subview
    /// geometry are configuration state, so a value-only refresh must never
    /// rebuild them.
    func networkPresentationDidChange() {
        guard model.settings.menuBarContentMode == .network,
              let button = statusItem.button else { return }
        let lines = model.statusLines()
        guard displayView.updateLines(lines) else { return }
        button.setAccessibilityValue(lines.joined(separator: " / "))
    }

    func settingsDidChange() {
        updatePresentation()
        configureFoldControlButton()
        if isHiddenZoneExpanded {
            scheduleAutoFoldIfNeeded()
        } else {
            cancelAutoFold()
        }
    }

    func refreshLocalizedUI() {
        configureFoldControlButton()
    }

    private func compactMenuFoldIcon() -> NSImage {
        if let cachedCompactMenuFoldIcon { return cachedCompactMenuFoldIcon }

        // Keep the status icon background-free, but add a high-contrast double
        // outline so the graphite manifold stays legible on both bright and
        // dark/translucent menu bars.
        let target = NSSize(width: 20, height: 20)
        let source: NSImage
        if let url = Bundle.main.url(forResource: "MenuFoldStatusIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            source = image
        } else {
            source = NSApp.applicationIconImage
        }

        func tintedSilhouette(_ color: NSColor, inset: CGFloat) -> NSImage {
            let image = NSImage(size: target)
            image.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            let rect = NSRect(x: inset, y: inset, width: target.width - inset * 2, height: target.height - inset * 2)
            source.draw(in: rect, from: NSRect(origin: .zero, size: source.size), operation: .sourceOver, fraction: 1.0)
            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                context.setBlendMode(.sourceAtop)
                context.setFillColor(color.cgColor)
                context.fill(NSRect(origin: .zero, size: target))
                context.restoreGState()
            }
            image.unlockFocus()
            return image
        }

        let darkMask = tintedSilhouette(NSColor(calibratedWhite: 0.05, alpha: 0.95), inset: 1.6)
        let lightMask = tintedSilhouette(NSColor(calibratedWhite: 0.98, alpha: 0.98), inset: 1.6)
        let result = NSImage(size: target)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let darkOffsets: [NSPoint] = [
            NSPoint(x: -1.35, y: 0), NSPoint(x: 1.35, y: 0),
            NSPoint(x: 0, y: -1.35), NSPoint(x: 0, y: 1.35)
        ]
        for offset in darkOffsets {
            darkMask.draw(at: offset, from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        let lightOffsets: [NSPoint] = [
            NSPoint(x: -0.75, y: 0), NSPoint(x: 0.75, y: 0),
            NSPoint(x: 0, y: -0.75), NSPoint(x: 0, y: 0.75)
        ]
        for offset in lightOffsets {
            lightMask.draw(at: offset, from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        let sourceRect = NSRect(x: 1.6, y: 1.6, width: target.width - 3.2, height: target.height - 3.2)
        source.draw(
            in: sourceRect,
            from: NSRect(origin: .zero, size: source.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        result.unlockFocus()
        result.isTemplate = false
        cachedCompactMenuFoldIcon = result
        return result
    }

    private func configureMainItem() {
        statusItem.autosaveName = MenuBarOrganizerSchema.mainStatusAutosaveName
        statusItem.isVisible = true

        guard let button = statusItem.button else {
            logger.error("MenuFold STATUS: main status button unavailable")
            return
        }

        // Keep a native AppKit status host, but avoid a whitespace title. On
        // macOS 26 that title was repeatedly re-styled/typeset while AppKit
        // generated NSStatusItem replicant snapshots, accounting for a large
        // share of idle CPU. A transparent non-nil image preserves the host
        // identity without introducing visible native content.
        button.title = ""
        button.image = statusHostPlaceholderImage
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(mainItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        displayView.autoresizingMask = [.minXMargin, .height]
        button.addSubview(displayView)

        mainIconView.imageScaling = .scaleProportionallyDown
        mainIconView.autoresizingMask = [.minXMargin, .height]
        mainIconView.isHidden = true
        button.addSubview(mainIconView)
    }

    private func restoreMainItemVisibility() {
        statusItem.isVisible = true
    }

    private func applyMainLengthForCurrentState() {
        // Critical invariant: folding must never change MenuFold's own status
        // item width. Build 26 grew this item by several thousand points, which
        // let AppKit move the whole host off-screen and made the network meter /
        // app icon disappear. Only the fold helper is allowed to provide spacer.
        if abs(statusItem.length - mainVisibleWidth) > 0.5 {
            statusItem.length = mainVisibleWidth
        }
    }

    private func layoutMainVisualsSoon() {
        layoutMainVisuals()
        DispatchQueue.main.async { [weak self] in self?.layoutMainVisuals() }
    }

    private func layoutMainVisuals() {
        guard let button = statusItem.button else { return }
        let bounds = button.bounds
        let visibleRect = NSRect(
            x: max(0, bounds.width - mainVisibleWidth),
            y: 0,
            width: min(mainVisibleWidth, bounds.width),
            height: bounds.height
        )
        if !rectNearlyEqual(displayView.frame, visibleRect) {
            displayView.frame = visibleRect
        }
        if !rectNearlyEqual(mainIconView.frame, visibleRect) {
            mainIconView.frame = visibleRect
        }
    }

    private func clickIsInsideVisibleMainContent(_ sender: NSStatusBarButton) -> Bool {
        guard let event = NSApp.currentEvent else { return true }
        let point = sender.convert(event.locationInWindow, from: nil)
        return point.x >= max(0, sender.bounds.width - mainVisibleWidth - 1)
    }

    // MARK: - Fold helper item

    private func ensureOrganizerItems() {
        if foldControlItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: foldControlWidth)
            item.autosaveName = MenuBarOrganizerSchema.foldControlAutosaveName
            item.isVisible = true
            foldControlItem = item
        }
        ensureFoldOverlay()
        configureFoldControlButton()
    }

    private func ensureFoldOverlay() {
        guard foldOverlayPanel == nil else { return }

        let overlayView = FoldOverlayView(frame: NSRect(x: 0, y: 0, width: foldControlWidth, height: NSStatusBar.system.thickness))
        overlayView.onLeftClick = { [weak self] in
            guard let self else { return }
            self.closePopover()
            self.collapseHiddenZone(markConfigured: true)
        }
        overlayView.onRightClick = { [weak self] in
            self?.toggleTemporaryExpansionPin()
        }

        let panel = FoldOverlayPanel(
            contentRect: overlayView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = overlayView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        foldOverlayView = overlayView
        foldOverlayPanel = panel
    }

    private var expansionIsPinned: Bool {
        model.settings.menuBarFoldMode == .keepExpanded || temporaryExpansionPinned
    }

    private func configureFoldControlButton() {
        guard let item = foldControlItem, let button = item.button else { return }

        item.isVisible = true
        button.title = ""
        button.image = nil
        button.imagePosition = .noImage
        button.target = nil
        button.action = nil
        button.toolTip = nil
        button.setAccessibilityLabel("")

        if isHiddenZoneExpanded {
            // The native NSStatusItem is intentionally invisible. The visible
            // manifold is a tiny non-activating overlay, so Command-drag cannot
            // rearrange the fold control.
            if abs(item.length - foldControlWidth) > 0.5 {
                item.length = foldControlWidth
            }
            ensureFoldOverlay()
            let desiredIcon = expansionIsPinned ? pinnedFoldIcon : normalFoldIcon
            if foldOverlayView?.image !== desiredIcon {
                foldOverlayView?.image = desiredIcon
            }
            let desiredToolTip = model.text(expansionIsPinned ? "menu.foldPinned" : "menu.foldPin")
            if foldOverlayView?.toolTip != desiredToolTip {
                foldOverlayView?.toolTip = desiredToolTip
            }
            if foldOverlayPanel?.isVisible == true {
                positionFoldOverlay()
            } else {
                showFoldOverlaySoon()
            }
            startFoldPlacementMonitoring()
        } else {
            hideFoldOverlay()
            stopFoldPlacementMonitoring()
            // The same invisible helper becomes the wide fold spacer. Keeping
            // the native item alive preserves the user's boundary placement.
            item.length = collapsedSpacerLength()
        }
    }

    private func showFoldOverlaySoon() {
        foldOverlayGeneration += 1
        let generation = foldOverlayGeneration

        // NSStatusItem restores its autosaved window geometry asynchronously at
        // launch. Build 30 only retried through +0.04s, so on slower restores the
        // transparent fold helper could still have no usable window/frame and the
        // visible manifold would remain absent until a later unrelated event.
        //
        // Try once immediately and once on the next run loop. Only if the helper
        // geometry is still unavailable do we continue through a short, bounded
        // retry sequence. There is no persistent organizer polling.
        positionFoldOverlay()
        DispatchQueue.main.async { [weak self] in
            self?.retryFoldOverlayPosition(generation: generation, retryIndex: 0)
        }
    }

    private func retryFoldOverlayPosition(generation: Int, retryIndex: Int) {
        guard isHiddenZoneExpanded, foldOverlayGeneration == generation else { return }
        if positionFoldOverlay() { return }

        let delays: [TimeInterval] = [0.05, 0.15, 0.35, 0.75, 1.50, 3.00]
        guard retryIndex < delays.count else {
            logger.error("MenuFold STATUS: fold overlay geometry unavailable after bounded startup retries")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delays[retryIndex]) { [weak self] in
            self?.retryFoldOverlayPosition(generation: generation, retryIndex: retryIndex + 1)
        }
    }

    private func hideFoldOverlay() {
        // Invalidate any delayed show requested by the previous expanded state.
        // Without this guard, a queued orderFront could resurrect the manifold
        // after the zone had already collapsed, visually inverting the state.
        foldOverlayGeneration += 1
        foldOverlayPanel?.orderOut(nil)
    }

    private func positionFoldOverlaySoon() {
        guard isHiddenZoneExpanded else { return }
        DispatchQueue.main.async { [weak self] in self?.positionFoldOverlay() }
    }

    @discardableResult
    private func positionFoldOverlay() -> Bool {
        guard isHiddenZoneExpanded,
              let panel = foldOverlayPanel,
              let statusWindow = foldControlItem?.button?.window else { return false }

        let statusFrame = statusWindow.frame
        guard statusFrame.width > 0,
              statusFrame.height > 0,
              frameIsOnAnyScreen(statusFrame) else { return false }

        let frame = NSRect(
            x: statusFrame.midX - foldControlWidth / 2,
            y: statusFrame.minY,
            width: foldControlWidth,
            height: statusFrame.height
        )
        if !rectNearlyEqual(panel.frame, frame) {
            panel.setFrame(frame, display: true)
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
        return true
    }

    private func startFoldPlacementMonitoring() {
        guard foldPlacementMouseMonitor == nil else { return }
        // Re-anchor only after the Command-drag gesture used by macOS menu-bar
        // rearrangement, and only when that gesture ends in a menu-bar region.
        // Ordinary mouse-up events elsewhere on the Mac do no MenuFold work.
        foldPlacementMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            guard event.modifierFlags.contains(.command) else { return }
            let releasePoint = NSEvent.mouseLocation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pointIsInMenuBar(releasePoint) else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                    self?.positionFoldOverlay()
                }
            }
        }
    }

    private func stopFoldPlacementMonitoring() {
        if let foldPlacementMouseMonitor {
            NSEvent.removeMonitor(foldPlacementMouseMonitor)
            self.foldPlacementMouseMonitor = nil
        }
    }

    private func toggleTemporaryExpansionPin() {
        closePopover()
        guard isHiddenZoneExpanded else { return }

        if model.settings.menuBarFoldMode == .automatic {
            temporaryExpansionPinned.toggle()
            if temporaryExpansionPinned { cancelAutoFold() } else { scheduleAutoFoldIfNeeded() }
        } else {
            cancelAutoFold()
        }
        configureFoldControlButton()
        onHiddenZoneStateChanged?(true)
    }

    private func restoreOrganizerVisibility() {
        restoreMainItemVisibility()
        foldControlItem?.isVisible = true
        configureFoldControlButton()
    }

    private func prepareConfiguredLayoutAfterLaunch() {
        startupCollapseWorkItem?.cancel()
        expandHiddenZone(userInitiated: false, scheduleAutomatic: false)
        if model.settings.menuBarFoldMode == .keepExpanded {
            configureFoldControlButton()
            return
        }
        verifyAnchorsThenCollapse(attempt: 0)
    }

    private func verifyAnchorsThenCollapse(attempt: Int) {
        restoreOrganizerVisibility()
        updatePresentation()

        if organizerAnchorsAreSafe() {
            logger.info("MenuFold STATUS: organizer anchors verified; restoring saved fold")
            collapseHiddenZone(markConfigured: false)
            return
        }

        guard attempt < 5 else {
            isHiddenZoneExpanded = true
            applyMainLengthForCurrentState()
            configureFoldControlButton()
            logger.error("MenuFold STATUS: organizer anchors not safe after launch; hidden zone left expanded")
            return
        }

        let item = DispatchWorkItem { [weak self] in
            self?.verifyAnchorsThenCollapse(attempt: attempt + 1)
        }
        startupCollapseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private func organizerAnchorsAreSafe() -> Bool {
        guard mainItemIsActuallyOnScreen(),
              itemIsActuallyOnScreen(foldControlItem),
              foldControlIsLeftOfMainItem() else { return false }
        return true
    }

    private func mainItemIsActuallyOnScreen() -> Bool {
        guard statusItem.isVisible,
              mainVisibleWidth > 1,
              let button = statusItem.button,
              !button.isHidden,
              button.alphaValue > 0,
              let window = button.window else { return false }

        switch model.settings.menuBarContentMode {
        case .network:
            guard displayView.superview === button,
                  !displayView.isHidden,
                  displayView.alphaValue > 0,
                  displayView.bounds.width > 1,
                  displayView.bounds.height > 1,
                  displayView.window === window else { return false }
        case .appIcon:
            guard !mainIconView.isHidden, mainIconView.image != nil else { return false }
        }

        return frameIsOnAnyScreen(NSRect(x: window.frame.maxX - mainVisibleWidth, y: window.frame.minY, width: mainVisibleWidth, height: window.frame.height))
    }

    private func itemIsActuallyOnScreen(_ item: NSStatusItem?) -> Bool {
        guard let item,
              item.isVisible,
              item.length > 1,
              let button = item.button,
              !button.isHidden,
              button.alphaValue > 0,
              let window = button.window,
              window.frame.width > 1,
              window.frame.height > 1 else { return false }
        return frameIsOnAnyScreen(window.frame)
    }

    private func rectNearlyEqual(_ lhs: NSRect, _ rhs: NSRect, tolerance: CGFloat = 0.25) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
        abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
        abs(lhs.size.width - rhs.size.width) <= tolerance &&
        abs(lhs.size.height - rhs.size.height) <= tolerance
    }

    private func pointIsInMenuBar(_ point: NSPoint) -> Bool {
        let bandHeight = max(NSStatusBar.system.thickness + 8, 30)
        return NSScreen.screens.contains { screen in
            screen.frame.contains(point) && point.y >= screen.frame.maxY - bandHeight
        }
    }

    private func frameIsOnAnyScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { screen in
            screen.frame.intersects(frame) && frame.midX >= screen.frame.minX && frame.midX <= screen.frame.maxX
        }
    }

    private func foldControlIsLeftOfMainItem() -> Bool {
        guard let control = foldControlItem?.button?.window?.frame,
              let main = statusItem.button?.window?.frame else { return false }
        return control.midX < main.maxX - mainVisibleWidth * 0.5
    }

    // MARK: - Fold state

    private func expandHiddenZone(userInitiated: Bool, scheduleAutomatic: Bool = true) {
        ensureOrganizerItems()
        let anchor = mainVisibleRightEdge()

        isHiddenZoneExpanded = true
        if !userInitiated { temporaryExpansionPinned = false }
        applyMainLengthForCurrentState()
        restoreMainItemVisibility()
        configureFoldControlButton()
        layoutMainVisualsSoon()
        onHiddenZoneStateChanged?(true)

        if scheduleAutomatic { scheduleAutoFoldIfNeeded() } else { cancelAutoFold() }
        verifyMainAnchor(expectedRightEdge: anchor, reason: "expand")
        logGeometry(reason: "expand")
    }

    private func collapseHiddenZone(markConfigured: Bool) {
        ensureOrganizerItems()
        cancelAutoFold()

        guard foldControlIsLeftOfMainItem() else {
            isHiddenZoneExpanded = true
            applyMainLengthForCurrentState()
            configureFoldControlButton()
            logger.error("MenuFold STATUS: collapse skipped because manifold/main ordering is unsafe")
            return
        }

        let anchor = mainVisibleRightEdge()
        temporaryExpansionPinned = false
        isHiddenZoneExpanded = false

        if markConfigured {
            model.settings.markOrganizerLayoutCurrent()
            model.settings.hasConfiguredMenuBar = true
        }

        applyMainLengthForCurrentState()
        configureFoldControlButton()
        restoreMainItemVisibility()
        layoutMainVisualsSoon()
        onHiddenZoneStateChanged?(false)
        verifyMainAnchor(expectedRightEdge: anchor, reason: "collapse")
        logGeometry(reason: "collapse")
    }

    @discardableResult
    func toggleHiddenZoneFromPopover() -> Bool {
        if isHiddenZoneExpanded {
            collapseHiddenZone(markConfigured: true)
        } else {
            requestExpansion(pin: true)
        }
        return isHiddenZoneExpanded
    }

    private func requestExpansion(pin: Bool) {
        guard !isHiddenZoneExpanded else {
            if pin {
                temporaryExpansionPinned = true
                cancelAutoFold()
                configureFoldControlButton()
                onHiddenZoneStateChanged?(true)
            }
            return
        }

        if !model.settings.suppressFoldWarning {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = model.text("menu.foldWarningTitle")
            alert.informativeText = model.text("menu.foldWarningBody")
            alert.icon = FoldIconFactory.preview()
            alert.addButton(withTitle: model.text("action.confirm"))
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = model.text("menu.foldWarningSuppress")

            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            if alert.suppressionButton?.state == .on {
                model.settings.suppressFoldWarning = true
            }
            guard response == .alertFirstButtonReturn else { return }
        }

        temporaryExpansionPinned = pin
        expandHiddenZone(userInitiated: true, scheduleAutomatic: true)
    }

    // MARK: - Automatic fold policy

    private func scheduleAutoFoldIfNeeded() {
        cancelAutoFold()
        guard isHiddenZoneExpanded,
              model.settings.hasConfiguredMenuBar,
              model.settings.menuBarFoldMode == .automatic,
              !temporaryExpansionPinned else {
            configureFoldControlButton()
            return
        }

        let delay = max(1, model.settings.autoFoldDelay)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isHiddenZoneExpanded else { return }
            if self.model.settings.waitWhilePointerInMenuBar && self.pointerIsInMenuBar() {
                self.scheduleAutoFoldIfNeeded()
                return
            }
            self.collapseHiddenZone(markConfigured: false)
        }
        autoFoldWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        configureFoldControlButton()
    }

    private func cancelAutoFold() {
        autoFoldWorkItem?.cancel()
        autoFoldWorkItem = nil
    }

    private func pointerIsInMenuBar() -> Bool {
        let point = NSEvent.mouseLocation
        let menuHeight = max(28, NSStatusBar.system.thickness + 4)
        return NSScreen.screens.contains { screen in
            point.x >= screen.frame.minX && point.x <= screen.frame.maxX &&
            point.y >= screen.frame.maxY - menuHeight && point.y <= screen.frame.maxY
        }
    }

    // MARK: - Interaction

    @objc private func foldControlPressed(_ sender: NSStatusBarButton) {
        // Kept only for compatibility with an already-instantiated native
        // button during an in-process code reload. New builds use the overlay.
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
        if isRightClick {
            toggleTemporaryExpansionPin()
        } else {
            closePopover()
            collapseHiddenZone(markConfigured: true)
        }
        sender.highlight(false)
        sender.state = .off
    }

    @objc private func mainItemClicked(_ sender: NSStatusBarButton) {
        guard clickIsInsideVisibleMainContent(sender) else {
            clearButtonHighlight()
            return
        }

        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
        if isRightClick {
            closePopover()
            if isHiddenZoneExpanded {
                collapseHiddenZone(markConfigured: true)
            } else {
                requestExpansion(pin: false)
            }
        } else {
            togglePopover(relativeTo: sender)
        }
        clearButtonHighlight()
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
            return
        }

        onWillOpenPopover?()
        let anchor = NSRect(
            x: max(0, button.bounds.width - mainVisibleWidth),
            y: 0,
            width: min(mainVisibleWidth, button.bounds.width),
            height: button.bounds.height
        )
        popover.show(relativeTo: anchor, of: button, preferredEdge: .minY)
        startOutsideClickMonitoring()
        clearButtonHighlight()
    }

    private func closePopover() {
        if popover.isShown { popover.performClose(nil) }
        stopOutsideClickMonitoring()
        clearButtonHighlight()
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.closePopover() }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.popover.isShown else { return event }

            if let popoverWindow = self.popover.contentViewController?.view.window,
               event.window === popoverWindow {
                return event
            }
            if let statusWindow = self.statusItem.button?.window,
               event.window === statusWindow {
                return event
            }

            DispatchQueue.main.async { [weak self] in self?.closePopover() }
            return event
        }
    }

    private func stopOutsideClickMonitoring() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }

    private func clearButtonHighlight() {
        guard let button = statusItem.button else { return }
        button.highlight(false)
        button.state = .off
        DispatchQueue.main.async {
            button.highlight(false)
            button.state = .off
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            button.highlight(false)
            button.state = .off
        }
    }

    // MARK: - Geometry / diagnostics

    private func collapsedSpacerLength() -> CGFloat {
        let widest = NSScreen.screens.map(\.frame.width).max() ?? 1440
        return max(500, min(widest * 2, 10_000))
    }

    private func mainVisibleRightEdge() -> CGFloat? {
        statusItem.button?.window?.frame.maxX
    }

    private func verifyMainAnchor(expectedRightEdge: CGFloat?, reason: String) {
        guard let expectedRightEdge else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let actual = self.mainVisibleRightEdge() else { return }
            let delta = abs(actual - expectedRightEdge)
            if delta > 1.5 {
                self.logger.error("MenuFold STATUS: visible main anchor moved during \(reason, privacy: .public) by \(delta, privacy: .public)pt")
            }
            self.layoutMainVisuals()
        }
    }

    private func logGeometry(reason: String) {
        let mainFrame = statusItem.button?.window?.frame.debugDescription ?? "nil"
        logger.info("MenuFold STATUS [\(reason, privacy: .public)] main visible=\(self.statusItem.isVisible, privacy: .public) length=\(self.statusItem.length, privacy: .public) visibleWidth=\(self.mainVisibleWidth, privacy: .public) window=\(mainFrame, privacy: .public)")

        if let foldControlItem {
            let frame = foldControlItem.button?.window?.frame.debugDescription ?? "nil"
            logger.info("MenuFold STATUS [\(reason, privacy: .public)] manifold length=\(foldControlItem.length, privacy: .public) pinned=\(self.expansionIsPinned, privacy: .public) window=\(frame, privacy: .public)")
        }
    }
}
