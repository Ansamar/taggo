import Foundation

/// Pattern in stile `%artist% - %title%` per i convertitori tag ↔ nome file.
enum Patterns {
    private static let placeholderRegex = try! NSRegularExpression(pattern: "%([A-Za-z]+)%")
    private static let numRegex = try! NSRegularExpression(pattern: #"\$num\(%([A-Za-z]+)%\s*,\s*(\d+)\)"#)

    /// Tag → nome file. Restituisce il nuovo percorso relativo alla cartella del file,
    /// estensione inclusa. Una `/` nel pattern crea sottocartelle.
    /// Restituisce "" se tutti i campi usati sono vuoti (es. file senza tag).
    static func filename(_ pattern: String, for file: AudioFile) -> String {
        var result = pattern
        var hasContent = false
        result = replace(numRegex, in: result) { groups in
            let value = Self.value(groups[0], in: file)
            if !value.isEmpty { hasContent = true }
            let width = Int(groups[1]) ?? 0
            let number = AudioFile.leadingNumber(value)
            return number > 0 ? String(format: "%0\(width)d", number) : value
        }
        result = replace(placeholderRegex, in: result) { groups in
            let value = Self.value(groups[0], in: file)
            if !value.isEmpty { hasContent = true }
            return value
        }
        guard hasContent else { return "" }
        let components = result
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix(".") ? "_" + $0.dropFirst() : $0 }
            .filter { !$0.isEmpty }
        guard !components.isEmpty else { return "" }
        let ext = file.url.pathExtension
        return components.joined(separator: "/") + (ext.isEmpty ? "" : "." + ext)
    }

    /// Nome file → tag. `nil` se il nome non corrisponde al pattern.
    /// Ogni `/` nel pattern consuma una cartella superiore. `%dummy%` ignora una parte.
    static func parse(_ pattern: String, file: AudioFile) -> [TagField: String]? {
        let depth = pattern.filter { $0 == "/" }.count
        var parts = [file.url.deletingPathExtension().lastPathComponent]
        var dir = file.url.deletingLastPathComponent()
        for _ in 0..<depth {
            parts.insert(dir.lastPathComponent, at: 0)
            dir = dir.deletingLastPathComponent()
        }
        return parse(pattern, text: parts.joined(separator: "/"))
    }

    static func parse(_ pattern: String, text: String) -> [TagField: String]? {
        let ns = pattern as NSString
        var regex = "^"
        var names: [String] = []
        var cursor = 0
        for match in placeholderRegex.matches(in: pattern, range: NSRange(location: 0, length: ns.length)) {
            regex += NSRegularExpression.escapedPattern(for: ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            regex += "(.+?)"
            names.append(ns.substring(with: match.range(at: 1)))
            cursor = match.range.location + match.range.length
        }
        regex += NSRegularExpression.escapedPattern(for: ns.substring(from: cursor)) + "$"
        guard !names.isEmpty, let re = try? NSRegularExpression(pattern: regex) else { return nil }

        let nsText = text as NSString
        guard let match = re.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else { return nil }
        var result: [TagField: String] = [:]
        for (i, name) in names.enumerated() {
            guard let field = TagField(placeholder: name) else { continue }
            let value = nsText.substring(with: match.range(at: i + 1)).trimmingCharacters(in: .whitespaces)
            result[field] = value
        }
        return result
    }

    private static func value(_ name: String, in file: AudioFile) -> String {
        let raw: String
        switch name.lowercased() {
        case "filename": raw = file.url.deletingPathExtension().lastPathComponent
        case "folder": raw = file.url.deletingLastPathComponent().lastPathComponent
        case "track": raw = String(file[.track].prefix { $0 != "/" })
        case "discnumber", "disc": raw = String(file[.disc].prefix { $0 != "/" })
        default: raw = TagField(placeholder: name).map { file[$0] } ?? ""
        }
        return sanitize(raw)
    }

    private static func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, _ transform: ([String]) -> String) -> String {
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let groups = (1..<match.numberOfRanges).map { ns.substring(with: match.range(at: $0)) }
            result += transform(groups)
            cursor = match.range.location + match.range.length
        }
        return result + ns.substring(from: cursor)
    }
}

enum CaseMode: String, CaseIterable, Identifiable {
    case title = "Iniziali Maiuscole"
    case sentence = "Prima lettera maiuscola"
    case upper = "TUTTO MAIUSCOLO"
    case lower = "tutto minuscolo"

    var id: String { rawValue }

    func apply(_ s: String) -> String {
        switch self {
        case .title: s.lowercased().capitalized(with: .current)
        case .upper: s.uppercased()
        case .lower: s.lowercased()
        case .sentence:
            s.lowercased().prefix(1).uppercased() + s.lowercased().dropFirst()
        }
    }
}

struct Replacement {
    var find: String
    var replaceWith: String
    var useRegex: Bool
    var caseSensitive: Bool

    /// `nil` se l'espressione regolare non è valida.
    func apply(_ s: String) -> String? {
        guard !find.isEmpty else { return s }
        if useRegex {
            guard let re = try? NSRegularExpression(pattern: find, options: caseSensitive ? [] : .caseInsensitive) else { return nil }
            return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: replaceWith)
        }
        return s.replacingOccurrences(of: find, with: replaceWith, options: caseSensitive ? [] : .caseInsensitive)
    }
}
