import Foundation
@testable import DeluxKit

// Ejecutable de pruebas: este toolchain (Command Line Tools) no incluye XCTest ni Swift Testing.
var failures = 0
var current = ""
func expect(_ ok: @autoclosure () -> Bool, _ comment: String = "", line: Int = #line) {
    if !ok() { failures += 1; print("  ✘ \(current) (línea \(line)) \(comment)") }
}
struct Comment { let rawValue: String }
func expect(_ ok: @autoclosure () -> Bool, _ c: Comment, line: Int = #line) { expect(ok(), c.rawValue, line: line) }


struct ProtocolTests {
    /// `reference/windows-driver/ms_4_pro.data`, perfil de fábrica exportado de DELUX Office Driver.
    static var windowsProfile: MouseProfile {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("reference/windows-driver/ms_4_pro.data")
        let profiles = try! WindowsProfileImporter.importProfiles(from: url)
        precondition(profiles.count == 1)
        return profiles[0]
    }

    func testImportMatchesFactoryDefault() {
        var imported = Self.windowsProfile
        expect(imported.name == "Profile1")
        imported.name = MouseProfile.factoryDefault.name
        expect(imported == MouseProfile.factoryDefault)
        expect(imported.validationErrors() == [])
    }

    func testPacketLengthsMatchDescriptor() throws {
        for (label, bytes) in try Protocol.applySequence(.factoryDefault) {
            expect(bytes.count == Protocol.reportLength[bytes[0]], Comment(rawValue: label))
        }
    }

    func testDPIPacket() {
        let b = Protocol.dpiPacket(Self.windowsProfile)
        expect(Array(b[0...7]) == [0x04, 0x38, 0x01, 0x00, 0x00, 0x1f, 0x10, 0x10])
        // 800, 1200, 1800, 2400, 4000 DPI; los niveles 6–8 están desactivados (0).
        expect(Array(b[8...15]) == [0x20, 0xb0, 0x08, 0x60, 0xa0, 0, 0, 0])
        expect(Array(b[16...23]) == [0x03, 0x04, 0x07, 0x09, 0x0f, 0, 0, 0])
        expect(b[24] == 4)
        expect(Array(b[25...27]) == [0xff, 0, 0])
        expect(b[49] == 0x02)
        let sum = b[3..<50].reduce(0) { $0 + Int($1) }
        expect(Int(b[50]) << 8 | Int(b[51]) == sum)
    }

    func testOptionsPacket() {
        // Brillo 8, velocidad 6, suspensión 10, apagado 1, debounce 1, modo 0, color azul.
        expect(Protocol.optionsPacket(Self.windowsProfile) == [0x05, 0x0f, 0x01, 0x80, 0x03, 0xa8, 0x00, 0x00, 0xff, 0x01, 0x01, 0x02, 0x2c])
    }

    func testOptionsPacketSplitsSleepAcrossNibbles() {
        var p = MouseProfile.factoryDefault
        p.power.sleepMinutes = 60 // 0x3c
        p.lighting.offWhileMoving = true
        p.lighting.mode = .staticColor
        let b = Protocol.optionsPacket(p)
        expect(b[3] == 0x05)
        expect(b[4] == 0x30 | 3)
        expect(b[5] == 0xc0 | 8)
    }

    func testPollingPacket() {
        var p = MouseProfile.factoryDefault
        expect(Protocol.pollingPacket(p) == [0x06, 0x09, 0x01, 0x01, 0xfe, 0, 0, 0, 0])
        p.pollingRate = .hz125
        expect(Protocol.pollingPacket(p) == [0x06, 0x09, 0x01, 0x08, 0xf7, 0, 0, 0, 0])
    }

    func testButtonsPacket() {
        var p = MouseProfile.factoryDefault
        p.buttons[2] = .shortcut(modifiers: 8, key: 0x06)
        p.buttons[3] = .macro(Macro(name: "m", events: []))
        let b = Protocol.buttonsPacket(p)
        expect(Array(b[0...2]) == [0x08, 0x3b, 0x01])
        expect(Array(b[3...5]) == [2, 0, 0])            // clic izquierdo (ID 1)
        expect(Array(b[6...8]) == [3, 0, 0])            // clic derecho (ID 2)
        expect(Array(b[9...11]) == [0x11, 8, 0x06])     // ⌘C
        expect(Array(b[12...14]) == [0x12, 0, 4])       // macro en la ranura 4
        expect(Array(b[15...17]) == [4, 0, 0])          // central (ID 3)
        expect(Array(b[18...20]) == [13, 0, 0])         // ciclo de DPI (ID 6)
        expect(Array(b[21...23]) == [1, 0, 0])          // ranura sin uso (ID 0)
        let sum = b[3..<57].reduce(0) { $0 + Int($1) }
        expect(Int(b[57]) << 8 | Int(b[58]) == sum)
    }

    func testMacroPackets() throws {
        let m = Macro(name: "A", repeatMode: 1, repeatCount: 2, events: [
            MacroEvent(key: 0x04, pressed: true, delayMs: 50),
            MacroEvent(key: 0x04, pressed: false, delayMs: 2000),
        ])
        let pkts = try Protocol.macroPackets(m, slot: 5)
        expect(pkts.count == 3)
        expect(pkts.allSatisfy { $0.count == 64 && $0[0] == 0x09 && $0[1] == 0x40 && $0[2] == 6 })
        expect(pkts.map { $0[3] } == [0, 1, 2])
        // Bloque lógico: byte 3 → pkts[0][4]. 2000 ms = 10 × 200 → par extra [10, 3].
        expect(Array(pkts[0][4...8]) == [1, 2, 2, 2, 1])
        expect(pkts[0][4 + 25] == 3) // cantidad de pares
        expect(Array(pkts[0][4 + 26...4 + 31]) == [5 | 1, 0x04, 1 | 0x81, 0x04, 10, 3])
    }

    func testMacroTooLongIsRejected() {
        let events = (0..<60).map { MacroEvent(key: 4, pressed: $0 % 2 == 0, delayMs: 10) }
        var p = MouseProfile.factoryDefault
        p.buttons[2] = .macro(Macro(name: "larga", events: events))
        expect(!(p.validationErrors().isEmpty))
    }

    func testValidationRequiresLeftClick() {
        var p = MouseProfile.factoryDefault
        p.buttons[0] = .function(2)
        expect(p.validationErrors().contains { $0.contains("Clic izquierdo") })
    }

    func testBluetoothSequence() throws {
        var p = MouseProfile.factoryDefault
        p.buttons[2] = .macro(Macro(name: "m", events: [MacroEvent(key: 4, pressed: true, delayMs: 10)]))
        let seq = try Protocol.applySequence(p, for: .bluetooth)
        // Largo = byte 1 de cada paquete; sin polling; la macro va en un solo bloque de 131 bytes.
        expect(seq.map { $0.bytes.count } == [10, 56, 15, 59, 131])
        expect(seq.allSatisfy { Int($0.bytes[1]) == $0.bytes.count })
        expect(!seq.contains { $0.bytes[0] == 0x06 })
        let hid = try Protocol.applySequence(p, for: .wired)
        expect(Array(seq[1].bytes.prefix(52)) == hid[1].bytes)
    }

    func testEventParsing() {
        expect(MouseEvent.parse([0x03, 0x28, 0x50, 0x00, 0x00]) == .ack(accepted: true, reportID: 0))
        expect(MouseEvent.parse([0x03, 0x28, 0x50, 0x00, 0x04]) == .ack(accepted: true, reportID: 4))
        expect(MouseEvent.parse([0x03, 0x28, 0x10, 0x03, 0x00]) == .dpiStageChanged(stage: 3))
        expect(MouseEvent.parse([0x03, 0x28, 0x40, 0x00, 0x55]) == .battery(percent: 0x55))
        expect(MouseEvent.parse([0x03, 0x28, 0x40, 0x02, 0x00]) == .charging)
        expect(MouseEvent.parse([0x03, 0x21, 0x50, 0x00, 0x00]) == nil)
    }
}

let suite = ProtocolTests()
current = "testImportMatchesFactoryDefault"; suite.testImportMatchesFactoryDefault()
current = "testPacketLengthsMatchDescriptor"; try! suite.testPacketLengthsMatchDescriptor()
current = "testDPIPacket"; suite.testDPIPacket()
current = "testOptionsPacket"; suite.testOptionsPacket()
current = "testOptionsPacketSplitsSleepAcrossNibbles"; suite.testOptionsPacketSplitsSleepAcrossNibbles()
current = "testPollingPacket"; suite.testPollingPacket()
current = "testButtonsPacket"; suite.testButtonsPacket()
current = "testMacroPackets"; try! suite.testMacroPackets()
current = "testMacroTooLongIsRejected"; suite.testMacroTooLongIsRejected()
current = "testValidationRequiresLeftClick"; suite.testValidationRequiresLeftClick()
current = "testBluetoothSequence"; try! suite.testBluetoothSequence()
current = "testEventParsing"; suite.testEventParsing()
print(failures == 0 ? "✔ \(12) pruebas OK" : "✘ \(failures) fallo(s)")
exit(failures == 0 ? 0 : 1)
