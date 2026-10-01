//
//  MainMenu.swift
//  QLMarkdown Viewer
//

import Cocoa

enum MainMenu {
    static func build() -> NSMenu {
        let appName = ProcessInfo.processInfo.processName
        let main = NSMenu()

        main.addSubmenu("") {
            $0.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
            $0.addItem(.separator())
            $0.addItem(withTitle: "QLMarkdown Settings…", action: #selector(AppDelegate.openQLMarkdownSettings(_:)), keyEquivalent: ",")
            $0.addItem(withTitle: "Reload Settings", action: #selector(AppDelegate.reloadSettings(_:)), keyEquivalent: "")
            $0.addItem(.separator())
            let services = NSMenu()
            $0.addItem(withTitle: "Services", action: nil, keyEquivalent: "").submenu = services
            NSApp.servicesMenu = services
            $0.addItem(.separator())
            $0.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
            $0.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h").keyEquivalentModifierMask = [.command, .option]
            $0.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
            $0.addItem(.separator())
            $0.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        }

        main.addSubmenu("File") {
            $0.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
            // NSDocumentController fills the menu that contains `clearRecentDocuments:`.
            let recent = NSMenu(title: "Open Recent")
            recent.addItem(withTitle: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
            $0.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "").submenu = recent
            $0.addItem(.separator())
            $0.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
            $0.addItem(withTitle: "Reload", action: #selector(ViewerWindowController.reload(_:)), keyEquivalent: "r")
            $0.addItem(withTitle: "Show in Finder", action: #selector(ViewerWindowController.showInFinder(_:)), keyEquivalent: "R").keyEquivalentModifierMask = [.command, .shift]
            $0.addItem(withTitle: "Export HTML…", action: #selector(ViewerWindowController.exportHTML(_:)), keyEquivalent: "e").keyEquivalentModifierMask = [.command, .shift]
            $0.addItem(.separator())
            $0.addItem(withTitle: "Print…", action: #selector(ViewerWindowController.printDocument(_:)), keyEquivalent: "p")
        }

        main.addSubmenu("Edit") {
            $0.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            $0.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
            $0.addItem(.separator())
            let find = NSMenu(title: "Find")
            let items: [(String, String, NSEvent.ModifierFlags, NSTextFinder.Action)] = [
                ("Find…", "f", [.command], .showFindInterface),
                ("Find Next", "g", [.command], .nextMatch),
                ("Find Previous", "g", [.command, .shift], .previousMatch),
                ("Use Selection for Find", "e", [.command], .setSearchString),
            ]
            for (title, key, modifiers, action) in items {
                let item = find.addItem(withTitle: title, action: #selector(ViewerWindowController.performFindAction(_:)), keyEquivalent: key)
                item.keyEquivalentModifierMask = modifiers
                item.tag = action.rawValue
            }
            $0.addItem(withTitle: "Find", action: nil, keyEquivalent: "").submenu = find
        }

        main.addSubmenu("View") {
            $0.addItem(withTitle: "Actual Size", action: #selector(ViewerWindowController.actualSize(_:)), keyEquivalent: "0")
            $0.addItem(withTitle: "Zoom In", action: #selector(ViewerWindowController.zoomIn(_:)), keyEquivalent: "+")
            // ⌘= without shift, as in Safari.
            let zoomIn = $0.addItem(withTitle: "Zoom In", action: #selector(ViewerWindowController.zoomIn(_:)), keyEquivalent: "=")
            zoomIn.isHidden = true
            zoomIn.allowsKeyEquivalentWhenHidden = true
            $0.addItem(withTitle: "Zoom Out", action: #selector(ViewerWindowController.zoomOut(_:)), keyEquivalent: "-")
            $0.addItem(.separator())
            $0.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f").keyEquivalentModifierMask = [.command, .control]
        }

        let window = main.addSubmenu("Window") {
            $0.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
            $0.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
            $0.addItem(.separator())
            $0.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        }
        NSApp.windowsMenu = window

        let help = main.addSubmenu("Help") { _ in }
        NSApp.helpMenu = help

        return main
    }
}

private extension NSMenu {
    @discardableResult
    func addSubmenu(_ title: String, _ build: (NSMenu) -> Void) -> NSMenu {
        let menu = NSMenu(title: title)
        build(menu)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        addItem(item)
        return menu
    }
}
