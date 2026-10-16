import Foundation
import IOKit
import IOKit.hid

/// Evento que el mouse envía por el input report 0x03 (colección de página 0x0A).
public enum MouseEvent: Equatable, Sendable {
    case dpiStageChanged(stage: Int)
    case pollingChanged(raw: Int)
    case battery(percent: Int)
    case charging
    case ack(accepted: Bool, reportID: UInt8)
    case lightModeChanged(raw: Int)
    case other(type: UInt8, value: UInt16)

    /// `report` incluye el report ID en el byte 0: `03 28 TT VV VV`.
    static func parse(_ report: [UInt8]) -> MouseEvent? {
        guard report.count >= 5, report[0] == 0x03, report[1] == Protocol.modelByte else { return nil }
        let type = report[2]
        let value = UInt16(report[3]) | UInt16(report[4]) << 8
        switch type {
        case 0x10: return .dpiStageChanged(stage: Int(value))
        case 0x20: return .pollingChanged(raw: Int(value))
        case 0x40:
            if value & 0xff == 2 { return .charging }
            let pct = Int(value >> 8)
            return (1...100).contains(pct) ? .battery(percent: pct) : .other(type: type, value: value)
        case 0x50: return .ack(accepted: value & 0xff == 0, reportID: UInt8(value >> 8))
        case 0x70: return .lightModeChanged(raw: Int(value >> 4 & 0xf))
        default: return .other(type: type, value: value)
        }
    }
}

public enum ConnectionMode: String, Sendable {
    case wired = "Cable USB"
    case receiver = "Receptor 2.4G"
    case bluetooth = "Bluetooth"
}

/// Conexión con el mouse, sea por HID (cable/receptor) o por Bluetooth LE.
public protocol MouseConnection: AnyObject, Sendable {
    var mode: ConnectionMode { get }
    /// Eventos del mouse (DPI, batería, ACK…).
    var onEvent: ((MouseEvent) -> Void)? { get set }
    func startEvents(on runLoop: RunLoop)
    func close()
    /// Envía un paquete de configuración; devuelve true si el mouse lo confirmó.
    @discardableResult func send(_ packet: [UInt8], label: String) throws -> Bool
}

public extension MouseConnection {
    /// Aplica un perfil completo. Bloquea varios segundos: llamar fuera del hilo principal.
    /// `progress` recibe (paso, índice, total, ¿confirmado?) tras enviar cada paso.
    func apply(_ profile: MouseProfile, progress: ((String, Int, Int, Bool) -> Void)? = nil) throws {
        let errors = profile.validationErrors()
        guard errors.isEmpty else { throw MouseError.invalidProfile(errors) }
        let seq = try Protocol.applySequence(profile, for: mode)
        for (i, step) in seq.enumerated() {
            let acked = try send(step.bytes, label: step.label)
            progress?(step.label, i + 1, seq.count, acked)
        }
    }

    func startEvents() { startEvents(on: .main) }
}

/// Busca el mouse por cable, Bluetooth y receptor, en ese orden. El receptor puede seguir
/// enchufado con el mouse en modo Bluetooth, así que Bluetooth va antes si macOS lo ve conectado.
public enum MouseFinder {
    public static func connect(includeBluetooth: Bool = true, bluetoothTimeout: TimeInterval = 5) throws -> MouseConnection {
        let hid = try? HIDMouse.find()
        if let hid, hid.mode == .wired { return hid }
        if includeBluetooth, HIDMouse.bluetoothMousePresent() {
            if let ble = try? BLEMouse.connect(timeout: bluetoothTimeout) {
                hid?.close()
                return ble
            }
        }
        if let hid { return hid }
        throw MouseError.notFound
    }
}

public enum MouseError: Error, CustomStringConvertible {
    case notFound
    case openFailed(IOReturn)
    case sendFailed(label: String, IOReturn)
    case noAck(label: String)
    case invalidProfile([String])
    case bluetooth(String)

    public var description: String {
        switch self {
        case .notFound: return "No se encontró el M618XSD (cable 1d57:fa28, receptor 1d57:fa60 ni Bluetooth «BT5.2Mouse»)."
        case .openFailed(let r): return "No se pudo abrir el dispositivo HID (IOReturn 0x\(String(UInt32(bitPattern: r), radix: 16)))."
        case .sendFailed(let l, let r): return "Falló el envío de «\(l)» (IOReturn 0x\(String(UInt32(bitPattern: r), radix: 16)))."
        case .noAck(let l): return "El mouse no confirmó «\(l)» tras 10 intentos."
        case .invalidProfile(let e): return "Perfil inválido:\n- " + e.joined(separator: "\n- ")
        case .bluetooth(let m): return "Bluetooth: \(m)"
        }
    }
}

/// Conexión con el M618XSD por IOKit. El canal de configuración y el de eventos
/// son colecciones del mismo `IOHIDDevice` (interfaz MI_02).
public final class HIDMouse: MouseConnection, @unchecked Sendable {
    public let mode: ConnectionMode
    private let device: IOHIDDevice
    private let manager: IOHIDManager
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private let ackLock = NSCondition()
    /// Último ACK recibido: (aceptado, report ID confirmado).
    private var lastAck: (accepted: Bool, reportID: UInt8)?

    /// Se llama en el run loop donde se programaron los eventos.
    public var onEvent: ((MouseEvent) -> Void)?

    deinit { inputBuffer.deallocate() }

    private init(device: IOHIDDevice, manager: IOHIDManager, mode: ConnectionMode) {
        self.device = device
        self.manager = manager
        self.mode = mode
    }

    /// Busca el mouse: primero por cable y después el receptor.
    public static func find() throws -> HIDMouse {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Any]] = [Protocol.wiredProductID, Protocol.receiverProductID].map {
            [kIOHIDVendorIDKey: Protocol.vendorID, kIOHIDProductIDKey: $0]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { throw MouseError.notFound }

        let candidates = set.filter { hasUsagePage($0, Protocol.configUsagePage) }
        func pid(_ d: IOHIDDevice) -> Int { (IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? Int) ?? 0 }
        guard let dev = candidates.first(where: { pid($0) == Protocol.wiredProductID })
            ?? candidates.first(where: { pid($0) == Protocol.receiverProductID }) else { throw MouseError.notFound }

        let r = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else { throw MouseError.openFailed(r) }
        let mode: ConnectionMode = pid(dev) == Protocol.wiredProductID ? .wired : .receiver
        return HIDMouse(device: dev, manager: manager, mode: mode)
    }

    /// true si el mouse está conectado al sistema por Bluetooth (HID con VID 0x045E / PID 0x0028).
    public static func bluetoothMousePresent() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x045e, kIOHIDProductIDKey: 0x0028] as CFDictionary)
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return false }
        return set.contains {
            let transport = IOHIDDeviceGetProperty($0, kIOHIDTransportKey as CFString) as? String ?? ""
            let product = IOHIDDeviceGetProperty($0, kIOHIDProductKey as CFString) as? String ?? ""
            return transport.contains("Bluetooth") && product.hasPrefix("BT5.2Mouse")
        }
    }

    private static func hasUsagePage(_ d: IOHIDDevice, _ page: Int) -> Bool {
        guard let pairs = IOHIDDeviceGetProperty(d, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Any]] else {
            return false
        }
        return pairs.contains { ($0[kIOHIDDeviceUsagePageKey] as? Int) == page }
    }

    /// Activa la recepción de eventos en `runLoop` (el principal en la app; el actual en la CLI).
    public func startEvents(on runLoop: RunLoop) {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, 64, { ctx, _, _, _, reportID, report, length in
                guard let ctx else { return }
                let me = Unmanaged<HIDMouse>.fromOpaque(ctx).takeUnretainedValue()
                var bytes = Array(UnsafeBufferPointer(start: report, count: length))
                // Según el driver, el report ID puede venir o no al inicio del buffer.
                if bytes.first != UInt8(truncatingIfNeeded: reportID) { bytes.insert(UInt8(truncatingIfNeeded: reportID), at: 0) }
                guard let ev = MouseEvent.parse(bytes) else { return }
                if case .ack(let ok, let rid) = ev {
                    me.ackLock.lock(); me.lastAck = (ok, rid); me.ackLock.broadcast(); me.ackLock.unlock()
                }
                me.onEvent?(ev)
        }, ctx)
        IOHIDDeviceScheduleWithRunLoop(device, runLoop.getCFRunLoop(), CFRunLoopMode.defaultMode.rawValue)
    }

    public func close() {
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, 64, nil, nil)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Envía un feature report tal cual (byte 0 = report ID).
    public func sendRaw(_ packet: [UInt8], label: String = "report") throws {
        let r = packet.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(packet[0]), $0.baseAddress!, $0.count)
        }
        guard r == kIOReturnSuccess else { throw MouseError.sendFailed(label: label, r) }
    }

    /// Espera hasta `timeout` un ACK aceptado del report `reportID`.
    private func waitAck(for reportID: UInt8, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        ackLock.lock(); defer { ackLock.unlock() }
        while !(lastAck?.reportID == reportID && lastAck?.accepted == true) {
            if !ackLock.wait(until: deadline) { return false }
        }
        return true
    }

    /// Envía un paquete con la misma estrategia que la app de Windows:
    /// por cable, un envío y hasta 500 ms de espera; por receptor, hasta 10 envíos
    /// cada 500 ms hasta recibir el ACK.
    /// Devuelve true si el mouse confirmó el comando con un ACK.
    @discardableResult
    public func send(_ packet: [UInt8], label: String) throws -> Bool {
        let attempts = mode == .wired ? 1 : 10
        for _ in 0..<attempts {
            ackLock.lock(); lastAck = nil; ackLock.unlock()
            let start = Date()
            try sendRaw(packet, label: label)
            let acked = waitAck(for: packet[0], timeout: 0.5)
            // Como la app de Windows: 500 ms entre comandos aunque el ACK llegue antes;
            // si no, el mouse descarta el siguiente mientras guarda el anterior.
            let remaining = 0.5 - Date().timeIntervalSince(start)
            if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
            if acked || mode == .wired { return acked }
        }
        throw MouseError.noAck(label: label)
    }
}
