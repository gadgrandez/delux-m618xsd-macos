import Foundation

/// Codificación de los feature reports del M618XSD (modelo `ms_4` de DELUX Office Driver).
/// Cada función reproduce la rutina equivalente de `Mouse.exe`; ver `docs/PROTOCOLO.md`.
public enum Protocol {
    public static let vendorID = 0x1d57
    public static let wiredProductID = 0xfa28
    public static let receiverProductID = 0xfa60
    /// Byte de modelo que el M618XSD pone en sus eventos (`03 28 …`).
    public static let modelByte: UInt8 = 0x28
    public static let configUsagePage = 0x0B
    public static let eventUsagePage = 0x0A

    /// Tamaño total (ID incluido) de cada feature report según el descriptor HID del mouse.
    public static let reportLength: [UInt8: Int] = [0x04: 52, 0x05: 13, 0x06: 9, 0x08: 59, 0x09: 64, 0x0c: 6]

    public enum EncodingError: Error, CustomStringConvertible {
        case macroTooLong(Int)
        public var description: String {
            switch self { case .macroTooLong(let n): return "La macro ocupa \(n) bytes; el máximo es 100." }
        }
    }

    /// Suma de 16 bits de `bytes[from..<to]`, guardada big-endian en `bytes[to]`, `bytes[to+1]`.
    static func writeChecksum(_ bytes: inout [UInt8], from: Int, to: Int) {
        let sum = bytes[from..<to].reduce(UInt16(0)) { $0 &+ UInt16($1) }
        bytes[to] = UInt8(sum >> 8)
        bytes[to + 1] = UInt8(sum & 0xff)
    }

    /// Report 0x0C: lo envía siempre la app antes de aplicar cambios.
    public static func beginPacket() -> [UInt8] {
        [0x0c, 0x0a, 0x01, 0xfe, 0x01, 0xfe]
    }

    /// Report 0x04 (`FUN_00433ff0`).
    public static func dpiPacket(_ p: MouseProfile) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 52)
        b[0] = 0x04; b[1] = 0x38; b[2] = 0x01
        var enabledMask: UInt8 = 0
        var highMask: UInt8 = 0
        for (i, s) in p.dpiStages.prefix(8).enumerated() {
            if s.enabled { enabledMask |= 1 << i }
            // La UI guarda DPI/40 y marca los niveles con valor > 60 (DPI > 2400).
            let raw = max(0, s.dpi / 40) * 40
            if raw / 40 > 60 { highMask |= 1 << i }
            b[8 + i] = UInt8(raw & 0xff)
            b[16 + i] = UInt8((raw >> 8) & 0xff)
            b[25 + i * 3] = s.color.r
            b[26 + i * 3] = s.color.g
            b[27 + i * 3] = s.color.b
        }
        b[5] = enabledMask
        b[6] = highMask
        b[7] = highMask
        b[24] = UInt8(p.activeStage + 1)
        b[49] = 0x02
        writeChecksum(&b, from: 3, to: 50)
        return b
    }

    /// Report 0x05: luz, energía y tiempo de respuesta (`FUN_00433cd0`).
    public static func optionsPacket(_ p: MouseProfile) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 13)
        b[0] = 0x05; b[1] = 0x0f; b[2] = 0x01
        let sleep = UInt8(clamping: p.power.sleepMinutes)
        let moveFlag: UInt8 = p.lighting.offWhileMoving ? 0 : 1
        b[3] = (moveFlag << 7) | UInt8(p.lighting.mode.rawValue)
        b[4] = (sleep & 0xf0) | UInt8(clamping: 9 - p.lighting.speed)
        b[5] = ((sleep & 0x0f) << 4) | (UInt8(clamping: p.lighting.brightness) & 0x0f)
        b[6] = p.lighting.color.r
        b[7] = p.lighting.color.g
        b[8] = p.lighting.color.b
        b[9] = UInt8(clamping: p.power.lightOffMinutes)
        b[10] = UInt8(clamping: p.debounce)
        writeChecksum(&b, from: 3, to: 11)
        return b
    }

    /// Report 0x06: tasa de sondeo.
    public static func pollingPacket(_ p: MouseProfile) -> [UInt8] {
        let r = p.pollingRate.intervalCode
        return [0x06, 0x09, 0x01, r, ~r, 0, 0, 0, 0]
    }

    /// Report 0x08: asignación de las 18 ranuras (`FUN_00434690`).
    public static func buttonsPacket(_ p: MouseProfile) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 59)
        b[0] = 0x08; b[1] = 0x3b; b[2] = 0x01
        for (slot, a) in p.buttons.prefix(MouseProfile.slotCount).enumerated() {
            let o = 3 + slot * 3
            switch a {
            case .function(let id):
                let w = ButtonFunction.wireCode(for: id) ?? (0, 0, 0)
                (b[o], b[o + 1], b[o + 2]) = w
            case .shortcut(let mods, let key):
                (b[o], b[o + 1], b[o + 2]) = (0x11, mods, key)
            case .macro:
                (b[o], b[o + 1], b[o + 2]) = (0x12, 0, UInt8(slot + 1))
            }
        }
        writeChecksum(&b, from: 3, to: 57)
        return b
    }

    /// Pares de 2 bytes que describen los eventos de una macro (`FUN_00434400`).
    static func macroPayload(_ m: Macro) throws -> [UInt8] {
        func delayByte(_ ms: Int, pressed: Bool) -> UInt8 {
            let flag: UInt8 = pressed ? 0x01 : 0x81
            let steps = Int((Double(max(ms, 1)) / 10.0 + 0.5).rounded(.down))
            return UInt8(truncatingIfNeeded: steps) | flag
        }
        var out: [UInt8] = []
        for e in m.events {
            if e.delayMs < 0x4f7 {
                out += [delayByte(e.delayMs, pressed: e.pressed), e.key]
            } else {
                let rem = e.delayMs % 200
                out += [delayByte(rem == 0 ? 1 : rem, pressed: e.pressed), e.key]
                out += [UInt8(truncatingIfNeeded: e.delayMs / 200), 0x03]
            }
        }
        // Espacio entre el byte 29 y el checksum (byte 0x81).
        guard out.count <= 0x81 - 29 else { throw EncodingError.macroTooLong(out.count) }
        return out
    }

    /// Bloque lógico de 131 bytes del report 0x09 (`FUN_00434400`).
    static func macroBlock(_ m: Macro, slot: Int) throws -> [UInt8] {
        let pairs = try macroPayload(m)
        var block = [UInt8](repeating: 0, count: 300)
        block[0] = 0x09; block[1] = 0x83; block[2] = UInt8(slot + 1)
        block[3] = m.repeatMode
        block[4] = m.repeatCount; block[5] = m.repeatCount; block[6] = m.repeatCount
        block[7] = 1
        block[28] = UInt8(pairs.count / 2)
        for (i, v) in pairs.enumerated() { block[29 + i] = v }
        writeChecksum(&block, from: 3, to: 0x81)
        return Array(block.prefix(0x83))
    }

    /// Report 0x09 troceado en 3 paquetes de 64 bytes para la ranura `slot` (0-based).
    public static func macroPackets(_ m: Macro, slot: Int) throws -> [[UInt8]] {
        let block = try macroBlock(m, slot: slot) + [UInt8](repeating: 0, count: 300 - 0x83)
        return (0..<3).map { k in
            var pkt = [UInt8](repeating: 0, count: 64)
            pkt[0] = 0x09; pkt[1] = 0x40; pkt[2] = UInt8(slot + 1); pkt[3] = UInt8(k)
            for i in 0..<60 { pkt[4 + i] = block[3 + k * 60 + i] }
            return pkt
        }
    }

    /// Por Bluetooth (`FEE3`), la app de Windows envía cada paquete con el largo de su byte 1
    /// (sin recortar al descriptor HID), omite el polling y manda cada macro en un solo bloque.
    public static func applySequence(_ p: MouseProfile, for mode: ConnectionMode) throws -> [(label: String, bytes: [UInt8])] {
        guard mode == .bluetooth else { return try applySequence(p) }
        var seq: [(String, [UInt8])] = []
        for (label, bytes) in try applySequence(p) where bytes[0] != 0x06 && bytes[0] != 0x09 {
            seq.append((label, bytes + [UInt8](repeating: 0, count: max(0, Int(bytes[1]) - bytes.count))))
        }
        for (slot, a) in p.buttons.enumerated() {
            if case .macro(let m) = a { seq.append(("Macro ranura \(slot + 1)", try macroBlock(m, slot: slot))) }
        }
        return seq
    }

    /// Secuencia completa de "Aplicar" por HID, en el mismo orden que la app de Windows.
    public static func applySequence(_ p: MouseProfile) throws -> [(label: String, bytes: [UInt8])] {
        var seq: [(String, [UInt8])] = [
            ("Inicio", beginPacket()),
            ("DPI", dpiPacket(p)),
            ("Luz y energía", optionsPacket(p)),
            ("Polling", pollingPacket(p)),
            ("Botones", buttonsPacket(p)),
        ]
        for (slot, a) in p.buttons.enumerated() {
            if case .macro(let m) = a {
                for (k, pkt) in try macroPackets(m, slot: slot).enumerated() {
                    seq.append(("Macro ranura \(slot + 1) (\(k + 1)/3)", pkt))
                }
            }
        }
        return seq
    }
}

public extension Array where Element == UInt8 {
    var hex: String { map { String(format: "%02x", $0) }.joined(separator: " ") }
}
