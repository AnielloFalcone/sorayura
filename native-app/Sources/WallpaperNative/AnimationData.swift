import AppKit

struct AnimationReading {
    var value: String
    var fraction: Double? = nil
    var title: String? = nil
}

extension Model {
    nonisolated static let animationSides = ["right", "left", "top", "bottom"]
    nonisolated static let animationSourceIDs = metricIDs + ["claudeSession", "claudeWeek", "codexSession", "codexWeek"]
    nonisolated static let animationFieldIDs = widgetIDs + ["claudeSession", "claudeWeek", "codexSession", "codexWeek"]
    nonisolated static func animationTitle(_ id: String) -> String {
        let extra = ["claudeSession": "Claude · Sessione", "claudeWeek": "Claude · Settimana", "codexSession": "Codex · Sessione", "codexWeek": "Codex · Settimana"]
        return extra[id].map(L) ?? localizedName(id)
    }
    func animationFields(_ side: String) -> [String] {
        if let boxes = prefs.animationBoxes { return boxes[side] ?? [] }
        return side == "right" ? prefs.layers.map(\.metric) : []
    }
    func setAnimationFields(_ fields: [String], side: String) {
        var boxes = prefs.animationBoxes ?? ["right": prefs.layers.map(\.metric)]
        boxes[side] = fields
        prefs.animationBoxes = boxes
    }
    func animationReading(_ id: String, now: Date = Date()) -> AnimationReading {
        let unavailable = AnimationReading(value: L("Non disponibile"))
        if id.hasPrefix("agent") || id.hasPrefix("claude") || id.hasPrefix("codex") {
            guard prefs.agentUsageEnabled == true else { return AnimationReading(value: L("Attiva da Integrazioni")) }
        }
        switch id {
        case "cpu", "memory", "disk", "battery":
            if id == "battery", metrics.battery == nil { return unavailable }
            let value = metrics.percentage(id)
            return AnimationReading(value: String(format: "%.0f%%", locale: Localizer.locale, value), fraction: min(1, max(0, value / 100)))
        case "network":
            return AnimationReading(value: "↓ \(networkRate(metrics.download))", fraction: min(1, max(0, metrics.percentage(id) / max(0.1, prefs.networkScaleMBps))), title: LF("RETE · ↑ \(networkRate(metrics.upload))"))
        case "thermal": return AnimationReading(value: L(ThermalPresentation.title(metrics.thermal)))
        case "clock":
            _ = metrics.uptime // Use the existing sampler for refresh; no extra timer.
            return AnimationReading(value: now.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Localizer.locale)))
        case "uptime": return AnimationReading(value: LF("\(Int(metrics.uptime / 86400))g \(Int(metrics.uptime.truncatingRemainder(dividingBy: 86400) / 3600))h"))
        case "device": return AnimationReading(value: metrics.hostname)
        case "apps":
            guard prefs.appStatusEnabled == true else { return AnimationReading(value: L("Attiva da Integrazioni")) }
            return AnimationReading(value: appPresence.filter(\.running).map(\.name).joined(separator: " · ").nilIfEmpty ?? L("Nessuna"))
        case "spotify":
            guard prefs.spotifyEnabled == true else { return AnimationReading(value: L("Attiva da Integrazioni")) }
            return AnimationReading(value: spotify.available ? spotify.title + (spotify.artist.isEmpty ? "" : " · " + spotify.artist) : L(spotify.title))
        case "claudeSession", "claudeWeek", "codexSession", "codexWeek":
            let quota: AgentQuota?
            if id.hasPrefix("claude") {
                let local = agentUsage.claudeSessions.max(by: { $0.date < $1.date })?.quota
                let desktop = agentUsage.claudeDesktop?.quota
                quota = (desktop?.date ?? .distantPast) > (local?.date ?? .distantPast) ? desktop : local ?? desktop
            } else { quota = prefs.codexAccountEnabled == true ? codexAccount.quota ?? agentUsage.codexQuota : agentUsage.codexQuota }
            guard let quota, let limit = id.hasSuffix("Week") ? quota.week : quota.session else {
                if id == "claudeSession", let date = agentUsage.claudeDesktop?.quota.date, now.timeIntervalSince(date) >= 300 * 60 {
                    return AnimationReading(value: L("Lettura scaduta"), title: L("Claude · apri l’app per aggiornare"))
                }
                if id.hasPrefix("codex"), prefs.codexAccountEnabled == true {
                    return AnimationReading(value: L(updatingCodexAccount ? "Aggiornamento…" : "Limiti non disponibili"))
                }
                return unavailable
            }
            if let reset = limit.reset, reset <= now {
                return AnimationReading(value: L(id.hasPrefix("codex") && updatingCodexAccount ? "Aggiornamento…" : "Lettura scaduta"))
            }
            let text = String(format: "%.0f%%", locale: Localizer.locale, limit.used)
            if now.timeIntervalSince(quota.date) > 1800 { return AnimationReading(value: text + " · " + L("Lettura non recente")) }
            return AnimationReading(value: text, fraction: min(1, max(0, limit.used / 100)))
        default: break
        }
        guard agentUsage.updated != nil else { return unavailable }
        let summary = agentUsage.periods[prefs.agentPeriod ?? "all"] ?? AgentPeriodSummary()
        switch id {
        case "agents", "agentTrend": return AnimationReading(value: tokenLabel(summary.tokens) + " token")
        case "agentModels": return AnimationReading(value: summary.models.first.map { $0.0 + " · " + tokenLabel($0.1) } ?? L("Non disponibile"))
        case "agentProjects": return AnimationReading(value: summary.projects.first.map { $0.0 + " · " + tokenLabel($0.1) } ?? L("Non disponibile"))
        case "agentActivity":
            let start = Calendar.current.date(byAdding: .day, value: -90, to: Calendar.current.startOfDay(for: now)) ?? now
            let days = agentUsage.dayTotals.filter { $0.key >= start && $0.key <= now && $0.value > 0 }.count
            return AnimationReading(value: LF("\(days) giorni attivi"))
        case "agentSpending":
            let claude = agentUsage.claudeSessions.compactMap(\.apiValue)
            let codex = Array(codexAccount.costs.values)
            guard !claude.isEmpty || !codex.isEmpty else { return unavailable }
            return AnimationReading(value: String(format: "$%.2f", locale: Localizer.locale, claude.reduce(0,+) + codex.reduce(0,+)))
        case "agentNow": return AnimationReading(value: agentUsage.events.last.map { $0.provider + " · " + $0.project } ?? L("Non disponibile"))
        case "agentLive": return AnimationReading(value: liveAgents.last.map { $0.provider + " · " + L($0.displayState(now: now)) } ?? L("Non disponibile"))
        default: return unavailable
        }
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

struct AnimationBoxGeometry {
    var frame: CGRect
    var rows: Int
    var columnWidth: CGFloat
    static func layout(side: String, bounds: CGSize, visual: CGSize, point: Point, count: Int) -> Self {
        let center = CGPoint(x: bounds.width * point.x / 100, y: bounds.height * point.y / 100)
        let horizontal = ["top", "bottom"].contains(side)
        let maxRows = max(1, Int((bounds.height * (horizontal ? 0.30 : 0.90) - 24) / 57))
        let maxColumns = max(1, Int((bounds.width - 24) / 220))
        let columns = min(maxColumns, max(1, Int(ceil(Double(count) / Double(maxRows)))))
        let rows = max(1, Int(ceil(Double(count) / Double(columns))))
        let columnWidth = min(220, max(1, (bounds.width - 24) / CGFloat(columns)))
        let size = CGSize(width: CGFloat(columns) * columnWidth, height: min(max(1, bounds.height - 24), CGFloat(rows) * 57 + 15))
        var x = center.x - size.width / 2, y = center.y - size.height / 2
        switch side {
        case "left": x = center.x - visual.width / 2 - size.width - 24
        case "top": y = center.y - visual.height / 2 - size.height - 24
        case "bottom": y = center.y + visual.height / 2 + 24
        default: x = center.x + visual.width / 2 + 24
        }
        x = min(max(12, x), max(12, bounds.width - size.width - 12))
        y = min(max(12, y), max(12, bounds.height - size.height - 12))
        return Self(frame: CGRect(origin: CGPoint(x: x, y: y), size: size), rows: rows, columnWidth: columnWidth)
    }
}
