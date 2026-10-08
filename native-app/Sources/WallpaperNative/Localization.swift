import Foundation
import Observation
import os
import SwiftUI

/// A single cached catalog shared by SwiftUI, AppKit and background readers.
enum Localizer {
    static let preferenceKey = "SorayuraInterfaceLanguage"
    static let supported = ["it", "en", "es"]
    private struct Snapshot: Sendable {
        let language: String
        let locale: Locale
        init(_ choice: String) {
            language = Localizer.resolved(choice)
            let defaultRegion = ["it": "IT", "en": "US", "es": "ES"][language] ?? "US"
            locale = Locale(identifier: language + "_" + (Locale.current.region?.identifier ?? defaultRegion))
        }
    }
    private static let selection = OSAllocatedUnfairLock(initialState: Snapshot(validated(UserDefaults.standard.string(forKey: preferenceKey) ?? "system")))
    static let catalogs: [String: [String: String]] = {
        var result: [String: [String: String]] = [:]
        for language in supported {
            guard let url = Bundle.main.url(forResource: language, withExtension: "json", subdirectory: "Localization"),
                  let data = try? Data(contentsOf: url),
                  let strings = try? JSONDecoder().decode([String: String].self, from: data) else { continue }
            result[language] = strings
        }
        return result
    }()
    static func validated(_ value: String) -> String {
        supported.contains(value) ? value : "system"
    }
    static func resolved(_ choice: String, preferred: [String] = Locale.preferredLanguages) -> String {
        if supported.contains(choice) { return choice }
        return preferred.compactMap { code in
            let base = code.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
            return supported.contains(base) ? base : nil
        }.first ?? "en"
    }
    static var language: String { selection.withLock { $0.language } }
    static var locale: Locale { selection.withLock { $0.locale } }
    static func select(_ value: String) {
        let snapshot = Snapshot(validated(value))
        selection.withLock { $0 = snapshot }
    }
    static func text(_ key: String, language: String? = nil) -> String {
        let language = language ?? self.language
        return catalogs[language]?[key] ?? catalogs["en"]?[key] ?? key
    }
    static func format(_ key: String, arguments: [String], language: String? = nil) -> String {
        let template = text(key, language: language)
        // A single pass prevents values containing placeholders from being interpreted.
        var result = "", index = template.startIndex
        while index < template.endIndex {
            if template[index] == "{", let end = template[index...].firstIndex(of: "}"),
               let argument = Int(template[template.index(after: index)..<end]), arguments.indices.contains(argument) {
                result += arguments[argument]; index = template.index(after: end)
            } else { result.append(template[index]); index = template.index(after: index) }
        }
        return result
    }
}

struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    var key: String
    var arguments: [String]
    init(stringLiteral value: String) { key = value; arguments = [] }
    init(stringInterpolation: StringInterpolation) { key = stringInterpolation.key; arguments = stringInterpolation.arguments }
    struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity); arguments.reserveCapacity(interpolationCount) }
        mutating func appendLiteral(_ literal: String) { key += literal }
        mutating func appendInterpolation<T>(_ value: T) {
            key += "{\(arguments.count)}"; arguments.append(String(describing: value))
        }
    }
}

func L(_ key: String) -> String { Localizer.text(key) }
func LF(_ message: LocalizedMessage) -> String { Localizer.format(message.key, arguments: message.arguments) }

extension Date {
    func localizedFormatted(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time).locale(Localizer.locale))
    }
}

@MainActor @Observable final class LocalizationSettings {
    static let shared = LocalizationSettings()
    private(set) var choice = Localizer.validated(UserDefaults.standard.string(forKey: Localizer.preferenceKey) ?? "system")
    var locale: Locale { _ = choice; return Localizer.locale }
    func choose(_ value: String) {
        let next = Localizer.validated(value)
        guard choice != next else { return }
        choice = next
        Localizer.select(next)
        UserDefaults.standard.set(next, forKey: Localizer.preferenceKey)
        NotificationCenter.default.post(name: .sorayuraLanguageChanged, object: nil)
    }
}

extension Notification.Name {
    static let sorayuraLanguageChanged = Notification.Name("dev.aniello.macsystemwallpaper.languageChanged")
}

struct LocalizedRoot<Content: View>: View {
    let content: Content
    var body: some View {
        content.environment(\.locale, LocalizationSettings.shared.locale)
    }
}
