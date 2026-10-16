import DeluxKit
import Foundation

let usage = """
deluxctl — configuración del DELUX M618XSD en macOS

  deluxctl info                         Detecta el mouse y el modo de conexión
  deluxctl dump [perfil.json]           Muestra los paquetes que se enviarían (no envía nada)
  deluxctl import-windows pro.data [salida.json]
                                        Convierte un perfil de DELUX Office Driver a JSON
  deluxctl apply perfil.json --yes      Envía el perfil al mouse
  deluxctl listen [segundos]            Muestra los eventos del mouse (DPI, batería, ACK…)

La CLI usa cable o receptor. Por Bluetooth usa la app (macOS exige un .app para Bluetooth):
  open -W "DELUX M618XSD.app" --args --apply perfil.json --log salida.txt

Sin perfil.json se usa el perfil seleccionado en la app (\(ProfileStore.fileURL.path)).
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
        fail("No se pudo leer \(path): \(error)")
    }
}

/// Ejecuta `work` en segundo plano mientras el hilo principal atiende el run loop (eventos HID).
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
        print("Encontrado: DELUX M618XSD — \(mouse.mode.rawValue)")
        mouse.close()
    } catch { fail("\(error)") }

case "dump":
    let profile = loadProfile(args.first)
    let errors = profile.validationErrors()
    if !errors.isEmpty { print("⚠️  Perfil inválido:\n- " + errors.joined(separator: "\n- ")) }
    do {
        for (label, bytes) in try Protocol.applySequence(profile) {
            print("\(label.padding(toLength: 26, withPad: " ", startingAt: 0)) \(bytes.hex)")
        }
    } catch { fail("\(error)") }

case "import-windows":
    guard let src = args.first else { fail("Falta la ruta a pro.data") }
    do {
        let profiles = try WindowsProfileImporter.importProfiles(from: URL(fileURLWithPath: src))
        guard !profiles.isEmpty else { fail("No hay perfiles en \(src)") }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if args.count > 1 {
            try enc.encode(profiles[0]).write(to: URL(fileURLWithPath: args[1]))
            print("Guardado «\(profiles[0].name)» en \(args[1]) (\(profiles.count) perfil(es) en el archivo).")
        } else {
            var store = ProfileStore.load()
            store.profiles.append(contentsOf: profiles)
            try store.save()
            print("Importados \(profiles.count) perfil(es) a \(ProfileStore.fileURL.path).")
        }
    } catch { fail("\(error)") }

case "apply":
    let path = args.first { !$0.hasPrefix("--") }
    guard args.contains("--yes") else {
        fail("Por seguridad, añade --yes para enviar. Usa «deluxctl dump» para revisar los paquetes antes.")
    }
    let profile = loadProfile(path)
    runWithRunLoop {
        do {
            let mouse = try MouseFinder.connect(includeBluetooth: false)
            mouse.startEvents()
            print("Aplicando «\(profile.name)» por \(mouse.mode.rawValue)…")
            try mouse.apply(profile) { label, i, n, acked in
                print("  [\(i)/\(n)] \(label) \(acked ? "✔ confirmado" : "· sin ACK")")
            }
            print("Listo.")
            mouse.close()
            return 0
        } catch {
            FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
            return 1
        }
    }

case "raw":
    // Diagnóstico: deluxctl raw 05 0f 01 … --yes  (envía un feature report tal cual y muestra el ACK)
    let hexBytes = args.filter { !$0.hasPrefix("--") }.compactMap { UInt8($0, radix: 16) }
    guard !hexBytes.isEmpty, args.contains("--yes") else { fail("Uso: deluxctl raw <bytes hex> --yes") }
    runWithRunLoop {
        do {
            let mouse = try MouseFinder.connect(includeBluetooth: false)
            mouse.onEvent = { if case .ack = $0 { print("  \($0)") } }
            mouse.startEvents()
            let acked = try mouse.send(hexBytes, label: "raw")
            Thread.sleep(forTimeInterval: 0.3)
            print("Enviados \(hexBytes.count) bytes: \(acked ? "✔ confirmado" : "· sin ACK")")
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
        mouse.onEvent = { print("Evento: \($0)") }
        mouse.startEvents()
        print("Escuchando \(Int(seconds)) s por \(mouse.mode.rawValue)… (pulsa el botón DPI para probar)")
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        mouse.close()
    } catch { fail("\(error)") }

default:
    print(usage)
    exit(1)
}
