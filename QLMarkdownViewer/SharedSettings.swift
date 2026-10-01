//
//  SharedSettings.swift
//  QLMarkdown Viewer
//

import Foundation
import OSLog

/// Keeps `Settings.shared` in sync with the settings saved by the QLMarkdown app.
///
/// The viewer is not a member of the `group.org.sbarex.qlmarkdown` App Group (it is not signed
/// by the same team), so `UserDefaults(suiteName:)` would not see the group preferences.
/// The preferences file is read directly from the group container instead.
enum SharedSettings {
    static let didReload = Notification.Name("QLMarkdownViewer.settingsReloaded")

    static var preferencesUrl: URL {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/\(Settings.appGroup)/Library/Preferences/\(Settings.appGroup).plist")
    }

    static func reload() {
        let settings = Settings.shared
        settings.update(from: Settings.factorySettings)
        if let defaults = NSDictionary(contentsOf: preferencesUrl) as? [String: Any] {
            settings.update(from: defaults)
        } else {
            os_log("Unable to read the QLMarkdown settings from %{public}@, using the defaults.", log: OSLog.rendering, type: .info, preferencesUrl.path)
        }
        // Read the custom style now, as the Quick Look extension does.
        settings.customCSSCode = settings.getCustomCSSCode()
        settings.customCSSFetched = true
    }

    static func startMonitoring() {
        DistributedNotificationCenter.default().addObserver(forName: .QLMarkdownSettingsUpdated, object: nil, queue: .main) { _ in
            // The QLMarkdown app posts the notification right after `synchronize()`: give
            // cfprefsd a moment to flush the file to disk.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                reload()
                NotificationCenter.default.post(name: didReload, object: nil)
            }
        }
    }
}
