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

    // AppKit asks for an untitled document only on a launch without documents to open or
    // windows to restore, and on a Dock click with no window open: show the open panel instead.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSDocumentController.shared.openDocument(nil)
        return true
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
