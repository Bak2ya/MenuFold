import Foundation
import AppKit
import UniformTypeIdentifiers

enum QuickLaunchKind: String, Codable {
    case app
    case fileOrFolder
    case web
    case systemSetting
}

enum QuickLaunchIconColorPreset: String, CaseIterable, Codable {
    case `default`
    case red
    case orange
    case yellow
    case green
    case blue
    case sky
    case purple
    case pink
    case burgundy
    case gray

    var localizationKey: String {
        switch self {
        case .default: return "quick.color.default"
        case .red: return "quick.color.red"
        case .orange: return "quick.color.orange"
        case .yellow: return "quick.color.yellow"
        case .green: return "quick.color.green"
        case .blue: return "quick.color.blue"
        case .sky: return "quick.color.sky"
        case .purple: return "quick.color.purple"
        case .pink: return "quick.color.pink"
        case .burgundy: return "quick.color.burgundy"
        case .gray: return "quick.color.gray"
        }
    }

    /// nil means keep the native template foreground color for the current
    /// light/dark appearance. App icons intentionally ignore these presets.
    var tintColor: NSColor? {
        switch self {
        case .default: return nil
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .sky: return NSColor(calibratedRed: 0.28, green: 0.68, blue: 0.96, alpha: 1.0)
        case .purple: return .systemPurple
        case .pink: return NSColor(calibratedRed: 0.96, green: 0.31, blue: 0.62, alpha: 1.0)
        case .burgundy: return NSColor(calibratedRed: 0.50, green: 0.10, blue: 0.23, alpha: 1.0)
        case .gray: return .systemGray
        }
    }
}

struct QuickLaunchItem: Codable, Equatable {
    var id: UUID
    var name: String
    var kind: QuickLaunchKind
    var target: String
    var bookmarkData: Data?
    // Optional for backward-compatible decoding of Quick Launch entries saved
    // by Build 38 and earlier. nil is the native/default template color.
    var iconColor: QuickLaunchIconColorPreset?

    init(
        id: UUID = UUID(),
        name: String,
        kind: QuickLaunchKind,
        target: String,
        bookmarkData: Data? = nil,
        iconColor: QuickLaunchIconColorPreset? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.target = target
        self.bookmarkData = bookmarkData
        self.iconColor = iconColor
    }
}

struct SystemSettingShortcut {
    let id: String
    let localizationKey: String
    let symbol: String
    let url: String

    static let presets: [SystemSettingShortcut] = [
        .init(id: "wifi", localizationKey: "setting.wifi", symbol: "wifi", url: "x-apple.systempreferences:com.apple.wifi-settings-extension"),
        .init(id: "bluetooth", localizationKey: "setting.bluetooth", symbol: "bluetooth", url: "x-apple.systempreferences:com.apple.BluetoothSettings"),
        .init(id: "display", localizationKey: "setting.display", symbol: "display", url: "x-apple.systempreferences:com.apple.Displays-Settings.extension"),
        .init(id: "battery", localizationKey: "setting.battery", symbol: "battery.100", url: "x-apple.systempreferences:com.apple.Battery-Settings.extension"),
        .init(id: "keyboard", localizationKey: "setting.keyboard", symbol: "keyboard", url: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"),
        .init(id: "mouse", localizationKey: "setting.mouse", symbol: "computermouse", url: "x-apple.systempreferences:com.apple.Mouse-Settings.extension"),
        .init(id: "trackpad", localizationKey: "setting.trackpad", symbol: "rectangle.and.hand.point.up.left", url: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension"),
        .init(id: "privacy", localizationKey: "setting.privacy", symbol: "lock.shield", url: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"),
        .init(id: "accessibility", localizationKey: "setting.accessibility", symbol: "accessibility", url: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension")
    ]
}

final class QuickLaunchStore {
    private(set) var items: [QuickLaunchItem] = []
    var onChange: (() -> Void)?

    private let defaultsKey = "quickLaunchItems"

    // Keep at most one tiny raster per Quick Launch item. If a larger size is
    // requested later, replace the cached raster instead of accumulating one
    // image per size. This preserves sharp 32pt icons without growing memory.
    private var iconCache: [UUID: (pointSize: CGFloat, image: NSImage)] = [:]

    init() {
        load()
    }

    func addApplication(title: String) {
        let url: URL? = autoreleasepool {
            let panel = NSOpenPanel()
            panel.title = title
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            return panel.runModal() == .OK ? panel.url : nil
        }

        guard let url else { return }
        addFileURL(url, kind: .app)
    }

    func addFileOrFolder(title: String) {
        let url: URL? = autoreleasepool {
            let panel = NSOpenPanel()
            panel.title = title
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = true
            panel.canChooseFiles = true
            return panel.runModal() == .OK ? panel.url : nil
        }

        guard let url else { return }
        addFileURL(url, kind: .fileOrFolder)
    }

    func addWeb(name: String, urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard URL(string: normalized) != nil else { return }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = cleanName.isEmpty ? normalized : cleanName
        items.append(.init(name: displayName, kind: .web, target: normalized))
        changed()
    }

    func addSystemSetting(_ shortcut: SystemSettingShortcut, displayName: String) {
        items.append(.init(name: displayName, kind: .systemSetting, target: shortcut.url))
        changed()
    }

    func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        let removedID = items[index].id
        items.remove(at: index)
        iconCache.removeValue(forKey: removedID)
        changed()
    }

    func moveUp(at index: Int) {
        guard items.indices.contains(index), index > 0 else { return }
        items.swapAt(index, index - 1)
        changed()
    }

    func moveDown(at index: Int) {
        guard items.indices.contains(index), index < items.count - 1 else { return }
        items.swapAt(index, index + 1)
        changed()
    }

    func effectiveIconColor(for item: QuickLaunchItem) -> QuickLaunchIconColorPreset {
        item.kind == .app ? .default : (item.iconColor ?? .default)
    }

    func setIconColor(_ preset: QuickLaunchIconColorPreset, forID id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].kind != .app else { return }
        // Store default as nil so older entries and newly reset entries remain
        // compact and the native light/dark template color stays authoritative.
        items[index].iconColor = preset == .default ? nil : preset
        changed()
    }

    func open(_ item: QuickLaunchItem) {
        switch item.kind {
        case .app, .fileOrFolder:
            if let bookmarkData = item.bookmarkData {
                var stale = false
                if let url = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                ) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    NSWorkspace.shared.open(url)
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    return
                }
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: item.target))

        case .web, .systemSetting:
            guard let url = URL(string: item.target) else { return }
            NSWorkspace.shared.open(url)
        }
    }

    /// Returns one small cached icon per Quick Launch item. The cache keeps the
    /// largest requested raster for that item and lets smaller controls scale it
    /// down. App bundle icons are read directly from the bundle when possible.
    func icon(for item: QuickLaunchItem, pointSize: CGFloat) -> NSImage {
        let requested = max(18, pointSize)
        if let cached = iconCache[item.id], cached.pointSize >= requested {
            return cached.image
        }

        let cachePointSize = requested
        let image: NSImage
        switch item.kind {
        case .app:
            image = withResolvedSecurityScopedURL(for: item) { url in
                if let source = appBundleIcon(at: url) {
                    return rasterizedImage(source, pointSize: cachePointSize)
                }

                // In the sandbox, reading an app bundle's icon/metadata needs
                // the security scope obtained when the user selected the app.
                let workspaceIcon = NSWorkspace.shared.icon(forFile: url.path)
                if workspaceIcon.representations.isEmpty {
                    return systemSymbolImage(
                        candidates: ["app", "square.grid.2x2"],
                        accessibilityDescription: item.name,
                        pointSize: cachePointSize
                    )
                }
                return rasterizedImage(workspaceIcon, pointSize: cachePointSize)
            }

        case .fileOrFolder:
            image = withResolvedSecurityScopedURL(for: item) { url in
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                return systemSymbolImage(
                    candidates: isDirectory.boolValue ? ["folder", "folder.fill"] : ["doc", "doc.fill"],
                    accessibilityDescription: item.name,
                    pointSize: cachePointSize
                )
            }

        case .web:
            image = systemSymbolImage(
                candidates: ["globe", "network"],
                accessibilityDescription: item.name,
                pointSize: cachePointSize
            )

        case .systemSetting:
            let shortcut = SystemSettingShortcut.presets.first { $0.url == item.target }
            let primary = shortcut?.symbol ?? "gearshape"
            let secondary: [String]
            switch shortcut?.id {
            case "bluetooth": secondary = ["antenna.radiowaves.left.and.right", "dot.radiowaves.left.and.right"]
            case "wifi": secondary = ["network", "antenna.radiowaves.left.and.right"]
            case "display": secondary = ["rectangle.on.rectangle", "rectangle"]
            case "battery": secondary = ["bolt", "powerplug"]
            case "keyboard": secondary = ["rectangle.and.pencil.and.ellipsis", "textformat"]
            case "mouse": secondary = ["cursorarrow", "hand.point.up.left"]
            case "trackpad": secondary = ["hand.point.up.left", "cursorarrow"]
            case "privacy": secondary = ["lock", "shield"]
            case "accessibility": secondary = ["figure.stand", "person"]
            default: secondary = []
            }
            image = systemSymbolImage(
                candidates: [primary] + secondary + ["gearshape"],
                accessibilityDescription: item.name,
                pointSize: cachePointSize
            )
        }

        iconCache[item.id] = (cachePointSize, image)
        return image
    }

    private func systemSymbolImage(
        candidates: [String],
        accessibilityDescription: String,
        pointSize: CGFloat
    ) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        for symbol in candidates {
            if let base = NSImage(
                systemSymbolName: symbol,
                accessibilityDescription: accessibilityDescription
            ) {
                let configured = base.withSymbolConfiguration(configuration) ?? base
                return rasterizedImage(
                    configured,
                    pointSize: pointSize,
                    preserveAspectRatio: true,
                    template: true
                )
            }
        }

        // `gearshape` is available on every macOS version supported by
        // MenuFold. Keep the application icon as a final non-empty fallback in
        // case a future system changes symbol availability unexpectedly.
        if let gear = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: accessibilityDescription
        ) {
            let configured = gear.withSymbolConfiguration(configuration) ?? gear
            return rasterizedImage(
                configured,
                pointSize: pointSize,
                preserveAspectRatio: true,
                template: true
            )
        }

        if let applicationIcon = NSApp.applicationIconImage {
            return rasterizedImage(applicationIcon, pointSize: pointSize)
        }

        return NSImage(size: NSSize(width: pointSize, height: pointSize))
    }

    func purgeIconCache() {
        iconCache.removeAll(keepingCapacity: false)
    }

    private func appBundleIcon(at appURL: URL) -> NSImage? {
        guard let bundle = Bundle(url: appURL) else { return nil }

        let iconName = (bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String)
        guard var iconName, !iconName.isEmpty else { return nil }

        if URL(fileURLWithPath: iconName).pathExtension.isEmpty {
            iconName += ".icns"
        }

        if let resourceURL = bundle.resourceURL?.appendingPathComponent(iconName),
           let image = NSImage(contentsOf: resourceURL) {
            return image
        }

        let base = URL(fileURLWithPath: iconName).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: iconName).pathExtension
        if let path = bundle.path(forResource: base, ofType: ext.isEmpty ? "icns" : ext),
           let image = NSImage(contentsOfFile: path) {
            return image
        }
        return nil
    }

    private func withResolvedSecurityScopedURL<T>(
        for item: QuickLaunchItem,
        _ body: (URL) -> T
    ) -> T {
        if let bookmarkData = item.bookmarkData {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                }
                return body(url)
            }
        }

        // Unsandboxed legacy entries can still use their stored path. In an
        // App Sandbox build, an entry whose bookmark can no longer resolve may
        // need to be removed and selected again by the user.
        return body(URL(fileURLWithPath: item.target))
    }

    private func rasterizedImage(
        _ source: NSImage,
        pointSize: CGFloat,
        preserveAspectRatio: Bool = false,
        template: Bool = false
    ) -> NSImage {
        // Two physical pixels per point is enough for a crisp menu-bar/settings
        // icon on Retina displays while keeping each cached icon tiny.
        let pixelSize = max(1, Int(ceil(pointSize * 2.0)))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            source.size = NSSize(width: pointSize, height: pointSize)
            source.isTemplate = template
            return source
        }

        rep.size = NSSize(width: pointSize, height: pointSize)
        let targetRect: NSRect
        if preserveAspectRatio, source.size.width > 0, source.size.height > 0 {
            let scale = min(pointSize / source.size.width, pointSize / source.size.height)
            let drawSize = NSSize(width: source.size.width * scale, height: source.size.height * scale)
            targetRect = NSRect(
                x: (pointSize - drawSize.width) / 2,
                y: (pointSize - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            )
        } else {
            targetRect = NSRect(x: 0, y: 0, width: pointSize, height: pointSize)
        }

        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            source.draw(
                in: targetRect,
                from: .zero,
                operation: .copy,
                fraction: 1.0,
                respectFlipped: false,
                hints: nil
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: NSSize(width: pointSize, height: pointSize))
        result.addRepresentation(rep)
        result.isTemplate = template
        return result
    }

    private func addFileURL(_ url: URL, kind: QuickLaunchKind) {
        let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let name = kind == .app
            ? FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            : FileManager.default.displayName(atPath: url.path)

        items.append(.init(name: name, kind: kind, target: url.path, bookmarkData: bookmark))
        changed()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([QuickLaunchItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    private func changed() {
        save()
        onChange?()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
