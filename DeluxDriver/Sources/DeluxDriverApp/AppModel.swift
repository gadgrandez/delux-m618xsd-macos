import AppKit
import DeluxKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var store: ProfileStore = .load() {
        didSet { try? store.save() }
    }
    @Published private(set) var connection: ConnectionMode?
    @Published private(set) var battery: String?
    @Published private(set) var liveStage: Int?
    @Published private(set) var applying: String?
    @Published var message: String?

    private var mouse: MouseConnection?
    private var searching = false
    private var timer: Timer?

    var profile: MouseProfile {
        get { store.profiles[store.selected] }
        set { store.profiles[store.selected] = newValue }
    }

    init() {
        connect()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.connect() }
        }
    }

    /// Tries to connect if there is no mouse (cable → Bluetooth → receiver). The Bluetooth search
    /// takes a few seconds, so it runs in the background.
    func connect() {
        guard mouse == nil, applying == nil, !searching else { return }
        searching = true
        Thread.detachNewThread { [weak self] in
            let found = try? MouseFinder.connect()
            Task { @MainActor in
                guard let self else { return }
                self.searching = false
                guard let m = found else { self.connection = nil; return }
                m.onEvent = { [weak self] ev in
                    Task { @MainActor in self?.handle(ev) }
                }
                m.startEvents()
                self.mouse = m
                self.connection = m.mode
            }
        }
    }

    private func handle(_ ev: MouseEvent) {
        switch ev {
        case .battery(let pct): battery = "\(pct) %"
        case .charging: battery = "Charging"
        case .dpiStageChanged(let s): liveStage = s
        default: break
        }
    }

    private func dropConnection() {
        mouse?.close()
        mouse = nil
        connection = nil
    }

    func apply() {
        let errors = profile.validationErrors()
        guard errors.isEmpty else {
            message = "Cannot apply:\n• " + errors.joined(separator: "\n• ")
            return
        }
        guard let mouse else {
            message = MouseError.notFound.description
            return
        }
        let profile = self.profile
        applying = "Preparing…"
        Thread.detachNewThread { [weak self] in
            var failure: String?
            do {
                try mouse.apply(profile) { label, i, n, _ in
                    Task { @MainActor in self?.applying = "\(label) (\(i)/\(n))" }
                }
            } catch {
                failure = "\(error)"
            }
            Task { @MainActor in
                guard let self else { return }
                self.applying = nil
                if let failure {
                    self.message = failure
                    self.dropConnection()
                } else {
                    self.message = "Profile \"\(profile.name)\" applied."
                }
            }
        }
    }

    // MARK: Profiles

    func addProfile() {
        var p = MouseProfile.factoryDefault
        p.name = "Profile \(store.profiles.count + 1)"
        store.profiles.append(p)
        store.selected = store.profiles.count - 1
    }

    func duplicateProfile() {
        var p = profile
        p.name += " (copy)"
        store.profiles.append(p)
        store.selected = store.profiles.count - 1
    }

    func deleteProfile() {
        guard store.profiles.count > 1 else {
            message = "At least one profile must remain."
            return
        }
        store.profiles.remove(at: store.selected)
        store.selected = max(0, store.selected - 1)
    }

    func resetProfile() {
        let name = profile.name
        profile = .factoryDefault
        profile.name = name
    }

    func importWindowsProfile() {
        let panel = NSOpenPanel()
        panel.title = "Select DELUX Office Driver's pro.data (Data/ms_4)"
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try WindowsProfileImporter.importProfiles(from: url)
            guard !imported.isEmpty else { message = "The file contains no profiles."; return }
            store.profiles.append(contentsOf: imported)
            store.selected = store.profiles.count - 1
            message = "Imported \(imported.count) profile(s)."
        } catch {
            message = "Could not import: \(error.localizedDescription)"
        }
    }

    func exportProfile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(profile.name).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { try enc.encode(profile).write(to: url) } catch { message = error.localizedDescription }
    }

    func importJSONProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let p = try JSONDecoder().decode(MouseProfile.self, from: Data(contentsOf: url))
            store.profiles.append(p)
            store.selected = store.profiles.count - 1
        } catch {
            message = "Could not import: \(error.localizedDescription)"
        }
    }
}
