import Foundation

/// Color RGB de 8 bits por canal.
public struct RGB: Codable, Equatable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
}

/// Un nivel de DPI. `dpi` debe ser múltiplo de 40 (la UI de Windows usa pasos de 40, de 40 a 4800).
public struct DPIStage: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var dpi: Int
    public var color: RGB
    public init(enabled: Bool, dpi: Int, color: RGB) { self.enabled = enabled; self.dpi = dpi; self.color = color }
}

public enum PollingRate: Int, Codable, CaseIterable, Sendable {
    case hz125 = 125, hz250 = 250, hz500 = 500, hz1000 = 1000

    /// Intervalo en ms que viaja en el report 0x06.
    var intervalCode: UInt8 {
        switch self { case .hz125: return 8; case .hz250: return 4; case .hz500: return 2; case .hz1000: return 1 }
    }
}

/// Modos de luz del combo `ms_4_combo_light` (índice 0–11).
public enum LightMode: Int, Codable, CaseIterable, Sendable {
    case off = 0, rainbowWave, neon, breathing, colorJump, staticColor
    case mixedBreathing, rainbowWave2, lightning, staticMixed, marquee, marquee2

    public var displayName: String {
        switch self {
        case .off: return "Apagado"
        case .rainbowWave: return "Ola arcoíris"
        case .neon: return "Neón"
        case .breathing: return "Respiración"
        case .colorJump: return "Salto de color"
        case .staticColor: return "Color fijo"
        case .mixedBreathing: return "Respiración mixta"
        case .rainbowWave2: return "Ola arcoíris 2"
        case .lightning: return "Relámpago"
        case .staticMixed: return "Mezcla fija"
        case .marquee: return "Marquesina"
        case .marquee2: return "Marquesina 2"
        }
    }
}

public struct Lighting: Codable, Equatable, Sendable {
    public var mode: LightMode
    public var color: RGB
    /// 1–8
    public var brightness: Int
    /// 4–8 (la UI de Windows limita el slider a ese rango)
    public var speed: Int
    /// "Enable move close led": apaga la luz mientras el mouse se mueve.
    public var offWhileMoving: Bool
}

public struct Power: Codable, Equatable, Sendable {
    /// Minutos hasta apagar la luz, 1–60.
    public var lightOffMinutes: Int
    /// Minutos hasta suspender el mouse, 1–60.
    public var sleepMinutes: Int
}

/// Evento de una macro: tecla HID (o botón de mouse 0xF1–0xF5) pulsada o soltada, y retardo posterior.
public struct MacroEvent: Codable, Equatable, Sendable {
    public var key: UInt8
    public var pressed: Bool
    public var delayMs: Int
    public init(key: UInt8, pressed: Bool, delayMs: Int) { self.key = key; self.pressed = pressed; self.delayMs = delayMs }
}

public struct Macro: Codable, Equatable, Sendable {
    public var name: String
    /// Modo de repetición (byte en +0x0C del bloque de botón en `pro.data`).
    public var repeatMode: UInt8
    public var repeatCount: UInt8
    public var events: [MacroEvent]
    public init(name: String, repeatMode: UInt8 = 1, repeatCount: UInt8 = 1, events: [MacroEvent]) {
        self.name = name; self.repeatMode = repeatMode; self.repeatCount = repeatCount; self.events = events
    }
}

/// Asignación de una ranura de botón.
public enum ButtonAssignment: Codable, Equatable, Sendable {
    /// Función predefinida por ID (ver `ButtonFunction`).
    case function(UInt8)
    /// Atajo de teclado: modificadores (1 Ctrl, 2 Shift, 4 Alt, 8 Cmd/Win) + tecla HID.
    case shortcut(modifiers: UInt8, key: UInt8)
    case macro(Macro)
}

public struct MouseProfile: Codable, Equatable, Sendable {
    public static let stageCount = 8
    public static let slotCount = 18

    public var name: String
    public var dpiStages: [DPIStage]
    /// Índice 0–7 del nivel activo.
    public var activeStage: Int
    public var pollingRate: PollingRate
    public var lighting: Lighting
    public var power: Power
    /// Tiempo de respuesta de teclas, 1–25.
    public var debounce: Int
    public var buttons: [ButtonAssignment]

    /// Perfil por defecto del driver de Windows para el M618XSD (`Data/ms_4/pro.data`, perfil "Profile1").
    public static let factoryDefault = MouseProfile(
        name: "Predeterminado",
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

    /// Lista de problemas que impedirían enviar el perfil. Vacía si es válido.
    public func validationErrors() -> [String] {
        var errors: [String] = []
        if dpiStages.count != Self.stageCount { errors.append("Debe haber \(Self.stageCount) niveles de DPI.") }
        for (i, s) in dpiStages.enumerated() where s.enabled {
            if !(40...4800).contains(s.dpi) || s.dpi % 40 != 0 {
                errors.append("Nivel \(i + 1): el DPI debe ser múltiplo de 40 entre 40 y 4800.")
            }
        }
        if !dpiStages.contains(where: \.enabled) { errors.append("Al menos un nivel de DPI debe estar activo.") }
        if !(0..<Self.stageCount).contains(activeStage) || !dpiStages[activeStage].enabled {
            errors.append("El nivel activo debe ser uno de los habilitados.")
        }
        if !(1...8).contains(lighting.brightness) { errors.append("Brillo fuera de rango (1–8).") }
        if !(4...8).contains(lighting.speed) { errors.append("Velocidad fuera de rango (4–8).") }
        if !(1...60).contains(power.lightOffMinutes) { errors.append("Apagado de luz fuera de rango (1–60).") }
        if !(1...60).contains(power.sleepMinutes) { errors.append("Suspensión fuera de rango (1–60).") }
        if !(1...25).contains(debounce) { errors.append("Tiempo de respuesta fuera de rango (1–25).") }
        if buttons.count != Self.slotCount { errors.append("Debe haber \(Self.slotCount) ranuras de botón.") }
        // Regla de la app de Windows: al menos un botón debe ser "clic izquierdo".
        if !buttons.contains(.function(ButtonFunction.leftClick)) {
            errors.append("Al menos un botón debe ser «Clic izquierdo».")
        }
        for (i, b) in buttons.enumerated() {
            if case .function(let id) = b, ButtonFunction.wireCode(for: id) == nil {
                errors.append("Ranura \(i + 1): función desconocida \(id).")
            }
            if case .macro(let m) = b, (try? Protocol.macroPayload(m)) == nil {
                errors.append("Ranura \(i + 1): la macro «\(m.name)» es demasiado larga.")
            }
        }
        return errors
    }
}
