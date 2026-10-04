//
//  main.swift
//  QLMarkdown Viewer
//

import Cocoa

// Overlay scrollers that hide when not scrolling. Registered as a fallback: an explicit
// "Show scroll bars" choice in System Settings (global domain) still wins, only the
// "Automatically" mode, which shows them permanently when a mouse is connected, is overridden.
UserDefaults.standard.register(defaults: ["AppleShowScrollBars": "WhenScrolling"])

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
