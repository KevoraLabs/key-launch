import AppKit
import Carbon
import Foundation

enum ShortcutModifier: String, Codable, CaseIterable, Hashable {
    case command
    case option
    case control
    case shift

    var carbonMask: UInt32 {
        switch self {
        case .command:
            return UInt32(cmdKey)
        case .option:
            return UInt32(optionKey)
        case .control:
            return UInt32(controlKey)
        case .shift:
            return UInt32(shiftKey)
        }
    }

    var symbol: String {
        switch self {
        case .command:
            return "⌘"
        case .option:
            return "⌥"
        case .control:
            return "⌃"
        case .shift:
            return "⇧"
        }
    }
}

struct AppShortcut: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var bundleIdentifier: String
    var key: String
    var modifiers: [ShortcutModifier]
    var enabled: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        bundleIdentifier: String,
        key: String,
        modifiers: [ShortcutModifier],
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.key = key
        self.modifiers = modifiers
        self.enabled = enabled
    }

    var keyCode: UInt32? {
        ShortcutKeyMap.keyCode(for: key)
    }

    var carbonModifiers: UInt32 {
        sortedModifiers.reduce(0) { $0 | $1.carbonMask }
    }

    var displayHotKey: String {
        sortedModifiers.map(\.symbol).joined() + ShortcutKeyMap.displayName(for: key)
    }

    var localizedName: String {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
              let bundle = Bundle(url: appURL) else {
            return name
        }
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? name
    }

    private var sortedModifiers: [ShortcutModifier] {
        let modifierSet = Set(modifiers)
        return Self.modifierOrder.filter { modifierSet.contains($0) }
    }

    private static let modifierOrder: [ShortcutModifier] = [.command, .option, .control, .shift]
}
