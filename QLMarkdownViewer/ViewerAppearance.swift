//
//  ViewerAppearance.swift
//  QLMarkdown Viewer
//

import Cocoa

/// Appearance chosen in View ▸ Appearance. It overrides the appearance of the QLMarkdown settings.
enum ViewerAppearance: String, CaseIterable {
    case system
    case light
    case dark

    private static let defaultsKey = "appearance"

    static var current: ViewerAppearance {
        get {
            return UserDefaults.standard.string(forKey: defaultsKey).flatMap(ViewerAppearance.init(rawValue:)) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// Appearance of the windows (title bar, find bar and the web view color scheme).
    var appAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// Appearance used by the renderer.
    var renderAppearance: Appearance {
        switch self {
        case .system: return .undefined
        case .light: return .light
        case .dark: return .dark
        }
    }
}
