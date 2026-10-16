import Foundation

/// Funciones asignables a un botón, con los IDs que usa `Mouse.exe` (manejador del menú `ms_4_*`)
/// y su traducción a los 3 bytes del report 0x08 (tabla en `Mouse.exe` @ 0x447778).
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

    /// ID → (código, b1, b2) tal cual la tabla del driver de Windows.
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

    /// Funciones que ofrece el menú de botones del M618XSD en Windows.
    public static let all: [Info] = [
        Info(id: 1, name: "Clic izquierdo", group: "Mouse"),
        Info(id: 2, name: "Clic derecho", group: "Mouse"),
        Info(id: 3, name: "Botón central", group: "Mouse"),
        Info(id: 4, name: "Adelante", group: "Mouse"),
        Info(id: 5, name: "Atrás", group: "Mouse"),
        Info(id: 9, name: "Doble clic", group: "Mouse"),
        Info(id: 10, name: "Disparo rápido", group: "Mouse"),
        Info(id: 22, name: "Easy Aim", group: "Mouse"),
        Info(id: 11, name: "Rueda arriba", group: "Mouse"),
        Info(id: 12, name: "Rueda abajo", group: "Mouse"),
        Info(id: 13, name: "Desplazar a la izquierda", group: "Mouse"),
        Info(id: 14, name: "Desplazar a la derecha", group: "Mouse"),
        Info(id: 0, name: "Desactivado", group: "Mouse"),
        Info(id: 6, name: "Ciclo de DPI", group: "DPI"),
        Info(id: 7, name: "DPI +", group: "DPI"),
        Info(id: 8, name: "DPI −", group: "DPI"),
        Info(id: 23, name: "Ciclo de luz", group: "DPI"),
        Info(id: 64, name: "Reproductor", group: "Multimedia"),
        Info(id: 65, name: "Reproducir / pausa", group: "Multimedia"),
        Info(id: 66, name: "Detener", group: "Multimedia"),
        Info(id: 67, name: "Pista anterior", group: "Multimedia"),
        Info(id: 68, name: "Pista siguiente", group: "Multimedia"),
        Info(id: 69, name: "Volumen +", group: "Multimedia"),
        Info(id: 70, name: "Volumen −", group: "Multimedia"),
        Info(id: 71, name: "Silencio", group: "Multimedia"),
        Info(id: 80, name: "Navegador: inicio", group: "Navegador"),
        Info(id: 81, name: "Navegador: favoritos", group: "Navegador"),
        Info(id: 82, name: "Navegador: adelante", group: "Navegador"),
        Info(id: 83, name: "Navegador: atrás", group: "Navegador"),
        Info(id: 84, name: "Navegador: detener", group: "Navegador"),
        Info(id: 85, name: "Navegador: recargar", group: "Navegador"),
        Info(id: 86, name: "Navegador: buscar", group: "Navegador"),
        Info(id: 87, name: "Correo", group: "Navegador"),
        Info(id: 88, name: "Calculadora", group: "Navegador"),
        Info(id: 89, name: "Mi PC", group: "Navegador"),
    ]

    public static func name(for id: UInt8) -> String {
        all.first { $0.id == id }?.name ?? "Función \(id)"
    }

    /// Asignación de fábrica de las 18 ranuras (perfil por defecto de Windows).
    public static let defaultSlots: [UInt8] = [1, 2, 4, 5, 3, 6, 0, 0, 0, 0, 0, 0, 0, 0, 13, 14, 11, 12]

    /// Nombre de la ranura física según la asignación de fábrica.
    public static func slotName(_ slot: Int) -> String {
        switch slot {
        case 0: return "Botón izquierdo"
        case 1: return "Botón derecho"
        case 2: return "Lateral adelante"
        case 3: return "Lateral atrás"
        case 4: return "Botón central"
        case 5: return "Botón DPI"
        case 14: return "Inclinación izquierda"
        case 15: return "Inclinación derecha"
        case 16: return "Rueda arriba"
        case 17: return "Rueda abajo"
        default: return "Ranura \(slot + 1)"
        }
    }

    /// Ranuras que corresponden a controles físicos del M618XSD.
    public static let physicalSlots: [Int] = [0, 1, 2, 3, 4, 5, 14, 15, 16, 17]
}

/// Atajos útiles en macOS, implementados como atajo personalizado (Cmd = modificador 8).
public enum MacShortcut {
    public struct Preset: Sendable {
        public let name: String
        public let modifiers: UInt8
        public let key: UInt8
    }

    public static let presets: [Preset] = [
        Preset(name: "Copiar (⌘C)", modifiers: 8, key: 0x06),
        Preset(name: "Pegar (⌘V)", modifiers: 8, key: 0x19),
        Preset(name: "Cortar (⌘X)", modifiers: 8, key: 0x1b),
        Preset(name: "Deshacer (⌘Z)", modifiers: 8, key: 0x1d),
        Preset(name: "Rehacer (⇧⌘Z)", modifiers: 10, key: 0x1d),
        Preset(name: "Seleccionar todo (⌘A)", modifiers: 8, key: 0x04),
        Preset(name: "Guardar (⌘S)", modifiers: 8, key: 0x16),
        Preset(name: "Buscar (⌘F)", modifiers: 8, key: 0x09),
        Preset(name: "Nueva pestaña (⌘T)", modifiers: 8, key: 0x17),
        Preset(name: "Cerrar ventana (⌘W)", modifiers: 8, key: 0x1a),
        Preset(name: "Cambiar de app (⌘Tab)", modifiers: 8, key: 0x2b),
        Preset(name: "Captura de pantalla (⇧⌘4)", modifiers: 10, key: 0x21),
        Preset(name: "Mission Control (⌃↑)", modifiers: 1, key: 0x52),
        Preset(name: "Escritorio izquierda (⌃←)", modifiers: 1, key: 0x50),
        Preset(name: "Escritorio derecha (⌃→)", modifiers: 1, key: 0x4f),
        Preset(name: "Spotlight (⌘Espacio)", modifiers: 8, key: 0x2c),
    ]
}
