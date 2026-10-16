import Foundation

/// Functions that can be assigned to a button, with the IDs used by `Mouse.exe` (`ms_4_*` menu handler)
/// and their translation to the 3 bytes of report 0x08 (table in `Mouse.exe` @ 0x447778).
public enum ButtonFunction {
    public static let off: UInt8 = 0
    public static let leftClick: UInt8 = 1
    public static let customShortcut: UInt8 = 0x10
    public static let macro: UInt8 = 0x11

    public struct Info: Sendable {
        public let id: UInt8
        public let name: String
        public let group: String
    }

    /// ID → (code, b1, b2), exactly as in the Windows driver's table.
    static let wireTable: [UInt8: (UInt8, UInt8, UInt8)] = [
        0: (1, 0, 0), 1: (2, 0, 0), 2: (3, 0, 0), 3: (4, 0, 0), 4: (6, 0, 0), 5: (5, 0, 0),
        9: (7, 0, 0), 10: (8, 0, 0), 11: (9, 0, 0), 12: (10, 0, 0), 13: (11, 0, 0), 14: (12, 0, 0),
        6: (13, 0, 0), 7: (14, 0, 0), 8: (15, 0, 0), 16: (17, 0, 0), 17: (18, 0, 0), 19: (19, 0, 0),
        115: (20, 0, 0), 21: (43, 0, 0), 22: (16, 0, 3), 23: (41, 0, 3),
        54: (52, 0, 0), 55: (53, 0, 0), 56: (54, 0, 0), 52: (60, 0, 0), 24: (40, 0, 0),
        64: (21, 0, 0), 67: (22, 0, 0), 68: (23, 0, 0), 65: (24, 0, 0), 66: (25, 0, 0),
        71: (26, 0, 0), 69: (27, 0, 0), 70: (28, 0, 0), 88: (29, 0, 0), 87: (30, 0, 0),
        81: (17, 3, 18), 82: (32, 0, 0), 83: (33, 0, 0), 84: (34, 0, 0), 89: (35, 0, 0),
        85: (36, 0, 0), 80: (37, 0, 0), 86: (38, 0, 0),
        32: (17, 1, 27), 33: (17, 1, 6), 34: (17, 1, 25), 35: (17, 1, 18), 47: (17, 1, 17),
        36: (17, 1, 22), 41: (17, 1, 19), 37: (17, 1, 9), 38: (17, 1, 28), 39: (17, 1, 29),
        48: (17, 1, 46), 49: (17, 1, 45), 40: (17, 1, 4), 43: (17, 4, 43), 44: (17, 8, 7),
        42: (17, 4, 61), 45: (17, 8, 21), 46: (17, 8, 15), 50: (17, 10, 22),
    ]

    static func wireCode(for id: UInt8) -> (UInt8, UInt8, UInt8)? { wireTable[id] }

    /// Functions offered by the M618XSD button menu on Windows.
    public static let all: [Info] = [
        Info(id: 1, name: "Left click", group: "Mouse"),
        Info(id: 2, name: "Right click", group: "Mouse"),
        Info(id: 3, name: "Middle click", group: "Mouse"),
        Info(id: 4, name: "Forward", group: "Mouse"),
        Info(id: 5, name: "Back", group: "Mouse"),
        Info(id: 9, name: "Double click", group: "Mouse"),
        Info(id: 10, name: "Fire key", group: "Mouse"),
        Info(id: 22, name: "Easy Aim", group: "Mouse"),
        Info(id: 11, name: "Scroll up", group: "Mouse"),
        Info(id: 12, name: "Scroll down", group: "Mouse"),
        Info(id: 13, name: "Scroll left", group: "Mouse"),
        Info(id: 14, name: "Scroll right", group: "Mouse"),
        Info(id: 0, name: "Disabled", group: "Mouse"),
        Info(id: 6, name: "DPI cycle", group: "DPI and lighting"),
        Info(id: 7, name: "DPI +", group: "DPI and lighting"),
        Info(id: 8, name: "DPI −", group: "DPI and lighting"),
        Info(id: 23, name: "Lighting cycle", group: "DPI and lighting"),
        Info(id: 64, name: "Media player", group: "Multimedia"),
        Info(id: 65, name: "Play / pause", group: "Multimedia"),
        Info(id: 66, name: "Stop", group: "Multimedia"),
        Info(id: 67, name: "Previous track", group: "Multimedia"),
        Info(id: 68, name: "Next track", group: "Multimedia"),
        Info(id: 69, name: "Volume +", group: "Multimedia"),
        Info(id: 70, name: "Volume −", group: "Multimedia"),
        Info(id: 71, name: "Mute", group: "Multimedia"),
        Info(id: 80, name: "Browser: home", group: "Browser and apps"),
        Info(id: 81, name: "Browser: favorites", group: "Browser and apps"),
        Info(id: 82, name: "Browser: forward", group: "Browser and apps"),
        Info(id: 83, name: "Browser: back", group: "Browser and apps"),
        Info(id: 84, name: "Browser: stop", group: "Browser and apps"),
        Info(id: 85, name: "Browser: refresh", group: "Browser and apps"),
        Info(id: 86, name: "Browser: search", group: "Browser and apps"),
        Info(id: 87, name: "Mail", group: "Browser and apps"),
        Info(id: 88, name: "Calculator", group: "Browser and apps"),
        Info(id: 89, name: "My Computer", group: "Browser and apps"),
    ]

    /// Groups in menu order (as they first appear in `all`).
    public static let groups: [String] = all.reduce(into: []) { if !$0.contains($1.group) { $0.append($1.group) } }

    public static func name(for id: UInt8) -> String {
        all.first { $0.id == id }?.name ?? "Function \(id)"
    }

    /// Factory assignment of the 18 slots (Windows default profile).
    public static let defaultSlots: [UInt8] = [1, 2, 4, 5, 3, 6, 0, 0, 0, 0, 0, 0, 0, 0, 13, 14, 11, 12]

    /// Name of the physical slot according to the factory assignment.
    public static func slotName(_ slot: Int) -> String {
        switch slot {
        case 0: return "Left button"
        case 1: return "Right button"
        case 2: return "Side forward"
        case 3: return "Side back"
        case 4: return "Middle button"
        case 5: return "DPI button"
        case 14: return "Wheel tilt left"
        case 15: return "Wheel tilt right"
        case 16: return "Wheel up"
        case 17: return "Wheel down"
        default: return "Slot \(slot + 1)"
        }
    }

    /// Slots that map to physical controls on the M618XSD.
    public static let physicalSlots: [Int] = [0, 1, 2, 3, 4, 5, 14, 15, 16, 17]
}

/// Useful macOS shortcuts, implemented as custom shortcuts (Cmd = modifier 8).
public enum MacShortcut {
    public struct Preset: Sendable {
        public let name: String
        public let modifiers: UInt8
        public let key: UInt8
    }

    public static let presets: [Preset] = [
        Preset(name: "Copy (⌘C)", modifiers: 8, key: 0x06),
        Preset(name: "Paste (⌘V)", modifiers: 8, key: 0x19),
        Preset(name: "Cut (⌘X)", modifiers: 8, key: 0x1b),
        Preset(name: "Undo (⌘Z)", modifiers: 8, key: 0x1d),
        Preset(name: "Redo (⇧⌘Z)", modifiers: 10, key: 0x1d),
        Preset(name: "Select all (⌘A)", modifiers: 8, key: 0x04),
        Preset(name: "Save (⌘S)", modifiers: 8, key: 0x16),
        Preset(name: "Find (⌘F)", modifiers: 8, key: 0x09),
        Preset(name: "New tab (⌘T)", modifiers: 8, key: 0x17),
        Preset(name: "Close window (⌘W)", modifiers: 8, key: 0x1a),
        Preset(name: "Switch app (⌘Tab)", modifiers: 8, key: 0x2b),
        Preset(name: "Screenshot (⇧⌘4)", modifiers: 10, key: 0x21),
        Preset(name: "Mission Control (⌃↑)", modifiers: 1, key: 0x52),
        Preset(name: "Desktop left (⌃←)", modifiers: 1, key: 0x50),
        Preset(name: "Desktop right (⌃→)", modifiers: 1, key: 0x4f),
        Preset(name: "Spotlight (⌘Space)", modifiers: 8, key: 0x2c),
    ]
}
