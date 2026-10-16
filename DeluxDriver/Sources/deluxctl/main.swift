import DeluxKit
import Foundation

let usage = """
deluxctl — DELUX M618XSD configuration on macOS

  deluxctl info                         Detect the mouse and the connection mode
  deluxctl dump [profile.json]          Print the packets that would be sent (sends nothing)
  deluxctl import-windows pro.data [output.json]
                                        Convert a DELUX Office Driver profile to JSON
  deluxctl apply profile.json --yes     Send the profile to the mouse
  deluxctl listen [seconds]             Print mouse events (DPI, battery, ACK…)

The CLI uses cable or receiver. For Bluetooth use the app (macOS requires a .app for Bluetooth):
  open -W "DELUX M618XSD.app" --args --apply profile.json --log output.txt

Without profile.json, the profile selected in the app is used (\(ProfileStore.fileURL.path)).
"""

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func loadProfile(_ path: String?) -> MouseProfile {
    guard let path else {
        let store = ProfileStore.load()
        return store.profiles[store.selected]
    }
    do {
        return try JSONDecoder().decode(MouseProfile.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    } catch {
        fail("Could not read \(path): \(error)")
    }
}

/// Runs `work` in the background while the main thread services the run loop (HID events).
func runWithRunLoop(_ work: @escaping @Sendable () -> Int32) -> Never {
    var code: Int32 = 0
    let done = DispatchSemaphore(value: 0)
    Thread.detachNewThread { code = work(); done.signal() }
    while done.wait(timeout: .now()) == .timedOut {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    exit(code)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { print(usage); exit(0) }
args.removeFirst()

switch command {
case "info":
    do {
        let mouse = try MouseFinder.connect(includeBluetooth: false)
        print("Found: DELUX M618XSD — \(mouse.mode.rawValue)")
        mouse.close()
    } catch { fail("\(error)") }

case "dump":
    let profile = loadProfile(args.first)
    let errors = profile.validationErrors()
    if !errors.isEmpty { print("⚠️  Invalid profile:\n- " + errors.joined(separator: "\n- ")) }
    do {
        for (label, bytes) in try Protocol.applySequence(profile) {
            print("\(label.padding(toLength: 26, withPad: " ", startingAt: 0)) \(bytes.hex)")
        }
    } catch { fail("\(error)") }

case "import-windows":
    guard let src = args.first else { fail("Missing path to pro.data") }
    do {
        let profiles = try WindowsProfileImporter.importProfiles(from: URL(fileURLWithPath: src))
        guard !profiles.isEmpty else { fail("No profiles in \(src)") }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if args.count > 1 {
            try enc.encode(profiles[0]).write(to: URL(fileURLWithPath: args[1]))
            print("Saved \"\(profiles[0].name)\" to \(args[1]) (\(profiles.count) profile(s) in the file).")
        } else {
            var store = ProfileStore.load()
            store.profiles.append(contentsOf: profiles)
            try store.save()
            print("Imported \(profiles.count) profile(s) into \(ProfileStore.fileURL.path).")
        }
    } catch { fail("\(error)") }

case "apply":
    let path = args.first { !$0.hasPrefix("--") }
    guard args.contains("--yes") else {
        fail("For safety, add --yes to send. Use \"deluxctl dump\" to review the packets first.")
    }
    let profile = loadProfile(path)
    runWithRunLoop {
        do {
            let mouse = try MouseFinder.connect(includeBluetooth: false)
            mouse.startEvents()
            print("Applying \"\(profile.name)\" over \(mouse.mode.rawValue)…")
            try mouse.apply(profile) { label, i, n, acked in
                print("  [\(i)/\(n)] \(label) \(acked ? "✔ acknowledged" : "· no ACK")")
            }
            print("Done.")
            mouse.close()
            return 0
        } catch {
            FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
            return 1
        }
    }

case "raw":
    // Diagnostics: deluxctl raw 05 0f 01 … --yes  (sends a feature report as is and prints the ACK)
    let hexBytes = args.filter { !$0.hasPrefix("--") }.compactMap { UInt8($0, radix: 16) }
    guard !hexBytes.isEmpty, args.contains("--yes") else { fail("Usage: deluxctl raw <hex bytes> --yes") }
    runWithRunLoop {
        do {
            let mouse = try MouseFinder.connect(includeBluetooth: false)
            mouse.onEvent = { if case .ack = $0 { print("  \($0)") } }
            mouse.startEvents()
            let acked = try mouse.send(hexBytes, label: "raw")
            Thread.sleep(forTimeInterval: 0.3)
            print("Sent \(hexBytes.count) bytes: \(acked ? "✔ acknowledged" : "· no ACK")")
            mouse.close()
            return 0
        } catch {
            FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
            return 1
        }
    }

case "listen":
    let seconds = args.first.flatMap(Double.init) ?? 30
    do {
        let mouse = try MouseFinder.connect(includeBluetooth: false)
        mouse.onEvent = { print("Event: \($0)") }
        mouse.startEvents()
        print("Listening for \(Int(seconds)) s over \(mouse.mode.rawValue)… (press the DPI button to test)")
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        mouse.close()
    } catch { fail("\(error)") }

default:
    print(usage)
    exit(1)
}
