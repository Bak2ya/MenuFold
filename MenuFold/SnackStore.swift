import AppKit
import Foundation
import StoreKit


/// Loads bundled artwork without depending on whether Xcode flattens a resource
/// into Contents/Resources or preserves its source subdirectory. The recursive
/// fallback runs only when a settings/info image is requested; there is no
/// polling or process-lifetime image cache.
enum BundledImageLoader {
    static func image(named name: String, withExtension ext: String, subdirectory: String? = nil) -> NSImage? {
        var candidates: [URL] = []

        if let subdirectory,
           let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            candidates.append(url)
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            candidates.append(url)
        }

        if let resourceURL = Bundle.main.resourceURL {
            let wanted = "\(name).\(ext)"
            if let enumerator = FileManager.default.enumerator(
                at: resourceURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                for case let url as URL in enumerator where url.lastPathComponent == wanted {
                    candidates.append(url)
                    break
                }
            }
        }

        var seen = Set<String>()
        for url in candidates where seen.insert(url.path).inserted {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }
}

enum SnackPurchaseOutcome {
    case purchased
    case cancelled
    case pending
    case failed
}

/// Optional, consumable "Maneem snack" tip. It never unlocks features.
///
/// Build 45 ships as a completely free App Store 1.0.0 release. The StoreKit
/// implementation and final App Store Connect product ID are intentionally kept
/// ready in source, but `purchasesEnabled` remains false until the developer can
/// legally enable paid activity. With the flag false, MenuFold does not query
/// StoreKit products and does not start a transaction listener.
final class SnackStore {
    static let productID = "com.bak2ya.MenuFold.catsnack"
    static let purchasesEnabled = false

    private var cachedProduct: Product?
    private var transactionUpdatesTask: Task<Void, Never>?

    init() {
        guard Self.purchasesEnabled else { return }

        // Event-driven StoreKit stream only; this is not polling. A pending
        // purchase can complete later, including on a subsequent app launch.
        transactionUpdatesTask = Task {
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                guard case .verified(let transaction) = result,
                      transaction.productID == Self.productID else { continue }
                await transaction.finish()
            }
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func loadProduct() async -> Product? {
        guard Self.purchasesEnabled else { return nil }
        if let cachedProduct { return cachedProduct }
        do {
            let products = try await Product.products(for: [Self.productID])
            let product = products.first(where: { $0.id == Self.productID })
            cachedProduct = product
            return product
        } catch {
            return nil
        }
    }

    func purchase() async -> SnackPurchaseOutcome {
        guard Self.purchasesEnabled else { return .failed }
        guard let product = await loadProduct() else { return .failed }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    return .purchased
                case .unverified:
                    return .failed
                }
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed
            }
        } catch {
            return .failed
        }
    }
}

/// Settings-owned sheet used for the Maneem easter egg / optional tip flow.
/// Only one photo is decoded per presentation and the whole controller is
/// released when the sheet closes so this feature has no permanent image cache.
final class SnackPurchaseWindowController: NSWindowController {
    private let model: MenuFoldModel
    private let photoName: String
    private let onDismiss: () -> Void

    private let mainText = NSTextField(wrappingLabelWithString: "")
    private let noteText = NSTextField(wrappingLabelWithString: "")
    private let businessPendingText = NSTextField(wrappingLabelWithString: "")
    private let purchaseButton = NSButton()
    private let closeButton = NSButton()
    private let comingLaterButton = NSButton()
    private var purchaseInProgress = false

    init(model: MenuFoldModel, photoName: String, onDismiss: @escaping () -> Void) {
        self.model = model
        self.photoName = photoName
        self.onDismiss = onDismiss

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 585),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = model.text("info.snack")
        window.isReleasedWhenClosed = false
        window.titleVisibility = .visible
        window.animationBehavior = .documentWindow

        super.init(window: window)
        buildContent()

        // v1.0.0 is intentionally free-only. No StoreKit product request is
        // made until the feature flag is explicitly enabled in a later build.
        if SnackStore.purchasesEnabled {
            loadStoreProduct()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(asSheetOf parentWindow: NSWindow) {
        guard let window else { return }
        parentWindow.beginSheet(window)
    }

    func dismiss() {
        guard let window else {
            onDismiss()
            return
        }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.close()
        }
        onDismiss()
    }

    private func buildContent() {
        guard let window else { return }

        let root = NSView()
        window.contentView = root

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 10
        imageView.layer?.masksToBounds = true
        let snackPhoto = NSImage(named: NSImage.Name(photoName))
        imageView.image = snackPhoto

        mainText.stringValue = model.text("snack.easterEgg")
        mainText.alignment = .center
        mainText.font = .systemFont(ofSize: 13, weight: .semibold)
        mainText.maximumNumberOfLines = 0
        mainText.translatesAutoresizingMaskIntoConstraints = false

        noteText.stringValue = model.text("snack.noPhotoUnlock")
        noteText.alignment = .center
        noteText.font = .systemFont(ofSize: 11.5)
        noteText.textColor = .secondaryLabelColor
        noteText.maximumNumberOfLines = 0
        noteText.translatesAutoresizingMaskIntoConstraints = false

        businessPendingText.stringValue = model.text("snack.businessPending")
        businessPendingText.alignment = .center
        businessPendingText.font = .systemFont(ofSize: 11.5)
        businessPendingText.textColor = .secondaryLabelColor
        businessPendingText.maximumNumberOfLines = 0
        businessPendingText.translatesAutoresizingMaskIntoConstraints = false

        closeButton.title = model.text("snack.close")
        closeButton.bezelStyle = .rounded
        closeButton.target = self
        closeButton.action = #selector(closePressed)

        purchaseButton.title = model.text("snack.loadingPrice")
        purchaseButton.bezelStyle = .rounded
        purchaseButton.keyEquivalent = "\r"
        purchaseButton.target = self
        purchaseButton.action = #selector(purchasePressed)
        purchaseButton.isEnabled = false

        comingLaterButton.title = model.text("snack.comingLaterButton")
        comingLaterButton.bezelStyle = .rounded
        comingLaterButton.keyEquivalent = "\r"
        comingLaterButton.target = self
        comingLaterButton.action = #selector(closePressed)

        var arrangedViews: [NSView] = []
        if snackPhoto != nil { arrangedViews.append(imageView) }
        arrangedViews.append(contentsOf: [mainText, noteText])

        if SnackStore.purchasesEnabled {
            let buttons = NSStackView(views: [closeButton, purchaseButton])
            buttons.orientation = .horizontal
            buttons.alignment = .centerY
            buttons.spacing = 10
            buttons.distribution = .fillProportionally
            buttons.translatesAutoresizingMaskIntoConstraints = false
            arrangedViews.append(buttons)
        } else {
            // Free v1.0 keeps the existing two-button layout intact. Only the
            // purchase button is replaced by a non-purchasing placeholder; the
            // business-status note is added below the buttons.
            let buttons = NSStackView(views: [closeButton, comingLaterButton])
            buttons.orientation = .horizontal
            buttons.alignment = .centerY
            buttons.spacing = 10
            buttons.distribution = .fillProportionally
            buttons.translatesAutoresizingMaskIntoConstraints = false
            arrangedViews.append(buttons)
            arrangedViews.append(businessPendingText)
        }

        let stack = NSStackView(views: arrangedViews)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        var constraints = [
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22),
            mainText.widthAnchor.constraint(equalToConstant: 360),
            noteText.widthAnchor.constraint(equalToConstant: 360),
            businessPendingText.widthAnchor.constraint(equalToConstant: 360)
        ]
        if snackPhoto != nil {
            constraints.append(imageView.widthAnchor.constraint(equalToConstant: 348))
            constraints.append(imageView.heightAnchor.constraint(equalToConstant: 330))
        }
        NSLayoutConstraint.activate(constraints)
    }

    private func loadStoreProduct() {
        guard SnackStore.purchasesEnabled else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let product = await self.model.snackStore.loadProduct() else {
                self.purchaseButton.title = self.model.text("snack.priceUnavailable")
                self.purchaseButton.isEnabled = false
                return
            }
            self.purchaseButton.title = String(
                format: self.model.text("snack.buyFormat"),
                product.displayPrice
            )
            self.purchaseButton.isEnabled = true
        }
    }

    @objc private func closePressed() {
        dismiss()
    }

    @objc private func purchasePressed() {
        guard SnackStore.purchasesEnabled else { return }
        guard !purchaseInProgress else { return }
        purchaseInProgress = true
        closeButton.isEnabled = false
        purchaseButton.isEnabled = false

        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await self.model.snackStore.purchase()
            self.purchaseInProgress = false
            self.closeButton.isEnabled = true

            switch outcome {
            case .purchased:
                self.mainText.stringValue = self.model.text("snack.thanks")
                self.mainText.font = .systemFont(ofSize: 14, weight: .semibold)
                self.noteText.isHidden = true
                self.purchaseButton.isHidden = true
            case .cancelled:
                self.purchaseButton.isEnabled = true
            case .pending:
                self.purchaseButton.title = self.model.text("snack.pendingButton")
                self.purchaseButton.isEnabled = false
                self.showAlert(
                    title: self.model.text("snack.pendingTitle"),
                    message: self.model.text("snack.pendingMessage")
                )
            case .failed:
                self.purchaseButton.isEnabled = true
                self.showAlert(
                    title: self.model.text("snack.errorTitle"),
                    message: self.model.text("snack.errorMessage")
                )
            }
        }
    }

    private func showAlert(title: String, message: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: model.text("snack.ok"))
        alert.beginSheetModal(for: window)
    }
}
