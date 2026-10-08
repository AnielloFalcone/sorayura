import AppKit
import SwiftUI

struct ScreenView: View {
    let screen: NSScreen
    @Environment(Model.self) private var model
    @State private var dragOrigins: [String:Point] = [:]
    @State private var animationScaleOrigin: Double? = nil
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment:.topLeading) {
                Image(nsImage: WallpaperRenderer.image(for:screen,prefs:model.prefs))
                    .resizable().scaledToFill().frame(width:geometry.size.width,height:geometry.size.height).clipped()
                if model.editing && model.prefs.layout == "grid" {
                    Canvas { context, size in
                        var grid = Path()
                        let spacing = max(40, model.prefs.cellSize)
                        for x in stride(from:0.0,through:Double(size.width),by:spacing) {
                            grid.move(to:CGPoint(x:x,y:0))
                            grid.addLine(to:CGPoint(x:x,y:size.height))
                        }
                        for y in stride(from:0.0,through:Double(size.height),by:spacing) {
                            grid.move(to:CGPoint(x:0,y:y))
                            grid.addLine(to:CGPoint(x:size.width,y:y))
                        }
                        context.stroke(grid,with:.color(.cyan.opacity(0.25)),lineWidth:1)
                    }
                    .frame(width:geometry.size.width,height:geometry.size.height)
                    .allowsHitTesting(false)
                }
                if model.content(screen).animation && model.prefs.animationStyle != "off" {
                    AnimationView(screen:screen).environment(model)
                        .frame(width:geometry.size.width,height:geometry.size.height).allowsHitTesting(false)
                    if model.editing {
                        animationEditor(in: geometry.size)
                    }
                }
                ForEach(model.performanceVariant.hidesWidgets ? [] : model.content(screen).widgets,id:\.self) { id in
                    draggable(id,at:model.position(id,screen),in:geometry.size) {
                        WidgetView(id:id).environment(model)
                            .frame(width:dimension(id,"width"),height:dimension(id,"height"))
                    }
                }
                if model.editing {
                    VStack {
                        HStack(spacing:12) {
                            Text("Modifica layout · \(screen.localizedName)").bold()
                            Picker("Posizione",selection:Bindable(model).prefs.layout) {
                                Text("Libero").tag("free"); Text("Griglia").tag("grid")
                            }.pickerStyle(.segmented).frame(width:160)
                            Menu("Aggiungi") {
                                ForEach(Model.widgetIDs.filter { !model.content(screen).widgets.contains($0) }, id: \.self) { id in
                                    Button(Model.names[id] ?? id) {
                                        var content = model.content(screen)
                                        content.widgets.append(id)
                                        model.setContent(screen, content)
                                    }
                                }
                                if !model.content(screen).animation {
                                    Button("Animazione") {
                                        var content = model.content(screen)
                                        content.animation = true
                                        if model.prefs.animationStyle == "off" { model.prefs.animationStyle = "aurora" }
                                        model.setContent(screen, content)
                                    }
                                }
                            }
                            Button("Fine") { model.editing = false }
                        }
                        .padding(12).wallpaperGlass(cornerRadius:14)
                        Spacer()
                    }.frame(maxWidth:.infinity).padding(.top,40)
                }
                if model.identifyUntil > Date() {
                    TimelineView(.periodic(from:.now,by:0.2)) { _ in
                        if model.identifyUntil > Date() {
                            ZStack {
                                Color.black.opacity(0.65)
                                VStack {
                                    Text("\(orderedScreens().first == screen ? 1 : (orderedScreens().firstIndex(of:screen) ?? 0)+1)").font(.system(size:260,weight:.semibold,design:.rounded))
                                    Text(screen.localizedName).font(.largeTitle)
                                }.foregroundStyle(.white)
                            }.frame(width:geometry.size.width,height:geometry.size.height).allowsHitTesting(false)
                        }
                    }
                }
            }.frame(width:geometry.size.width,height:geometry.size.height)
        }.ignoresSafeArea()
            .environment(\.wallpaperGlassDisabled, model.performanceVariant.disablesGlass)
    }
    private func dimension(_ id:String,_ axis:String) -> CGFloat {
        let units = model.widgetUnits(id, axis: axis)
        return min(CGFloat(units)*model.prefs.cellSize, axis == "width" ? screen.frame.width : screen.frame.height)
    }
    private func animationEditor(in size: CGSize) -> some View {
        let point = model.animationPosition(screen)
        let frame = AnimationView.visualSize(style: model.prefs.animationStyle,
                                             bounds: size, scale: model.animationScale(screen))
        return RoundedRectangle(cornerRadius: 20)
            .fill(.cyan.opacity(0.035))
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(.cyan.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [7])) }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                let start = dragOrigins["animation"] ?? point
                if dragOrigins["animation"] == nil { dragOrigins["animation"] = start }
                let x = min(100, max(0, start.x + value.translation.width / max(1, size.width) * 100))
                let y = min(100, max(0, start.y + value.translation.height / max(1, size.height) * 100))
                let cell = max(40, model.prefs.cellSize)
                let px = model.prefs.layout == "grid" ? (Double((x * size.width / 100 / cell).rounded()) * cell / size.width * 100) : x
                let py = model.prefs.layout == "grid" ? (Double((y * size.height / 100 / cell).rounded()) * cell / size.height * 100) : y
                model.setAnimationPosition(screen, Point(x: px, y: py))
            }.onEnded { _ in dragOrigins["animation"] = nil })
            .overlay(alignment: .topLeading) {
                Text("✥ Animazione · trascina per spostare")
                    .font(.caption).padding(10).wallpaperGlass(cornerRadius: 12)
                    .padding(10).allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                Button { remove("animation") } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red).font(.title2)
                }
                .buttonStyle(.plain).padding(10)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .wallpaperGlass(cornerRadius: 12)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                        let start = animationScaleOrigin ?? model.animationScale(screen)
                        if animationScaleOrigin == nil { animationScaleOrigin = start }
                        let dx = Double(value.translation.width / max(1, frame.width))
                        let dy = Double(value.translation.height / max(1, frame.height))
                        let delta = abs(dx) > abs(dy) ? dx : dy
                        model.setAnimationScale(screen, start * (1 + delta))
                    }.onEnded { _ in animationScaleOrigin = nil })
                    .padding(10)
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: size.width * point.x / 100, y: size.height * point.y / 100)
    }
    private func draggable<Content:View>(_ id:String,at point:Point,in size:CGSize,@ViewBuilder content:()->Content) -> some View {
        let width = dimension(id,"width")
        let height = dimension(id,"height")
        let x = min(max(0,size.width*point.x/100),max(0,size.width-width))
        let y = min(max(0,size.height*point.y/100),max(0,size.height-height))
        return content()
            .frame(width: width, height: height)
            .overlay(alignment:.topTrailing) {
                if model.editing {
                    Button { remove(id) } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(.red).font(.title2) }
                        .buttonStyle(.plain).offset(x:9,y:-9)
                }
            }
            .overlay { if model.editing { RoundedRectangle(cornerRadius:16).stroke(.cyan.opacity(0.75),style:StrokeStyle(lineWidth:1,dash:[5])) } }
            .position(x:x+width/2,y:y+height/2)
            .gesture(model.editing ? DragGesture(minimumDistance:1).onChanged { value in
                let start = dragOrigins[id] ?? point
                if dragOrigins[id] == nil { dragOrigins[id] = start }
                let newX = min(max(0,start.x+value.translation.width/max(1,size.width)*100),100)
                let newY = min(max(0,start.y+value.translation.height/max(1,size.height)*100),100)
                let px = model.prefs.layout == "grid" ? (Double(Int((newX*size.width/100/model.prefs.cellSize).rounded()))*model.prefs.cellSize/size.width*100) : newX
                let py = model.prefs.layout == "grid" ? (Double(Int((newY*size.height/100/model.prefs.cellSize).rounded()))*model.prefs.cellSize/size.height*100) : newY
                model.setPosition(id,screen,Point(x:px,y:py))
            }.onEnded { _ in dragOrigins[id] = nil } : nil)
            .onLongPressGesture(minimumDuration:0.6) { model.editing = true }
    }
    private func remove(_ id:String) {
        var content = model.content(screen)
        if id == "animation" { content.animation = false }
        else { content.widgets.removeAll { $0 == id } }
        model.setContent(screen,content)
    }
}

struct WidgetView: View {
    let id:String
    @Environment(Model.self) private var model
    @Environment(\.wallpaperGlassDisabled) private var glassDisabled
    var body:some View {
        let metrics = model.metrics
        let expanded = (id == "cpu" && model.prefs.cpuDisplay.density == "expanded") || (id == "memory" && model.prefs.memoryDisplay.density == "expanded")
        let chart = id == "cpu" ? model.prefs.cpuDisplay.chart : model.prefs.memoryDisplay.chart
        let color = (Model.metricIDs.contains(id) || id == "thermal") ? Color(nsColor:model.metricColor(id,base:ColorValue(model.prefs.widgetTheme == "cyber" ? "#c89bff" : "#a9d9ff")).color) : .white
        ScrollView {
        VStack(alignment:.leading,spacing:5) {
            if id == "clock" {
                ClockWidget()
            } else if id == "device" {
                Text("●  \(metrics.hostname.uppercased())").font(.system(size:11,weight:.medium)).tracking(2).foregroundStyle(.white.opacity(0.6))
            } else if id == "spotify" {
                SpotifyWidget().environment(model)
            } else if id.hasPrefix("agent") {
                AgentWidget(id: id).environment(model)
            } else if id == "apps" {
                IntegrationWidget().environment(model)
            } else {
                HStack {
                    Text(Model.names[id]?.uppercased() ?? id).font(.system(size:10,weight:.bold)).tracking(2).foregroundStyle(.white.opacity(0.53))
                    if model.severity(id) != "normal" { Text(model.severity(id).uppercased()).font(.system(size:9,weight:.bold)).foregroundStyle(color) }
                }
                Text(value(metrics)).font(.system(size:31,weight:.light)).minimumScaleFactor(0.65).lineLimit(1)
                if let sub = subvalue(metrics) { Text(sub).font(.system(size:11)).foregroundStyle(.white.opacity(0.52)).lineLimit(1) }
                if ["cpu","memory"].contains(id) && chart != "bar" {
                    HistoryView(values:model.history(for: id),filled:chart == "area",color:color).frame(height:55)
                } else if ["cpu","memory","disk","battery"].contains(id) {
                    GeometryReader { geo in
                        ZStack(alignment:.leading) {
                            Capsule().fill(.white.opacity(0.12))
                            Capsule().fill(color).frame(width:geo.size.width*min(1,max(0,metrics.percentage(id)/100)))
                        }
                    }.frame(height:3).padding(.top,8)
                }
                if expanded {
                    Divider().overlay(.white.opacity(0.2)).padding(.vertical,4)
                    if id == "memory" {
                        detail("Memoria fisica",bytes(metrics.memoryTotal))
                        detail("Memoria usata",bytes(metrics.memoryUsed))
                        detail("File nella cache",bytes(metrics.memoryCached))
                        detail("Swap usato",bytes(metrics.swapUsed))
                        detail("Memoria app",bytes(metrics.memoryApp))
                        detail("Memoria vincolata",bytes(metrics.memoryWired))
                        detail("Compressa",bytes(metrics.memoryCompressed))
                    } else {
                        let average = (model.history(for: "cpu")).reduce(0,+)/Double(max(1,model.history(for: "cpu").count))
                        detail("Media · 90 s",String(format:"%.0f%%",average))
                    }
                }
            }
            Spacer(minLength:0)
            if model.editing && id != "clock" && id != "device" {
                HStack(spacing:8) {
                    Picker("↔", selection: Binding(get: { model.widgetUnits(id, axis: "width") }, set: { model.prefs.widths[id] = $0 })) {
                        ForEach(1...model.maximumUnits(axis: "width"), id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("↕", selection: Binding(get: { model.widgetUnits(id, axis: "height") }, set: { model.prefs.heights[id] = $0 })) {
                        ForEach(1...model.maximumUnits(axis: "height"), id: \.self) { Text("\($0)").tag($0) }
                    }
                }.font(.system(size:9)).controlSize(.mini)
            }
        }
        .padding(id == "clock" ? 0 : 16)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .clipped()
         .background {
            if id != "clock" && id != "device" {
                if model.prefs.widgetTheme == "glass" && !glassDisabled {
                    if #available(macOS 26, *) { RoundedRectangle(cornerRadius: 18).fill(.clear).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18)) }
                    else { RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial) }
                } else {
                    RoundedRectangle(cornerRadius: 18).fill(Color(red:0.05,green:0.09,blue:0.16).opacity(model.prefs.widgetTheme == "cyber" ? 0.85 : 0.62))
                }
            }
        }
        .overlay { if id != "clock" && id != "device" { RoundedRectangle(cornerRadius:18).stroke(color.opacity(model.severity(id) == "normal" ? 0.1 : 0.7),lineWidth:1) } }
        .foregroundStyle(.white)
        .contextMenu {
            Button("Modifica layout…") { model.editing = true }
            if ["cpu", "memory"].contains(id) {
                Menu("Dettaglio") {
                    Button("Compatto") { setDisplay(density: "compact") }
                    Button("Esteso") { setDisplay(density: "expanded") }
                }
                Menu("Grafico") {
                    Button("Barra") { setDisplay(chart: "bar") }
                    Button("Linea") { setDisplay(chart: "line") }
                    Button("Area") { setDisplay(chart: "area") }
                }
            }
        }
    }
    private func setDisplay(density: String? = nil, chart: String? = nil) {
        var value = id == "memory" ? model.prefs.memoryDisplay : model.prefs.cpuDisplay
        if let density { value.density = density }; if let chart { value.chart = chart }
        if id == "memory" { model.prefs.memoryDisplay = value } else { model.prefs.cpuDisplay = value }
    }
    private func detail(_ label:String,_ value:String)->some View {
        HStack { Text(label).foregroundStyle(.white.opacity(0.65)); Spacer(); Text(value) }.font(.system(size:10))
    }
    private func value(_ m:MetricReadings)->String {
        switch id {
        case "thermal": return ThermalPresentation.title(m.thermal)
        case "cpu": return String(format:"%.0f%%",m.cpu)
        case "memory": return String(format:"%.0f%%",m.memory)
        case "disk": return String(format:"%.0f%%",m.disk)
        case "battery": return m.battery.map { String(format:"%.0f%%",$0) } ?? "—"
        case "network": return "↓ \(networkRate(m.download))"
        case "uptime": return "\(Int(m.uptime/86400))g \(Int(m.uptime.truncatingRemainder(dividingBy:86400)/3600))h"
        default: return "—"
        }
    }
    private func subvalue(_ m:MetricReadings)->String? {
        switch id {
        case "thermal": return m.lowPower ? "Risparmio energetico attivo" : "Stato macOS · non temperatura in °C"
        case "memory": return "\(bytes(m.memoryUsed)) / \(bytes(m.memoryTotal))"
        case "disk": return "\(bytes(m.diskUsed)) / \(bytes(m.diskTotal))"
        case "network": return "↑ \(networkRate(m.upload))"
        case "battery": return m.charging ? "In carica" : "A batteria"
        default: return nil
        }
    }
}

private struct ClockWidget: View {
    private var minuteBoundary: Date {
        Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60)
    }
    var body: some View {
        TimelineView(.periodic(from: minuteBoundary, by: 60)) { context in
            VStack(alignment: .leading, spacing: 5) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 64, weight: .ultraLight, design: .rounded)).monospacedDigit()
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
    }
}

func bytes(_ value:Double)->String {
    if value < 1024 { return String(format:"%.0f B",value) }
    if value < 1_048_576 { return String(format:"%.0f KB",value/1024) }
    if value < 1_073_741_824 { return String(format:"%.1f MB",value/1_048_576) }
    return String(format:"%.1f GB",value/1_073_741_824)
}

struct HistoryView:View {
    let values:[Double]
    let filled:Bool
    let color:Color
    var body:some View {
        GeometryReader { geometry in
            Canvas { context,size in
                guard values.count > 1 else { return }
                var path = Path()
                for (index,value) in values.enumerated() {
                    let point = CGPoint(x:CGFloat(index)/CGFloat(max(1,values.count-1))*size.width,y:size.height*(1-CGFloat(value)/100))
                    if index == 0 { path.move(to:point) } else { path.addLine(to:point) }
                }
                if filled {
                    var area = path; area.addLine(to:CGPoint(x:size.width,y:size.height)); area.addLine(to:CGPoint(x:0,y:size.height)); area.closeSubpath()
                    context.fill(area,with:.color(color.opacity(0.2)))
                }
                context.stroke(path,with:.color(color),lineWidth:1.4)
            }.frame(width:geometry.size.width,height:geometry.size.height)
        }
    }
}
