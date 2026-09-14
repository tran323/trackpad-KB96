import AppKit

struct DragShortcut: Codable, Equatable {
    let code: CGKeyCode
    let modifiers: UInt64
    let name: String

    static let modifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    static let defaultShortcut = DragShortcut(code: 97, modifiers: 0, name: "F6")

    static func load(from defaults: UserDefaults) -> DragShortcut {
        if let data = defaults.data(forKey: "dragShortcut"),
           let shortcut = try? JSONDecoder().decode(Self.self, from: data), shortcut.isValid {
            return shortcut
        }
        let legacy: [String: CGKeyCode] = ["F6": 97, "F7": 98, "F8": 100, "F9": 101]
        let name = defaults.string(forKey: "dragKey") ?? "F6"
        return DragShortcut(code: legacy[name] ?? 97, modifiers: 0, name: legacy[name] == nil ? "F6" : name)
    }

    var isValid: Bool {
        code < 128 && code != 53 && code != 57 && !name.isEmpty && modifiers & ~Self.modifierMask.rawValue == 0
    }

    var modifierFlag: CGEventFlags? { Self.modifierFlag(for: code) }

    static func modifierFlag(for code: CGKeyCode) -> CGEventFlags? {
        switch code {
        case 54, 55: return .maskCommand
        case 56, 60: return .maskShift
        case 58, 61: return .maskAlternate
        case 59, 62: return .maskControl
        case 63: return .maskSecondaryFn
        default: return nil
        }
    }

    var displayName: String {
        let flags = CGEventFlags(rawValue: modifiers)
        return (flags.contains(.maskControl) ? "⌃" : "")
            + (flags.contains(.maskAlternate) ? "⌥" : "")
            + (flags.contains(.maskShift) ? "⇧" : "")
            + (flags.contains(.maskCommand) ? "⌘" : "") + name
    }

    func matches(code: CGKeyCode, flags: CGEventFlags) -> Bool {
        var relevant = flags.intersection(Self.modifierMask)
        if let modifierFlag { relevant.remove(modifierFlag) }
        return self.code == code && relevant.rawValue == modifiers
    }

    func mouseFlags(_ flags: CGEventFlags) -> CGEventFlags {
        var result = flags
        result.subtract(CGEventFlags(rawValue: modifiers))
        if let modifierFlag { result.remove(modifierFlag) }
        result.remove(.maskSecondaryFn)
        return result
    }

    static func recording(_ event: NSEvent) -> DragShortcut? {
        let code = event.keyCode
        guard code != 53 && code != 57 else { return nil }
        let special: [CGKeyCode: String] = [
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 117: "Forward Delete",
            54: "Right Command", 55: "Left Command", 56: "Left Shift", 60: "Right Shift",
            58: "Left Option", 61: "Right Option", 59: "Left Control", 62: "Right Control", 63: "Fn",
            123: "Left Arrow", 124: "Right Arrow", 125: "Down Arrow", 126: "Up Arrow",
            115: "Home", 119: "End", 116: "Page Up", 121: "Page Down", 76: "Keypad Enter",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
            100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13",
            107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"
        ]
        var flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)).intersection(modifierMask)
        if let flag = modifierFlag(for: code) { flags.remove(flag) }
        let characters = event.type == .keyDown ? event.charactersIgnoringModifiers?.uppercased() : nil
        let name = special[code] ?? characters.flatMap { $0.isEmpty ? nil : $0 } ?? "Key \(code)"
        let result = DragShortcut(code: code, modifiers: flags.rawValue, name: name)
        return result.isValid ? result : nil
    }
}
