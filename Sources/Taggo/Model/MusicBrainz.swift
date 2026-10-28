import Foundation

/// Client minimo per l'API pubblica di MusicBrainz e per il Cover Art Archive.
/// MusicBrainz chiede al massimo una richiesta al secondo e un User-Agent che identifichi l'app.
actor MusicBrainz {
    static let shared = MusicBrainz()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "Taggo/0.1 (macOS tag editor)", "Accept": "application/json"]
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()
    private var lastRequest = Date.distantPast

    // MARK: Modelli

    struct Credit: Decodable, Sendable {
        let name: String
        let joinphrase: String?
    }

    struct ReleaseSummary: Decodable, Identifiable, Sendable {
        let id: String
        let title: String
        let date: String?
        let country: String?
        let trackCount: Int?
        let artistCredit: [Credit]?
        let media: [MediumSummary]?
        let labelInfo: [LabelInfo]?

        struct MediumSummary: Decodable, Sendable { let format: String? }
        struct LabelInfo: Decodable, Sendable {
            let label: Label?
            struct Label: Decodable, Sendable { let name: String? }
        }

        enum CodingKeys: String, CodingKey {
            case id, title, date, country, media
            case trackCount = "track-count"
            case artistCredit = "artist-credit"
            case labelInfo = "label-info"
        }

        var artist: String { MusicBrainz.join(artistCredit) }
        var format: String {
            let formats = (media ?? []).compactMap(\.format)
            guard let first = formats.first else { return "" }
            return formats.count > 1 ? "\(formats.count)×\(first)" : first
        }
        var label: String { labelInfo?.compactMap { $0.label?.name }.first ?? "" }
    }

    struct Release: Decodable, Sendable {
        let id: String
        let title: String
        let date: String?
        let artistCredit: [Credit]?
        let media: [Medium]
        let releaseGroup: ReleaseGroup?
        let coverArtArchive: CoverArt?

        struct Medium: Decodable, Sendable {
            let position: Int
            let format: String?
            let tracks: [Track]?
        }
        struct Track: Decodable, Sendable {
            let position: Int
            let title: String
            let length: Int?
            let artistCredit: [Credit]?
            enum CodingKeys: String, CodingKey {
                case position, title, length
                case artistCredit = "artist-credit"
            }
        }
        struct ReleaseGroup: Decodable, Sendable {
            let firstReleaseDate: String?
            let genres: [Genre]?
            enum CodingKeys: String, CodingKey {
                case genres
                case firstReleaseDate = "first-release-date"
            }
        }
        struct Genre: Decodable, Sendable {
            let name: String
            let count: Int?
        }
        struct CoverArt: Decodable, Sendable { let front: Bool? }

        enum CodingKeys: String, CodingKey {
            case id, title, date, media
            case artistCredit = "artist-credit"
            case releaseGroup = "release-group"
            case coverArtArchive = "cover-art-archive"
        }

        var artist: String { MusicBrainz.join(artistCredit) }
        var hasFrontCover: Bool { coverArtArchive?.front ?? false }
        var topGenre: String? { releaseGroup?.genres?.max { ($0.count ?? 0) < ($1.count ?? 0) }?.name }
    }

    /// Una traccia della release, già con i numeri di disco e traccia.
    struct FlatTrack: Identifiable, Sendable {
        let id: String
        let disc: Int
        let discTotal: Int
        let track: Int
        let trackTotal: Int
        let title: String
        let artist: String
        let seconds: Int
    }

    private struct SearchResponse: Decodable { let releases: [ReleaseSummary] }

    // MARK: API

    func search(artist: String, album: String) async throws -> [ReleaseSummary] {
        var terms: [String] = []
        if !album.isEmpty { terms.append("release:\(Self.quote(album))") }
        if !artist.isEmpty { terms.append("artist:\(Self.quote(artist))") }
        guard !terms.isEmpty else { return [] }
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/release/")!
        components.queryItems = [
            URLQueryItem(name: "query", value: terms.joined(separator: " AND ")),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "40"),
        ]
        let data = try await get(components.url!)
        return try JSONDecoder().decode(SearchResponse.self, from: data).releases
    }

    func release(id: String) async throws -> Release {
        let url = URL(string: "https://musicbrainz.org/ws/2/release/\(id)?inc=recordings+artist-credits+release-groups+genres&fmt=json")!
        return try JSONDecoder().decode(Release.self, from: try await get(url))
    }

    func frontCover(releaseID: String) async throws -> Data {
        let url = URL(string: "https://coverartarchive.org/release/\(releaseID)/front-500")!
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw TagError("copertina non disponibile")
        }
        return data
    }

    nonisolated static func flatten(_ release: Release) -> [FlatTrack] {
        let media = release.media.filter { !($0.tracks ?? []).isEmpty }
        return media.flatMap { medium in
            let tracks = medium.tracks ?? []
            return tracks.map { track in
                FlatTrack(
                    id: "\(medium.position)-\(track.position)",
                    disc: medium.position,
                    discTotal: media.count,
                    track: track.position,
                    trackTotal: tracks.count,
                    title: track.title,
                    artist: track.artistCredit.map(join) ?? release.artist,
                    seconds: (track.length ?? 0) / 1000
                )
            }
        }
    }

    // MARK: Rete

    private func get(_ url: URL) async throws -> Data {
        for attempt in 0..<5 {
            let wait = 1.1 - Date().timeIntervalSince(lastRequest)
            if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
            lastRequest = Date()
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200: return data
            case 503, 429: try await Task.sleep(for: .seconds(1.5 * Double(attempt + 1)))
            case 404: throw TagError("non trovato su MusicBrainz")
            default: throw TagError("MusicBrainz ha risposto con errore \(status)")
            }
        }
        throw TagError("MusicBrainz è occupato, riprova tra poco")
    }

    nonisolated static func join(_ credits: [Credit]?) -> String {
        (credits ?? []).map { $0.name + ($0.joinphrase ?? "") }.joined()
    }

    /// Racchiude il testo tra virgolette per la sintassi di ricerca (Lucene) di MusicBrainz.
    nonisolated static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// Collegamenti a database e siti utili, con la ricerca già impostata.
enum WebLookup: String, CaseIterable, Identifiable {
    case musicBrainz = "MusicBrainz"
    case discogs = "Discogs"
    case allMusic = "AllMusic"
    case wikipedia = "Wikipedia"
    case lastFM = "Last.fm"
    case bandcamp = "Bandcamp"
    case appleMusic = "Apple Music"
    case coverImages = "Immagini di copertina (Google)"

    var id: String { rawValue }

    func url(for query: String) -> URL? {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))) ?? ""
        let string = switch self {
        case .musicBrainz: "https://musicbrainz.org/search?type=release&query=\(q)"
        case .discogs: "https://www.discogs.com/search/?type=release&q=\(q)"
        case .allMusic: "https://www.allmusic.com/search/albums/\(q)"
        case .wikipedia: "https://it.wikipedia.org/w/index.php?search=\(q)"
        case .lastFM: "https://www.last.fm/search/albums?q=\(q)"
        case .bandcamp: "https://bandcamp.com/search?item_type=a&q=\(q)"
        case .appleMusic: "https://music.apple.com/search?term=\(q)"
        case .coverImages: "https://www.google.com/search?tbm=isch&q=\(q)%20cover"
        }
        return URL(string: string)
    }
}
