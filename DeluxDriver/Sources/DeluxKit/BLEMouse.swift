import CoreBluetooth
import Foundation

/// Conexión por Bluetooth LE. El mouse (`BT5.2Mouse`, VID 0x045E / PID 0x0028) expone el
/// servicio `FEE0`: los comandos se escriben en `FEE3` y las respuestas llegan por `FEE4`
/// como `28 TT VV VV` (el mismo evento que por USB, sin el report ID 0x03).
///
/// Requiere un .app con `NSBluetoothAlwaysUsageDescription`; desde un binario suelto
/// macOS cierra el proceso al usar CoreBluetooth.
public final class BLEMouse: NSObject, MouseConnection, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    public let mode = ConnectionMode.bluetooth
    public var onEvent: ((MouseEvent) -> Void)?

    static let service = CBUUID(string: "FEE0")
    static let writeUUID = CBUUID(string: "FEE3")
    static let notifyUUID = CBUUID(string: "FEE4")

    private let queue = DispatchQueue(label: "delux.ble")
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var eventsEnabled = false
    private var eventRunLoop: RunLoop = .main

    private let cond = NSCondition()
    private var stateKnown = false
    private var ready = false
    private var failure: String?
    private var writeDone: Error??
    private var lastAck: (accepted: Bool, reportID: UInt8)?

    private override init() { super.init() }

    /// Busca el mouse entre los periféricos Bluetooth conectados y prepara `FEE3`/`FEE4`.
    /// Bloquea hasta `timeout`; no llamar desde el hilo de la cola Bluetooth.
    public static func connect(timeout: TimeInterval = 5) throws -> BLEMouse {
        let m = BLEMouse()
        m.central = CBCentralManager(delegate: m, queue: m.queue)
        let deadline = Date().addingTimeInterval(timeout)
        m.cond.lock(); defer { m.cond.unlock() }
        while !m.ready && m.failure == nil {
            if !m.cond.wait(until: deadline) {
                m.queue.async { if let p = m.peripheral { m.central.cancelPeripheralConnection(p) } }
                throw MouseError.notFound
            }
        }
        if let f = m.failure {
            if f == "notFound" { throw MouseError.notFound }
            throw MouseError.bluetooth(f)
        }
        return m
    }

    private func fail(_ msg: String) {
        cond.lock(); failure = msg; cond.broadcast(); cond.unlock()
    }

    // MARK: CBCentralManagerDelegate

    public func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:
            // El mouse ya está conectado al sistema como HID; se recupera por sus servicios.
            let found = c.retrieveConnectedPeripherals(withServices: [Self.service, CBUUID(string: "180F")])
            guard let p = found.first(where: { ($0.name ?? "").hasPrefix("BT5.2Mouse") }) ?? found.first(where: { _ in found.count == 1 })
            else { return fail("notFound") }
            peripheral = p
            p.delegate = self
            c.connect(p)
        case .unauthorized: fail("permiso denegado (Ajustes → Privacidad y seguridad → Bluetooth).")
        case .poweredOff: fail("Bluetooth está apagado.")
        case .unsupported: fail("este Mac no soporta Bluetooth LE.")
        default: break
        }
    }

    public func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([Self.service])
    }

    public func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        fail("no se pudo conectar: \(error?.localizedDescription ?? "?")")
    }

    public func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        writeChar = nil
        fail("el mouse se desconectó.")
    }

    // MARK: CBPeripheralDelegate

    public func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == Self.service }) else { return fail("el mouse no expone el servicio FEE0.") }
        p.discoverCharacteristics([Self.writeUUID, Self.notifyUUID], for: s)
    }

    public func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard let w = s.characteristics?.first(where: { $0.uuid == Self.writeUUID }),
              let n = s.characteristics?.first(where: { $0.uuid == Self.notifyUUID })
        else { return fail("faltan las características FEE3/FEE4.") }
        writeChar = w
        p.setNotifyValue(true, for: n)
    }

    public func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if let error { return fail("no se pudo suscribir a FEE4: \(error.localizedDescription)") }
        cond.lock(); ready = true; cond.broadcast(); cond.unlock()
    }

    public func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == Self.notifyUUID, let v = ch.value else { return }
        guard let ev = MouseEvent.parse([0x03] + [UInt8](v) + [0, 0, 0, 0]) else { return }
        if case .ack(let ok, let rid) = ev {
            cond.lock(); lastAck = (ok, rid); cond.broadcast(); cond.unlock()
        }
        if eventsEnabled, let handler = onEvent {
            eventRunLoop.perform { handler(ev) }
        }
    }

    public func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        cond.lock(); writeDone = .some(error); cond.broadcast(); cond.unlock()
    }

    // MARK: MouseConnection

    public func startEvents(on runLoop: RunLoop) {
        eventRunLoop = runLoop
        eventsEnabled = true
    }

    public func close() {
        eventsEnabled = false
        queue.sync {
            if let p = peripheral { central.cancelPeripheralConnection(p) }
        }
    }

    /// Escribe con respuesta en `FEE3` (CoreBluetooth hace la escritura larga si hace falta),
    /// espera el ACK y respeta los 500 ms entre comandos.
    @discardableResult
    public func send(_ packet: [UInt8], label: String) throws -> Bool {
        guard let p = peripheral, let w = writeChar else { throw MouseError.bluetooth("no hay conexión con el mouse.") }
        let start = Date()
        cond.lock(); writeDone = nil; lastAck = nil; cond.unlock()
        queue.async { p.writeValue(Data(packet), for: w, type: .withResponse) }

        let deadline = start.addingTimeInterval(3)
        cond.lock()
        while writeDone == nil && failure == nil {
            if !cond.wait(until: deadline) { cond.unlock(); throw MouseError.bluetooth("tiempo agotado al escribir «\(label)».") }
        }
        if let f = failure { cond.unlock(); throw MouseError.bluetooth(f) }
        if case .some(.some(let err)) = writeDone { cond.unlock(); throw MouseError.bluetooth("error al escribir «\(label)»: \(err.localizedDescription)") }
        let ackDeadline = Date().addingTimeInterval(0.5)
        while !(lastAck?.reportID == packet[0] && lastAck?.accepted == true) {
            if !cond.wait(until: ackDeadline) { break }
        }
        let acked = lastAck?.reportID == packet[0] && lastAck?.accepted == true
        cond.unlock()

        let remaining = 0.5 - Date().timeIntervalSince(start)
        if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
        return acked
    }
}
