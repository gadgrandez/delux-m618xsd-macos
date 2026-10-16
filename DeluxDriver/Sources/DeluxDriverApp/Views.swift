import AppKit
import DeluxKit
import SwiftUI

@main
struct DeluxDriverApp: App {
    @StateObject private var model = AppModel()

    init() {
        Headless.runIfRequested()
        // Necesario al ejecutar el binario fuera de un .app (swift run).
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("DELUX M618XSD") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
    }
}

extension RGB {
    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(UInt8((c.redComponent * 255).rounded()), UInt8((c.greenComponent * 255).rounded()),
                  UInt8((c.blueComponent * 255).rounded()))
    }
}

extension Binding where Value == RGB {
    var color: Binding<Color> {
        Binding<Color>(get: { wrappedValue.color }, set: { wrappedValue = RGB($0) })
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TabView {
                DPIView().tabItem { Text("DPI") }
                ButtonsView().tabItem { Text("Botones") }
                LightingView().tabItem { Text("Iluminación") }
                PerformanceView().tabItem { Text("Rendimiento") }
            }
            .padding()
        }
        .alert(model.message ?? "", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("Perfil", selection: $model.store.selected) {
                ForEach(model.store.profiles.indices, id: \.self) { i in
                    Text(model.store.profiles[i].name).tag(i)
                }
            }
            .frame(maxWidth: 260)

            Menu("Perfiles") {
                Button("Nuevo") { model.addProfile() }
                Button("Duplicar") { model.duplicateProfile() }
                Button("Restablecer valores de fábrica") { model.resetProfile() }
                Divider()
                Button("Importar de Windows (pro.data)…") { model.importWindowsProfile() }
                Button("Importar JSON…") { model.importJSONProfile() }
                Button("Exportar JSON…") { model.exportProfile() }
                Divider()
                Button("Eliminar", role: .destructive) { model.deleteProfile() }
            }
            .fixedSize()

            TextField("Nombre", text: $model.profile.name)
                .frame(maxWidth: 160)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let mode = model.connection {
                    Label(mode.rawValue, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Label("Mouse no detectado", systemImage: "xmark.circle").foregroundStyle(.secondary)
                }
                if let b = model.battery { Text("Batería: \(b)").font(.caption).foregroundStyle(.secondary) }
            }

            if let step = model.applying {
                ProgressView().controlSize(.small)
                Text(step).font(.caption).frame(width: 150, alignment: .leading)
            } else {
                Button("Aplicar") { model.apply() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.connection == nil)
            }
        }
        .padding()
    }
}

struct DPIView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("Niveles de DPI") {
                ForEach(0..<MouseProfile.stageCount, id: \.self) { i in
                    let stage = $model.profile.dpiStages[i]
                    HStack {
                        Toggle("", isOn: Binding(get: { stage.wrappedValue.enabled }, set: { on in
                            stage.wrappedValue.enabled = on
                            if on && stage.wrappedValue.dpi < 40 { stage.wrappedValue.dpi = 800 }
                        })).labelsHidden()
                        Text("Nivel \(i + 1)").frame(width: 60, alignment: .leading)
                        Slider(value: Binding(get: { Double(max(stage.wrappedValue.dpi, 40)) },
                                              set: { stage.wrappedValue.dpi = Int($0 / 40) * 40 }),
                               in: 40...4800, step: 40)
                            .disabled(!stage.wrappedValue.enabled)
                        Text("\(stage.wrappedValue.dpi) DPI").monospacedDigit().frame(width: 80, alignment: .trailing)
                        ColorPicker("", selection: stage.color.color, supportsOpacity: false).labelsHidden()
                        Button {
                            model.profile.activeStage = i
                        } label: {
                            Image(systemName: model.profile.activeStage == i ? "largecircle.fill.circle" : "circle")
                        }
                        .buttonStyle(.plain)
                        .help("Nivel activo al aplicar")
                        .disabled(!stage.wrappedValue.enabled)
                    }
                }
            }
            if let live = model.liveStage {
                Text("El mouse informa que está en el nivel \(live).").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct ButtonsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                ForEach(ButtonFunction.physicalSlots, id: \.self) { slot in
                    ButtonRow(slot: slot, assignment: $model.profile.buttons[slot])
                }
            } header: {
                Text("Asignación de botones")
            } footer: {
                Text("Los atajos «macOS» envían Cmd (⌘) desde el propio mouse. Las macros solo se editan por JSON (experimental).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct ButtonRow: View {
    let slot: Int
    @Binding var assignment: ButtonAssignment

    private var selectionKey: String {
        switch assignment {
        case .function(let id): return "f\(id)"
        case .shortcut(let m, let k):
            if let i = MacShortcut.presets.firstIndex(where: { $0.modifiers == m && $0.key == k }) { return "s\(i)" }
            return "custom"
        case .macro: return "macro"
        }
    }

    var body: some View {
        HStack {
            Text(ButtonFunction.slotName(slot)).frame(width: 150, alignment: .leading)
            Picker("", selection: Binding(get: { selectionKey }, set: apply)) {
                ForEach(Array(Dictionary(grouping: ButtonFunction.all, by: \.group).sorted { $0.key < $1.key }), id: \.key) { group, items in
                    Section(group) {
                        ForEach(items, id: \.id) { Text($0.name).tag("f\($0.id)") }
                    }
                }
                Section("Atajos de macOS") {
                    ForEach(MacShortcut.presets.indices, id: \.self) { Text(MacShortcut.presets[$0].name).tag("s\($0)") }
                }
                if case .shortcut = assignment, selectionKey == "custom" { Text("Atajo personalizado").tag("custom") }
                if case .macro(let m) = assignment { Text("Macro: \(m.name)").tag("macro") }
            }
            .labelsHidden()
        }
    }

    private func apply(_ key: String) {
        if key.hasPrefix("f"), let id = UInt8(key.dropFirst()) {
            assignment = .function(id)
        } else if key.hasPrefix("s"), let i = Int(key.dropFirst()) {
            let p = MacShortcut.presets[i]
            assignment = .shortcut(modifiers: p.modifiers, key: p.key)
        }
    }
}

struct LightingView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let light = $model.profile.lighting
        Form {
            Section("Iluminación") {
                Picker("Modo", selection: light.mode) {
                    ForEach(LightMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                ColorPicker("Color", selection: light.color.color, supportsOpacity: false)
                LabeledContent("Brillo") {
                    Slider(value: intBinding(light.brightness), in: 1...8, step: 1)
                    Text("\(light.wrappedValue.brightness)").monospacedDigit().frame(width: 24)
                }
                LabeledContent("Velocidad") {
                    Slider(value: intBinding(light.speed), in: 4...8, step: 1)
                    Text("\(light.wrappedValue.speed)").monospacedDigit().frame(width: 24)
                }
                Toggle("Apagar la luz mientras el mouse se mueve", isOn: light.offWhileMoving)
            }
        }
        .formStyle(.grouped)
    }
}

struct PerformanceView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("Tasa de sondeo") {
                Picker("Polling", selection: $model.profile.pollingRate) {
                    Text("125 Hz (ahorro)").tag(PollingRate.hz125)
                    Text("250 Hz (oficina)").tag(PollingRate.hz250)
                    Text("500 Hz (juego)").tag(PollingRate.hz500)
                    Text("1000 Hz (e-sports)").tag(PollingRate.hz1000)
                }
                .pickerStyle(.segmented)
                if model.connection == .bluetooth {
                    Text("Por Bluetooth el mouse no admite cambiar la tasa de sondeo; se aplica por cable o receptor.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Respuesta de los botones") {
                LabeledContent("Tiempo de respuesta") {
                    Slider(value: intBinding($model.profile.debounce), in: 1...25, step: 1)
                    Text("\(model.profile.debounce)").monospacedDigit().frame(width: 24)
                }
            }
            Section("Energía") {
                LabeledContent("Apagar luz tras") {
                    Slider(value: intBinding($model.profile.power.lightOffMinutes), in: 1...60, step: 1)
                    Text("\(model.profile.power.lightOffMinutes) min").monospacedDigit().frame(width: 56)
                }
                LabeledContent("Suspender tras") {
                    Slider(value: intBinding($model.profile.power.sleepMinutes), in: 1...60, step: 1)
                    Text("\(model.profile.power.sleepMinutes) min").monospacedDigit().frame(width: 56)
                }
            }
        }
        .formStyle(.grouped)
    }
}

func intBinding(_ b: Binding<Int>) -> Binding<Double> {
    Binding<Double>(get: { Double(b.wrappedValue) }, set: { b.wrappedValue = Int($0.rounded()) })
}
