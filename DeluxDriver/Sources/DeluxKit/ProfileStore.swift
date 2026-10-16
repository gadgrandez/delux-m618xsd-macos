import Foundation

/// Lectura de `Data/ms_4/pro.data` de DELUX Office Driver: 4 bytes de cabecera y
/// perfiles de 0x80E4 bytes (offsets tomados de `Mouse.exe`).
public enum WindowsProfileImporter {
    static let header = 4
    static let profileSize = 0x80e4
    static let keyBase = 0x9a4
    static let keyStride = 0x4f8

    public static func importProfiles(from url: URL) throws -> [MouseProfile] {
        let data = try Data(contentsOf: url)
        let b = [UInt8](data)
        var result: [MouseProfile] = []
        var offset = header
        while offset + profileSize <= b.count {
            let p = Array(b[offset..<offset + profileSize])
            offset += profileSize
            let name = String(decoding: stride(from: 0, to: 64, by: 2).map { UInt16(p[$0]) | UInt16(p[$0 + 1]) << 8 }
                .prefix { $0 != 0 }, as: UTF16.self)
            // Los perfiles vacíos tienen todo a cero.
            guard !name.isEmpty else { continue }
            result.append(parse(p, name: name))
        }
        return result
    }

    static func i32(_ p: [UInt8], _ o: Int) -> Int {
        Int(Int32(bitPattern: UInt32(p[o]) | UInt32(p[o + 1]) << 8 | UInt32(p[o + 2]) << 16 | UInt32(p[o + 3]) << 24))
    }

    static func parse(_ p: [UInt8], name: String) -> MouseProfile {
        let stages = (0..<8).map { i in
            DPIStage(enabled: i32(p, 0x904 + 4 * i) == 1,
                     dpi: i32(p, 0x8c4 + 4 * i) * 40,
                     color: RGB(p[0x964 + 4 * i], p[0x965 + 4 * i], p[0x966 + 4 * i]))
        }
        let rates: [PollingRate] = [.hz125, .hz250, .hz500, .hz1000]
        let buttons: [ButtonAssignment] = (0..<MouseProfile.slotCount).map { slot in
            let k = keyBase + slot * keyStride
            let id = p[k + 1]
            switch id {
            case ButtonFunction.customShortcut:
                return .shortcut(modifiers: p[k + 7], key: p[k + 3])
            case ButtonFunction.macro:
                let n = Int(UInt16(p[k + 0x44]) | UInt16(p[k + 0x45]) << 8)
                let events = (0..<min(n, 100)).map { e -> MacroEvent in
                    let o = k + 0x440 + e * 4
                    return MacroEvent(key: p[o], pressed: p[o + 1] == 1, delayMs: Int(UInt16(p[o + 2]) | UInt16(p[o + 3]) << 8))
                }
                return .macro(Macro(name: "Macro ranura \(slot + 1)", repeatMode: p[k + 0xc],
                                    repeatCount: p[k + 0x43c], events: events))
            default:
                return .function(id)
            }
        }
        return MouseProfile(
            name: name,
            dpiStages: stages,
            activeStage: min(max(i32(p, 0x934), 0), 7),
            pollingRate: rates[min(max(i32(p, 0x938), 0), 3)],
            lighting: Lighting(mode: LightMode(rawValue: i32(p, 0x94c)) ?? .off,
                               color: RGB(p[0x960], p[0x961], p[0x962]),
                               brightness: i32(p, 0x924),
                               speed: i32(p, 0x928),
                               offWhileMoving: i32(p, 0x950) == 0),
            power: Power(lightOffMinutes: i32(p, 0x930), sleepMinutes: i32(p, 0x92c)),
            debounce: i32(p, 0x95c),
            buttons: buttons
        )
    }
}

/// Perfiles guardados en `~/Library/Application Support/DeluxDriver/profiles.json`.
public struct ProfileStore: Codable, Equatable, Sendable {
    public var profiles: [MouseProfile]
    public var selected: Int

    public init(profiles: [MouseProfile], selected: Int) {
        self.profiles = profiles
        self.selected = selected
    }

    public static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeluxDriver", isDirectory: true)
        return dir.appendingPathComponent("profiles.json")
    }

    public static func load() -> ProfileStore {
        if let data = try? Data(contentsOf: fileURL),
           let store = try? JSONDecoder().decode(ProfileStore.self, from: data), !store.profiles.isEmpty {
            return store
        }
        return ProfileStore(profiles: [.factoryDefault], selected: 0)
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: Self.fileURL, options: .atomic)
    }
}
