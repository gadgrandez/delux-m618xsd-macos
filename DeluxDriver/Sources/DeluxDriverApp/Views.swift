import AppKit
import DeluxKit
import SwiftUI

@main
struct DeluxDriverApp: App {
    @StateObject private var model = AppModel()

    init() {
        Headless.runIfRequested()
        // Needed when running the binary outside a .app (swift run).
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
                ButtonsView().tabItem { Text("Buttons") }
                LightingView().tabItem { Text("Lighting") }
                PerformanceView().tabItem { Text("Performance") }
            }
            .padding()
        }
        .alert(model.message ?? "", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("Profile", selection: $model.store.selected) {
                ForEach(model.store.profiles.indices, id: \.self) { i in
                    Text(model.store.profiles[i].name).tag(i)
                }
            }
            .frame(maxWidth: 260)

            Menu("Profiles") {
                Button("New") { model.addProfile() }
                Button("Duplicate") { model.duplicateProfile() }
                Button("Reset to factory defaults") { model.resetProfile() }
                Divider()
                Button("Import from Windows (pro.data)…") { model.importWindowsProfile() }
                Button("Import JSON…") { model.importJSONProfile() }
                Button("Export JSON…") { model.exportProfile() }
                Divider()
                Button("Delete", role: .destructive) { model.deleteProfile() }
            }
            .fixedSize()

            TextField("Name", text: $model.profile.name)
                .frame(maxWidth: 160)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let mode = model.connection {
                    Label(mode.rawValue, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Label("Mouse not detected", systemImage: "xmark.circle").foregroundStyle(.secondary)
                }
                if let b = model.battery { Text("Battery: \(b)").font(.caption).foregroundStyle(.secondary) }
            }

            if let step = model.applying {
                ProgressView().controlSize(.small)
                Text(step).font(.caption).frame(width: 150, alignment: .leading)
            } else {
                Button("Apply") { model.apply() }
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
            Section("DPI stages") {
                ForEach(0..<MouseProfile.stageCount, id: \.self) { i in
                    let stage = $model.profile.dpiStages[i]
                    HStack {
                        Toggle("", isOn: Binding(get: { stage.wrappedValue.enabled }, set: { on in
                            stage.wrappedValue.enabled = on
                            if on && stage.wrappedValue.dpi < 40 { stage.wrappedValue.dpi = 800 }
                        })).labelsHidden()
                        Text("Stage \(i + 1)").frame(width: 60, alignment: .leading)
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
                        .help("Active stage after applying")
                        .disabled(!stage.wrappedValue.enabled)
                    }
                }
            }
            if let live = model.liveStage {
                Text("The mouse reports it is on stage \(live).").font(.caption).foregroundStyle(.secondary)
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
                Text("Button assignment")
            } footer: {
                Text("macOS shortcuts send Cmd (⌘) from the mouse itself. Macros can only be edited as JSON (experimental).")
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
                ForEach(ButtonFunction.groups, id: \.self) { group in
                    Section(group) {
                        ForEach(ButtonFunction.all.filter { $0.group == group }, id: \.id) { Text($0.name).tag("f\($0.id)") }
                    }
                }
                Section("macOS shortcuts") {
                    ForEach(MacShortcut.presets.indices, id: \.self) { Text(MacShortcut.presets[$0].name).tag("s\($0)") }
                }
                if case .shortcut = assignment, selectionKey == "custom" { Text("Custom shortcut").tag("custom") }
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
            Section("Lighting") {
                Picker("Mode", selection: light.mode) {
                    ForEach(LightMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                ColorPicker("Color", selection: light.color.color, supportsOpacity: false)
                LabeledContent("Brightness") {
                    Slider(value: intBinding(light.brightness), in: 1...8, step: 1)
                    Text("\(light.wrappedValue.brightness)").monospacedDigit().frame(width: 24)
                }
                LabeledContent("Speed") {
                    Slider(value: intBinding(light.speed), in: 4...8, step: 1)
                    Text("\(light.wrappedValue.speed)").monospacedDigit().frame(width: 24)
                }
                Toggle("Turn the light off while the mouse moves", isOn: light.offWhileMoving)
            }
        }
        .formStyle(.grouped)
    }
}

struct PerformanceView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("Polling rate") {
                Picker("Polling", selection: $model.profile.pollingRate) {
                    Text("125 Hz (power saving)").tag(PollingRate.hz125)
                    Text("250 Hz (office)").tag(PollingRate.hz250)
                    Text("500 Hz (gaming)").tag(PollingRate.hz500)
                    Text("1000 Hz (e-sports)").tag(PollingRate.hz1000)
                }
                .pickerStyle(.segmented)
                if model.connection == .bluetooth {
                    Text("Over Bluetooth the mouse does not allow changing the polling rate; apply it over cable or receiver.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Button response") {
                LabeledContent("Response time") {
                    Slider(value: intBinding($model.profile.debounce), in: 1...25, step: 1)
                    Text("\(model.profile.debounce)").monospacedDigit().frame(width: 24)
                }
            }
            Section("Power") {
                LabeledContent("Light off after") {
                    Slider(value: intBinding($model.profile.power.lightOffMinutes), in: 1...60, step: 1)
                    Text("\(model.profile.power.lightOffMinutes) min").monospacedDigit().frame(width: 56)
                }
                LabeledContent("Sleep after") {
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
