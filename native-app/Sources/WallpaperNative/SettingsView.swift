import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(Model.self) private var model
    @Bindable var navigation: SettingsNavigation
    private var section: String {
        get { navigation.section }
        nonmutating set { navigation.section = newValue }
    }
    @State private var presetName = ""
    @State private var claudeHooksInstalled = ClaudeHooksInstaller.installed
    @State private var claudeBridgeInstalled = ClaudeBridgeInstaller.installed
    @State private var message: String?
    @StateObject private var loginItem = LoginItem()
    private let sections: [(title: String, icon: String, description: String)] = [
        ("Preset", "square.stack.3d.up", "Configurazioni pronte e personali"),
        ("Generali", "gearshape", "Avvio e backup delle impostazioni"),
        ("Schermi", "display.2", "Contenuti per monitor"),
        ("Widget", "square.grid.2x2", "Grafici e dettagli"),
        ("Layout", "rectangle.3.group", "Dimensioni e posizione"),
        ("Sfondo", "photo", "Immagine del desktop"),
        ("Animazione", "waveform.path", "Stile e livelli"),
        ("Integrazioni", "app.connected.to.app.below.fill", "Applicazioni e stato termico"),
        ("Avvisi", "exclamationmark.triangle", "Soglie delle risorse")
    ]
    var body: some View {
        let _ = LocalizationSettings.shared.choice
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:0) {
                Text("SORAYURA")
                    .font(.system(size:10,weight:.bold)).tracking(1.7)
                    .foregroundStyle(.secondary).padding(.horizontal,17).padding(.top,28).padding(.bottom,18)
                ForEach(sections,id:\.title) { item in
                    Button { section = item.title } label: {
                        HStack(spacing:11) {
                            Image(systemName:item.icon)
                                .font(.system(size:15,weight:.medium))
                                .frame(width:22)
                                .foregroundStyle(section == item.title ? .white : .secondary)
                            Text(L(item.title))
                                .font(.system(size:13,weight:section == item.title ? .semibold : .regular))
                            Spacer(minLength:0)
                        }
                        .foregroundStyle(section == item.title ? .white : .primary)
                        .padding(.horizontal,12).frame(height:35)
                        .background { selectedSidebarSurface(section == item.title) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal,9).padding(.bottom,3)
                }
                Spacer()
                Text(L("Le modifiche si salvano subito"))
                    .font(.system(size:10)).foregroundStyle(.tertiary)
                    .padding(17)
            }
            .frame(width:210)
            .background(.regularMaterial)
            Divider()
            VStack(alignment:.leading,spacing:0) {
                Text(L(section))
                    .font(.system(size:26,weight:.bold))
                    .padding(.bottom,4)
                Text(L(sections.first(where:{$0.title == section})?.description ?? ""))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.bottom,22)
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        switch section {
                        case "Preset": presetsSection
                        case "Generali": generalSection
                        case "Schermi": screensSection
                        case "Widget": widgetsSection
                        case "Layout": layoutSection
                        case "Sfondo": wallpaperSection
                        case "Animazione": animationSection
                        case "Integrazioni": integrationsSection
                        default: alertsSection
                        }
                    }
                    .frame(maxWidth:.infinity,alignment:.leading)
                }
                .contentMargins(.bottom,22)
            }
            .padding(.horizontal,28).padding(.top,28)
            .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .background(Color(red:0.07,green:0.11,blue:0.18))
        }
        .frame(minWidth:860,minHeight:680)
        .preferredColorScheme(.dark)
        .onAppear { loginItem.refresh(); if let notice = model.storageMessage { message = notice } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
        .alert("Sorayura", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(L(message ?? "")) }
        .onChange(of: model.storageMessage) { _, value in if let value { message = value } }
    }
    private func panel<Content:View>(_ title:String,@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:14) { Text(L(title)).font(.title3.bold()); content() }
            .padding(18).frame(maxWidth:.infinity,alignment:.leading)
            .wallpaperGlass(cornerRadius:16)
    }
    @ViewBuilder private func selectedSidebarSurface(_ selected:Bool)->some View {
        if selected {
            if #available(macOS 26, *) {
                RoundedRectangle(cornerRadius:10)
                    .fill(.clear)
                    .glassEffect(.regular.tint(.accentColor.opacity(0.32)),in:RoundedRectangle(cornerRadius:10))
            } else {
                RoundedRectangle(cornerRadius:10).fill(Color.accentColor.opacity(0.78))
            }
        }
    }
    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("Applica un preset a tutti i monitor collegati. Soglie di avviso e sincronizzazione dello sfondo vengono mantenute."))
                .font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(BuiltInPreset.all) { preset in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Circle().fill(Color(nsColor: NSColor(hex: preset.color))).frame(width: 12, height: 12)
                            Text(L(preset.name)).font(.headline)
                        }
                        Text(L(preset.description)).font(.subheadline).foregroundStyle(.secondary).frame(minHeight: 48, alignment: .top)
                        Button(L("Applica")) { model.apply(preset) }.buttonStyle(.bordered)
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).wallpaperGlass(cornerRadius: 16)
                }
            }
            panel(L("I tuoi preset")) {
                HStack {
                    TextField(L("Nome della configurazione"), text: $presetName)
                    Button(L("Salva attuale")) {
                        perform { try model.savePreset(name: presetName); presetName = "" }
                    }.disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if model.savedPresets.isEmpty { Text(L("Salva widget, colori e disposizione come preset personale.")).foregroundStyle(.secondary) }
                ForEach(model.savedPresets) { preset in
                    HStack {
                        Text(preset.name).lineLimit(1)
                        Spacer()
                        Button(L("Applica")) { perform { try model.apply(preset.archive) } }
                        Button { perform { try model.removePreset(preset.id) } } label: { Image(systemName: "trash") }
                            .help(L("Rimuovi preset"))
                    }
                }
            }
            panel(L("Aspetto dei widget")) {
                Picker(L("Tema"), selection: Binding(get: { model.prefs.widgetTheme ?? "minimal" }, set: { model.prefs.widgetTheme = $0 })) {
                    Text("Minimal").tag("minimal"); Text("Glass").tag("glass"); Text("Cyber").tag("cyber")
                }.pickerStyle(.segmented)
            }
            if model.previousSettings != nil {
                Button(L("Annulla ultima applicazione")) { model.undoSettings() }
            }
        }
    }
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            panel("Lingua") {
                Picker(L("Lingua"), selection: Binding(get: { LocalizationSettings.shared.choice }, set: { LocalizationSettings.shared.choose($0) })) {
                    Text(L("Segui la lingua del Mac")).tag("system")
                    Text("Italiano").tag("it")
                    Text("English").tag("en")
                }
                Text(L("La lingua cambia subito per impostazioni, menu e widget. I dialoghi di sistema seguono macOS."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            panel(L("Avvio")) {
                Toggle(L("Apri al login"), isOn: Binding(get: { loginItem.enabled }, set: { value in perform { try loginItem.setEnabled(value) } }))
                Text(L(loginItem.description)).font(.caption).foregroundStyle(.secondary)
                if loginItem.needsApproval { Button(L("Apri Elementi login…")) { loginItem.openApproval() } }
            }
            panel(L("Backup delle impostazioni")) {
                Text(L("Il file include layout, temi, contenuti per monitor e l'immagine dello sfondo. Su un altro Mac i monitor vengono abbinati per identità, poi per ordine."))
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Button(L("Esporta…")) {
                        let picker = NSSavePanel()
                        picker.allowedContentTypes = [.json]
                        picker.nameFieldStringValue = "Sorayura.json"
                        if picker.runModal() == .OK, let url = picker.url { perform { try model.exportSettings(to: url) } }
                    }
                    Button(L("Importa…")) {
                        let picker = NSOpenPanel()
                        picker.allowedContentTypes = [.json]
                        picker.allowsMultipleSelection = false
                        if picker.runModal() == .OK, let url = picker.url {
                            perform { try model.importSettings(from: url); message = L("Impostazioni importate. Puoi annullare dalla sezione Preset.") }
                        }
                    }
                }
            }

        }
    }
    private var integrationsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            panel(L("AI Agents")) {
                Toggle(L("Leggi utilizzo locale di Codex e Claude Code"), isOn: Binding(get: { model.prefs.agentUsageEnabled ?? false }, set: { model.prefs.agentUsageEnabled = $0; model.refreshAgentUsage(force: true) }))
                Text(L("Token, cache, modelli, progetti e attività dai contatori delle sessioni locali. Aggiornamento automatico quando cambiano i registri, con eventi raggruppati entro circa 2 secondi; controllo di sicurezza ogni 30 secondi. I limiti Codex riportano la data dell'ultimo dato registrato; Claude può fornire limiti tramite la status line o il file locale dell’app desktop. La fonte più recente viene indicata: l’account desktop può essere diverso da Claude Code.")).font(.caption).foregroundStyle(.secondary)
                Text(L("I contatori locali rimangono sul Mac. Il collegamento account Codex e le copertine Spotify usano la rete solo se abiliti quelle integrazioni. Nessuna credenziale viene letta dal wallpaper. Lo storico non equivale alla fattura o al costo dell'abbonamento.")).font(.caption).foregroundStyle(.secondary)
                Picker(L("Periodo grafici"), selection: Binding(get: { model.prefs.agentPeriod ?? "all" }, set: { model.prefs.agentPeriod = $0 })) {
                    Text(L("Oggi")).tag("today"); Text(L("7 giorni")).tag("week"); Text(L("30 giorni")).tag("month"); Text(L("Storico")).tag("all")
                }.pickerStyle(.segmented)
                Picker(L("Dettaglio AI"), selection: Binding(get: { model.prefs.agentDensity ?? "compact" }, set: { model.prefs.agentDensity = $0 })) {
                    Text(L("Compatto · 3 righe")).tag("compact"); Text(L("Esteso · 6 righe")).tag("expanded")
                }
                Toggle(L("Aggiorna limiti e stime Codex dall'account"), isOn: Binding(get: { model.prefs.codexAccountEnabled ?? false }, set: { model.prefs.codexAccountEnabled = $0; model.refreshCodexAccount(force: true) }))
                Text(L("Usa Codex CLI e il suo login esistente; contatta i servizi Codex ogni 5 minuti. Nessuna conversazione viene avviata. Le stime riguardano fino a 8 chat recenti, se disponibili per il tuo account.")).font(.caption).foregroundStyle(.secondary)
                Button(L("Scegli Codex CLI…")) {
                    let picker = NSOpenPanel(); picker.canChooseDirectories = false
                    if picker.runModal() == .OK, let url = picker.url { model.prefs.codexExecutable = url.path; model.refreshCodexAccount(force: true) }
                }
                if let error = model.codexAccount.error { Text(L(error)).font(.caption).foregroundStyle(.orange) }
                HStack {
                    Button(claudeHooksInstalled ? L("Scollega eventi Claude") : L("Collega eventi Claude")) {
                        perform { model.save(); try ClaudeHooksInstaller.setEnabled(!claudeHooksInstalled); claudeHooksInstalled = ClaudeHooksInstaller.installed }
                    }.disabled(model.prefs.agentUsageEnabled != true && !claudeHooksInstalled)
                }
                Text(L("Gli hook aggiungono eventi di lavoro, attesa e termine preservando gli altri hook. Non modificano le autorizzazioni dei tool.")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(claudeBridgeInstalled ? L("Scollega status line Claude") : L("Collega status line Claude")) {
                        perform {
                            if claudeBridgeInstalled { try ClaudeBridgeInstaller.uninstall() }
                            else { model.save(); try ClaudeBridgeInstaller.install() }
                            claudeBridgeInstalled = ClaudeBridgeInstaller.installed
                        }
                    }.disabled(model.prefs.agentUsageEnabled != true && !claudeBridgeInstalled)
                }
                Text(L("Il collegamento aggiorna la status line di Claude Code e preserva quella esistente. Fornisce limiti e valore API quando Claude li rende disponibili. Apri una nuova sessione dopo il collegamento.")).font(.caption).foregroundStyle(.secondary)
                Button(model.updatingCounters ? L("Aggiornamento…") : L("Aggiorna contatori")) { model.refreshCounters() }.disabled(model.prefs.agentUsageEnabled != true)
                if model.prefs.codexAccountEnabled != true {
                    Text(L("Per aggiornare i limiti Codex dall’account attiva il collegamento sopra. I registri locali conservano l’ultima rilevazione del client.")).font(.caption).foregroundStyle(.secondary)
                }
                if let date = model.agentUsage.updated {
                    Text(LF("Aggiornato \(date.localizedFormatted(date: .omitted, time: .standard)) · \(model.agentUsage.files) file · \(model.agentUsage.skipped) non leggibili")).font(.caption).foregroundStyle(.secondary)
                }
                Text(L("Aggiungi AI Agents, Andamento, Modelli, Progetti e Attività dalla sezione Schermi. Per AI Agents consigliamo 3 × 2 unità.")).font(.caption).foregroundStyle(.secondary)
            }
            if model.prefs.agentUsageEnabled == true {
                panel(L("Anteprima dashboard")) {
                    AgentWidget(id: "agents").environment(model)
                    Divider()
                    AgentWidget(id: "agentTrend").environment(model).frame(height: 135)
                    Divider()
                    HStack(alignment: .top, spacing: 20) {
                        AgentWidget(id: "agentModels").environment(model).frame(maxWidth: .infinity)
                        AgentWidget(id: "agentProjects").environment(model).frame(maxWidth: .infinity)
                    }
                    Divider()
                    AgentWidget(id: "agentActivity").environment(model)
                    Divider()
                    AgentWidget(id: "agentSpending").environment(model)
                    Divider()
                    AgentWidget(id: "agentNow").environment(model)
                    Divider()
                    AgentWidget(id: "agentLive").environment(model)
                }
            }
            panel("Spotify") {
                Toggle(L("Attiva brano e controlli Spotify"), isOn: Binding(get: { model.prefs.spotifyEnabled ?? false }, set: { model.prefs.spotifyEnabled = $0; model.refreshSpotify(retry: true) }))
                Text(L("macOS può chiederti il permesso di controllare Spotify. La copertina viene scaricata dal servizio Spotify. I controlli sono disponibili sul widget e nel suo menu secondario.")).font(.caption).foregroundStyle(.secondary)
                Button(L("Riprova collegamento")) { model.refreshSpotify(retry: true) }.disabled(model.prefs.spotifyEnabled != true)
                if model.prefs.spotifyEnabled == true { SpotifyWidget().environment(model).frame(height: 160) }
            }
            panel("Applicazioni") {
                Toggle(L("Mostra lo stato di Spotify, Codex e Claude"), isOn: Binding(get: { model.prefs.appStatusEnabled ?? false }, set: { model.prefs.appStatusEnabled = $0; model.tick() }))
                Text(L("Mostra se le app desktop sono aperte. Non legge conversazioni, task, musica o sessioni di Claude Code.")).font(.caption).foregroundStyle(.secondary)
                Text(L("Aggiungi il widget Applicazioni dalla sezione Schermi.")).font(.caption).foregroundStyle(.secondary)
            }
            panel(L("Energia e temperatura")) {
                Toggle(L("Adatta le animazioni allo stato del Mac"), isOn: Binding(get: { model.prefs.adaptiveAnimation ?? true }, set: { model.prefs.adaptiveAnimation = $0 }))
                Text(LF("Stato termico: \(L(ThermalPresentation.title(model.metrics.thermal)))"))
                Text(L("30 fps normalmente, 20 in risparmio energetico, 15 in warning e 10 in critical. Il widget Stato termico mostra la classificazione di macOS, non una temperatura in gradi.")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { message = error.localizedDescription }
    }
    private var screensSection:some View {
        panel(L("Contenuti per monitor")) {
            Text(L("Identifica gli schermi, poi scegli widget e animazione per ognuno.")).foregroundStyle(.secondary)
            Button(L("Identifica monitor")) { model.identifyUntil = Date().addingTimeInterval(6) }
            ForEach(Array(orderedScreens().enumerated()),id:\.offset) { index,screen in
                VStack(alignment:.leading,spacing:10) {
                    Text("\(index+1) · \(screen.localizedName) · #\(model.displayNumber(screen))").font(.headline)
                    HStack {
                        Button("Tutti") { var c=model.content(screen); c.widgets=Model.widgetIDs; model.setContent(screen,c) }
                        Button(L("Nessuno")) { var c=model.content(screen); c.widgets=[]; model.setContent(screen,c) }
                        Button(L("Riapplica sfondo")) { WallpaperRenderer.apply(to:screen,prefs:model.prefs) }
                    }
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],alignment:.leading) {
                        ForEach(Model.widgetIDs,id:\.self) { id in
                            Toggle(Model.localizedName(id),isOn:Binding(
                                get:{ model.content(screen).widgets.contains(id) },
                                set:{ enabled in var c=model.content(screen); if enabled { if !c.widgets.contains(id) { c.widgets.append(id) } } else { c.widgets.removeAll{$0==id} }; model.setContent(screen,c) }
                            ))
                        }
                    }
                    Toggle(L("Animazione"),isOn:Binding(get:{model.content(screen).animation},set:{value in var c=model.content(screen);c.animation=value;model.setContent(screen,c)}))
                }.padding(14).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:12))
            }
        }
    }
    private var widgetsSection:some View {
        panel(L("Grafici e dettagli")) {
            ForEach(["cpu","memory"],id:\.self) { metric in
                HStack {
                    Text(metric == "cpu" ? "CPU" : L("Memoria")).frame(width:90,alignment:.leading)
                    Picker(L("Grafico"),selection:displayBinding(metric,"chart")) {
                        Text(L("Barra")).tag("bar"); Text(L("Area · cronologia")).tag("area"); Text(L("Linea · cronologia")).tag("line")
                    }
                    Picker(L("Dettaglio"),selection:displayBinding(metric,"density")) {
                        Text(L("Compatto")).tag("compact"); Text(L("Esteso")).tag("expanded")
                    }
                }
            }
            Text(L("La cronologia mostra gli ultimi 90 secondi. La memoria estesa include cache, swap, memoria app, vincolata e compressa.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func displayBinding(_ metric:String,_ property:String)->Binding<String> {
        Binding(get:{ let d=metric == "cpu" ? model.prefs.cpuDisplay : model.prefs.memoryDisplay; return property == "chart" ? d.chart : d.density },
                set:{ value in if metric == "cpu" { if property == "chart" {model.prefs.cpuDisplay.chart=value} else {model.prefs.cpuDisplay.density=value} } else { if property == "chart" {model.prefs.memoryDisplay.chart=value} else {model.prefs.memoryDisplay.density=value} } })
    }
    private var layoutSection:some View {
        panel(L("Dimensioni e disposizione")) {
            Picker(L("Posizionamento"),selection:Bindable(model).prefs.layout) { Text(L("Libero")).tag("free");Text(L("Griglia")).tag("grid") }.pickerStyle(.segmented)
            HStack { Text(L("Dimensione cella")); Slider(value:Bindable(model).prefs.cellSize,in:80...220,step:10); Text("\(Int(model.prefs.cellSize)) px").monospacedDigit() }
            ForEach(Model.widgetIDs,id:\.self) { id in
                HStack {
                    Text(Model.localizedName(id)).frame(maxWidth:.infinity,alignment:.leading)
                    Picker(L("Larghezza"),selection:Binding(get:{model.widgetUnits(id, axis: "width")},set:{model.prefs.widths[id]=$0})) { ForEach(1...model.maximumUnits(axis: "width"),id:\.self) { Text("\($0)").tag($0) } }.frame(width:105)
                    Picker(L("Altezza"),selection:Binding(get:{model.widgetUnits(id, axis: "height")},set:{model.prefs.heights[id]=$0})) { ForEach(1...model.maximumUnits(axis: "height"),id:\.self) { Text("\($0)").tag($0) } }.frame(width:105)
                }
            }
            Text(L("Sposta i widget dal desktop con “Modifica layout…” nel menu della barra.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var wallpaperSection:some View {
        panel(L("Sfondo")) {
            Picker(L("Stile"),selection:Bindable(model).prefs.wallpaper) {
                Text("Aurora").tag("gradient");Text(L("Mezzanotte")).tag("midnight");Text(L("Immagine")).tag("image")
            }.pickerStyle(.segmented)
            Button(L("Scegli immagine…")) {
                let picker=NSOpenPanel();picker.allowedContentTypes=[.image];picker.allowsMultipleSelection=false
                if picker.runModal() == .OK { model.prefs.imagePath=picker.url?.path; model.prefs.wallpaper="image" }
            }
            Toggle(L("Usa lo stesso sfondo anche in macOS"),isOn:Bindable(model).prefs.syncWallpaper)
            Text(L("macOS mostra l’immagine statica nello Space attivo; widget e animazioni sono visibili sul desktop. Per altri Space usa “Riapplica sfondo” sul monitor interessato.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var animationSection:some View {
        panel(L("Animazione")) {
            Picker(L("Stile"),selection:Bindable(model).prefs.animationStyle) {
                Text(L("Nessuna")).tag("off")
                Text("Aurora").tag("aurora")
                Text(L("Impulso")).tag("pulse")
                Text(L("Tracce · 90 secondi")).tag("traces")
                Text(L("Nucleo luminoso")).tag("jarvis")
            }.pickerStyle(.menu)
            ForEach(Model.metricIDs,id:\.self) { metric in
                HStack {
                    Toggle(Model.localizedName(metric),isOn:Binding(get:{model.prefs.layers.contains{$0.metric==metric}},set:{enabled in if enabled {model.prefs.layers.append(Layer(metric:metric,color:ColorValue("#82c4ff")))} else {model.prefs.layers.removeAll{$0.metric==metric}} }))
                    if model.prefs.layers.contains(where:{$0.metric==metric}) {
                        ColorPicker("",selection:colorBinding(metric),supportsOpacity:false).labelsHidden()
                    }
                }
            }
            Text(L(animationDescription))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var animationDescription: String {
        switch model.prefs.animationStyle {
        case "aurora": return L("Una cortina per risorsa. Altezza e luminosità crescono con il valore.")
        case "pulse": return L("Un impulso per risorsa: frequenza e altezza aumentano con il valore. I colori segnalano warning e critical.")
        case "traces": return L("Andamento degli ultimi 90 secondi, su una corsia distinta per ogni risorsa.")
        case "jarvis": return L("Filamenti luminosi con i colori delle risorse selezionate.")
        default: return L("Seleziona uno stile per visualizzare le risorse sul desktop.")
        }
    }
    private func colorBinding(_ metric:String)->Binding<Color> {
        Binding(get:{Color(nsColor:model.prefs.layers.first(where:{$0.metric==metric})?.color.color ?? .cyan)},set:{color in
            let ns=NSColor(color).usingColorSpace(.deviceRGB) ?? .cyan
            let hex=String(format:"#%02x%02x%02x",Int(ns.redComponent*255),Int(ns.greenComponent*255),Int(ns.blueComponent*255))
            if let index=model.prefs.layers.firstIndex(where:{$0.metric==metric}) {model.prefs.layers[index].color=ColorValue(hex)}
        })
    }
    private var alertsSection:some View {
        panel(L("Warning e critical")) {
            Toggle(L("Attiva avvisi visivi"),isOn:Bindable(model).prefs.alerts)
            ForEach(["widgets", "animation"], id: \.self) { target in
                Toggle(target == "widgets" ? L("Applica ai widget") : L("Applica all’animazione"), isOn: Binding(get: { (model.prefs.alertTargets ?? ["widgets", "animation"]).contains(target) }, set: { enabled in
                    var values = model.prefs.alertTargets ?? ["widgets", "animation"]
                    values.removeAll { $0 == target }; if enabled { values.append(target) }; model.prefs.alertTargets = values
                }))
            }
            HStack { Text(L("Warning"));ColorPicker("",selection:alertColorBinding("warning"),supportsOpacity:false).labelsHidden();Text(L("Critical"));ColorPicker("",selection:alertColorBinding("critical"),supportsOpacity:false).labelsHidden() }
            ForEach(Model.metricIDs,id:\.self) { metric in
                HStack {
                    Toggle("", isOn: Binding(get: { (model.prefs.alertMetrics ?? Model.metricIDs + ["thermal"]).contains(metric) }, set: { enabled in
                        var values = model.prefs.alertMetrics ?? Model.metricIDs + ["thermal"]
                        values.removeAll { $0 == metric }; if enabled { values.append(metric) }; model.prefs.alertMetrics = values
                    })).labelsHidden()
                    Text(metric == "network" ? L("Rete (Mbps)") : (Model.localizedName(metric))).frame(maxWidth:.infinity,alignment:.leading)
                    Text(L("Warning"))
                    TextField("",value:thresholdBinding(metric,"warning"),format:.number).frame(width:55)
                    Text(L("Critical"))
                    TextField("",value:thresholdBinding(metric,"critical"),format:.number).frame(width:55)
                }
            }
            HStack { Text(L("Scala rete")); TextField("Mbps",value:networkScaleBinding,format:.number).frame(width:70);Text(L("Mbps = barra piena (↓ + ↑)")) }
        }
    }
    private func thresholdBinding(_ metric:String,_ level:String)->Binding<Double> {
        Binding(get: {
            let threshold = model.prefs.thresholds[metric] ?? Threshold(warning: 75, critical: 90)
            let value = level == "warning" ? threshold.warning : threshold.critical
            return metric == "network" ? value * 8 : value
        }, set: { value in
            guard value.isFinite else { return }
            var threshold = model.prefs.thresholds[metric] ?? Threshold(warning: 75, critical: 90)
            let stored = metric == "network" ? max(0, value / 8) : min(100, max(0, value))
            if level == "warning" {
                threshold.warning = stored
                threshold.critical = metric == "battery" ? min(stored, threshold.critical) : max(stored, threshold.critical)
            } else {
                threshold.critical = stored
                threshold.warning = metric == "battery" ? max(stored, threshold.warning) : min(stored, threshold.warning)
            }
            model.prefs.thresholds[metric] = threshold
        })
    }
    private var networkScaleBinding: Binding<Double> {
        Binding(get:{model.prefs.networkScaleMBps * 8},set:{model.prefs.networkScaleMBps = max(0.0125, $0 / 8)})
    }
    private func alertColorBinding(_ level:String)->Binding<Color> {
        Binding(get:{Color(nsColor:(level == "warning" ? model.prefs.warningColor:model.prefs.criticalColor).color)},set:{color in
            let ns=NSColor(color).usingColorSpace(.deviceRGB) ?? .orange
            let value=ColorValue(String(format:"#%02x%02x%02x",Int(ns.redComponent*255),Int(ns.greenComponent*255),Int(ns.blueComponent*255)))
            if level == "warning" {model.prefs.warningColor=value} else {model.prefs.criticalColor=value}
        })
    }
}
