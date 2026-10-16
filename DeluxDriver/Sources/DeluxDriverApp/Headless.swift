import DeluxKit
import Foundation

/// Windowless mode to apply a profile from Terminal, mainly over Bluetooth
/// (CoreBluetooth only works inside the .app):
///   open -W "DELUX M618XSD.app" --args --apply profile.json [--log output.txt]
enum Headless {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--apply"), i + 1 < args.count else { return }
        let logURL = args.firstIndex(of: "--log").flatMap { $0 + 1 < args.count ? URL(fileURLWithPath: args[$0 + 1]) : nil }
        var text = ""
        func log(_ s: String) {
            text += s + "\n"
            print(s)
            if let logURL { try? text.write(to: logURL, atomically: true, encoding: .utf8) }
        }
        do {
            let profile = try JSONDecoder().decode(MouseProfile.self, from: Data(contentsOf: URL(fileURLWithPath: args[i + 1])))
            let mouse = try MouseFinder.connect(bluetoothTimeout: 8)
            log("Applying \"\(profile.name)\" over \(mouse.mode.rawValue)…")
            try mouse.apply(profile) { label, n, total, acked in
                log("  [\(n)/\(total)] \(label) \(acked ? "✔ acknowledged" : "· no ACK")")
            }
            log("Done.")
            mouse.close()
            exit(0)
        } catch {
            log("Error: \(error)")
            exit(1)
        }
    }
}
