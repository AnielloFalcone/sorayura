import AppKit
import ServiceManagement

@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    var enabled: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }
    var description: String {
        switch status {
        case .enabled: return "L'app si aprirà automaticamente al prossimo accesso."
        case .requiresApproval: return "Completa l'autorizzazione in Impostazioni di Sistema → Generali → Elementi login."
        case .notFound: return "Attiva l'opzione per registrare l'app fra gli elementi di login."
        default: return "Avvia l'app automaticamente quando accedi al Mac."
        }
    }
    func refresh() { status = SMAppService.mainApp.status }
    func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refresh()
        } catch { refresh(); throw error }
    }
    func openApproval() { SMAppService.openSystemSettingsLoginItems() }
}
