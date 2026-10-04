import Foundation
import SwitchboardKit

/// Other apps' preferences (Finder, Dock, the global domain), read and written through
/// cfprefsd like `defaults` does, but without starting a process.
enum Prefs {
    static let global = kCFPreferencesAnyApplication as String

    static func bool(_ key: String, in domain: String) -> Bool? {
        // Drop any cached copy so changes made by other apps show up.
        CFPreferencesAppSynchronize(domain as CFString)
        return PreferenceValue.bool(CFPreferencesCopyAppValue(key as CFString, domain as CFString))
    }

    static func set(_ key: String, _ value: Bool, in domain: String) {
        CFPreferencesSetAppValue(key as CFString, value ? kCFBooleanTrue : kCFBooleanFalse, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
    }
}
