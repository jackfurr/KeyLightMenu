import SwiftUI
import ServiceManagement

// Elgato Key Light local API: http://<host>:9123/elgato/lights
// brightness 3...100, temperature in mireds 143...344 (7000K...2900K)

@MainActor
final class KeyLight: ObservableObject {
    @Published var isOn = false
    @Published var brightness: Double = 20
    @Published var kelvin: Double = 4300
    @Published var reachable = true
    @AppStorage("host") var host = "elgato-key-light-mk-2-7c38.local"

    private var pending: Task<Void, Never>?

    private var url: URL? { URL(string: "http://\(host):9123/elgato/lights") }

    private static func mired(fromKelvin k: Double) -> Int {
        min(344, max(143, Int((1_000_000 / k).rounded())))
    }

    func refresh() async {
        guard let url else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let light = (json["lights"] as? [[String: Any]])?.first else { return }
            isOn = (light["on"] as? Int ?? 0) == 1
            brightness = Double(light["brightness"] as? Int ?? 20)
            if let t = light["temperature"] as? Int, t > 0 { kelvin = (1_000_000 / Double(t) / 50).rounded() * 50 }
            reachable = true
        } catch {
            reachable = false
        }
    }

    // Debounced so dragging a slider doesn't flood the light.
    func push() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, let self, let url = self.url else { return }
            let body: [String: Any] = ["numberOfLights": 1, "lights": [[
                "on": self.isOn ? 1 : 0,
                "brightness": Int(self.brightness),
                "temperature": Self.mired(fromKelvin: self.kelvin),
            ]]]
            var req = URLRequest(url: url)
            req.httpMethod = "PUT"
            req.timeoutInterval = 3
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            do {
                _ = try await URLSession.shared.data(for: req)
                self.reachable = true
            } catch {
                self.reachable = false
            }
        }
    }
}

struct PanelView: View {
    @ObservedObject var light: KeyLight
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Key Light").font(.headline)
                Spacer()
                Toggle("", isOn: Binding(get: { light.isOn }, set: { light.isOn = $0; light.push() }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "sun.max")
                    Text("Brightness")
                    Spacer()
                    Text("\(Int(light.brightness))%").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { light.brightness }, set: { light.brightness = $0; light.push() }), in: 3...100)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "thermometer.medium")
                    Text("Temperature")
                    Spacer()
                    Text("\(Int(light.kelvin))K").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { light.kelvin }, set: { light.kelvin = $0; light.push() }), in: 2900...7000, step: 50)
            }

            if !light.reachable {
                Label("Light not reachable", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }

            Toggle("Launch at login", isOn: Binding(
                get: { loginEnabled },
                set: { on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        NSSound.beep()
                    }
                    loginEnabled = SMAppService.mainApp.status == .enabled
                }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)

            Divider()
            HStack {
                TextField("Host or IP", text: Binding(get: { light.host }, set: { light.host = $0 }))
                    .textFieldStyle(.roundedBorder).font(.caption)
                    .onSubmit { Task { await light.refresh() } }
                Button("Refresh") { Task { await light.refresh() } }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
        .task { await light.refresh() }
    }
}

@main
struct KeyLightMenuApp: App {
    @StateObject private var light = KeyLight()

    var body: some Scene {
        MenuBarExtra("Key Light", systemImage: light.isOn ? "lightbulb.fill" : "lightbulb") {
            PanelView(light: light)
        }
        .menuBarExtraStyle(.window)
    }
}
