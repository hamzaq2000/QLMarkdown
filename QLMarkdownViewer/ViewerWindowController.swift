//
//  ViewerWindowController.swift
//  QLMarkdown Viewer
//

import Cocoa
import WebKit
import OSLog

class ViewerWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private static let zoomKey = "pageZoom"
    private static let zoomSteps: [CGFloat] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]
    /// Emitted after the document styles, adapting the Quick Look layout to a document window:
    /// - no border around the content (the bundled style frames it in wide windows);
    /// - the vertical margins grow with the side margins once the window is wider than the
    ///   column, capped by the window height so short windows stay compact; the bottom one is
    ///   larger, as in book page layouts, so it does not read as cramped.
    private static let viewerStyle = """
        <style type='text/css'>
        article {
            border: none;
            --viewer-margin-top: clamp(32px, min(32px + (100vw - var(--content-max-width)) / 12, 8vh), 96px);
            padding-top: var(--viewer-margin-top);
            padding-bottom: calc(var(--viewer-margin-top) * 1.9);
        }
        </style>
        """

    private let webView: WKWebView
    private let container: FindBarContainerView
    private let textFinder = NSTextFinder()

    private var html = ""
    private var pendingScroll: Double = 0
    private var fileSource: DispatchSourceFileSystemObject?
    private var pendingReload: DispatchWorkItem?
    private var settingsObserver: NSObjectProtocol?

    private var markdownDocument: MarkdownDocument? {
        return document as? MarkdownDocument
    }

    init(document: MarkdownDocument) {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.pageZoom = UserDefaults.standard.object(forKey: Self.zoomKey) as? CGFloat ?? 1
        Self.disablePlatformFindUI(webView)
        container = FindBarContainerView(contentView: webView)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.minSize = NSSize(width: 320, height: 240)
        window.center()
        super.init(window: window)

        window.delegate = self
        webView.navigationDelegate = self
        textFinder.client = webView
        textFinder.findBarContainer = container
        textFinder.isIncrementalSearchingEnabled = true

        settingsObserver = NotificationCenter.default.addObserver(forName: SharedSettings.didReload, object: nil, queue: .main) { [weak self] _ in
            self?.reload(nil)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        fileSource?.cancel()
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    /// With the platform find UI WebKit does not search when driven by an `NSTextFinder` of the
    /// host app: turn it off so the find bar works (matches are shown by WebKit's own indicator).
    private static func disablePlatformFindUI(_ webView: WKWebView) {
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        let selector = NSSelectorFromString("_setUsePlatformFindUI:")
        guard webView.responds(to: selector) else {
            return
        }
        unsafeBitCast(webView.method(for: selector), to: Setter.self)(webView, selector, false)
    }

    /// Same size used for the Quick Look window, reduced to fit the screen.
    private static var initialContentSize: NSSize {
        let size = Settings.shared.qlWindowSize
        guard let available = NSScreen.main?.visibleFrame.size else {
            return size
        }
        return NSSize(width: min(size.width, available.width * 0.9), height: min(size.height, available.height * 0.9))
    }

    override var document: AnyObject? {
        didSet {
            if document != nil {
                render()
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        fileSource?.cancel()
        fileSource = nil
        pendingReload?.cancel()
    }

    // MARK: - Rendering

    private func render() {
        guard let url = markdownDocument?.fileURL else {
            return
        }
        let markdownUrl = Settings.getMarkdownFile(from: url)
        let settings = Settings.shared
        let body: String
        do {
            body = try settings.render(file: markdownUrl, baseDir: markdownUrl.deletingLastPathComponent().path)
        } catch {
            os_log("Unable to render %{public}@: %{public}@", log: OSLog.rendering, type: .error, markdownUrl.path, error.localizedDescription)
            body = "<p>Unable to render the file: \(error.localizedDescription)</p>"
        }
        html = settings.getCompleteHTML(title: url.lastPathComponent, body: body, header: Self.viewerStyle)
        webView.loadHTMLString(html, baseURL: markdownUrl.deletingLastPathComponent())
        watch(file: markdownUrl)
    }

    @objc func reload(_ sender: Any?) {
        webView.evaluateJavaScript("window.scrollY") { [weak self] value, _ in
            guard let self else {
                return
            }
            self.pendingScroll = value as? Double ?? 0
            self.render()
        }
    }

    // MARK: - File monitoring

    private func watch(file url: URL) {
        fileSource?.cancel()
        fileSource = nil

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .attrib], queue: .main)
        source.setEventHandler { [weak self] in
            // Editors usually save by writing a temp file and renaming it over the original,
            // which replaces the watched inode: drop the source and let the reload re-arm it.
            self?.fileSource?.cancel()
            self?.fileSource = nil
            self?.scheduleReload()
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        fileSource = source
        source.resume()
    }

    /// Debounced and retried, so the gap of an atomic save is not mistaken for a deletion.
    private func scheduleReload(retriesLeft: Int = 8) {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let url = self.markdownDocument?.markdownUrl else {
                return
            }
            if FileManager.default.fileExists(atPath: url.path) {
                self.reload(nil)
            } else if retriesLeft > 0 {
                self.scheduleReload(retriesLeft: retriesLeft - 1)
            }
        }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    // MARK: - Actions

    @objc func showInFinder(_ sender: Any?) {
        if let url = markdownDocument?.fileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc func exportHTML(_ sender: Any?) {
        guard let window else {
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = ((markdownDocument?.fileURL?.lastPathComponent ?? "document") as NSString).deletingPathExtension + ".html"
        panel.beginSheetModal(for: window) { [html] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            do {
                try html.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc func printDocument(_ sender: Any?) {
        guard let window else {
            return
        }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        let operation = webView.printOperation(with: info)
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    @objc func actualSize(_ sender: Any?) {
        setZoom(1)
    }

    @objc func zoomIn(_ sender: Any?) {
        setZoom(Self.zoomSteps.first(where: { $0 > webView.pageZoom + 0.001 }) ?? webView.pageZoom)
    }

    @objc func zoomOut(_ sender: Any?) {
        setZoom(Self.zoomSteps.last(where: { $0 < webView.pageZoom - 0.001 }) ?? webView.pageZoom)
    }

    private func setZoom(_ zoom: CGFloat) {
        webView.pageZoom = zoom
        UserDefaults.standard.set(zoom, forKey: Self.zoomKey)
    }

    @objc func performFindAction(_ sender: Any?) {
        if let item = sender as? NSValidatedUserInterfaceItem, let action = NSTextFinder.Action(rawValue: item.tag) {
            textFinder.performAction(action)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(performFindAction(_:)):
            guard let action = NSTextFinder.Action(rawValue: menuItem.tag) else {
                return false
            }
            return textFinder.validateAction(action)
        case #selector(actualSize(_:)):
            return webView.pageZoom != 1
        case #selector(zoomIn(_:)):
            return webView.pageZoom < Self.zoomSteps.last!
        case #selector(zoomOut(_:)):
            return webView.pageZoom > Self.zoomSteps.first!
        default:
            return true
        }
    }
}

// MARK: - WKNavigationDelegate
extension ViewerWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if pendingScroll > 0 {
            // The layout may still grow (images, fonts, diagrams): re-apply until it settles.
            webView.evaluateJavaScript("""
                (function(y) {
                    const go = () => window.scrollTo({ top: y, behavior: 'instant' });
                    go();
                    window.addEventListener('load', go, { once: true });
                    document.fonts.ready.then(go);
                    [50, 200, 500, 1000].forEach(t => setTimeout(go, t));
                })(\(pendingScroll));
                """)
            pendingScroll = 0
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if url.isFileURL {
            // Anchors within the document resolve against the base url (the document folder).
            if url.fragment != nil, url.path == markdownDocument?.markdownUrl?.deletingLastPathComponent().path {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            openLocalFile(url)
            return
        }

        // The document is untrusted, and WebKit reports a script-synthesized click as
        // .linkActivated too: hand only allowlisted schemes straight to the system.
        if Settings.isExternalSchemeAllowed(url) || Self.confirmOpen(url) {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    /// Opens linked markdown files in the viewer, anything else (after confirmation) in its default app.
    private func openLocalFile(_ url: URL) {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        let target = components?.url ?? url
        let controller = NSDocumentController.shared
        if let type = try? controller.typeForContents(of: target), controller.documentClass(forType: type) != nil {
            controller.openDocument(withContentsOf: target, display: true) { _, _, error in
                if let error {
                    NSAlert(error: error).runModal()
                }
            }
        } else if FileManager.default.fileExists(atPath: target.path), Self.confirmOpen(target) {
            NSWorkspace.shared.open(target)
        }
    }

    private static func confirmOpen(_ url: URL) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Open this link in another application?", comment: "")
        alert.informativeText = url.isFileURL ? url.path : url.absoluteString
        alert.addButton(withTitle: NSLocalizedString("Open", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        return alert.runModal() == .alertFirstButtonReturn
    }
}

// MARK: - Find bar container
/// Hosts the web view and the find bar provided by `NSTextFinder`.
class FindBarContainerView: NSView, NSTextFinderBarContainer {
    let contentView: NSView

    init(contentView: NSView) {
        self.contentView = contentView
        super.init(frame: .zero)
        addSubview(contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        return true
    }

    var findBarView: NSView? {
        didSet {
            if oldValue !== findBarView {
                oldValue?.removeFromSuperview()
            }
            updateFindBar()
        }
    }

    var isFindBarVisible = false {
        didSet {
            updateFindBar()
        }
    }

    /// The find bar is in the view hierarchy only while visible.
    private func updateFindBar() {
        if isFindBarVisible, let findBarView {
            if findBarView.superview !== self {
                addSubview(findBarView)
            }
        } else if let findBarView, findBarView.superview != nil {
            findBarView.removeFromSuperview()
            window?.makeFirstResponder(contentView)
        }
        needsLayout = true
    }

    func findBarViewDidChangeHeight() {
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var top: CGFloat = 0
        if isFindBarVisible, let findBarView {
            top = findBarView.frame.height
            findBarView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: top)
        }
        contentView.frame = NSRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
    }
}
