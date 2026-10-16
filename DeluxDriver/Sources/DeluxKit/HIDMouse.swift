import Foundation
import IOKit
import IOKit.hid

/// Event the mouse sends in input report 0x03 (collection on usage page 0x0A).
public enum MouseEvent: Equatable, Sendable {
    case dpiStageChanged(stage: Int)
    case pollingChanged(raw: Int)
    case battery(percent: Int)
    case charging
    case ack(accepted: Bool, reportID: UInt8)
    case lightModeChanged(raw: Int)
    case other(type: UInt8, value: UInt16)

    /// `report` includes the report ID in byte 0: `03 28 TT VV VV`.
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
    case wired = "USB cable"
    case receiver = "2.4G receiver"
    case bluetooth = "Bluetooth"
}

/// Connection to the mouse, either over HID (cable/receiver) or Bluetooth LE.
public protocol MouseConnection: AnyObject, Sendable {
    var mode: ConnectionMode { get }
    /// Mouse events (DPI, battery, ACK…).
    var onEvent: ((MouseEvent) -> Void)? { get set }
    func startEvents(on runLoop: RunLoop)
    func close()
    /// Sends a configuration packet; returns true if the mouse acknowledged it.
    @discardableResult func send(_ packet: [UInt8], label: String) throws -> Bool
}

public extension MouseConnection {
    /// Applies a full profile. Blocks for several seconds: call it off the main thread.
    /// `progress` receives (step, index, total, acknowledged?) after each step is sent.
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

/// Looks for the mouse over cable, Bluetooth and receiver, in that order. The receiver may stay
/// plugged in while the mouse is in Bluetooth mode, so Bluetooth goes first if macOS sees it connected.
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
        case .notFound: return "M618XSD not found (cable 1d57:fa28, receiver 1d57:fa60 or Bluetooth \"BT5.2Mouse\")."
        case .openFailed(let r): return "Could not open the HID device (IOReturn 0x\(String(UInt32(bitPattern: r), radix: 16)))."
        case .sendFailed(let l, let r): return "Failed to send \"\(l)\" (IOReturn 0x\(String(UInt32(bitPattern: r), radix: 16)))."
        case .noAck(let l): return "The mouse did not acknowledge \"\(l)\" after 10 attempts."
        case .invalidProfile(let e): return "Invalid profile:\n- " + e.joined(separator: "\n- ")
        case .bluetooth(let m): return "Bluetooth: \(m)"
        }
    }
}

/// Connection to the M618XSD through IOKit. The configuration and event channels
/// are collections of the same `IOHIDDevice` (interface MI_02).
public final class HIDMouse: MouseConnection, @unchecked Sendable {
    public let mode: ConnectionMode
    private let device: IOHIDDevice
    private let manager: IOHIDManager
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private let ackLock = NSCondition()
    /// Last ACK received: (accepted, acknowledged report ID).
    private var lastAck: (accepted: Bool, reportID: UInt8)?

    /// Called on the run loop where events were scheduled.
    public var onEvent: ((MouseEvent) -> Void)?

    deinit { inputBuffer.deallocate() }

    private init(device: IOHIDDevice, manager: IOHIDManager, mode: ConnectionMode) {
        self.device = device
        self.manager = manager
        self.mode = mode
    }

    /// Finds the mouse: cable first, then the receiver.
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

    /// true if the mouse is connected to the system over Bluetooth (HID with VID 0x045E / PID 0x0028).
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

    /// Starts receiving events on `runLoop` (the main one in the app; the current one in the CLI).
    public func startEvents(on runLoop: RunLoop) {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, 64, { ctx, _, _, _, reportID, report, length in
                guard let ctx else { return }
                let me = Unmanaged<HIDMouse>.fromOpaque(ctx).takeUnretainedValue()
                var bytes = Array(UnsafeBufferPointer(start: report, count: length))
                // Depending on the driver, the report ID may or may not be at the start of the buffer.
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

    /// Sends a feature report as is (byte 0 = report ID).
    public func sendRaw(_ packet: [UInt8], label: String = "report") throws {
        let r = packet.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(packet[0]), $0.baseAddress!, $0.count)
        }
        guard r == kIOReturnSuccess else { throw MouseError.sendFailed(label: label, r) }
    }

    /// Waits up to `timeout` for an accepted ACK of report `reportID`.
    private func waitAck(for reportID: UInt8, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        ackLock.lock(); defer { ackLock.unlock() }
        while !(lastAck?.reportID == reportID && lastAck?.accepted == true) {
            if !ackLock.wait(until: deadline) { return false }
        }
        return true
    }

    /// Sends a packet with the same strategy as the Windows app:
    /// over cable, one write and up to 500 ms of waiting; over the receiver, up to 10 writes
    /// every 500 ms until the ACK arrives.
    /// Returns true if the mouse acknowledged the command.
    @discardableResult
    public func send(_ packet: [UInt8], label: String) throws -> Bool {
        let attempts = mode == .wired ? 1 : 10
        for _ in 0..<attempts {
            ackLock.lock(); lastAck = nil; ackLock.unlock()
            let start = Date()
            try sendRaw(packet, label: label)
            let acked = waitAck(for: packet[0], timeout: 0.5)
            // Like the Windows app: 500 ms between commands even if the ACK arrives earlier;
            // otherwise the mouse drops the next one while it stores the previous one.
            let remaining = 0.5 - Date().timeIntervalSince(start)
            if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
            if acked || mode == .wired { return acked }
        }
        throw MouseError.noAck(label: label)
    }
}
