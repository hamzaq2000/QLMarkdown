//
//  AppDelegate.swift
//  QLMarkdown Viewer
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        NSApp.appearance = ViewerAppearance.current.appAppearance
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

    @objc func chooseAppearance(_ sender: NSMenuItem) {
        guard let appearance = sender.representedObject as? String, let appearance = ViewerAppearance(rawValue: appearance) else {
            return
        }
        ViewerAppearance.current = appearance
        NSApp.appearance = appearance.appAppearance
        SharedSettings.reload()
        NotificationCenter.default.post(name: SharedSettings.didReload, object: nil)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(chooseAppearance(_:)) {
            menuItem.state = menuItem.representedObject as? String == ViewerAppearance.current.rawValue ? .on : .off
        }
        return true
    }
}
