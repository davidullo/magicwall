import Foundation

/// Turns the app-written `magicwall-prefs.json` into `prefsLoaded` events: once at
/// launch and again on every `app.magicwall.prefsChanged` notification.
enum PrefsSource {
    private static var prefsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("magicwall-prefs.json")
    }

    static func start() {
        postCurrent()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in PrefsSource.postCurrent() },
            "app.magicwall.prefsChanged" as CFString,
            nil,
            .deliverImmediately,
        )
    }

    private static func postCurrent() {
        guard let data = try? Data(contentsOf: prefsURL) else { return } // written on the app's first launch
        do {
            let prefs = try JSONDecoder().decode(PlaybackPrefs.self, from: data)
            PlaybackStore.post(.prefsLoaded(prefs))
        } catch {
            extensionLog("[Prefs] Failed to decode prefs: \(error)")
        }
    }
}
