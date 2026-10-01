//
//  AppDelegate.swift
//  QLMarkdown Viewer
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    static let qlMarkdownBundleIdentifier = "org.sbarex.QLMarkdown"

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        SharedSettings.reload()
        SharedSettings.startMonitoring()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Documents passed at launch (Finder, `open -a`) are opened before this point, restored
        // windows right after: show the open panel only when nothing is on screen.
        DispatchQueue.main.async {
            if NSDocumentController.shared.documents.isEmpty {
                NSDocumentController.shared.openDocument(nil)
            }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSDocumentController.shared.openDocument(nil)
        }
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    @objc func openQLMarkdownSettings(_ sender: Any?) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.qlMarkdownBundleIdentifier) else {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("QLMarkdown is not installed.", comment: "")
            alert.informativeText = NSLocalizedString("The viewer uses the settings of the QLMarkdown app.", comment: "")
            alert.runModal()
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func reloadSettings(_ sender: Any?) {
        SharedSettings.reload()
        NotificationCenter.default.post(name: SharedSettings.didReload, object: nil)
    }
}
