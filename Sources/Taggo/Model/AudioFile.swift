import Foundation

/// I campi modificabili nel pannello, mappati sulle chiavi "property map" di TagLib,
/// che valgono per tutti i formati (ID3v2, MP4, Vorbis/FLAC, APE, ASF…).
enum TagField: String, CaseIterable, Identifiable, Hashable, Sendable {
    case title, artist, album, albumArtist, year, track, disc, genre, composer, comment

    var id: String { rawValue }

    var key: String {
        switch self {
        case .title: "TITLE"
        case .artist: "ARTIST"
        case .album: "ALBUM"
        case .albumArtist: "ALBUMARTIST"
        case .year: "DATE"
        case .track: "TRACKNUMBER"
        case .disc: "DISCNUMBER"
        case .genre: "GENRE"
        case .composer: "COMPOSER"
        case .comment: "COMMENT"
        }
    }

    var label: String {
        switch self {
        case .title: "Titolo"
        case .artist: "Artista"
        case .album: "Album"
        case .albumArtist: "Artista album"
        case .year: "Anno"
        case .track: "Traccia"
        case .disc: "Disco"
        case .genre: "Genere"
        case .composer: "Compositore"
        case .comment: "Commento"
        }
    }

    /// Nome usato nei pattern, es. `%artist%`.
    var placeholder: String {
        switch self {
        case .albumArtist: "albumartist"
        case .disc: "discnumber"
        default: rawValue
        }
    }

    init?(placeholder: String) {
        let name = placeholder.lowercased()
        if name == "disc" { self = .disc; return }
        guard let field = TagField.allCases.first(where: { $0.placeholder == name }) else { return nil }
        self = field
    }
}

enum CoverEdit: Hashable, Sendable {
    case set(Data, mime: String)
    case remove
}

struct AudioFile: Identifiable, Hashable, Sendable {
    let id = UUID()
    var url: URL
    var tags: [TagField: String]
    var original: [TagField: String]
    var coverEdit: CoverEdit?
    var hasCover = false
    var duration = 0
    var bitrate = 0
    var sampleRate = 0
    var channels = 0

    init(url: URL, tags: [TagField: String] = [:]) {
        self.url = url
        self.tags = tags
        self.original = tags
    }

    subscript(field: TagField) -> String {
        get { tags[field] ?? "" }
        set { tags[field] = newValue }
    }

    var changedFields: [TagField] {
        TagField.allCases.filter { (tags[$0] ?? "") != (original[$0] ?? "") }
    }

    var isDirty: Bool { coverEdit != nil || !changedFields.isEmpty }

    var showsCover: Bool {
        switch coverEdit {
        case .set: true
        case .remove: false
        case nil: hasCover
        }
    }

    mutating func markSaved() {
        original = tags
        hasCover = showsCover
        coverEdit = nil
    }

    // Proprietà per colonne e ordinamento.
    var filename: String { url.lastPathComponent }
    var path: String { url.path }
    var folder: String { url.deletingLastPathComponent().path }
    var format: String { url.pathExtension.uppercased() }
    var title: String { self[.title] }
    var artist: String { self[.artist] }
    var album: String { self[.album] }
    var albumArtist: String { self[.albumArtist] }
    var year: String { self[.year] }
    var genre: String { self[.genre] }
    var composer: String { self[.composer] }
    var comment: String { self[.comment] }
    var trackNumber: Int { Self.leadingNumber(self[.track]) }
    var discNumber: Int { Self.leadingNumber(self[.disc]) }
    var coverSortKey: Int { showsCover ? 1 : 0 }

    var durationText: String {
        guard duration > 0 else { return "" }
        let h = duration / 3600, m = duration / 60 % 60, s = duration % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "3/12" → 3
    static func leadingNumber(_ s: String) -> Int {
        Int(s.prefix { $0.isNumber }) ?? 0
    }
}
