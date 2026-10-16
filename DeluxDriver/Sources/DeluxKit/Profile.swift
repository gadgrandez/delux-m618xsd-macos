import Foundation

/// 8-bit-per-channel RGB color.
public struct RGB: Codable, Equatable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
}

/// One DPI stage. `dpi` must be a multiple of 40 (the Windows UI uses steps of 40, from 40 to 4800).
public struct DPIStage: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var dpi: Int
    public var color: RGB
    public init(enabled: Bool, dpi: Int, color: RGB) { self.enabled = enabled; self.dpi = dpi; self.color = color }
}

public enum PollingRate: Int, Codable, CaseIterable, Sendable {
    case hz125 = 125, hz250 = 250, hz500 = 500, hz1000 = 1000

    /// Interval in ms sent in report 0x06.
    var intervalCode: UInt8 {
        switch self { case .hz125: return 8; case .hz250: return 4; case .hz500: return 2; case .hz1000: return 1 }
    }
}

/// Lighting modes from the `ms_4_combo_light` combo box (index 0–11).
public enum LightMode: Int, Codable, CaseIterable, Sendable {
    case off = 0, rainbowWave, neon, breathing, colorJump, staticColor
    case mixedBreathing, rainbowWave2, lightning, staticMixed, marquee, marquee2

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .rainbowWave: return "Rainbow wave"
        case .neon: return "Neon"
        case .breathing: return "Breathing"
        case .colorJump: return "Color jump"
        case .staticColor: return "Static color"
        case .mixedBreathing: return "Mixed breathing"
        case .rainbowWave2: return "Rainbow wave 2"
        case .lightning: return "Flash"
        case .staticMixed: return "Static mix"
        case .marquee: return "Marquee"
        case .marquee2: return "Marquee 2"
        }
    }
}

public struct Lighting: Codable, Equatable, Sendable {
    public var mode: LightMode
    public var color: RGB
    /// 1–8
    public var brightness: Int
    /// 4–8 (the Windows UI limits the slider to this range)
    public var speed: Int
    /// "Enable move close led": turns the light off while the mouse is moving.
    public var offWhileMoving: Bool
}

public struct Power: Codable, Equatable, Sendable {
    /// Minutes until the light turns off, 1–60.
    public var lightOffMinutes: Int
    /// Minutes until the mouse goes to sleep, 1–60.
    public var sleepMinutes: Int
}

/// Macro event: HID key (or mouse button 0xF1–0xF5) pressed or released, and the delay after it.
public struct MacroEvent: Codable, Equatable, Sendable {
    public var key: UInt8
    public var pressed: Bool
    public var delayMs: Int
    public init(key: UInt8, pressed: Bool, delayMs: Int) { self.key = key; self.pressed = pressed; self.delayMs = delayMs }
}

public struct Macro: Codable, Equatable, Sendable {
    public var name: String
    /// Repeat mode (byte at +0x0C of the button block in `pro.data`).
    public var repeatMode: UInt8
    public var repeatCount: UInt8
    public var events: [MacroEvent]
    public init(name: String, repeatMode: UInt8 = 1, repeatCount: UInt8 = 1, events: [MacroEvent]) {
        self.name = name; self.repeatMode = repeatMode; self.repeatCount = repeatCount; self.events = events
    }
}

/// Assignment of one button slot.
public enum ButtonAssignment: Codable, Equatable, Sendable {
    /// Predefined function by ID (see `ButtonFunction`).
    case function(UInt8)
    /// Keyboard shortcut: modifiers (1 Ctrl, 2 Shift, 4 Alt, 8 Cmd/Win) + HID key.
    case shortcut(modifiers: UInt8, key: UInt8)
    case macro(Macro)
}

public struct MouseProfile: Codable, Equatable, Sendable {
    public static let stageCount = 8
    public static let slotCount = 18

    public var name: String
    public var dpiStages: [DPIStage]
    /// Index 0–7 of the active stage.
    public var activeStage: Int
    public var pollingRate: PollingRate
    public var lighting: Lighting
    public var power: Power
    /// Button response time, 1–25.
    public var debounce: Int
    public var buttons: [ButtonAssignment]

    /// The Windows driver's default profile for the M618XSD (`Data/ms_4/pro.data`, profile "Profile1").
    public static let factoryDefault = MouseProfile(
        name: "Default",
        dpiStages: [
            DPIStage(enabled: true, dpi: 800, color: RGB(0xff, 0, 0)),
            DPIStage(enabled: true, dpi: 1200, color: RGB(0, 0xff, 0)),
            DPIStage(enabled: true, dpi: 1800, color: RGB(0, 0, 0xff)),
            DPIStage(enabled: true, dpi: 2400, color: RGB(0xff, 0, 0xff)),
            DPIStage(enabled: true, dpi: 4000, color: RGB(0xff, 0xff, 0)),
            DPIStage(enabled: false, dpi: 0, color: RGB(0xff, 0, 0xff)),
            DPIStage(enabled: false, dpi: 0, color: RGB(0xff, 0x40, 0)),
            DPIStage(enabled: false, dpi: 0, color: RGB(0xff, 0xff, 0xff)),
        ],
        activeStage: 3,
        pollingRate: .hz1000,
        lighting: Lighting(mode: .off, color: RGB(0, 0, 0xff), brightness: 8, speed: 6, offWhileMoving: false),
        power: Power(lightOffMinutes: 1, sleepMinutes: 10),
        debounce: 1,
        buttons: ButtonFunction.defaultSlots.map { .function($0) }
    )

    /// Problems that would prevent sending the profile. Empty if it is valid.
    public func validationErrors() -> [String] {
        var errors: [String] = []
        if dpiStages.count != Self.stageCount { errors.append("There must be \(Self.stageCount) DPI stages.") }
        for (i, s) in dpiStages.enumerated() where s.enabled {
            if !(40...4800).contains(s.dpi) || s.dpi % 40 != 0 {
                errors.append("Stage \(i + 1): DPI must be a multiple of 40 between 40 and 4800.")
            }
        }
        if !dpiStages.contains(where: \.enabled) { errors.append("At least one DPI stage must be enabled.") }
        if !(0..<Self.stageCount).contains(activeStage) || !dpiStages[activeStage].enabled {
            errors.append("The active stage must be one of the enabled stages.")
        }
        if !(1...8).contains(lighting.brightness) { errors.append("Brightness out of range (1–8).") }
        if !(4...8).contains(lighting.speed) { errors.append("Speed out of range (4–8).") }
        if !(1...60).contains(power.lightOffMinutes) { errors.append("Light-off timer out of range (1–60).") }
        if !(1...60).contains(power.sleepMinutes) { errors.append("Sleep timer out of range (1–60).") }
        if !(1...25).contains(debounce) { errors.append("Response time out of range (1–25).") }
        if buttons.count != Self.slotCount { errors.append("There must be \(Self.slotCount) button slots.") }
        // Rule from the Windows app: at least one button must be "left click".
        if !buttons.contains(.function(ButtonFunction.leftClick)) {
            errors.append("At least one button must be \"Left click\".")
        }
        for (i, b) in buttons.enumerated() {
            if case .function(let id) = b, ButtonFunction.wireCode(for: id) == nil {
                errors.append("Slot \(i + 1): unknown function \(id).")
            }
            if case .macro(let m) = b, (try? Protocol.macroPayload(m)) == nil {
                errors.append("Slot \(i + 1): macro \"\(m.name)\" is too long.")
            }
        }
        return errors
    }
}
