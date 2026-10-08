import Foundation

/// Keep the existing data identity; relocate only integrations owned by this app.
@MainActor enum BrandMigration {
    static func relocate(settingsURL: URL = ClaudeBridgeInstaller.settings,
                         backupURL: URL = ClaudeBridgeInstaller.backup,
                         executableURL: URL? = Bundle.main.executableURL) throws {
        guard let executableURL,
              executableURL.path.hasSuffix("/Sorayura.app/Contents/MacOS/Sorayura") else { return }
        let oldPath = String(executableURL.path.dropLast("Sorayura.app/Contents/MacOS/Sorayura".count))
            + "Mac System Wallpaper.app/Contents/MacOS/MacSystemWallpaper"
        let developmentPath = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Developer/macbook-system-wallpaper-m0/native-app/build/Mac System Wallpaper.app/Contents/MacOS/MacSystemWallpaper").path
        let olds = [oldPath, developmentPath].map(ClaudeBridgeInstaller.quote)
        let new = ClaudeBridgeInstaller.quote(executableURL.path)
        var object = try ClaudeBridgeInstaller.current(at: settingsURL)
        var changed = false
        var saved: [String: Any]?
        if var line = object["statusLine"] as? [String: Any],
           let command = line["command"] as? String,
           let old = olds.first(where: { command == $0 + " --claude-statusline" || command.hasPrefix($0 + " --claude-statusline --forward-statusline ") }),
           let data = try? Data(contentsOf: backupURL),
           var backup = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           backup["installedCommand"] as? String == command {
            let relocated = new + command.dropFirst(old.count)
            line["command"] = relocated
            object["statusLine"] = line
            backup["installedCommand"] = relocated
            saved = backup
            changed = true
        }
        if var hooks = object["hooks"] as? [String: Any] {
            for event in ClaudeHooksInstaller.events {
                guard var groups = hooks[event] as? [[String: Any]] else { continue }
                for i in groups.indices {
                    guard var entries = groups[i]["hooks"] as? [[String: Any]] else { continue }
                    for j in entries.indices where olds.contains(where: { entries[j]["command"] as? String == $0 + " --claude-event" }) {
                        entries[j]["command"] = new + " --claude-event"
                        changed = true
                    }
                    groups[i]["hooks"] = entries
                }
                hooks[event] = groups
            }
            object["hooks"] = hooks
        }
        guard changed else { return }
        // Write settings first: if a backup update fails, ownership checks prevent
        // a later uninstall from overwriting another status line.
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            .write(to: settingsURL, options: .atomic)
        if let saved {
            try JSONSerialization.data(withJSONObject: saved, options: [.prettyPrinted, .sortedKeys])
                .write(to: backupURL, options: .atomic)
        }
    }
}
