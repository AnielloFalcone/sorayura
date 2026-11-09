import AppKit

@MainActor enum ClipboardChecks {
    static func run() throws {
        func check(_ passed: Bool, _ message: String) throws { if !passed { throw SettingsError.invalid(message) } }
        for type in ClipboardPolicy.ignoredTypes {
            try check(!ClipboardPolicy.accepts(types: [type, NSPasteboard.PasteboardType.string.rawValue], sources: [], excluded: []), "Sensitive pasteboard marker was accepted")
        }
        try check(!ClipboardPolicy.accepts(types: [], sources: ["com.1password.1password"], excluded: []), "Password-manager source was accepted")
        try check(!ClipboardPolicy.accepts(types: [], sources: ["test.private"], excluded: ["test.private"]), "Excluded source was accepted")
        try check(!ClipboardPolicy.validText(" \n") && !ClipboardPolicy.validText(String(repeating: "é", count: 8193)), "Empty or oversized text was accepted")
        let now = Date()
        var entries = ClipboardPolicy.adding("  indented\ntext", date: now, sourceID: "test", sourceName: "App", to: [], limit: 10)
        entries[0].favorite = true
        let originalID = entries[0].id
        entries = ClipboardPolicy.adding("  indented\ntext", date: now.addingTimeInterval(1), sourceID: "test", sourceName: "App", to: entries, limit: 10)
        try check(entries.count == 1 && entries[0].id == originalID && entries[0].favorite && entries[0].text.hasPrefix("  "), "Deduplication loses pins, identity or text whitespace")
        for i in 0..<30 { entries = ClipboardPolicy.adding("item \(i)", date: now.addingTimeInterval(Double(i + 2)), sourceID: "test", sourceName: "App", to: entries, limit: 10) }
        try check(entries.count == 11 && entries.filter(\.favorite).count == 1 && entries.first?.text == "item 29", "History limit removes favorites or keeps old recent items")
        try check(ClipboardEntry(text: "https://example.com", date: now, sourceID: "", sourceName: "").isLink && !ClipboardEntry(text: "file:///private/test", date: now, sourceID: "", sourceName: "").isLink, "Link classification enables arbitrary schemes")
        let folder = FileManager.default.temporaryDirectory.appending(path: "sorayura-clipboard-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "private/history.json")
        try ClipboardStorage.save(entries, to: file)
        let loaded = try ClipboardStorage.load(file)
        try check(loaded == entries.sorted { $0.date > $1.date }, "Clipboard archive round trip failed")
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        let directoryMode = try FileManager.default.attributesOfItem(atPath: file.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber
        try check(mode?.intValue == 0o600 && directoryMode?.intValue == 0o700, "Clipboard archive permissions are not private")
        let originalFile = try Data(contentsOf: file)
        var rejected = false
        do { try ClipboardStorage.save([entries[0], entries[0]], to: file) } catch { rejected = true }
        let unchangedFile = try Data(contentsOf: file)
        try check(rejected && unchangedFile == originalFile, "Invalid history overwrites the last valid archive")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let store = ClipboardStore(pasteboard: board)
        board.setString("Before enabling", forType: .string); store.sample()
        try check(store.entries.isEmpty, "Disabled clipboard starts collecting")
        store.configure(enabled: true, paused: false, limit: 10, exclusions: [])
        store.sample(); try check(store.entries.isEmpty, "Enable backfills pre-existing clipboard content")
        func write(_ text: String, type: String? = nil) {
            board.clearContents(); board.setString(text, forType: .string)
            board.setString("test.source", forType: .init("org.nspasteboard.source"))
            if let type { board.setString("", forType: .init(type)) }
        }
        let rich = Data(#"{\rtf1\b Example}"#.utf8)
        write("https://example.com")
        board.setData(rich, forType: .rtf); store.sample()
        try check(store.entries.count == 1 && store.entries[0].isLink, "Private test pasteboard was not collected")
        write("Sensitive", type: "org.nspasteboard.ConcealedType"); store.sample()
        try check(store.entries.count == 1, "Concealed copy leaked into history")
        store.configure(enabled: true, paused: true, limit: 10, exclusions: [])
        write("Paused"); store.sample()
        store.configure(enabled: true, paused: false, limit: 10, exclusions: []); store.sample()
        try check(store.entries.count == 1, "Resume collects content copied during pause")
        store.configure(enabled: true, paused: false, limit: 10, exclusions: ["test.source"])
        write("Excluded"); store.sample()
        try check(store.entries.count == 1, "Excluded app was collected")
        let item = store.entries[0]
        try check(item.rtf == rich && store.copy(item) && board.data(forType: .rtf) == rich, "Regular copy drops formatting")
        try check(store.copy(item, plainText: true) && board.string(forType: .string) == item.text && board.data(forType: .rtf) == nil, "Plain copy retains formatting")
        store.sample(); try check(store.entries.count == 1, "Copying history recursively creates entries")
        store.toggleFavorite(item.id); store.clear(includingFavorites: false)
        try check(store.entries.count == 1 && store.entries[0].favorite, "Clear recent history removes favorites")
        store.clear(includingFavorites: true)
        try check(store.entries.isEmpty && board.string(forType: .string) == item.text, "Clear removes the system's current pasteboard")
        try Data("corrupted".utf8).write(to: file)
        let broken = ClipboardStore(url: file, pasteboard: board)
        broken.configure(enabled: true, paused: false, limit: 10, exclusions: [])
        write("Do not overwrite"); broken.sample()
        let preserved = try Data(contentsOf: file)
        try check(broken.error != nil && preserved == Data("corrupted".utf8), "Corrupt history was silently overwritten")
        broken.clear(includingFavorites: false)
        let preservedAfterClear = try Data(contentsOf: file)
        try check(preservedAfterClear == preserved, "Clear recent items discards unknown favorites from a broken archive")
        broken.clear(includingFavorites: true)
        let cleared = try ClipboardStorage.load(file)
        try check(cleared.isEmpty, "Explicit clear cannot recover a damaged archive")
        var prefs = Prefs(); prefs.clipboardEnabled = true; prefs.clipboardLimit = 50; prefs.clipboardExcludedApps = ["test.private"]
        let restored = try JSONDecoder().decode(Prefs.self, from: JSONEncoder().encode(prefs))
        try restored.validate()
        try check(restored.clipboardEnabled == true && restored.clipboardExcludedApps == ["test.private"] && Prefs().clipboardEnabled != true, "Clipboard opt-in or preference compatibility changed")
        let scene = SceneSettings.applying(Prefs(), to: prefs)
        try check(scene.clipboardEnabled == true && scene.clipboardLimit == 50 && scene.clipboardExcludedApps == ["test.private"], "A scene changes clipboard privacy settings")
        try check(ClipboardHotKey().configure(enabled: false), "Disabled shortcut failed to release its registration")
        print("Clipboard checks passed: private named pasteboard only; opt-in, markers, pause, exclusions, pins, persistence, corruption and scene isolation")
    }
}
