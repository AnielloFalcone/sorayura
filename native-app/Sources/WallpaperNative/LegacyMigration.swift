import AppKit
import SQLite3

@MainActor
enum LegacyMigration {
    static func load() -> Prefs? {
        let root = FileManager.default.homeDirectoryForCurrentUser.appending(path:"Library/WebKit/macbook-system-wallpaper/WebsiteData/Default")
        guard let enumerator = FileManager.default.enumerator(at:root,includingPropertiesForKeys:nil) else { return nil }
        for case let file as URL in enumerator where file.lastPathComponent == "localstorage.sqlite3" {
            if let prefs = read(file) { return prefs }
        }
        return nil
    }
    private static func read(_ file:URL)->Prefs? {
        var database:OpaquePointer?
        guard sqlite3_open_v2(file.path,&database,SQLITE_OPEN_READONLY,nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(database) }
        var statement:OpaquePointer?
        guard sqlite3_prepare_v2(database,"SELECT value FROM ItemTable WHERE key = 'mac-system-wallpaper.preferences.v1'",-1,&statement,nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(statement,0) else { return nil }
        let data = Data(bytes:bytes,count:Int(sqlite3_column_bytes(statement,0)))
        guard let json = String(data:data,encoding:.utf16LittleEndian)?.data(using:.utf8),
              let raw = try? JSONSerialization.jsonObject(with:json) as? [String:Any] else { return nil }
        return convert(raw)
    }
    private static func convert(_ raw:[String:Any])->Prefs {
        var prefs = Prefs()
        prefs.wallpaper = raw["wallpaper"] as? String ?? prefs.wallpaper
        prefs.syncWallpaper = raw["syncMacWallpaper"] as? Bool ?? true
        if let image = raw["image"] as? String,
           let comma = image.firstIndex(of:","),
           let data = Data(base64Encoded:String(image[image.index(after:comma)...])) {
            let file = Model.preferencesURL.deletingLastPathComponent().appending(path:"imported-wallpaper.jpg")
            try? FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
            try? data.write(to:file,options:.atomic)
            prefs.imagePath = file.path
        }
        if let layout = raw["layout"] as? [String:Any] {
            prefs.layout = layout["mode"] as? String ?? prefs.layout
            prefs.cellSize = layout["cellSize"] as? Double ?? prefs.cellSize
            for (key,target) in [("sizes","width"),("heights","height")] {
                if let values = layout[key] as? [String:Int] {
                    if target == "width" { prefs.widths.merge(values){_,new in new} }
                    else { prefs.heights.merge(values){_,new in new} }
                }
            }
        }
        if let animation = raw["animation"] as? [String:Any] {
            prefs.animationStyle = animation["style"] as? String ?? prefs.animationStyle
            if let layers = animation["layers"] as? [[String:Any]] {
                prefs.layers = layers.compactMap { item in
                    guard let metric=item["metric"] as? String,Model.metricIDs.contains(metric) else { return nil }
                    return Layer(metric:metric,color:ColorValue(item["color"] as? String ?? "#82c4ff"))
                }
            }
            if let point = point(animation["position"]) {
                for screen in NSScreen.screens { prefs.animationPositions[screenID(screen)] = point }
            }
        }
        if let displaySettings = raw["widgetDisplay"] as? [String:[String:String]] {
            if let cpu=displaySettings["cpu"] { prefs.cpuDisplay = WidgetDisplay(chart:cpu["chart"] ?? "bar",density:cpu["density"] ?? "compact") }
            if let memory=displaySettings["memory"] { prefs.memoryDisplay = WidgetDisplay(chart:memory["chart"] ?? "bar",density:memory["density"] ?? "compact") }
        }
        if let alerts = raw["alerts"] as? [String:Any] {
            prefs.alerts=alerts["enabled"] as? Bool ?? true
            prefs.warningColor=ColorValue(alerts["warningColor"] as? String ?? "#ffbd59")
            prefs.criticalColor=ColorValue(alerts["criticalColor"] as? String ?? "#ff5b68")
            prefs.networkScaleMBps=alerts["networkScaleMBps"] as? Double ?? 20
            if let thresholds=alerts["thresholds"] as? [String:[String:Double]] {
                for (metric,t) in thresholds { prefs.thresholds[metric]=Threshold(warning:t["warning"] ?? 75,critical:t["critical"] ?? 90) }
            }
        }
        let ordered = orderedScreens()
        let displayContent = raw["displayContent"] as? [String:[String:Any]] ?? [:]
        let defaultWidgets = raw["widgets"] as? [String] ?? DisplayContent().widgets
        let positions = raw["positions"] as? [String:[String:Double]] ?? [:]
        let layouts = raw["displays"] as? [String:[String:Any]] ?? [:]
        for (index,screen) in ordered.enumerated() {
            let oldKey = index == 0 ? "main" : "wallpaper-\(index)"
            let id = screenID(screen)
            let content = displayContent[oldKey] ?? [:]
            prefs.displays[id] = DisplayContent(widgets:(content["widgets"] as? [String] ?? defaultWidgets).filter { Model.widgetIDs.contains($0) }, animation:content["animation"] as? Bool ?? true)
            let local = (layouts[oldKey]?["positions"] as? [String:[String:Double]]) ?? positions
            prefs.positions[id] = local.compactMapValues { item in point(item) }
            if let animationPoint = point(layouts[oldKey]?["animationPosition"]) { prefs.animationPositions[id] = animationPoint }
        }
        return prefs
    }
    private static func point(_ raw:Any?)->Point? {
        guard let p=raw as? [String:Double],let x=p["x"],let y=p["y"] else { return nil }
        return Point(x:min(100,max(0,x)),y:min(100,max(0,y)))
    }
    private static func screenID(_ screen:NSScreen)->String {
        String((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0)
    }
    private static func orderedScreens()->[NSScreen] {
        guard let primary=NSScreen.screens.first else { return [] }
        return [primary]+NSScreen.screens.dropFirst().sorted { $0.frame.minX == $1.frame.minX ? $0.frame.minY < $1.frame.minY : $0.frame.minX < $1.frame.minX }
    }
}
