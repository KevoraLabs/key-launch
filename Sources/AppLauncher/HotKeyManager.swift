import Carbon
import Foundation

final class HotKeyManager {
    static let shared = HotKeyManager()

    var onHotKeyPressed: ((AppShortcut) -> Void)?

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var shortcutsByHotKeyID: [UInt32: AppShortcut] = [:]
    private var handlerRef: EventHandlerRef?
    private var isHandlerInstalled = false

    private init() {}

    @discardableResult
    func start(shortcuts: [AppShortcut]) -> HotKeyRegistrationState {
        installHandlerIfNeeded()
        return registerHotKeys(shortcuts: shortcuts)
    }

    private func installHandlerIfNeeded() {
        guard !isHandlerInstalled else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, eventRef, _ in
            guard let eventRef else {
                return noErr
            }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.stride,
                nil,
                &hotKeyID
            )

            guard status == noErr else {
                return noErr
            }

            HotKeyManager.shared.handleHotKeyPressed(hotKeyID.id)
            return noErr
        }

        InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            &eventType,
            nil,
            &handlerRef
        )

        isHandlerInstalled = true
    }

    private func registerHotKeys(shortcuts: [AppShortcut]) -> HotKeyRegistrationState {
        unregisterAllHotKeys()
        var warnings: [String] = []
        var unavailableShortcutIDs: Set<String> = []
        var hotKeyIDCounter: UInt32 = 1

        for shortcut in shortcuts where shortcut.enabled {
            guard let keyCode = shortcut.keyCode else {
                warnings.append(L10n.format("warning.hotkey_key_not_supported", shortcut.localizedName, shortcut.key))
                unavailableShortcutIDs.insert(shortcut.id)
                continue
            }

            let hotKeyID = EventHotKeyID(signature: fourCharCode(from: "APPL"), id: hotKeyIDCounter)
            var hotKeyRef: EventHotKeyRef?

            let status = RegisterEventHotKey(
                keyCode,
                shortcut.carbonModifiers,
                hotKeyID,
                GetEventDispatcherTarget(),
                OptionBits(kEventHotKeyExclusive),
                &hotKeyRef
            )

            guard status == noErr, let hotKeyRef else {
                warnings.append(L10n.format("warning.hotkey_register_failed", shortcut.localizedName, shortcut.displayHotKey))
                unavailableShortcutIDs.insert(shortcut.id)
                continue
            }

            hotKeyRefs[hotKeyIDCounter] = hotKeyRef
            shortcutsByHotKeyID[hotKeyIDCounter] = shortcut
            hotKeyIDCounter += 1
        }

        return HotKeyRegistrationState(
            warnings: warnings,
            unavailableShortcutIDs: unavailableShortcutIDs
        )
    }

    private func unregisterAllHotKeys() {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }

        hotKeyRefs.removeAll()
        shortcutsByHotKeyID.removeAll()
    }

    private func handleHotKeyPressed(_ hotKeyID: UInt32) {
        guard let shortcut = shortcutsByHotKeyID[hotKeyID] else {
            return
        }

        print("HotKey pressed: \(shortcut.displayHotKey) -> \(shortcut.localizedName)")
        DispatchQueue.main.async {
            self.onHotKeyPressed?(shortcut)
        }
    }

    private func fourCharCode(from string: String) -> OSType {
        string.utf8.reduce(0) { value, byte in
            (value << 8) + OSType(byte)
        }
    }
}

struct HotKeyRegistrationState {
    let warnings: [String]
    let unavailableShortcutIDs: Set<String>
}
