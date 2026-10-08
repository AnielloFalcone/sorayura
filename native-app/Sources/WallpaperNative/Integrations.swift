import AppKit
import SwiftUI

struct AppPresence: Identifiable, Equatable {
    let id: String
    let name: String
    let running: Bool
}
@MainActor enum AppIntegrations {
    static func sample() -> [AppPresence] {
        let apps = NSWorkspace.shared.runningApplications
        return [("com.spotify.client", "Spotify"), ("com.openai.codex", "Codex"), ("com.anthropic.claudefordesktop", "Claude")].map { id, name in
            AppPresence(id: id, name: name, running: apps.contains { $0.bundleIdentifier == id || $0.localizedName == name })
        }
    }
}
enum ThermalPresentation {
    static func title(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Normale"
        case .fair: return "Elevato"
        case .serious: return "Warning"
        case .critical: return "Critical"
        @unknown default: return "Non disponibile"
        }
    }
    static func frames(_ state: ProcessInfo.ThermalState, lowPower: Bool, adaptive: Bool) -> Int {
        guard adaptive else { return 30 }
        switch state {
        case .critical: return 10
        case .serious: return 15
        default: return lowPower ? 20 : 30
        }
    }
}
struct IntegrationWidget: View {
    @Environment(Model.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("APPLICAZIONI").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(.secondary)
            if model.prefs.appStatusEnabled == true {
                ForEach(model.appPresence) { app in
                    HStack {
                        Circle().fill(app.running ? Color.green : Color.gray).frame(width: 6, height: 6)
                        Text(app.name)
                        Spacer()
                        Text(app.running ? "Aperta" : "Chiusa").foregroundStyle(.secondary)
                    }.font(.system(size: 12))
                }
            } else { Text("Attiva da Integrazioni").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
