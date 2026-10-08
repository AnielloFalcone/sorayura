import Foundation

@MainActor enum LocalizationChecks {
    static func run() throws {
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw SettingsError.invalid(message) }
        }
        func placeholders(_ text: String) -> [String] {
            let expression = try! NSRegularExpression(pattern: "\\{[0-9]+\\}")
            return expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .map { (text as NSString).substring(with: $0.range) }.sorted()
        }
        let en = Localizer.catalogs["en"] ?? [:], it = Localizer.catalogs["it"] ?? [:]
        try check(en.count > 250 && Set(en.keys) == Set(it.keys), "Missing or inconsistent bundled language catalogs")
        for key in en.keys {
            try check(!(en[key] ?? "").isEmpty, "Empty English translation: \(key)")
            try check(placeholders(key) == placeholders(en[key]!), "English placeholders changed: \(key)")
            try check(placeholders(key) == placeholders(it[key]!), "Italian placeholders changed: \(key)")
        }
        try check(Localizer.resolved("en", preferred: ["it-IT"]) == "en", "Explicit language ignored")
        try check(Localizer.resolved("system", preferred: ["it_IT", "en-US"]) == "it", "Italian system dialect not resolved")
        try check(Localizer.resolved("system", preferred: ["ja-JP", "en-GB"]) == "en", "Preferred supported language not resolved")
        try check(Localizer.resolved("system", preferred: ["ja-JP"]) == "en", "Unsupported system language has no fallback")
        try check(Localizer.validated("unknown") == "system", "Invalid persisted language accepted")
        try check(Localizer.text("Memoria", language: "en") == "Memory", "Widget name not translated")
        try check(Localizer.text("Memoria", language: "it") == "Memoria", "Italian widget name changed")
        try check(Localizer.text("My custom preset", language: "en") == "My custom preset", "Unknown user content changed")
        try check(Localizer.format("Rimuovi {0}", arguments: ["{1} · Memory"], language: "en") == "Remove {1} · Memory", "Interpolated content was reinterpreted")
        let message: LocalizedMessage = "Rimuovi \("CPU")"
        try check(message.key == "Rimuovi {0}" && message.arguments == ["CPU"], "String interpolation lost its stable key")
        let before = try JSONEncoder().encode(Prefs())
        let original = Localizer.language
        Localizer.select("en")
        try check(Model.localizedName("memory") == "Memory", "English selection not propagated")
        Localizer.select("it")
        try check(Model.localizedName("memory") == "Memoria", "Italian selection not propagated")
        Localizer.select(original)
        let after = try JSONEncoder().encode(Prefs())
        let left = try JSONSerialization.jsonObject(with: before) as! NSDictionary
        let right = try JSONSerialization.jsonObject(with: after) as! NSDictionary
        try check(left == right, "Language selection changed layout defaults or stable settings identifiers")
        print("Localization checks passed: bundled catalogs, placeholders, system fallback, interpolation, language switching and stable settings")
    }
}
