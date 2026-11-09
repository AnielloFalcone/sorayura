import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardSettingsView: View {
    @Environment(Model.self) private var model
    @State private var confirmingClear = false
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            card("Cronologia locale") {
                Toggle(L("Attiva cronologia clipboard"), isOn: Binding(get: { model.prefs.clipboardEnabled ?? false }, set: { model.prefs.clipboardEnabled = $0 }))
                Text(L("Testi e link copiati da ora in poi. La raccolta è disattivata all’installazione e macOS può chiedere il consenso per leggere gli appunti.")).font(.caption).foregroundStyle(.secondary)
                Toggle(L("Pausa raccolta"), isOn: Binding(get: { model.prefs.clipboardPaused ?? false }, set: { model.prefs.clipboardPaused = $0 }))
                    .disabled(model.prefs.clipboardEnabled != true)
                Picker(L("Elementi recenti"), selection: Binding(get: { model.prefs.clipboardLimit ?? 100 }, set: { model.prefs.clipboardLimit = $0 })) {
                    ForEach([10, 50, 100, 200, 500], id: \.self) { Text("\($0)").tag($0) }
                }
                Text(L("I preferiti non scadono con la cronologia: massimo 50. I testi possono occupare fino a 16 KB ciascuno.")).font(.caption).foregroundStyle(.secondary)
                Toggle(L("Apri Clipboard con ⌘⇧V"), isOn: Binding(get: { model.prefs.clipboardShortcutEnabled ?? true }, set: { model.prefs.clipboardShortcutEnabled = $0 }))
                Text(L("⌘C copia con la formattazione disponibile. Incolla senza formattazione richiede il permesso Accessibilità.")).font(.caption).foregroundStyle(.secondary)
                Button(L("Apri Clipboard…")) {
                    DistributedNotificationCenter.default().postNotificationName(.init("dev.sorayura.openClipboard"), object: nil, userInfo: nil, deliverImmediately: true)
                }
                if let error = model.clipboard.shortcutError { Text(L(error)).font(.caption).foregroundStyle(.orange) }
                if model.clipboard.accessDenied { Text(L("Accesso agli appunti negato da macOS. Controlla le autorizzazioni di Sorayura nelle Impostazioni di Sistema.")).font(.caption).foregroundStyle(.orange) }
            }
            card("Privacy clipboard") {
                Text(L("I testi restano in un file privato su questo Mac, senza cifratura aggiuntiva né invio in rete. Le copie marcate come riservate o temporanee e i principali password manager vengono esclusi. Non è possibile riconoscere ogni password: usa pausa e app escluse per i contenuti sensibili.")).font(.caption).foregroundStyle(.secondary)
                ForEach(model.prefs.clipboardExcludedApps ?? [], id: \.self) { id in
                    HStack {
                        Text(id).font(.caption).lineLimit(1)
                        Spacer()
                        Button { model.prefs.clipboardExcludedApps?.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }.help(L("Rimuovi esclusione"))
                    }
                }
                Button(L("Escludi app…")) { excludeApplication() }
                Text(L("App escluse e raccolta clipboard sono impostazioni globali: le Scene non le modificano.")).font(.caption).foregroundStyle(.secondary)
            }
            card("Dati salvati") {
                Text(LF("\(model.clipboard.entries.count) elementi · \(model.clipboard.entries.filter(\.favorite).count) preferiti"))
                if let error = model.clipboard.error { Text(L(error)).font(.caption).foregroundStyle(.orange) }
                Button(L("Svuota cronologia…"), role: .destructive) { confirmingClear = true }
                Text(L("Disattivare la raccolta conserva la cronologia. Puoi cancellare i recenti oppure anche i preferiti; non vengono cancellati gli appunti correnti del Mac.")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(L("Cancellare la cronologia clipboard?"), isPresented: $confirmingClear, titleVisibility: .visible) {
            Button(L("Elimina solo recenti"), role: .destructive) { model.clipboard.clear(includingFavorites: false) }
            Button(L("Elimina tutto, inclusi i preferiti"), role: .destructive) { model.clipboard.clear(includingFavorites: true) }
            Button(L("Annulla"), role: .cancel) { }
        } message: { Text(L("Questa operazione non può essere annullata.")) }
        .alert("Sorayura", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(L(message ?? "")) }
    }
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { Text(L(title)).font(.title3.bold()); content() }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).wallpaperGlass(cornerRadius: 16)
    }
    private func excludeApplication() {
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.application]; picker.allowsMultipleSelection = false
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        guard picker.runModal() == .OK, let url = picker.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        var next = model.prefs.clipboardExcludedApps ?? []
        guard !next.contains(id) else { return }
        guard next.count < 100 else { message = "Puoi escludere al massimo 100 app."; return }
        next.append(id); model.prefs.clipboardExcludedApps = next
    }
}
