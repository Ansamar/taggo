import Foundation

/// Divide un album in dischi: assegna DISCNUMBER e, se richiesto, rinumera
/// le tracce da 1 per ogni disco.
struct DiscSplit {
    enum Mode: String, CaseIterable, Identifiable {
        case restart = "Quando la numerazione riparte"
        case folders = "Una sottocartella per disco"
        case count = "Ogni N brani"
        case points = "Dai brani indicati"

        var id: String { rawValue }

        var help: String {
            switch self {
            case .restart: "Un nuovo disco inizia quando il numero di traccia non cresce rispetto al brano precedente (es. …12, 1, 2…)."
            case .folders: "Ogni sottocartella (CD1, CD2, Disc 1…) diventa un disco, in ordine alfabetico."
            case .count: "I brani vengono divisi in blocchi di N, nell'ordine della tabella."
            case .points: "Indica la posizione del primo brano di ogni disco successivo, nell'ordine della tabella (es. 13, 25)."
            }
        }
    }

    var mode: Mode = .restart
    var perDisc = 10
    var points: [Int] = []
    var renumber = true
    var withTotals = true
    /// Divide separatamente ogni album presente tra i file.
    var groupByAlbum = true

    struct AlbumSummary: Identifiable {
        let id: String
        let album: String
        let tracksPerDisc: [Int]
    }

    /// Numero di disco (da 1) per ogni file, nell'ordine ricevuto.
    func discs(for files: [AudioFile]) -> [Int] {
        var result = Array(repeating: 1, count: files.count)
        for indices in albumGroups(files) {
            let group = indices.map { files[$0] }
            for (i, disc) in zip(indices, discs(inAlbum: group)) { result[i] = disc }
        }
        return result
    }

    func apply(_ files: [AudioFile]) -> [AudioFile] {
        var result = files
        let assigned = discs(for: files)
        for indices in albumGroups(files) {
            let totalDiscs = indices.map { assigned[$0] }.max() ?? 1
            for disc in 1...totalDiscs {
                let tracks = indices.filter { assigned[$0] == disc }
                for (n, i) in tracks.enumerated() {
                    result[i][.disc] = withTotals ? "\(disc)/\(totalDiscs)" : "\(disc)"
                    if renumber {
                        result[i][.track] = withTotals ? "\(n + 1)/\(tracks.count)" : "\(n + 1)"
                    }
                }
            }
        }
        return result
    }

    func summary(for files: [AudioFile]) -> [AlbumSummary] {
        let assigned = discs(for: files)
        return albumGroups(files).map { indices in
            let total = indices.map { assigned[$0] }.max() ?? 1
            let counts = (1...total).map { disc in indices.count { assigned[$0] == disc } }
            let album = files[indices[0]].album
            return AlbumSummary(id: albumKey(files[indices[0]]), album: album.isEmpty ? "(senza album)" : album, tracksPerDisc: counts)
        }
    }

    private func discs(inAlbum files: [AudioFile]) -> [Int] {
        guard !files.isEmpty else { return [] }
        switch mode {
        case .restart:
            var disc = 1
            var previous = 0
            return files.map { file in
                let track = file.trackNumber
                if track > 0, previous > 0, track <= previous { disc += 1 }
                if track > 0 { previous = track }
                return disc
            }
        case .folders:
            let folders = Array(Set(files.map(\.folder))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            let index = Dictionary(uniqueKeysWithValues: folders.enumerated().map { ($1, $0 + 1) })
            return files.map { index[$0.folder] ?? 1 }
        case .count:
            let size = max(perDisc, 1)
            return files.indices.map { $0 / size + 1 }
        case .points:
            let starts = Set(points.filter { $0 > 1 && $0 <= files.count })
            var disc = 1
            return files.indices.map { i in
                if starts.contains(i + 1) { disc += 1 }
                return disc
            }
        }
    }

    /// Indici dei file raggruppati per album, nell'ordine di prima apparizione.
    private func albumGroups(_ files: [AudioFile]) -> [[Int]] {
        guard groupByAlbum else { return files.isEmpty ? [] : [Array(files.indices)] }
        var order: [String] = []
        var groups: [String: [Int]] = [:]
        for (i, file) in files.enumerated() {
            let key = albumKey(file)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(i)
        }
        return order.map { groups[$0]! }
    }

    private func albumKey(_ file: AudioFile) -> String {
        groupByAlbum ? file.albumArtist.lowercased() + "\u{1F}" + file.album.lowercased() : ""
    }

    /// "13, 25 37" → [13, 25, 37]
    static func parsePoints(_ text: String) -> [Int] {
        text.split { !$0.isNumber }.compactMap { Int($0) }.sorted()
    }
}
