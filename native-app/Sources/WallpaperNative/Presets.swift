import AppKit

struct SettingsArchive: Codable {
    var version = 1
    var displayOrder: [String]
    var settings: Prefs
    var imageData: Data? = nil

    func validated() throws -> SettingsArchive {
        guard version == 1 else { throw SettingsError.invalid("Versione del file non supportata.") }
        try settings.validate()
        guard displayOrder.count <= 32, Set(displayOrder).count == displayOrder.count else {
            throw SettingsError.invalid("Elenco monitor non valido.")
        }
        if let imageData, imageData.count > 25_000_000 || NSImage(data: imageData) == nil {
            throw SettingsError.invalid("Immagine dello sfondo non valida o troppo grande.")
        }
        return self
    }

    func mapped(to displayKeys: [String], displaySizes: [String: NSSize] = [:]) -> Prefs {
        var result = settings
        var remaining = displayOrder.filter { !displayKeys.contains($0) }
        for key in displayKeys {
            let source: String?
            if settings.displays[key] != nil { source = key }
            else if !remaining.isEmpty { source = remaining.removeFirst() }
            else { source = displayOrder.first }
            guard let source else { continue }
            result.displays[key] = settings.displays[source] ?? DisplayContent()
            result.positions[key] = settings.positions[source] ?? Prefs.defaults
            if let sizes = settings.widgetSizes?[source] {
                if result.widgetSizes == nil { result.widgetSizes = [:] }
                result.widgetSizes?[key] = sizes
            } else { result.widgetSizes?.removeValue(forKey: key) }
            result.animationPositions[key] = settings.animationPositions[source] ?? Point(x: 50, y: 50)
            result.animationScales = result.animationScales ?? [:]
            result.animationScales?[key] = settings.animationScales?[source] ?? 1
        }
        return result
    }
}

struct SavedPreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var archive: SettingsArchive
}

enum SettingsError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let text): return L(text) } }
}

struct BuiltInPreset: Identifiable {
    let id: String
    let name: String
    let description: String
    let color: String
    static let all: [BuiltInPreset] = [
        .init(id: "minimal", name: "Minimal", description: "Orologio, CPU e memoria. Pochi elementi, nessuna animazione.", color: "#c7d8e9"),
        .init(id: "glass", name: "Glass", description: "Superfici in vetro e Aurora con CPU, memoria e rete.", color: "#89d8ff"),
        .init(id: "monitoring", name: "Monitoraggio", description: "Grafici storici, memoria estesa e tutte le risorse.", color: "#9ae4be"),
        .init(id: "cyber", name: "Cyber", description: "Accenti luminosi e nucleo con più risorse.", color: "#df89ff"),
        .init(id: "ai", name: "AI Studio", description: "Utilizzo agenti, attività live, grafici e controlli Spotify.", color: "#8997ee")
    ]
    func settings(from current: Prefs, displayKeys: [String], displaySizes: [String: NSSize] = [:]) -> Prefs {
        var result = current
        result.widgetSizes = nil
        result.animationBoxes = nil
        if id == "ai" {
            result.widgetTheme = "glass"; result.animationStyle = "off"; result.layout = "free"; result.cellSize = 120
            let widgets = ["agents", "agentLive", "spotify", "agentTrend", "agentModels", "agentProjects", "agentActivity", "agentSpending"]
            for widget in widgets { result.widths[widget] = 3; result.heights[widget] = ["agents", "agentLive", "spotify", "agentActivity"].contains(widget) ? 2 : 1 }
            let units = displaySizes.values.contains { $0.width < 1236 } ? 2 : 3
            for widget in widgets { result.widths[widget] = units }
            for key in displayKeys {
                let size = displaySizes[key] ?? NSSize(width: 1440, height: 900)
                let width = Double(units) * 120 + Double(units - 1) * 10
                let columns = max(1, Int((size.width - 48 + 16) / (width + 16)))
                var positions: [String: Point] = [:], top = 40.0
                for rowStart in stride(from: 0, to: widgets.count, by: columns) {
                    let row = Array(widgets[rowStart..<min(widgets.count, rowStart + columns)])
                    for (column, widget) in row.enumerated() {
                        positions[widget] = Point(x: (24 + Double(column) * (width + 16)) / size.width * 100, y: top / size.height * 100)
                    }
                    let rowUnits: Int = row.map { result.heights[$0] ?? 1 }.max() ?? 1
                    let height: Double = Double(rowUnits * 120 + (rowUnits - 1) * 10)
                    top += height + 16
                }
                result.displays[key] = DisplayContent(widgets: widgets, animation: false)
                result.positions[key] = positions
            }
            return result
        }
        result.widgetTheme = id == "glass" ? "glass" : id == "cyber" ? "cyber" : "minimal"
        result.wallpaper = id == "glass" ? "gradient" : "midnight"
        result.imagePath = nil
        result.layout = "free"
        result.cellSize = 130
        result.widths = Prefs().widths
        result.heights = [:]
        result.cpuDisplay = WidgetDisplay(chart: id == "monitoring" ? "line" : "bar", density: "compact")
        result.memoryDisplay = WidgetDisplay(chart: id == "monitoring" ? "area" : "bar", density: id == "monitoring" ? "expanded" : "compact")
        result.animationStyle = id == "minimal" ? "off" : id == "glass" ? "aurora" : id == "monitoring" ? "traces" : "jarvis"
        result.layers = [Layer(metric: "cpu", color: ColorValue("#dd8cff")), Layer(metric: "memory", color: ColorValue("#74baff")), Layer(metric: "network", color: ColorValue("#89e2b5"))]
        if id == "monitoring" { result.heights["memory"] = 3; result.heights["cpu"] = 2 }
        let widgets = id == "minimal" ? ["clock", "cpu", "memory"] : id == "monitoring" ? Model.systemWidgetIDs : ["clock", "cpu", "memory", "network", "battery"]
        for key in displayKeys {
            result.displays[key] = DisplayContent(widgets: widgets, animation: id != "minimal")
            var positions = Prefs.defaults
            if id == "monitoring" {
                positions["clock"] = Point(x: 5, y: 8)
                positions["device"] = Point(x: 5, y: 23)
                positions["memory"] = Point(x: 5, y: 34)
                positions["cpu"] = Point(x: 77, y: 8)
                positions["network"] = Point(x: 77, y: 25)
                positions["battery"] = Point(x: 77, y: 42)
                positions["disk"] = Point(x: 77, y: 59)
                positions["uptime"] = Point(x: 77, y: 76)
            }
            if let size = displaySizes[key], size.width > 0, size.height > 0 {
                let right = widgets.filter { $0 != "clock" && $0 != "device" && !(id == "monitoring" && $0 == "memory") }
                let width = 2 * result.cellSize + 10
                let totalHeight = right.reduce(0.0) { total, widget in
                    let units = result.heights[widget] ?? 1
                    return total + Double(units) * result.cellSize + Double(units - 1) * 10
                }
                let gap = max(4, min(18, (size.height - 48 - totalHeight) / Double(max(1, right.count - 1))))
                var top = 24.0
                for widget in right {
                    positions[widget] = Point(x: max(0, size.width - width - 40) / size.width * 100, y: top / size.height * 100)
                    let units = result.heights[widget] ?? 1
                    top += Double(units) * result.cellSize + Double(units - 1) * 10 + gap
                }
                positions["clock"] = Point(x: 5, y: 7)
                if id == "monitoring" {
                    positions["device"] = Point(x: 5, y: 185 / size.height * 100)
                    positions["memory"] = Point(x: 5, y: min(230, max(0, size.height - 430)) / size.height * 100)
                }
            }
            result.positions[key] = positions
            result.animationPositions[key] = Point(x: 47, y: 56)
            result.animationScales = result.animationScales ?? [:]
            result.animationScales?[key] = id == "monitoring" ? 0.7 : 0.85
        }
        return result
    }
}

extension Prefs {
    func validate() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw SettingsError.invalid(message) }
        }
        try require(["today", "week", "month", "all"].contains(agentPeriod ?? "all"), "Periodo AI non valido.")
        try require(["compact", "expanded"].contains(agentDensity ?? "compact"), "Dettaglio AI non valido.")
        try require(["gradient", "midnight", "image"].contains(wallpaper), "Sfondo non valido.")
        try require(["off", "aurora", "pulse", "traces", "jarvis"].contains(animationStyle), "Animazione non valida.")
        try require(["free", "grid"].contains(layout), "Layout non valido.")
        try require(["minimal", "glass", "cyber"].contains(widgetTheme ?? "minimal"), "Tema non valido.")
        try require(cellSize.isFinite && (80...220).contains(cellSize), "La griglia deve essere fra 80 e 220 punti.")
        try require(networkScaleMBps.isFinite && networkScaleMBps > 0, "Scala della rete non valida.")
        for units in Array(widths.values) + Array(heights.values) { try require((1...100).contains(units), "Dimensione widget non valida.") }
        for sizes in (widgetSizes ?? [:]).values {
            for (id, size) in sizes {
                try require(Model.widgetIDs.contains(id) && size.width.isFinite && size.height.isFinite &&
                            (1...100_000).contains(size.width) && (1...100_000).contains(size.height), "Dimensione widget non valida.")
            }
        }
        for content in displays.values {
            try require(Set(content.widgets).count == content.widgets.count && content.widgets.allSatisfy(Model.widgetIDs.contains), "Elenco widget non valido.")
        }
        for point in positions.values.flatMap({ $0.values }) + Array(animationPositions.values) {
            try require(point.x.isFinite && point.y.isFinite && (0...100).contains(point.x) && (0...100).contains(point.y), "Posizione non valida.")
        }
        for scale in (animationScales ?? [:]).values { try require(scale.isFinite && (0.5...1.8).contains(scale), "Dimensione animazione non valida.") }
        try require(Set(layers.map(\.metric)).count == layers.count && layers.allSatisfy { Model.animationSourceIDs.contains($0.metric) }, "Livelli animazione non validi.")
        for (side, fields) in animationBoxes ?? [:] {
            try require(Model.animationSides.contains(side) && Set(fields).count == fields.count && fields.allSatisfy(Model.animationFieldIDs.contains), "Livelli animazione non validi.")
        }
        for color in layers.map(\.color) + [warningColor, criticalColor] {
            try require(color.hex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil, "Colore non valido.")
        }
        for display in [cpuDisplay, memoryDisplay] {
            try require(["bar", "area", "line"].contains(display.chart) && ["compact", "expanded"].contains(display.density), "Grafico non valido.")
        }
        for (key, threshold) in thresholds {
            try require(threshold.warning.isFinite && threshold.critical.isFinite && threshold.warning >= 0 && threshold.critical >= 0, "Soglie non valide.")
            try require(key == "battery" ? threshold.critical <= threshold.warning : threshold.warning <= threshold.critical, "Ordine delle soglie non valido.")
        }
    }
}
