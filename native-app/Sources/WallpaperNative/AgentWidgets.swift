import SwiftUI

struct AgentWidget: View {
    let id: String
    @Environment(Model.self) private var model
    private var snapshot: AgentUsageSnapshot { model.agentUsage }
    private var period: String { model.prefs.agentPeriod ?? "all" }
    private var summary: AgentPeriodSummary { snapshot.periods[period] ?? AgentPeriodSummary() }
    private var periodTitle: String { ["today":"Oggi", "week":"Ultimi 7 giorni", "month":"Ultimi 30 giorni", "all":"Storico locale"][period] ?? "Storico locale" }
    private var codexQuota: AgentQuota? { model.prefs.codexAccountEnabled == true ? model.codexAccount.quota ?? snapshot.codexQuota : snapshot.codexQuota }
    private let claudeColor = Color(red: 0.80, green: 0.44, blue: 0.32)
    private let codexColor = Color(red: 0.48, green: 0.57, blue: 0.94)
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Model.names[id] ?? id, systemImage: icon).font(.system(size: 14, weight: .semibold))
            if model.prefs.agentUsageEnabled != true {
                Text("Attiva da Integrazioni").font(.caption).foregroundStyle(.secondary)
            } else if snapshot.updated == nil {
                Text("Lettura dei contatori locali…").font(.caption).foregroundStyle(.secondary)
            } else if snapshot.events.isEmpty && snapshot.claudeSessions.isEmpty && snapshot.claudeDesktop == nil {
                Text("Nessun contatore locale disponibile").font(.caption).foregroundStyle(.secondary)
            } else {
                switch id {
                case "agents": providers
                case "agentTrend": trend
                case "agentModels": rankings(summary.models)
                case "agentProjects": rankings(summary.projects)
                case "agentActivity": activity
                case "agentSpending": spending
                case "agentNow": recent
                case "agentLive": live
                default: providers
                }
            }
        }
    }
    private var icon: String {
        switch id { case "agentTrend": return "chart.bar"; case "agentModels": return "cpu"; case "agentProjects": return "folder"; case "agentActivity": return "square.grid.3x3"; default: return "sparkles" }
    }
    private var live: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 8) {
                if model.liveAgents.isEmpty { Text("Nessun evento recente. Collega gli hook Claude nelle impostazioni.").font(.caption).foregroundStyle(.secondary) }
                ForEach(model.liveAgents.prefix(model.prefs.agentDensity == "expanded" ? 6 : 3)) { agent in
                    HStack {
                        Circle().fill(agent.displayState(now: context.date) == "Al lavoro" ? Color.green : agent.displayState(now: context.date) == "In attesa" ? Color.orange : Color.gray).frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(agent.provider) · \(agent.project)").font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            Text(agent.displayState(now: context.date)).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Text(agent.date, style: .relative).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                Text("Eventi locali · aggiornamento automatico · inattivi oltre 5 min da verificare").font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
    }
    private var recentEvents: [AgentUsageEvent] {
        var selected: [AgentUsageEvent] = [], keys = Set<String>()
        for event in snapshot.events.reversed() {
            let key = event.provider + ":" + event.project + ":" + event.model
            if keys.insert(key).inserted { selected.append(event) }
            if selected.count == 3 { break }
        }
        return selected
    }
    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(recentEvents.enumerated()), id: \.offset) { _, event in
                HStack {
                    Circle().fill(event.provider == "Claude" ? claudeColor : codexColor).frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.project).lineLimit(1).font(.system(size: 11, weight: .semibold))
                        Text("\(event.model) · \(tokenLabel(event.tokens)) token").lineLimit(1).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(event.date, style: .relative).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            Text("Ultimi contatori registrati · non stato live del task").font(.system(size: 8)).foregroundStyle(.secondary)
        }
    }
    private var spending: some View {
        VStack(alignment: .leading, spacing: 5) {
            if snapshot.claudeSessions.contains(where: { $0.apiValue != nil }) {
                Text(String(format: "$%.2f", snapshot.claudeSessions.reduce(0) { $0 + ($1.apiValue ?? 0) })).font(.title.bold())
                Text("Claude · valore API delle sessioni collegate").font(.system(size: 10)).foregroundStyle(.secondary)
                Text("Claude · sessioni intere, indipendenti dal filtro periodo").font(.system(size: 9)).foregroundStyle(.secondary)
            } else { Text("Claude · collega la status line").font(.caption).foregroundStyle(.secondary) }
            if !model.codexAccount.costs.isEmpty {
                Text(String(format: "$%.2f", model.codexAccount.costs.values.reduce(0, +))).font(.title3.bold())
                Text("Codex · stima delle ultime \(model.codexAccount.costs.count) chat lette").font(.system(size: 10)).foregroundStyle(.secondary)
            } else { Text("Codex · valore API non disponibile").font(.system(size: 10)).foregroundStyle(.secondary) }
            Text("Valori API di sessione · non sono fatture o costi dell'abbonamento").font(.system(size: 8)).foregroundStyle(.secondary)
        }
    }
    private var providers: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                provider("Claude", color: claudeColor)
                provider("Codex", color: codexColor)
            }
            HStack {
                Text("\(periodTitle) · \(tokenLabel(summary.tokens)) token")
                Spacer()
                Text("\(Int(summary.tokens > 0 ? summary.cached / summary.tokens * 100 : 0))% cache")
            }.font(.system(size: 10)).foregroundStyle(.secondary)

        }
    }
    private var claudeQuota: AgentQuota? {
        let status = snapshot.claudeSessions.max(by: { $0.date < $1.date })?.quota
        let desktop = snapshot.claudeDesktop?.quota
        if let desktop, desktop.date > (status?.date ?? .distantPast) { return desktop }
        return status ?? desktop
    }
    private var usesClaudeDesktop: Bool { claudeQuota?.date == snapshot.claudeDesktop?.quota.date }
    private func provider(_ name: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(name).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                if name == "Codex", let plan = codexQuota?.plan { Text(plan.capitalized).font(.system(size: 9)).foregroundStyle(color) }
            }
            quota("Sessione", limit: name == "Codex" ? codexQuota?.session : claudeQuota?.session, color: color)
            quota("Settimana", limit: name == "Codex" ? codexQuota?.week : claudeQuota?.week, color: color)
            if let quota = name == "Codex" ? codexQuota : claudeQuota {
                Text("Rilevato \(quota.date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
            }
            if name == "Claude", usesClaudeDesktop {
                Text("Claude desktop · account dell’app").font(.system(size: 8)).foregroundStyle(.secondary)
                if let date = claudeQuota?.date, Date().timeIntervalSince(date) > 1800 {
                    Text("Lettura non recente").font(.system(size: 8)).foregroundStyle(.orange)
                }
                if model.prefs.agentDensity == "expanded", let desktop = snapshot.claudeDesktop {
                    quota("Opus · settimana", limit: desktop.opus, color: color)
                    quota("Sonnet · settimana", limit: desktop.sonnet, color: color)
                }
            } else if name == "Claude", claudeQuota != nil {
                Text("Claude Code · status line").font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .topLeading).wallpaperGlass(cornerRadius: 12)
    }
    private func quota(_ title: String, limit: AgentLimit?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer(minLength: 0)
                Text(limit.map { "\(Int($0.used.rounded()))%" } ?? "—").monospacedDigit()
            }.font(.system(size: 10))
            if let limit {
                ProgressView(value: limit.used, total: 100).tint(color)
                Text(limit.reset.map { $0 > Date() ? "Reset \($0.formatted(date: .omitted, time: .shortened)) · \($0.formatted(date: .abbreviated, time: .omitted))" : "Da aggiornare" } ?? "Reset non fornito")
                    .font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
            } else { Text("Limiti non disponibili").font(.system(size: 8)).foregroundStyle(.secondary) }
        }
    }
    @ViewBuilder private var trend: some View {
        if period != "today" { dailyTrend } else { hourlyTrend }
    }
    private var hourlyTrend: some View {
        let maximum = max(1, (0..<24).map { snapshot.hourlyClaude[$0] + snapshot.hourlyCodex[$0] }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Oggi · \(tokenLabel(snapshot.todayTokens)) token").font(.caption).foregroundStyle(.secondary)
            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<24, id: \.self) { hour in
                        let c = snapshot.hourlyClaude[hour]
                        let o = snapshot.hourlyCodex[hour]
                        VStack(spacing: 0) {
                            Rectangle().fill(codexColor).frame(height: geometry.size.height * o / maximum)
                            Rectangle().fill(claudeColor).frame(height: geometry.size.height * c / maximum)
                        }.frame(maxWidth: .infinity).frame(minHeight: 2).background(.white.opacity(0.08))
                            .help("\(hour):00 · Claude \(tokenLabel(c)) · Codex \(tokenLabel(o))")
                    }
                }
            }.frame(minHeight: 30, maxHeight: 90)
            HStack { Text("00"); Spacer(); Text("12"); Spacer(); Text("23") }.font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
    private var dailyTrend: some View {
        let calendar = Calendar.current
        let count = period == "week" ? 7 : 30
        let dates = (0..<count).map { calendar.date(byAdding: .day, value: $0 + 1 - count, to: calendar.startOfDay(for: Date()))! }
        let maximum = max(1, dates.map { summary.days[$0] ?? 0 }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(period == "all" ? "Ultimi 30 giorni" : periodTitle)").font(.caption).foregroundStyle(.secondary)
            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(dates, id: \.self) { day in
                        VStack(spacing: 0) {
                            Rectangle().fill(codexColor).frame(height: geometry.size.height * (summary.codexDays[day] ?? 0) / maximum)
                            Rectangle().fill(claudeColor).frame(height: geometry.size.height * (summary.claudeDays[day] ?? 0) / maximum)
                        }.frame(maxWidth: .infinity).frame(minHeight: 2).background(.white.opacity(0.08))
                            .help("\(day.formatted(date: .abbreviated, time: .omitted)) · \(tokenLabel(summary.days[day] ?? 0)) token")
                    }
                }
            }.frame(minHeight: 30, maxHeight: 90)
            HStack { Text(dates.first!, format: .dateTime.day().month()); Spacer(); Text(dates.last!, format: .dateTime.day().month()) }.font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
    private func rankings(_ values: [(String, Double)]) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(values.prefix(model.prefs.agentDensity == "expanded" ? 6 : 3).enumerated()), id: \.offset) { _, value in
                HStack {
                    Text(value.0).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(tokenLabel(value.1)).monospacedDigit().foregroundStyle(.secondary)
                }.font(.system(size: 11))
            }
            Text("Token · \(periodTitle)").font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
    private var activity: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let dates = (0..<91).map { cal.date(byAdding: .day, value: $0 - 90, to: today)! }
        let totals = snapshot.dayTotals
        let maxValue = max(1, totals.values.max() ?? 1)
        return HStack(spacing: 12) {
            LazyHGrid(rows: Array(repeating: GridItem(.fixed(9), spacing: 3), count: 7), spacing: 3) {
                ForEach(dates, id: \.self) { day in
                    let value = totals[day] ?? 0
                    RoundedRectangle(cornerRadius: 2).fill(.white.opacity(value > 0 ? 0.25 + 0.75 * sqrt(value / maxValue) : 0.08)).frame(width: 9, height: 9)
                        .help("\(day.formatted(date: .abbreviated, time: .omitted)) · \(tokenLabel(value)) token")
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(tokenLabel(dates.reduce(0) { $0 + (totals[$1] ?? 0) })).font(.title3.bold())
                Text("13 settimane").font(.system(size: 9)).foregroundStyle(.secondary)
                Text("\(dates.filter { (totals[$0] ?? 0) > 0 }.count) giorni attivi").font(.system(size: 9))
            }
        }
    }
}
