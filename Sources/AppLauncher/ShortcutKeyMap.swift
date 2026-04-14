import Carbon
import Foundation

enum ShortcutKeyMap {
    static func keyCode(for rawKey: String) -> UInt32? {
        let key = normalize(rawKey)
        if key.count == 1, let character = key.first {
            return singleKeyCodes[character]
        }

        return namedKeyCodes[key]?.code
    }

    static func displayName(for rawKey: String) -> String {
        let key = normalize(rawKey)
        if key.count == 1 {
            return key.uppercased()
        }

        if let displayKey = namedKeyCodes[key]?.displayKey {
            return L10n.tr(displayKey)
        }
        return rawKey
    }

    private static func normalize(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static let namedKeyCodes: [String: (code: UInt32, displayKey: String)] = [
        "space": (UInt32(kVK_Space), "key.space"),
        "return": (UInt32(kVK_Return), "key.return"),
        "enter": (UInt32(kVK_Return), "key.return"),
        "tab": (UInt32(kVK_Tab), "key.tab"),
        "esc": (UInt32(kVK_Escape), "key.esc"),
        "escape": (UInt32(kVK_Escape), "key.esc"),
        "delete": (UInt32(kVK_Delete), "key.delete"),
        "f1": (UInt32(kVK_F1), "key.f1"),
        "f2": (UInt32(kVK_F2), "key.f2"),
        "f3": (UInt32(kVK_F3), "key.f3"),
        "f4": (UInt32(kVK_F4), "key.f4"),
        "f5": (UInt32(kVK_F5), "key.f5"),
        "f6": (UInt32(kVK_F6), "key.f6"),
        "f7": (UInt32(kVK_F7), "key.f7"),
        "f8": (UInt32(kVK_F8), "key.f8"),
        "f9": (UInt32(kVK_F9), "key.f9"),
        "f10": (UInt32(kVK_F10), "key.f10"),
        "f11": (UInt32(kVK_F11), "key.f11"),
        "f12": (UInt32(kVK_F12), "key.f12")
    ]

    private static let singleKeyCodes: [Character: UInt32] = [
        "a": UInt32(kVK_ANSI_A),
        "b": UInt32(kVK_ANSI_B),
        "c": UInt32(kVK_ANSI_C),
        "d": UInt32(kVK_ANSI_D),
        "e": UInt32(kVK_ANSI_E),
        "f": UInt32(kVK_ANSI_F),
        "g": UInt32(kVK_ANSI_G),
        "h": UInt32(kVK_ANSI_H),
        "i": UInt32(kVK_ANSI_I),
        "j": UInt32(kVK_ANSI_J),
        "k": UInt32(kVK_ANSI_K),
        "l": UInt32(kVK_ANSI_L),
        "m": UInt32(kVK_ANSI_M),
        "n": UInt32(kVK_ANSI_N),
        "o": UInt32(kVK_ANSI_O),
        "p": UInt32(kVK_ANSI_P),
        "q": UInt32(kVK_ANSI_Q),
        "r": UInt32(kVK_ANSI_R),
        "s": UInt32(kVK_ANSI_S),
        "t": UInt32(kVK_ANSI_T),
        "u": UInt32(kVK_ANSI_U),
        "v": UInt32(kVK_ANSI_V),
        "w": UInt32(kVK_ANSI_W),
        "x": UInt32(kVK_ANSI_X),
        "y": UInt32(kVK_ANSI_Y),
        "z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0),
        "1": UInt32(kVK_ANSI_1),
        "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3),
        "4": UInt32(kVK_ANSI_4),
        "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6),
        "7": UInt32(kVK_ANSI_7),
        "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9),
        "-": UInt32(kVK_ANSI_Minus),
        "_": UInt32(kVK_ANSI_Minus),
        "=": UInt32(kVK_ANSI_Equal),
        "+": UInt32(kVK_ANSI_Equal),
        "[": UInt32(kVK_ANSI_LeftBracket),
        "{": UInt32(kVK_ANSI_LeftBracket),
        "]": UInt32(kVK_ANSI_RightBracket),
        "}": UInt32(kVK_ANSI_RightBracket),
        "\\": UInt32(kVK_ANSI_Backslash),
        "|": UInt32(kVK_ANSI_Backslash),
        ";": UInt32(kVK_ANSI_Semicolon),
        ":": UInt32(kVK_ANSI_Semicolon),
        "'": UInt32(kVK_ANSI_Quote),
        "\"": UInt32(kVK_ANSI_Quote),
        ",": UInt32(kVK_ANSI_Comma),
        "<": UInt32(kVK_ANSI_Comma),
        ".": UInt32(kVK_ANSI_Period),
        ">": UInt32(kVK_ANSI_Period),
        "/": UInt32(kVK_ANSI_Slash),
        "?": UInt32(kVK_ANSI_Slash),
        "`": UInt32(kVK_ANSI_Grave),
        "~": UInt32(kVK_ANSI_Grave)
    ]
}
