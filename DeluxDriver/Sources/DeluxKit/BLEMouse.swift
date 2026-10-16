import CoreBluetooth
import Foundation

/// Bluetooth LE connection. The mouse (`BT5.2Mouse`, VID 0x045E / PID 0x0028) exposes the
/// `FEE0` service: commands are written to `FEE3` and replies arrive on `FEE4`
/// as `28 TT VV VV` (the same event as over USB, without report ID 0x03).
///
/// Requires a .app with `NSBluetoothAlwaysUsageDescription`; from a bare binary,
/// macOS kills the process when it uses CoreBluetooth.
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

    /// Finds the mouse among the connected Bluetooth peripherals and sets up `FEE3`/`FEE4`.
    /// Blocks up to `timeout`; do not call it from the Bluetooth queue.
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
            // The mouse is already connected to the system as HID; retrieve it by its services.
            let found = c.retrieveConnectedPeripherals(withServices: [Self.service, CBUUID(string: "180F")])
            guard let p = found.first(where: { ($0.name ?? "").hasPrefix("BT5.2Mouse") }) ?? found.first(where: { _ in found.count == 1 })
            else { return fail("notFound") }
            peripheral = p
            p.delegate = self
            c.connect(p)
        case .unauthorized: fail("permission denied (System Settings → Privacy & Security → Bluetooth).")
        case .poweredOff: fail("Bluetooth is off.")
        case .unsupported: fail("this Mac does not support Bluetooth LE.")
        default: break
        }
    }

    public func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([Self.service])
    }

    public func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        fail("could not connect: \(error?.localizedDescription ?? "?")")
    }

    public func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        writeChar = nil
        fail("the mouse disconnected.")
    }

    // MARK: CBPeripheralDelegate

    public func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == Self.service }) else { return fail("the mouse does not expose the FEE0 service.") }
        p.discoverCharacteristics([Self.writeUUID, Self.notifyUUID], for: s)
    }

    public func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard let w = s.characteristics?.first(where: { $0.uuid == Self.writeUUID }),
              let n = s.characteristics?.first(where: { $0.uuid == Self.notifyUUID })
        else { return fail("the FEE3/FEE4 characteristics are missing.") }
        writeChar = w
        p.setNotifyValue(true, for: n)
    }

    public func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if let error { return fail("could not subscribe to FEE4: \(error.localizedDescription)") }
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

    /// Writes with response to `FEE3` (CoreBluetooth does a long write if needed),
    /// waits for the ACK and keeps 500 ms between commands.
    @discardableResult
    public func send(_ packet: [UInt8], label: String) throws -> Bool {
        guard let p = peripheral, let w = writeChar else { throw MouseError.bluetooth("not connected to the mouse.") }
        let start = Date()
        cond.lock(); writeDone = nil; lastAck = nil; cond.unlock()
        queue.async { p.writeValue(Data(packet), for: w, type: .withResponse) }

        let deadline = start.addingTimeInterval(3)
        cond.lock()
        while writeDone == nil && failure == nil {
            if !cond.wait(until: deadline) { cond.unlock(); throw MouseError.bluetooth("timed out writing \"\(label)\".") }
        }
        if let f = failure { cond.unlock(); throw MouseError.bluetooth(f) }
        if case .some(.some(let err)) = writeDone { cond.unlock(); throw MouseError.bluetooth("error writing \"\(label)\": \(err.localizedDescription)") }
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
